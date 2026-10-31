#!/usr/bin/env node
// Host-side logic tests. Native HTTP, codecs, files and system dialogs are mocked;
// this runner does not establish HarmonyOS device or UI compatibility.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require(process.env.ARKTS_TEST_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/tools/ohpm/node_modules/typescript');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'entry/src/main/ets');

function loader(mocks = {}) {
  const modules = new Map();
  function load(filename) {
    if (Object.hasOwn(mocks, filename)) return mocks[filename];
    if (modules.has(filename)) return modules.get(filename).exports;
    const module = { exports: {} };
    modules.set(filename, module);
    const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS,
        experimentalDecorators: true }
    }).outputText;
    const localRequire = (id) => {
      if (Object.hasOwn(mocks, id)) return mocks[id];
      if (!id.startsWith('.')) throw new Error('Unmocked native import: ' + id);
      return load(path.resolve(path.dirname(filename), id + '.ets'));
    };
    new Function('require', 'exports', 'module', 'ObservedV2', 'Trace', 'Computed', 'Scroller', 'canIUse', output)(
      localRequire, module.exports, module, (value) => value, () => {}, () => {}, class {}, mocks.canIUse || (() => true));
    return module.exports;
  }
  return load;
}

const fixtureLoad = loader({
  '@ohos/hypium': {
    describe: (_name, body) => body(),
    it: (name, _flags, body) => test(name, body),
    expect: (value) => ({
      assertEqual: (expected) => assert.equal(value, expected),
      assertTrue: () => assert.equal(value, true),
      assertFalse: () => assert.equal(value, false),
      assertUndefined: () => assert.equal(value, undefined)
    })
  }
});
for (const name of ['PageExpansion', 'SaveReceipt', 'GalleryBatching', 'BatchView', 'PictureFilters']) {
  fixtureLoad(path.join(root, 'entry/src/ohosTest/ets/test/' + name + '.test.ets')).default();
}

function previewHarness(response, config = {}) {
  const calls = [];
  const deleted = [];
  const released = [];
  const files = new Map();
  const descriptors = new Map();
  let descriptor = 0;
  let cookie = 'session=test';
  const requests = [];
  function createNativeRequest() {
    const listeners = new Map();
    requests.push(listeners);
    return {
    destroy: () => calls.push('destroy'),
    on: (event, callback) => { listeners.set(event, callback); },
    requestInStream: async (url, options) => {
      calls.push({ url, options });
      if (config.headers) listeners.get('headersReceive')?.(config.headers);
      const result = await (typeof response === 'function' ? response(url) : response);
      const chunks = config.chunks || (result.result instanceof ArrayBuffer ? [result.result] : []);
      let received = 0;
      for (const chunk of chunks) {
        listeners.get('dataReceive')?.(chunk);
        received += chunk.byteLength;
        listeners.get('dataReceiveProgress')?.({ receiveSize: received, totalSize: config.total || 0 });
        if (config.chunkDelay) await new Promise((resolve) => setTimeout(resolve, config.chunkDelay));
      }
      if (config.endAfterStatus) setTimeout(() => listeners.get('dataEnd')?.(), 0);
      else listeners.get('dataEnd')?.();
      return result.responseCode;
    }
    };
  }
  const load = loader({
    '@kit.NetworkKit': { http: { createHttp: createNativeRequest,
      RequestMethod: { GET: 'GET' }, HttpDataType: { ARRAY_BUFFER: 2 } } },
    '@kit.ArkWeb': { webview: { WebCookieManager: { fetchCookieSync: () => cookie } } },
    '@kit.CoreFileKit': {
      fileUri: { getUriFromPath: (value) => 'file://' + value },
      fileIo: { OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
        openSync: (name) => { descriptors.set(++descriptor, name); files.set(name, 0); return { fd: descriptor }; },
        writeSync: (fd, data) => {
          if (config.diskFailure) throw new Error('disk full');
          const name = descriptors.get(fd);
          files.set(name, (files.get(name) || 0) + data.byteLength); return config.partialWrite ? 1 : data.byteLength;
        },
        closeSync: () => {}, statSync: (name) => {
          if (!files.has(name)) throw new Error('missing');
          return { size: files.get(name) };
        },
        unlinkSync: (value) => { deleted.push(value); files.delete(value); } }
    },
    '@kit.ImageKit': { image: {
      createImageSource: (input) => {
        calls.push({ source: input });
        if (config.badImage) throw new Error('bad format');
        return { getImageInfo: async () => ({ size: config.size || { width: 4000, height: 2000 } }),
          getFrameCount: async () => config.frames || 1,
          createPixelMap: async (options) => {
            calls.push({ decode: options });
            if (config.decode) await config.decode();
            return { release: async () => released.push('frame') };
          }, release: async () => released.push('source') };
      },
      createImagePacker: () => ({ packToFile: async (_frame, fd, options) => {
        assert.equal(options.format, 'image/png', 'preview must preserve transparency');
        files.set(descriptors.get(fd), config.thumbnailBytes || 1024);
      }, release: async () => released.push('packer') })
    } }
  });
  const Preview = load(path.join(source, 'service/AuthenticatedPreview.ets')).AuthenticatedPreview;
  return { preview: new Preview(), createPreview: () => new Preview(),
    calls, deleted, released, files, emit: (event, value) => requests.at(-1)?.get(event)?.(value),
    setCookie: (value) => { cookie = value; } };
}

test('preview sends page credentials only to the requested URL and bounds memory', async () => {
  const harness = previewHarness({ responseCode: 200, result: new ArrayBuffer(10) });
  const result = await harness.preview.load('https://image.test/a.png', 'https://page.test/', '/cache');
  assert.ok(result.uri.startsWith('file:///cache/inspection-preview-'));
  const request = harness.calls.find((entry) => entry.url);
  const headers = { ...request.options.header };
  assert.ok(headers['User-Agent'].startsWith('Mozilla/5.0'), 'CDN requests must identify as a browser');
  delete headers['User-Agent'];
  assert.deepEqual(headers, { Cookie: 'session=test', Referer: 'https://page.test/' });
  assert.equal(request.options.maxRedirects, 0);
  assert.equal(request.options.maxLimit, 64 * 1024 * 1024);
  assert.equal(request.options.usingCache, false);
  assert.deepEqual(harness.released.sort(), ['frame', 'packer', 'source']);
  assert.deepEqual(harness.calls.find((entry) => entry.decode).decode.desiredSize, { width: 1200, height: 600 });
  assert.ok(harness.files.has(result.path));
  harness.preview.cancel();
  assert.ok(harness.deleted.includes(result.uri.substring('file://'.length)));
});

test('large preview streams more than 8 MiB to disk and decodes the file with ordered progress', async () => {
  const chunks = Array.from({ length: 12 }, () => new ArrayBuffer(1024 * 1024));
  const h = previewHarness({ responseCode: 200 }, { chunks, total: 12 * 1024 * 1024, chunkDelay: 12 });
  const progress = [];
  const result = await h.preview.load('https://image/large', '', '/cache', false, (p) => progress.push(p));
  assert.equal(result.failure, '');
  assert.equal(h.files.get(result.path), 12 * 1024 * 1024);
  assert.equal(h.calls.find((c) => c.source).source, result.path);
  assert.equal(progress[0].phase, 'connecting');
  assert.equal(progress.at(-2).phase, 'decoding');
  assert.equal(progress.at(-1).phase, 'ready');
  assert.ok(progress.filter((p) => p.phase === 'receiving').length >= 2);
  assert.ok(progress.every((p, i) => i === 0 || p.received >= progress[i - 1].received));
  h.preview.cancel();
});

test('unknown-length progress stays indeterminate and stream end can follow status', async () => {
  const h = previewHarness({ responseCode: 200, result: new ArrayBuffer(32) }, { endAfterStatus: true });
  const progress = [];
  const result = await h.preview.load('https://image/chunked', '', '/cache', false, (p) => progress.push(p));
  assert.equal(result.failure, '');
  assert.ok(progress.filter((p) => p.phase === 'receiving').every((p) => p.total === 0));
  assert.equal(h.files.get(result.path), 32);
  h.preview.cancel();
});

test('cancel resolves even if native destroy emits no completion and late chunks cannot recreate files', async () => {
  const h = previewHarness(() => new Promise(() => {}));
  const work = h.preview.load('https://image/stalled', '', '/cache');
  h.emit('dataReceive', new ArrayBuffer(64));
  h.preview.cancelRequest();
  assert.equal((await work).uri, '');
  assert.equal(h.files.size, 0);
  h.emit('dataReceive', new ArrayBuffer(64));
  h.emit('dataEnd');
  assert.equal(h.files.size, 0);
});

test('unknown-length stream enforces the byte limit while receiving and removes partial data', async () => {
  const chunk = new ArrayBuffer(8 * 1024 * 1024);
  const h = previewHarness({ responseCode: 200 }, { chunks: Array(9).fill(chunk) });
  const result = await h.preview.load('https://image/oversize', '', '/cache');
  assert.equal(result.failure, 'size');
  assert.equal(h.files.size, 0);
  assert.ok(!h.calls.some((c) => c.decode));
});

test('native response-limit errors use declared bytes without misclassifying small write failures', async () => {
  for (const bytes of [65 * 1024 * 1024, 1024]) {
    const h = previewHarness(() => { throw { code: 2300023 }; }, { headers: { 'CoNtEnT-LeNgTh': String(bytes) } });
    const result = await h.preview.load('https://image.test/a.png', 'https://page.test/', '/cache');
    assert.equal(result.failure, bytes > 64 * 1024 * 1024 ? 'size' : 'network');
    assert.equal(h.files.size, 0);
  }
});

test('expired login has an actionable failure and creates no preview', async () => {
  const harness = previewHarness({ responseCode: 403, result: new ArrayBuffer(0) });
  const result = await harness.preview.load('https://image.test/a.png', 'https://page.test/', '/cache');
  assert.equal(result.uri, '');
  assert.ok(result.message.includes('登录状态'));
  assert.deepEqual(harness.released, []);
});

test('cancel ignores a late successful network response', async () => {
  let resolveResponse;
  const harness = previewHarness(() => new Promise((resolve) => { resolveResponse = resolve; }));
  const work = harness.preview.load('https://image.test/a.png', 'https://page.test/', '/cache');
  harness.preview.cancel();
  resolveResponse({ responseCode: 200, result: new ArrayBuffer(10) });
  const result = await work;
  assert.equal(result.uri, '');
  assert.equal(result.message, '');
  assert.deepEqual(harness.released, []);
});

test('preview network failure retains the source-page/download fallback', async () => {
  const harness = previewHarness(() => { throw new Error('network unavailable'); });
  const result = await harness.preview.load('https://image.test/a.png', 'https://page.test/', '/cache');
  assert.equal(result.uri, '');
  assert.ok(result.message.includes('下载原文件'));
});

const geometry = loader()(path.join(source, 'util/PreviewGeometry.ets')).PreviewGeometry;
const motion = loader()(path.join(source, 'util/PreviewMotion.ets')).PreviewMotion;
const reading = loader()(path.join(source, 'model/PreviewReadingState.ets'));

test('fling advances after release, settles in bounds, and is frame-delay bounded', () => {
  const image = { width: 2000, height: 3000 }, viewport = { width: 400, height: 800 };
  let state = { x: 0, y: 0, vx: 1200, vy: -1800 };
  const first = motion.advance(image, viewport, 3, state, 0.016);
  assert.ok(first.x > 0 && first.y < 0);
  state = first;
  for (let i = 0; i < 600 && !state.done; i++) state = motion.advance(image, viewport, 3, state, 0.016);
  assert.equal(state.done, true);
  assert.deepEqual({ x: state.x, y: state.y }, geometry.clamp(image, viewport, 3, state));
  assert.deepEqual(motion.advance(image, viewport, 3, first, 30), motion.advance(image, viewport, 3, first, 0.032));
});
test('edge rubber band is monotonic, bounded and springs back without velocity', () => {
  assert.equal(motion.resistance(60, 100), 60);
  assert.ok(motion.resistance(200, 100) > 100);
  assert.ok(motion.resistance(1e7, 100) < 164);
  assert.equal(motion.resistance(-200, 100), -motion.resistance(200, 100));
  const image = { width: 1000, height: 1000 }, viewport = { width: 400, height: 800 };
  let state = { x: 250, y: 60, vx: 0, vy: 0 };
  for (let i = 0; i < 600 && !state.done; i++) state = motion.advance(image, viewport, 2, state, 0.016);
  assert.equal(state.done, true);
  assert.deepEqual({ x: state.x, y: state.y }, geometry.clamp(image, viewport, 2, state));
});
test('pull close rejects small or upward movements, permits deliberate distance or fast pull', () => {
  assert.equal(motion.dismiss(20, 1500, 800), false);
  assert.equal(motion.dismiss(-200, -1500, 800), false);
  assert.equal(motion.dismiss(60, 1000, 800), true);
  assert.equal(motion.dismiss(150, 0, 800), true);
  assert.equal(motion.dismiss(90, 0, 800), false);
});
test('long reading progress reaches both exact edges and arbitrary middle position', () => {
  const image = { width: 1000, height: 50000 }, viewport = { width: 400, height: 800 };
  const zoom = geometry.widthScale(image, viewport);
  for (const value of [0, 0.25, 0.5, 0.82, 1]) {
    const position = motion.seek(image, viewport, zoom, value);
    assert.ok(Math.abs(motion.progress(image, viewport, zoom, position.y) - value) < 1e-9);
    assert.deepEqual(position, geometry.clamp(image, viewport, zoom, position));
  }
});
test('reading positions retain image identity, scale and source center across viewport rotation', () => {
  const image = { width: 1000, height: 50000 }, viewport = { width: 400, height: 800 };
  const zoom = geometry.widthScale(image, viewport);
  const snapshot = reading.PreviewReadingState.capture('local:alpha', image, viewport, zoom,
    motion.seek(image, viewport, zoom, 0.7), 'width');
  const rotated = { width: 800, height: 400 }, nextZoom = snapshot.zoom(image, rotated, 3);
  const next = snapshot.position(image, rotated, nextZoom);
  const samePoint = reading.PreviewReadingState.capture('local:alpha', image, rotated, nextZoom, next, 'width');
  assert.ok(Math.abs(samePoint.centerY - snapshot.centerY) < 1e-9);
  assert.equal(nextZoom, geometry.widthScale(image, rotated));
  const cache = new reading.PreviewReadingCache();
  cache.put(snapshot);
  cache.put(reading.PreviewReadingState.capture('local:beta', image, viewport, 1, {x: 0, y: 0}, 'screen'));
  assert.equal(cache.get('local:alpha', 1000, 50000).centerY, snapshot.centerY);
  assert.equal(cache.get('local:beta', 1000, 50000).mode, 'screen');
  assert.equal(cache.get('local:alpha', 1000, 1000), undefined);
});
test('reading persistence restores usable models and excludes remote sources and invalid records', () => {
  const cache = new reading.PreviewReadingCache();
  const image = { width: 1600, height: 1200 }, viewport = { width: 400, height: 800 };
  cache.put(reading.PreviewReadingState.capture('local:one', image, viewport, 2, { x: 40, y: 10 }, 'free'));
  cache.put(reading.PreviewReadingState.capture('web:private-url', image, viewport, 2, { x: 0, y: 0 }, 'free'));
  const text = cache.serialize();
  assert.equal(text.includes('private-url'), false);
  const restored = new reading.PreviewReadingCache();
  restored.restore(text);
  const value = restored.get('local:one', 1600, 1200);
  assert.equal(value.zoom(image, viewport, 3), 2);
  assert.ok(Math.abs(value.position(image, viewport, 2).x - 40) < 1e-9);
  assert.equal(value.position(image, viewport, 2).y, 0);
  restored.restore('[null,42,{}, {"key":"local:bad","scale":-1}]');
  assert.equal(restored.get('local:bad', 1, 1), undefined);
  restored.restore('bad-json');
});
test('reading memory evicts older IDs at 100 and never retains image buffers', () => {
  const cache = new reading.PreviewReadingCache();
  for (let i = 0; i <= 100; i++) cache.put(reading.PreviewReadingState.capture('local:' + i,
    { width: 1000, height: 1000 }, { width: 400, height: 800 }, 1, { x: 0, y: 0 }, 'screen'));
  assert.equal(cache.get('local:0', 1000, 1000), undefined);
  assert.ok(cache.get('local:100', 1000, 1000));
  assert.equal(JSON.parse(cache.serialize()).length, 100);
});

test('reading store writes local positions atomically and preserves prior file when a write is partial', () => {
  const files = new Map(), descriptors = new Map();
  let partial = false, next = 0;
  const filesystem = {
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    statSync: name => { if (!files.has(name)) throw Error('missing'); return { size: files.get(name).length }; },
    readTextSync: name => { if (!files.has(name)) throw Error('missing'); return files.get(name); },
    openSync: name => { files.set(name, ''); descriptors.set(++next, name); return { fd: next }; },
    writeSync: (fd, text) => { files.set(descriptors.get(fd), partial ? text.slice(0, 8) : text); return partial ? 8 : text.length; },
    closeSync: file => descriptors.delete(file.fd),
    renameSync: (from, to) => { files.set(to, files.get(from)); files.delete(from); },
    unlinkSync: name => files.delete(name)
  };
  const make = () => loader({ '@kit.CoreFileKit': { fileIo: filesystem } })(path.join(source, 'service/PreviewReadingStore.ets')).PreviewReadingStore;
  const store = make(); store.initialize('/files');
  const snapshot = reading.PreviewReadingState.capture('local:one', {width: 2000, height: 3000},
    {width: 400, height: 800}, 2, {x: 40, y: 20}, 'free');
  store.remember(snapshot); store.flush();
  const original = files.get('/files/preview-reading.json');
  assert.ok(original.includes('local:one'));
  const restarted = make(); restarted.initialize('/files');
  assert.ok(restarted.get('local:one', 2000, 3000));
  partial = true;
  snapshot.centerY = 0.8; store.remember(snapshot); store.flush();
  assert.equal(files.get('/files/preview-reading.json'), original);
  assert.equal(files.has('/files/preview-reading.json.pending'), false);
  partial = false; store.flush();
  assert.equal(JSON.parse(files.get('/files/preview-reading.json'))[0].centerY, 0.8);
  assert.equal(descriptors.size, 0);
  const beforeRemote = files.get('/files/preview-reading.json');
  snapshot.key = 'web:https://private/'; store.remember(snapshot); store.flush();
  assert.equal(files.get('/files/preview-reading.json'), beforeRemote);
});

test('landscape letterboxing cannot be dragged vertically beyond the actual image', () => {
  const image = { width: 1600, height: 900 };
  const viewport = { width: 400, height: 800 };
  assert.deepEqual(geometry.fit(image, viewport), { width: 400, height: 225 });
  assert.deepEqual(geometry.clamp(image, viewport, 2, { x: 999, y: 999 }), { x: 200, y: 0 });
  assert.deepEqual(geometry.clamp(image, viewport, 1, { x: -999, y: 999 }), { x: 0, y: 0 });
});

test('portrait drag bounds are symmetric and based on rendered content', () => {
  const image = { width: 600, height: 1200 };
  const viewport = { width: 400, height: 800 };
  assert.deepEqual(geometry.clamp(image, viewport, 2, { x: -999, y: -999 }), { x: -200, y: -400 });
  assert.deepEqual(geometry.clamp(image, viewport, 2, { x: 999, y: 999 }), { x: 200, y: 400 });
});

test('pinch and double tap keep the selected image point beneath the finger', () => {
  const initial = { x: 20, y: -40 };
  const oldAnchor = { x: 100, y: 200 };
  const nextAnchor = { x: 130, y: 160 };
  const actual = geometry.anchor(initial, 2, 3, oldAnchor, nextAnchor);
  assert.deepEqual(actual, { x: 10, y: -200 });
  assert.equal((oldAnchor.x - initial.x) / 2, (nextAnchor.x - actual.x) / 3);
  assert.equal((oldAnchor.y - initial.y) / 2, (nextAnchor.y - actual.y) / 3);
  assert.deepEqual(geometry.anchor({ x: 0, y: 0 }, 1, 2, oldAnchor, oldAnchor), { x: -100, y: -200 });
});

test('long image fit-width exceeds the normal zoom limit and starts exactly at its top', () => {
  const image = { width: 1000, height: 10000 };
  const viewport = { width: 400, height: 800 };
  const zoom = geometry.widthScale(image, viewport);
  assert.equal(zoom, 5);
  const top = geometry.top(image, viewport, zoom);
  assert.deepEqual(top, { x: 0, y: 1600 });
  assert.equal(viewport.height / 2 + top.y - geometry.fit(image, viewport).height * zoom / 2, 0);
  assert.deepEqual(geometry.clamp(image, viewport, zoom, { x: 300, y: -99999 }), { x: 0, y: -1600 });
});

test('zero-size layout is safe and decoded images respect edge and pixel budgets', () => {
  assert.deepEqual(geometry.fit({ width: 0, height: 0 }, { width: 400, height: 800 }), { width: 0, height: 0 });
  assert.equal(geometry.widthScale({ width: 0, height: 0 }, { width: 400, height: 800 }), 1);
  for (const size of [{ width: 20000, height: 20000 }, { width: 1000, height: 100000 }, { width: 10, height: 10 }]) {
    const decoded = geometry.decodeSize(size, 16384, 12000000);
    assert.ok(Math.max(decoded.width, decoded.height) <= 16384);
    assert.ok(decoded.width * decoded.height <= 12000000);
    assert.ok(decoded.width <= size.width && decoded.height <= size.height);
  }
});

test('zoom decoding requests more original detail with a bounded allocation', () => {
  const original = { width: 6000, height: 4000 };
  const base = geometry.decodeSize(original, 2400, 3000000);
  const detail = geometry.decodeSize(original, 7200, 12000000);
  assert.ok(detail.width > base.width && detail.height > base.height);
  assert.ok(detail.width * detail.height <= 12000000);
});

test('revisiting an image uses its session cache, closing releases every file', async () => {
  const h = previewHarness({ responseCode: 200, result: new ArrayBuffer(10) });
  const a = await h.preview.load('https://image/a', 'https://page/', '/cache');
  await h.preview.load('https://image/b', 'https://page/', '/cache');
  const again = await h.preview.load('https://image/a', 'https://page/', '/cache');
  assert.equal(again.path, a.path);
  assert.equal(h.calls.filter((call) => call.url).length, 2);
  assert.equal(h.files.size, 4);
  h.preview.cancel();
  assert.equal(h.files.size, 0);
});

test('cache never reuses a preview for another source page or login session', async () => {
  const h = previewHarness({ responseCode: 200, result: new ArrayBuffer(10) });
  await h.preview.load('https://image/a', 'https://page/one', '/cache');
  await h.preview.load('https://image/a', 'https://page/two', '/cache');
  h.setCookie('session=changed');
  await h.preview.load('https://image/a', 'https://page/two', '/cache');
  assert.equal(h.calls.filter((call) => call.url).length, 3);
  h.preview.cancel();
});

test('cache enforces five entries with LRU eviction, retaining a recently revisited image', async () => {
  const h = previewHarness({ responseCode: 200, result: new ArrayBuffer(10) });
  const first = await h.preview.load('https://image/0', '', '/cache');
  const second = await h.preview.load('https://image/1', '', '/cache');
  for (let i = 2; i < 5; i++) await h.preview.load('https://image/' + i, '', '/cache');
  await h.preview.load('https://image/0', '', '/cache');
  await h.preview.load('https://image/5', '', '/cache');
  assert.equal(h.files.size, 10);
  assert.ok(h.files.has(first.path));
  assert.ok(!h.files.has(second.path));
  h.preview.cancel();
});

test('cache evicts by combined source and thumbnail bytes before its count limit', async () => {
  const h = previewHarness({ responseCode: 200, result: new ArrayBuffer(32 * 1024 * 1024) }, { thumbnailBytes: 1024 * 1024 });
  for (let i = 0; i < 5; i++) await h.preview.load('https://image/' + i, '', '/cache');
  assert.equal(h.files.size, 6);
  assert.ok([...h.files.values()].reduce((a, b) => a + b, 0) <= 128 * 1024 * 1024);
  h.preview.cancel();
});

test('explicit retry and missing cache files trigger a new request', async () => {
  const h = previewHarness({ responseCode: 200, result: new ArrayBuffer(10) });
  const first = await h.preview.load('https://image/a', '', '/cache');
  const retry = await h.preview.load('https://image/a', '', '/cache', true);
  assert.notEqual(first.path, retry.path);
  h.files.delete(retry.path);
  await h.preview.load('https://image/a', '', '/cache');
  assert.equal(h.calls.filter((call) => call.url).length, 3);
  h.preview.cancel();
});

test('cancellation while decoding prevents cache insertion and cleans temporary files', async () => {
  let resume;
  let decoding;
  const entered = new Promise((resolve) => { decoding = resolve; });
  const h = previewHarness({ responseCode: 200, result: new ArrayBuffer(10) }, {
    decode: () => { decoding(); return new Promise((resolve) => { resume = resolve; }); }
  });
  const pending = h.preview.load('https://image/a', '', '/cache');
  await entered;
  h.preview.cancel();
  resume();
  assert.equal((await pending).uri, '');
  assert.equal(h.files.size, 0);
  assert.deepEqual(h.released.sort(), ['frame', 'source']);
});

test('animated network images explicitly label the preview as a static first frame', async () => {
  const h = previewHarness({ responseCode: 200, result: new ArrayBuffer(10) }, { frames: 5 });
  const result = await h.preview.load('https://image/animation', '', '/cache');
  assert.equal(result.animated, true);
  assert.match(result.message, /静态预览.*首帧/);
  assert.equal(result.width, 4000);
  h.preview.cancel();
});

for (const [name, response, config, expected] of [
  ['redirect', { responseCode: 302, result: new ArrayBuffer(0) }, {}, 'redirect'],
  ['size', () => { throw { code: 2300063 }; }, {}, 'size'],
  ['timeout', () => { throw { code: 2300028 }; }, {}, 'timeout'],
  ['unsupported image', { responseCode: 200, result: new ArrayBuffer(10) }, { badImage: true }, 'decode'],
  ['disk full', { responseCode: 200, result: new ArrayBuffer(10) }, { diskFailure: true }, 'storage'],
  ['partial write', { responseCode: 200, result: new ArrayBuffer(10) }, { partialWrite: true }, 'storage']
]) {
  test('preview distinguishes ' + name + ' and leaves no partial files', async () => {
    const h = previewHarness(response, config);
    const result = await h.preview.load('https://image/a', '', '/cache');
    assert.equal(result.uri, '');
    assert.equal(result.failure, expected);
    assert.equal(h.files.size, 0);
  });
}

// Exercise the real view-model orchestration, with only native/services replaced.
function discoveryPreviewHarness() {
  const mocks = {};
  const filename = path.join(source, 'viewmodel/DiscoverViewModel.ets');
  const text = fs.readFileSync(filename, 'utf8');
  for (const match of text.matchAll(/import \{([^}]+)\} from '([^']+)'/g)) {
    const id = match[2].startsWith('.') ? path.resolve(path.dirname(filename), match[2] + '.ets') : match[2];
    mocks[id] = Object.fromEntries(match[1].split(',').map((name) => [name.trim(), class {}]));
  }
  mocks['@kit.ArkWeb'] = { webview: { WebviewController: class {} } };
  mocks['@kit.CoreFileKit'] = { fileUri: { getUriFromPath: (value) => 'file://' + value } };
  const queued = [];
  const { DownloadAdmission } = loader()(path.join(source, 'service/DownloadAdmission.ets'));
  mocks[path.join(source, 'service/DownloadAdmission.ets')] = { DownloadAdmission };
  mocks[path.join(source, 'service/PictureFilters.ets')] = loader()(path.join(source, 'service/PictureFilters.ets'));
  const existingFiles = new Set();
  const store = { downloads: [], exists: (file) => existingFiles.has(file),
    add: (pictures, url, title, zip, allowCompleted = false) => {
      const plan = DownloadAdmission.plan(pictures, store.downloads, store.exists, allowCompleted);
      if (plan.result.added > 0) {
        queued.push([plan.items, url, title, zip, allowCompleted]);
        for (const picture of plan.items) {
          store.downloads.push({ url: picture.url, kind: picture.kind, status: 'queued', path: '' });
        }
      }
      return plan.result;
    } };
  mocks[path.join(source, 'service/DownloadStore.ets')] = { DownloadStore: store };
  const local = { value: undefined };
  mocks[path.join(source, 'service/LocalPreview.ets')] = { LocalPreview: { find: () => local.value } };
  mocks[path.join(source, 'service/LibraryCatalog.ets')] = { LIBRARY_CATALOG: {
    assetForPreview: (items) => items[0]?.id ?? ''
  } };
  mocks[path.join(source, 'service/SizeArbiter.ets')] = { SizeArbiter: { measure: async () => 42 } };
  mocks[path.join(source, 'service/PictureFactory.ets')] = {
    PictureFactory: { fromUrl: (url) => ({ url, selected: true }) }
  };
  const VM = loader(mocks)(filename).DiscoverViewModel;
  const vm = new VM();
  const pending = [];
  const cancellations = [];
  vm.ui = { context: () => ({ cacheDir: '/cache' }), say: () => {} };
  vm.preview = {
    load: (url, referer, cacheDir, force, progress) => new Promise((resolve) => pending.push({ url, referer, cacheDir, force, progress, resolve })),
    cancelRequest: () => cancellations.push('request'), cancel: () => cancellations.push('session')
  };
  vm.pageUrl = 'https://page/';
  vm.pageTitle = 'Pictures';
  vm.pictures = [
    { uid: 'a', url: 'https://image/a', kind: 'image', selected: false, name: 'a.png', width: 0, height: 0 },
    { uid: 'b', url: 'https://image/b', kind: 'image', selected: true, name: 'b.png', width: 0, height: 0 }
  ];
  return { vm, pending, cancellations, queued, store, local, existingFiles };
}

test('discovery tools use the same surviving local copy as the preview', () => {
  const h = discoveryPreviewHarness();
  const picture = h.vm.pictures[0];
  h.store.downloads.push(
    { id: 'new', url: picture.url, kind: 'image', status: 'completed', path: '/missing.png', finishedAt: 2 },
    { id: 'old', url: picture.url, kind: 'image', status: 'completed', path: '/valid.png', finishedAt: 1 }
  );
  h.local.value = { path: '/valid.png', size: 120, stillPath: '', motionPath: '', animated: false };
  const asset = h.vm.previewAsset(picture);
  assert.equal(asset.localPath, '/valid.png');
  assert.equal(asset.src, 'file:///valid.png');
  assert.equal(asset.libraryId, 'old');
  assert.equal(asset.bytes, 120);
  assert.equal(asset.downloadedAt, 1);
});

test('discovery ignores late preview results, preserves visited cache on navigation, and clears on close', async () => {
  const h = discoveryPreviewHarness();
  h.vm.inspect('a');
  h.vm.inspect('b');
  h.pending[0].resolve({ uri: 'old', path: '/old', width: 999, height: 999, message: '', failure: '' });
  await Promise.resolve();
  assert.equal(h.vm.previewUri, '');
  assert.equal(h.vm.pictures[0].width, 0);
  h.pending[1].resolve({ uri: 'current', path: '/current', width: 200, height: 300, message: 'preview', failure: '' });
  await Promise.resolve();
  assert.equal(h.vm.previewUri, 'current');
  assert.equal(h.vm.previewLocalPath, '/current');
  assert.equal(h.vm.pictures[1].width, 200);
  assert.ok(!h.cancellations.includes('session'));
  h.vm.closeInspection();
  assert.equal(h.cancellations.at(-1), 'session');
  assert.equal(h.vm.previewLocalPath, '');
});

test('discovery retry forwards force-refresh and exposes the actionable failure type', async () => {
  const h = discoveryPreviewHarness();
  h.vm.inspect('a', true);
  assert.equal(h.pending[0].force, true);
  h.pending[0].resolve({ uri: '', path: '', width: 0, height: 0, message: 'too large', failure: 'size' });
  await Promise.resolve();
  assert.equal(h.vm.previewFailure, 'size');
  assert.equal(h.vm.previewLoading, false);
  assert.equal(h.vm.pictures[0].selected, false);
});

test('background suspension cancels pending discovery and ignores late results without clearing visited cache', async () => {
  const h = discoveryPreviewHarness();
  h.vm.inspect('a');
  h.vm.suspendInspection();
  assert.equal(h.vm.previewLoading, false);
  assert.equal(h.vm.inspectedUid, 'a');
  assert.equal(h.cancellations.at(-1), 'request');
  h.pending[0].resolve({ uri: 'late', path: '/late', width: 999, height: 999, message: '', failure: '' });
  await Promise.resolve();
  assert.equal(h.vm.previewUri, '');
  h.vm.inspect('a');
  h.pending[1].resolve({ uri: 'resumed', path: '/resumed', width: 200, height: 300, message: '', failure: '' });
  await Promise.resolve();
  h.vm.suspendInspection();
  assert.equal(h.vm.previewUri, 'resumed');
  assert.equal(h.vm.previewLocalPath, '/resumed');
  assert.equal(h.cancellations.includes('session'), false);
});

test('single-image recovery download does not change existing selections or ZIP mode', () => {
  const h = discoveryPreviewHarness();
  h.vm.mode = 'zip';
  h.vm.inspectedUid = 'a';
  h.vm.downloadInspected();
  h.vm.downloadInspected();
  assert.equal(h.queued.length, 1);
  assert.equal(h.queued[0][0].length, 1);
  assert.equal(h.queued[0][0][0].url, 'https://image/a');
  assert.equal(h.queued[0][0][0].selected, true);
  assert.equal(h.queued[0][3], false);
  assert.deepEqual(h.vm.pictures.map((item) => item.selected), [false, true]);
  assert.equal(h.vm.mode, 'zip');
});

test('hiding a page stops scanning without destroying its open animated preview', async () => {
  const h = discoveryPreviewHarness();
  let scansStopped = 0, expansionsStopped = 0;
  h.vm.scanner = { invalidate: () => scansStopped++ };
  h.vm.expansion = { stop: () => expansionsStopped++ };
  h.vm.inspect('a');
  h.pending[0].resolve({ uri: 'file:///animation.gif', path: '/animation.gif', animated: true,
    width: 100, height: 100, message: '', failure: '' });
  await Promise.resolve();
  h.vm.scanning = true;
  h.vm.expanding = true;
  h.vm.cancelScan(true);
  assert.equal(scansStopped, 1);
  assert.equal(expansionsStopped, 1);
  assert.equal(h.vm.scanning, false);
  assert.equal(h.vm.expanding, false);
  assert.equal(h.vm.inspectedUid, 'a');
  assert.equal(h.vm.previewUri, 'file:///animation.gif');
  assert.equal(h.vm.previewLocalPath, '/animation.gif');
  assert.equal(h.vm.previewLocalAnimated, true);
  assert.equal(h.cancellations.includes('session'), false);
  h.vm.cancelScan();
  assert.equal(h.vm.inspectedUid, '');
  assert.equal(h.vm.previewUri, '');
  assert.equal(h.cancellations.at(-1), 'session');
});

test('single-image recovery reuses an already pending download instead of duplicating it', () => {
  const h = discoveryPreviewHarness();
  h.vm.inspectedUid = 'a';
  h.store.downloads.push({ url: 'https://image/a', kind: 'image', status: 'running' });
  h.vm.downloadInspected();
  assert.equal(h.queued.length, 0);
  assert.equal(h.vm.previewDownloadQueued, true);
});

test('local preview prefers an existing completed copy of the exact image URL', () => {
  const files = new Map([['/old.png', 120], ['/new.png', 240]]);
  const load = loader({ '@kit.CoreFileKit': { fileIo: { statSync: (path) => {
    if (!files.has(path)) throw new Error('missing');
    return { isFile: () => true, size: files.get(path) };
  } } } });
  const { LocalPreview } = load(path.join(source, 'service/LocalPreview.ets'));
  const records = [
    { url: 'https://image.test/a.png', kind: 'image', status: 'completed', path: '/new.png' },
    { url: 'https://image.test/a.png', kind: 'image', status: 'completed', path: '/missing.png' },
    { url: 'https://image.test/a.png', kind: 'image', status: 'running', path: '/new.png' },
    { url: 'https://image.test/a.png?other=1', kind: 'image', status: 'completed', path: '/new.png' },
    { url: 'https://image.test/a.png', kind: 'image', status: 'completed', path: '/old.png' }
  ];
  assert.deepEqual(LocalPreview.find('https://image.test/a.png', 'image', records),
    { path: '/new.png', size: 240, stillPath: '', motionPath: '', animated: false });
  files.delete('/new.png');
  assert.deepEqual(LocalPreview.find('https://image.test/a.png', 'image', records),
    { path: '/old.png', size: 120, stillPath: '', motionPath: '', animated: false });
  files.delete('/old.png');
  assert.equal(LocalPreview.find('https://image.test/a.png', 'image', records), undefined);
});

test('local preview uses a live photo cover only when its local file exists', () => {
  const files = new Map([['/photo.livp', 500], ['/cover.jpg', 50], ['/motion.mov', 300]]);
  const load = loader({ '@kit.CoreFileKit': { fileIo: { statSync: (path) => {
    if (!files.has(path)) throw new Error('missing');
    return { isFile: () => true, size: files.get(path) };
  } } } });
  const { LocalPreview } = load(path.join(source, 'service/LocalPreview.ets'));
  const records = [{ url: 'https://image.test/photo.livp', kind: 'livephoto',
    status: 'completed', path: '/photo.livp', stillPath: '/cover.jpg', motionPath: '/motion.mov' }];
  assert.deepEqual(LocalPreview.find(records[0].url, 'livephoto', records),
    { path: '/photo.livp', size: 500, stillPath: '/cover.jpg', motionPath: '/motion.mov', animated: false });
  files.delete('/motion.mov');
  assert.deepEqual(LocalPreview.find(records[0].url, 'livephoto', records),
    { path: '/photo.livp', size: 500, stillPath: '/cover.jpg', motionPath: '', animated: false });
  files.delete('/cover.jpg');
  assert.deepEqual(LocalPreview.find(records[0].url, 'livephoto', records),
    { path: '/photo.livp', size: 500, stillPath: '', motionPath: '', animated: false });
  files.set('/older.livp', 400);
  files.set('/older.jpg', 40);
  records.push({ url: records[0].url, kind: 'livephoto', status: 'completed',
    path: '/older.livp', stillPath: '/older.jpg', motionPath: '' });
  assert.deepEqual(LocalPreview.find(records[0].url, 'livephoto', records),
    { path: '/older.livp', size: 400, stillPath: '/older.jpg', motionPath: '', animated: false });
});

function deliveryHarness(save) {
  const load = loader({
    [path.join(source, 'service/FileActions.ets')]: {
      saveImagesToGallery: save,
      copyIntoDirectory: async () => ({ ok: false, message: '目录授权失效，请重新选择目录' })
    }
  });
  const { Delivery, DeliveryTarget } = load(path.join(source, 'service/Delivery.ets'));
  const { DownloadItem } = load(path.join(source, 'model/Models.ets'));
  const delivery = new Delivery();
  const target = new DeliveryTarget();
  target.location = 'gallery';
  delivery.target = () => target;
  delivery.context = () => ({});
  delivery.alive = () => true;
  const item = new DownloadItem();
  item.id = 'one'; item.path = '/images/one.png'; item.name = 'one.png'; item.status = 'completed';
  return { delivery, item, target };
}

test('partial Live Photo save retries only its unsaved video', async () => {
  const requests = [];
  const harness = deliveryHarness(async (_context, paths, _names, _active, onSaved) => {
    requests.push(paths.slice());
    onSaved([paths[0]], false);
    return { ok: requests.length === 2, cancelled: requests.length === 1,
      message: 'fixture', savedCount: 1, remainingCount: requests.length === 1 ? 1 : 0 };
  });
  const { delivery, item } = harness;
  item.kind = 'livephoto'; item.stillPath = '/still.jpg'; item.motionPath = '/motion.mov';
  await delivery.deliver(item);
  await new Promise((resolve) => setTimeout(resolve, 850));
  assert.equal(item.status, 'completed');
  assert.equal(item.receipt.status, 'cancelled');
  assert.deepEqual(item.receipt.parts, ['still']);
  await delivery.deliver(item, true);
  await new Promise((resolve) => setTimeout(resolve, 850));
  assert.deepEqual(requests, [['/still.jpg', '/motion.mov'], ['/motion.mov']]);
  assert.equal(item.receipt.status, 'saved');
  assert.ok(item.receipt.message.includes('分别保存'));
  delivery.stop();
});

test('gallery confirmation is deferred while the app is in background', async () => {
  let dialogs = 0;
  const { delivery, item } = deliveryHarness(async (_context, paths, _names, _active, onSaved) => {
    dialogs++; onSaved(paths, false); return { ok: true, message: '' };
  });
  delivery.setForeground(false);
  await delivery.deliver(item);
  await new Promise((resolve) => setTimeout(resolve, 850));
  assert.equal(dialogs, 0);
  assert.equal(item.receipt.status, 'pending');
  delivery.setForeground(true);
  await new Promise((resolve) => setTimeout(resolve, 850));
  assert.equal(dialogs, 1);
  assert.equal(item.receipt.status, 'saved');
  delivery.stop();
});

test('external save failure never changes a completed download into failed', async () => {
  const { delivery, item, target } = deliveryHarness(async () => ({ ok: false, message: '' }));
  target.location = 'custom'; target.folderUri = 'file://docs/expired';
  await delivery.deliver(item);
  assert.equal(item.status, 'completed');
  assert.equal(item.receipt.status, 'failed');
  assert.ok(item.receipt.message.includes('原件仍保留'));
  assert.ok(item.receipt.message.includes('重新选择目录'));
});

function recoveryHarness(show) {
  const states = { RUNNING: 1, WAITING: 2, PAUSED: 3, COMPLETED: 4, FAILED: 5, STOPPED: 6, RETRYING: 7 };
  const mocks = {
    '@kit.BasicServicesKit': { request: { agent: { State: states, show } } },
    '@kit.CoreFileKit': { fileIo: {} },
    '@kit.ArkWeb': { webview: {} },
    '@kit.ArkTS': { util: {} },
    '@kit.ImageKit': { image: {} },
    [path.join(source, 'service/EditJournal.ets')]: { EditJournal: { recover: async () => {} } },
    [path.join(source, 'service/LibraryCatalog.ets')]: { LIBRARY_CATALOG: {} },
    [path.join(source, 'service/Delivery.ets')]: { Delivery: class {} },
    [path.join(source, 'service/GripSensor.ets')]: {},
    [path.join(source, 'service/AntiPeep.ets')]: {},
    [path.join(source, 'service/FileActions.ets')]: {},
    [path.join(source, 'service/LivePhoto.ets')]: {},
    [path.join(source, 'service/StillFrames.ets')]: {},
    [path.join(source, 'widget/WidgetForms.ets')]: {},
    [path.join(source, 'widget/WidgetSnapshot.ets')]: {}
  };
  const load = loader(mocks);
  const { DownloadStore } = load(path.join(source, 'service/DownloadStore.ets'));
  const { DownloadItem } = load(path.join(source, 'model/Models.ets'));
  const item = new DownloadItem();
  item.id = 'task'; item.taskId = 'native-task'; item.status = 'running';
  DownloadStore.notify = () => {};
  DownloadStore.initialized = true;
  DownloadStore.foreground = true;
  DownloadStore.downloads = [item];
  return { store: DownloadStore, item, states };
}

test('foreground refresh observes waiting and running without progress events', async () => {
  let state = 2;
  const { store, item } = recoveryHarness(async () => ({ progress: { state, processed: 42, sizes: [100] } }));
  item.speedBps = 5;
  await store.refreshAgentStates();
  assert.equal(item.status, 'waiting');
  assert.equal(item.speedBps, 0);
  assert.equal(item.processed, 42);
  state = 1;
  await store.refreshAgentStates();
  assert.equal(item.status, 'running');
});

test('state refresh does not override a manual pause', async () => {
  const { store, item } = recoveryHarness(async () => ({ progress: { state: 1, processed: 42, sizes: [100] } }));
  item.status = 'paused';
  await store.refreshAgentStates();
  assert.equal(item.status, 'paused');
});

test('late state query cannot resurrect a cancelled download', async () => {
  let resolveInfo;
  const { store, item } = recoveryHarness(() => new Promise((resolve) => { resolveInfo = resolve; }));
  const work = store.refreshAgentStates();
  item.status = 'cancelled';
  resolveInfo({ progress: { state: 1, processed: 42, sizes: [100] } });
  await work;
  assert.equal(item.status, 'cancelled');
  assert.equal(item.processed, 0);
});

test('temporary status-query failure preserves the native task for the next refresh', async () => {
  const { store, item } = recoveryHarness(async () => { throw new Error('service temporarily unavailable'); });
  await store.refreshAgentStates();
  assert.equal(item.status, 'running');
  assert.equal(item.taskId, 'native-task');
  assert.equal(store.refreshing, false);
});

test('resume succeeds when a running callback arrives before resume resolves', async () => {
  const { store, item } = recoveryHarness(async () => ({}));
  item.status = 'paused';
  store.active.set(item.id, { tid: item.taskId, resume: async () => { item.status = 'running'; } });
  assert.equal(await store.resume(item), true);
  assert.equal(item.status, 'running');
  assert.equal(item.recoveryMessage, '正在确认继续位置');
});


const previewNavigation = loader()(path.join(source, 'util/PreviewNavigation.ets')).PreviewNavigation;
test('preview selection filtering preserves order, current identity, and advances after deselection', () => {
  const all = ['a', 'b', 'c', 'd'];
  const selected = previewNavigation.selected(all, ['d', 'b', 'c']);
  assert.deepEqual(selected, ['b', 'c', 'd']);
  assert.equal(previewNavigation.index(selected, 'c', 2), 1);
  assert.equal(previewNavigation.index(['b', 'd'], 'c', 1), 1);
  assert.equal(previewNavigation.index(['b'], 'd', 1), 0);
  assert.equal(previewNavigation.index([], 'b', 0), 0);
});

test('page jumps reject empty, fractional, negative, out-of-range and unsafe values', () => {
  for (const input of ['', '0', '-1', '1.5', '4', '1e0', '9007199254740993']) {
    assert.equal(previewNavigation.jump(input, 3), -1, input);
  }
  assert.equal(previewNavigation.jump(' 3 ', 3), 2);
  assert.equal(previewNavigation.jump('1', 0), -1);
});

test('download admission skips active and saved files, but permits an explicit new copy', () => {
  const { DownloadAdmission } = loader()(path.join(source, 'service/DownloadAdmission.ets'));
  const pictures = [
    { url: 'https://image/a?sig=1', kind: 'image', selected: true },
    { url: 'https://image/a?sig=1', kind: 'image', selected: true },
    { url: 'https://image/b', kind: 'image', selected: true },
    { url: 'https://image/c', kind: 'livephoto', selected: true },
    { url: 'https://image/a?sig=2', kind: 'image', selected: true }
  ];
  const downloads = [
    { url: 'https://image/a?sig=1', kind: 'image', status: 'completed', path: '/a' },
    { url: 'https://image/b', kind: 'image', status: 'running', path: '/b' },
    { url: 'https://image/c', kind: 'livephoto', status: 'completed', path: '/missing' }
  ];
  const exists = (file) => file === '/a';
  const normal = DownloadAdmission.plan(pictures, downloads, exists);
  assert.equal(DownloadAdmission.presence('https://image/c', 'livephoto', downloads, exists), 'new');
  assert.equal(DownloadAdmission.presence('https://image/a?sig=1', 'livephoto', downloads, exists), 'new');
  assert.deepEqual(normal.items.map((item) => item.url), ['https://image/c', 'https://image/a?sig=2']);
  assert.equal(normal.result.skippedCompleted, 1);
  assert.equal(normal.result.skippedActive, 1);
  assert.equal(normal.result.skippedRepeated, 1);
  const repeated = DownloadAdmission.plan(pictures, downloads, exists, true);
  assert.equal(repeated.result.added, 3);
  assert.equal(repeated.result.skippedActive, 1);
});

test('discovery shows saved state, filters new results, and confirms a new copy', () => {
  const h = discoveryPreviewHarness();
  let confirmAction;
  h.vm.ui.confirm = (_title, _message, _confirm, action) => { confirmAction = action; };
  h.store.downloads.push({ url: 'https://image/a', kind: 'image', status: 'completed', path: '/saved' });
  h.existingFiles.add('/saved');
  h.vm.syncDownloads();
  assert.equal(h.vm.downloadState(h.vm.pictures[0]), 'completed');
  h.vm.onlyNew = true;
  assert.deepEqual(h.vm.visiblePictures.map((item) => item.uid), ['b']);
  h.vm.filterText = 'a.png';
  assert.deepEqual(h.vm.visiblePictures.map((item) => item.uid), []);
  h.vm.clearFilters();
  assert.deepEqual(h.vm.visiblePictures.map((item) => item.uid), ['a', 'b']);
  h.vm.inspectedUid = 'a';
  h.vm.requestInspectedDownload();
  assert.equal(h.queued.length, 0);
  assert.equal(typeof confirmAction, 'function');
  confirmAction();
  assert.equal(h.queued.length, 1);
  assert.equal(h.queued[0][4], true);
  assert.equal(h.queued[0][0][0].url, 'https://image/a');
});

test('discovery does not create an empty ZIP when every selected picture is saved', () => {
  const h = discoveryPreviewHarness();
  h.vm.pictures[0].selected = true;
  h.vm.pictures[1].selected = false;
  h.vm.mode = 'zip';
  h.store.downloads.push({ url: 'https://image/a', kind: 'image', status: 'completed', path: '/saved' });
  h.existingFiles.add('/saved');
  h.vm.syncDownloads();
  assert.equal(h.vm.eligibleSelectedCount(), 0);
  h.vm.enqueue();
  assert.equal(h.queued.length, 0);
});

test('preview bulk download keeps selections and ZIP mode, limits scope and skips pending duplicates', () => {
  const h = discoveryPreviewHarness();
  h.vm.mode = 'zip';
  h.vm.pictures[0].selected = true;
  h.vm.pictures.push({ uid: 'c', url: 'https://image/c', kind: 'image', selected: true, name: 'c.png' });
  h.store.downloads.push({ url: 'https://image/a', kind: 'image', status: 'running' });
  h.vm.downloadPreviewSelection(['a', 'b']);
  assert.equal(h.queued.length, 1);
  assert.deepEqual(h.queued[0][0].map((item) => item.url), ['https://image/b']);
  assert.equal(h.queued[0][3], true);
  assert.deepEqual(h.vm.pictures.map((item) => item.selected), [true, true, true]);
  assert.equal(h.vm.mode, 'zip');
  h.store.downloads.push({ url: 'https://image/b', kind: 'image', status: 'queued' });
  h.vm.downloadPreviewSelection(['a', 'b']);
  assert.equal(h.queued.length, 1);
});

test('completed local original supersedes in-flight preview and ignores late metadata', async () => {
  const h = discoveryPreviewHarness();
  h.vm.inspect('a');
  h.local.value = { path: '/original.png', size: 1234, stillPath: '', motionPath: '', animated: false };
  h.vm.refreshLocalPreview();
  assert.equal(h.vm.inspectedPicture.uid, 'a');
  assert.equal(h.vm.previewUri, 'file:///original.png');
  assert.equal(h.vm.previewFromLocal, true);
  assert.equal(h.vm.previewLoading, false);
  assert.equal(h.vm.inspectionBytes, 1234);
  h.pending[0].resolve({ uri: 'remote', path: '/cache', width: 20, height: 10, failure: '', message: 'remote' });
  await Promise.resolve();
  assert.equal(h.vm.previewUri, 'file:///original.png');
  assert.equal(h.vm.inspectionBytes, 1234);
  const before = h.cancellations.length;
  h.vm.refreshLocalPreview();
  assert.equal(h.cancellations.length, before);
});

test('download failure restores the preview download action and closing ignores store changes', () => {
  const h = discoveryPreviewHarness();
  h.vm.inspectedUid = 'a';
  h.store.downloads.push({ url: 'https://image/a', kind: 'image', status: 'running' });
  h.vm.refreshLocalPreview();
  assert.equal(h.vm.previewDownloadQueued, true);
  h.store.downloads[0].status = 'failed';
  h.vm.refreshLocalPreview();
  assert.equal(h.vm.previewDownloadQueued, false);
  h.vm.closeInspection();
  h.local.value = { path: '/late.png', size: 8, stillPath: '', motionPath: '', animated: false };
  h.vm.refreshLocalPreview();
  assert.equal(h.vm.previewUri, '');
});

test('Weibo live photo previews its still image before download and plays a complete local pair', async () => {
  const h = discoveryPreviewHarness();
  h.vm.pictures[0].kind = 'livephoto';
  h.vm.pictures[0].motionUrl = 'https://video.test/motion.mov';
  h.vm.inspect('a');
  assert.equal(h.pending.length, 1);
  assert.equal(h.pending[0].url, 'https://image/a');
  h.pending[0].resolve({ uri: 'file:///cache/still.png', path: '/cache/still.png',
    width: 200, height: 300, failure: '', message: 'ready', animated: false });
  await Promise.resolve();
  assert.equal(h.vm.previewUri, 'file:///cache/still.png');
  assert.equal(h.vm.previewMotionPath, '');
  h.local.value = { path: '/photo.livp', size: 500, stillPath: '/cover.jpg',
    motionPath: '/motion.mov', animated: false };
  h.vm.refreshLocalPreview();
  assert.equal(h.vm.previewUri, 'file:///cover.jpg');
  assert.equal(h.vm.previewMotionPath, '/motion.mov');
  assert.equal(h.vm.previewFromLocal, true);
});

test('old live photo packages without a cover fall back to the remote still image', () => {
  const h = discoveryPreviewHarness();
  h.vm.pictures[0].kind = 'livephoto';
  h.vm.pictures[0].motionUrl = 'https://video.test/motion.mov';
  h.local.value = { path: '/old.livp', size: 500, stillPath: '', motionPath: '', animated: false };
  h.vm.inspect('a');
  assert.equal(h.pending.length, 1);
  assert.equal(h.vm.previewFromLocal, false);
  assert.equal(h.vm.previewMotionPath, '');
});

test('Weibo preview downloads preserve the motion URL for single and selected downloads', () => {
  const h = discoveryPreviewHarness();
  h.vm.pictures[0].kind = 'livephoto';
  h.vm.pictures[0].motionUrl = 'https://video.test/motion.mov';
  h.vm.pictures[0].selected = true;
  h.vm.inspect('a');
  h.vm.downloadInspected();
  assert.equal(h.queued[0][0][0].motionUrl, 'https://video.test/motion.mov');
  h.vm.downloadPreviewSelection(['a']);
  assert.equal(h.queued.length, 1);
  const selected = discoveryPreviewHarness();
  selected.vm.pictures[0].kind = 'livephoto';
  selected.vm.pictures[0].motionUrl = 'https://video.test/motion.mov';
  selected.vm.pictures[0].selected = true;
  selected.vm.downloadPreviewSelection(['a']);
  assert.equal(selected.queued[0][0][0].motionUrl, 'https://video.test/motion.mov');
});


test('native pixel viewing accounts for display density and small originals', () => {
  assert.equal(geometry.nativeScale({ width: 1200, height: 2400 }, { width: 400, height: 800 }, 3), 1);
  assert.equal(geometry.nativeScale({ width: 100, height: 100 }, { width: 400, height: 800 }, 2), 0.125);
  assert.equal(geometry.nativeScale({ width: 4000, height: 8000 }, { width: 400, height: 800 }, 2), 5);
  assert.deepEqual(geometry.anchor({ x: 0, y: 0 }, 0.5, 1, { x: 10, y: 20 }, { x: 10, y: 20 }), { x: -10, y: -20 });
});

test('visible-region decoding covers the viewport at long-image top, middle and bottom', () => {
  const image = { width: 1000, height: 50000 };
  const viewport = { width: 400, height: 800 };
  const zoom = geometry.widthScale(image, viewport);
  const fitted = geometry.fit(image, viewport);
  for (const requested of [-1e9, 0, 1e9]) {
    const position = geometry.clamp(image, viewport, zoom, { x: 0, y: requested });
    const region = geometry.visibleRegion(image, viewport, zoom, position);
    const unit = fitted.width * zoom / image.width;
    const top = viewport.height / 2 + position.y - fitted.height * zoom / 2;
    assert.ok(region.y >= 0 && region.y + region.height <= image.height);
    assert.equal(region.x, 0);
    assert.equal(region.width, image.width);
    assert.ok(top + region.y * unit <= 0.001);
    assert.ok(top + (region.y + region.height) * unit >= viewport.height - 0.001);
    assert.ok(region.height < image.height / 10);
    const decode = geometry.decodeSize(region, 8192, 8000000);
    assert.ok(decode.width * decode.height <= 8000000);
  }
});

test('system back dismisses comparison, tools and navigation before the image browser', () => {
  const State = loader()(path.join(source, 'model/PreviewOverlayState.ets')).PreviewOverlayState;
  const state = new State();
  state.tools = state.comparison = state.navigation = true;
  assert.equal(state.dismissTop(), true);
  assert.equal(state.comparison, false);
  assert.equal(state.tools, true);
  assert.equal(state.dismissTop(), true);
  assert.equal(state.tools, false);
  assert.equal(state.dismissTop(), true);
  assert.equal(state.dismissTop(), false);
  state.tools = true;
  state.reset();
  assert.equal(state.dismissTop(), false);
});

function imageToolsHarness(config = {}) {
  const events = [];
  const files = new Map();
  const descriptors = new Map();
  let serial = 0;
  const sourceMock = () => ({
    getImageInfo: async () => ({ size: { width: 2000, height: 1000 }, mimeType: 'image/png', isHdr: config.hdr === true }),
    createPixelMap: async (options) => {
      events.push(['decode', options]);
      if (config.decodeFail) throw new Error('decode failure');
      return { release: async () => events.push('frame.release') };
    },
    release: async () => events.push('source.release')
  });
  const mocks = {
    canIUse: () => config.supported !== false,
    '@kit.AbilityKit': {},
    '@kit.ImageKit': { image: {
      PixelMapFormat: { RGBA_8888: 3 }, createImageSource: sourceMock,
      createImagePacker: () => ({ packToFile: async (_frame, fd) => {
        files.set(descriptors.get(fd), config.emptyOutput ? 0 : 8);
      }, release: async () => events.push('packer.release') })
    } },
    '@kit.CoreFileKit': { fileUri: { getUriFromPath: (path) => 'file://' + path }, fileIo: {
      OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
      statSync: (path) => ({ size: files.has(path) ? files.get(path) : 123 }),
      openSync: (path) => { const fd = ++serial; descriptors.set(fd, path); files.set(path, 0); return { fd }; },
      writeSync: (fd, bytes) => { files.set(descriptors.get(fd), bytes.byteLength); return config.shortWrite ? 1 : bytes.byteLength; },
      closeSync: (file) => { descriptors.delete(file.fd); },
      unlinkSync: (path) => { events.push(['delete', path]); files.delete(path); }
    } },
    '@kit.CoreVisionKit': { textRecognition: {
      init: async () => { events.push('ocr.init'); return true; },
      recognizeText: async () => {
        events.push('ocr.recognize');
        if (config.ocrFail) throw new Error('OCR failure');
        return { value: '识别文字' };
      },
      release: async () => events.push('ocr.release')
    } },
    '@kit.ScanKit': { detectBarcode: { decode: async (input, options) => {
      events.push(['scan', input.uri]);
      if (config.scanFail) throw new Error('scan failure');
      const results = [{ originalValue: 'https://example.com' }, { originalValue: 'plain text' }, { originalValue: 'https://example.com' }];
      return options?.enableMultiMode ? results : results.slice(0, 1);
    } } },
    [path.join(source, 'service/Clipboard.ets')]: { Clipboard: { writeText: async (value) => events.push(['copy', value]) } },
    [path.join(source, 'service/FileActions.ets')]: { exportFile: async (_context, path, name) => {
      assert.ok(files.has(path)); events.push(['export', name]);
      if (config.saveError) throw new Error('destination failure');
      return config.saveOutcome ?? { ok: false, message: '' };
    }, saveImageToGallery: async (_context, path, name) => {
      assert.ok(files.has(path)); events.push(['album', name]);
      if (config.saveError) throw new Error('destination failure');
      return config.saveOutcome ?? { ok: false, message: '' };
    } }
  };
  const ImageTools = loader(mocks)(path.join(source, 'service/ImageTools.ets')).ImageTools;
  return { ImageTools, events, files, descriptors };
}

test('preview rotation restores the original preference before the next preview enters', async () => {
  let preference = 0;
  const changes = [];
  const target = {
    getPreferredOrientation: () => preference,
    setPreferredOrientation: async (value) => { preference = value; changes.push(value); }
  };
  const PreviewOrientation = loader({
    '@kit.AbilityKit': {},
    '@kit.ArkUI': { window: {
      Orientation: { UNSPECIFIED: 0, AUTO_ROTATION_RESTRICTED: 8 },
      getLastWindow: async () => target
    } }
  })(path.join(source, 'service/PreviewOrientation.ets')).PreviewOrientation;
  const first = new PreviewOrientation();
  const second = new PreviewOrientation();
  first.enter({});
  first.leave();
  second.enter({});
  second.leave();
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(changes, [8, 0, 8, 0]);
  assert.equal(preference, 0);
});

test('image details use codec metadata, and OCR serializes init-recognize-release lifetimes', async () => {
  const h = imageToolsHarness();
  assert.deepEqual({ ...await h.ImageTools.metadata('/a') }, { width: 2000, height: 1000, bytes: 123, format: 'image/png', isHdr: false });
  assert.deepEqual(await Promise.all([h.ImageTools.text('/a'), h.ImageTools.text('/b')]), ['识别文字', '识别文字']);
  assert.deepEqual(h.events.filter((value) => typeof value === 'string' && value.startsWith('ocr.')),
    ['ocr.init', 'ocr.recognize', 'ocr.release', 'ocr.init', 'ocr.recognize', 'ocr.release']);
  assert.equal(h.events.filter((value) => value === 'source.release').length, 3);
  assert.equal(h.events.filter((value) => value === 'frame.release').length, 2);
});

test('HDR sources are reported in the details metadata', async () => {
  const h = imageToolsHarness({ hdr: true });
  assert.equal((await h.ImageTools.metadata('/a')).isHdr, true);
});

test('OCR releases resources after failure and reports unsupported capability without decoding', async () => {
  const h = imageToolsHarness({ ocrFail: true });
  await assert.rejects(h.ImageTools.text('/a'));
  assert.ok(h.events.includes('ocr.release'));
  assert.ok(h.events.includes('source.release'));
  assert.ok(h.events.includes('frame.release'));
  const unavailable = imageToolsHarness({ supported: false });
  await assert.rejects(unavailable.ImageTools.text('/a'), /不支持文字识别/);
  await assert.rejects(unavailable.ImageTools.codes('/a', '/cache'), /不支持二维码识别/);
  assert.deepEqual(unavailable.events, []);
});

test('QR results are deduplicated, temporary PNG is removed, and links never open automatically', async () => {
  const h = imageToolsHarness();
  assert.deepEqual(await h.ImageTools.codes('/a', '/cache'), ['https://example.com', 'plain text']);
  assert.equal(h.files.size, 0);
  assert.equal(h.descriptors.size, 0);
  for (const value of ['javascript:alert(1)', 'file:///etc/passwd', 'data:text/html,hi', 'https://a b']) {
    assert.equal(h.ImageTools.link(value), '');
  }
  const opened = [];
  await assert.rejects(h.ImageTools.open({ openLink: async (url) => opened.push(url) }, 'javascript:alert(1)'));
  assert.deepEqual(opened, []);
  await h.ImageTools.open({ openLink: async (url) => opened.push(url) }, 'https://example.com');
  assert.deepEqual(opened, ['https://example.com']);
  await h.ImageTools.copy('full\ntext');
  assert.deepEqual(h.events.at(-1), ['copy', 'full\ntext']);
});

test('QR errors, empty codec output and cancelled frame export leave no temporary files', async () => {
  for (const config of [{ scanFail: true }, { emptyOutput: true }]) {
    const h = imageToolsHarness(config);
    await assert.rejects(h.ImageTools.codes('/a', '/cache'));
    assert.equal(h.files.size, 0);
    assert.equal(h.descriptors.size, 0);
    assert.ok(h.events.includes('frame.release'));
    assert.ok(h.events.includes('source.release'));
    assert.ok(h.events.includes('packer.release'));
  }
  const h = imageToolsHarness();
  await h.ImageTools.saveFrame({ cacheDir: '/cache' }, '/animation', 'clip.gif', 7);
  assert.equal(h.events.find((value) => Array.isArray(value) && value[0] === 'decode')[1].index, 7);
  assert.deepEqual(h.events.find((value) => Array.isArray(value) && value[0] === 'export'), ['export', 'clip-第8帧.png']);
  assert.equal(h.files.size, 0);
});

test('frame saving selects album or folder and preserves the requested frame and PNG filename', async () => {
  for (const [destination, event, message] of [
    [undefined, 'export', '已保存当前帧到文件夹'],
    ['folder', 'export', '已保存当前帧到文件夹'],
    ['album', 'album', '已保存当前帧到相册']
  ]) {
    const h = imageToolsHarness({ saveOutcome: { ok: true, message: 'saved' } });
    const result = await h.ImageTools.saveFrame({ cacheDir: '/cache' }, '/animation', 'clip:test.webp', 2, destination);
    assert.equal(result.ok, true);
    assert.equal(result.message, message);
    assert.equal(h.events.find((value) => Array.isArray(value) && value[0] === 'decode')[1].index, 2);
    assert.deepEqual(h.events.filter((value) => Array.isArray(value) && ['export', 'album'].includes(value[0])),
      [[event, 'clip_test-第3帧.png']]);
    assert.equal(h.files.size, 0);
    assert.equal(h.descriptors.size, 0);
  }
});

test('frame saving cancels silently and cleans up on destination failure for both destinations', async () => {
  for (const destination of ['album', 'folder']) {
    for (const saveOutcome of [
      { ok: false, cancelled: true, message: '已取消保存到系统相册' },
      { ok: false, message: '' },
      { ok: false, message: 'destination unavailable' }
    ]) {
      const h = imageToolsHarness({ saveOutcome });
      const result = await h.ImageTools.saveFrame({ cacheDir: '/cache' }, '/animation', 'clip.gif', 1, destination);
      assert.equal(result.ok, false);
      assert.equal(result.message, saveOutcome.cancelled ? '' : saveOutcome.message);
      if (saveOutcome.cancelled) assert.equal(result.cancelled, true);
      assert.equal(h.files.size, 0);
      assert.equal(h.descriptors.size, 0);
      for (const released of ['frame.release', 'source.release', 'packer.release']) assert.ok(h.events.includes(released));
    }
    for (const config of [{ saveError: true }, { decodeFail: true }, { emptyOutput: true }]) {
      const h = imageToolsHarness(config);
      await assert.rejects(h.ImageTools.saveFrame({ cacheDir: '/cache' }, '/animation', 'clip.gif', 1, destination));
      assert.equal(h.files.size, 0);
      assert.equal(h.descriptors.size, 0);
      assert.ok(h.events.includes('source.release'));
      assert.ok(h.events.includes('packer.release'));
      if (!config.decodeFail) assert.ok(h.events.includes('frame.release'));
    }
  }
});

function animationHarness(gate) {
  const events = [];
  let resident = 0, peak = 0;
  const load = loader({ '@kit.ImageKit': { image: {
    AlphaType: { OPAQUE: 0 },
    createImageSource: () => ({
      getImageInfo: async () => ({ size: { width: 4000, height: 2000 }, alphaType: 0 }),
      getFrameCount: async () => 1000,
      getDelayTimeList: async () => [20, 20, 20],
      createPixelMap: async (options) => {
        events.push(['decode', options.index]);
        assert.ok(options.desiredSize.width * options.desiredSize.height <= 4000000);
        if (gate) await gate(options.index);
        resident++; peak = Math.max(peak, resident);
        return { release: async () => { resident--; events.push('frame.release'); } };
      },
      release: async () => events.push('source.release')
    })
  } } });
  const Playback = load(path.join(source, 'service/AnimationPlayback.ets')).AnimationPlayback;
  return { session: new Playback(), events, resident: () => resident, peak: () => peak };
}

test('animation pauses on the displayed frame, resumes, and keeps at most two decoded frames', async () => {
  const h = animationHarness();
  let firstReady;
  const first = new Promise((resolve) => { firstReady = resolve; });
  const indexes = [];
  const run = h.session.run('/animation', (_frame, info) => {
    indexes.push(info.index);
    if (info.index === 0) { h.session.pause(); firstReady(); }
    else { h.session.stop(); }
  }, () => assert.fail('unexpected decode failure'));
  await first;
  assert.deepEqual(indexes, [0]);
  assert.equal(h.events.filter((value) => Array.isArray(value)).length, 1);
  h.session.resume();
  await run;
  assert.deepEqual(indexes, [0, 1]);
  assert.equal(h.resident(), 0);
  assert.ok(h.peak() <= 2);
  assert.ok(h.events.includes('source.release'));
});

test('stopping an animation during decode suppresses late frames and releases native resources', async () => {
  let decoding, release;
  const started = new Promise((resolve) => { decoding = resolve; });
  const gate = new Promise((resolve) => { release = resolve; });
  const h = animationHarness(async () => { decoding(); await gate; });
  const frames = [];
  const run = h.session.run('/animation', (_frame, info) => frames.push(info.index), () => assert.fail('cancel is not error'));
  await started;
  h.session.stop();
  release();
  await run;
  assert.deepEqual(frames, []);
  assert.equal(h.resident(), 0);
  assert.ok(h.events.includes('source.release'));
});

test('animation reconstruction restores the visible frame and manual pause before resuming', async () => {
  const h = animationHarness();
  h.session.pause();
  let ready;
  const first = new Promise(resolve => { ready = resolve; });
  const indexes = [];
  const run = h.session.run('/animation', (_frame, info) => {
    indexes.push(info.index);
    if (indexes.length === 1) ready();
    else h.session.stop();
  }, () => assert.fail('unexpected restore error'), 7);
  await first;
  await new Promise(resolve => setTimeout(resolve, 60));
  assert.deepEqual(indexes, [7]);
  assert.equal(h.events.filter(value => Array.isArray(value)).length, 1);
  h.session.resume();
  await run;
  assert.deepEqual(indexes, [7, 8]);
  assert.equal(h.resident(), 0);
});


test('comparison preview sessions use separate files even when created in the same millisecond', async () => {
  const h = previewHarness({ responseCode: 200, result: new ArrayBuffer(10) });
  const reference = h.createPreview();
  const now = Date.now;
  Date.now = () => 123456;
  try {
    const primary = await h.preview.load('https://image/a', 'https://page/', '/cache');
    const secondary = await reference.load('https://image/b', 'https://page/', '/cache');
    assert.notEqual(primary.path, secondary.path);
    reference.cancel();
    assert.ok(h.files.has(primary.path));
    assert.ok(!h.files.has(secondary.path));
    h.preview.cancel();
    assert.equal(h.files.size, 0);
  } finally { Date.now = now; }
});

test('preview falls back to its session source when ZIP packaging removes the downloaded file', () => {
  const h = discoveryPreviewHarness();
  h.vm.inspectedUid = 'a';
  h.vm.previewFromLocal = true;
  h.vm.previewLocalPath = '/removed.png';
  h.vm.refreshLocalPreview();
  assert.equal(h.vm.previewFromLocal, false);
  assert.equal(h.pending.length, 1);
  assert.equal(h.pending[0].url, 'https://image/a');
  assert.equal(h.vm.inspectedPicture.uid, 'a');
});


test('preview cancellation freezes progress, ignores late completion and retry starts afresh', async () => {
  const h = discoveryPreviewHarness();
  h.vm.inspect('a');
  h.pending[0].progress({ phase: 'receiving', received: 400, total: 1000 });
  assert.equal(h.vm.previewPercent, 40);
  h.vm.cancelPreviewLoading();
  assert.equal(h.vm.previewFailure, 'cancelled');
  assert.equal(h.vm.previewLoading, false);
  h.pending[0].progress({ phase: 'ready', received: 1000, total: 1000 });
  h.pending[0].resolve({ uri: 'late', path: '/late', width: 20, height: 20, message: '', failure: '' });
  await Promise.resolve();
  assert.equal(h.vm.previewPhase, 'cancelled');
  assert.equal(h.vm.previewReceived, 400);
  assert.equal(h.vm.previewUri, '');
  h.vm.inspect('a', true);
  assert.equal(h.vm.previewReceived, 0);
  assert.equal(h.vm.previewTotal, 0);
  assert.equal(h.vm.previewPhase, 'connecting');
  h.pending[1].resolve({ uri: 'new', path: '/new', width: 20, height: 20, message: '', failure: '' });
  await Promise.resolve();
  assert.equal(h.vm.previewPhase, 'ready');
});

function thumbnailHarness(config = {}) {
  const files = new Map([['/long.png', 100]]);
  const descriptors = new Map();
  const calls = [];
  let fd = 0;
  const load = loader({
    '@kit.ArkWeb': { webview: { WebCookieManager: { fetchCookieSync: () => config.cookie || '' } } },
    '@kit.CoreFileKit': { fileUri: { getUriFromPath: p => 'file://' + p,
      FileUri: class { constructor(uri) { this.path = uri.slice(7); } } },
      fileIo: { OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
        statSync: p => { if (!files.has(p)) throw Error('missing'); return { size: files.get(p), mtime: 1 }; },
        mkdirSync: () => {}, listFileSync: () => [], unlinkSync: p => files.delete(p),
        openSync: p => { descriptors.set(++fd, p); files.set(p, 0); return { fd }; }, closeSync: () => {} } },
    '@kit.ImageKit': { image: { CropAndScaleStrategy: { CROP_FIRST: 1 },
      createImageSource: p => ({ getImageInfo: async () => ({ size: config.size || { width: 1000, height: 50000 } }),
        createPixelMap: async options => { calls.push(options); if (config.decode) await config.decode(); return { release: async () => {} }; },
        release: async () => {} }),
      createImagePacker: () => ({ packToFile: async (_frame, fd) => files.set(descriptors.get(fd), 1000), release: async () => {} }) } },
    [path.join(source, 'service/PreviewTransfer.ets')]: { PreviewTransfer: class {
      async run(url, referer, cookie, raw, _progress, redirectLimit) { calls.push({url, referer, cookie, redirectLimit}); files.set(raw, 200); return { code: 200, bytes: 200, failure: '' }; }
      cancel() { calls.push('cancel'); }
    } }
  });
  const mod = load(path.join(source, 'service/ThumbnailImages.ets'));
  return { ...mod, files, calls };
}

test('long thumbnail crops at native geometry before scaling and never distorts an unknown local file', async () => {
  const h = thumbnailHarness();
  const result = await h.ThumbnailImages.load('file:///long.png', '/cache', 1, false, new h.ThumbnailRequest());
  assert.ok(result.uri.endsWith('.png'));
  assert.deepEqual({ width: result.width, height: result.height }, { width: 1000, height: 50000 });
  assert.deepEqual(h.calls[0].desiredRegion, { x: 0, y: 24500, size: { width: 1000, height: 1000 } });
  assert.deepEqual(h.calls[0].desiredSize, { width: 512, height: 512 });
  assert.equal(h.calls[0].cropAndScaleStrategy, 1);
  assert.equal(h.files.get('/long.png'), 100, 'original remains untouched');
});

test('batch thumbnails use their source and image-domain cookies without forwarding credentials through redirects', async () => {
  const h = thumbnailHarness({ cookie: 'image_session=fixture' });
  await h.ThumbnailImages.load('https://cdn.test/a.jpg', '/cache', 1, false,
    new h.ThumbnailRequest(), 'https://page.test/post');
  assert.deepEqual(h.calls[0], { url: 'https://cdn.test/a.jpg', referer: 'https://page.test/post',
    cookie: 'image_session=fixture', redirectLimit: 0 });
});

test('thumbnail cache returns original dimensions without decoding again', async () => {
  const h = thumbnailHarness({ size: { width: 3000, height: 2000 } });
  const first = await h.ThumbnailImages.load('file:///long.png', '/cache', 1, false, new h.ThumbnailRequest());
  const cached = await h.ThumbnailImages.load('file:///long.png', '/cache', 1, false, new h.ThumbnailRequest());
  assert.deepEqual(cached, first);
  assert.deepEqual({ width: cached.width, height: cached.height }, { width: 3000, height: 2000 });
  assert.equal(h.calls.length, 1);
});

test('thumbnail crop follows rectangular cells while contain preserves the original aspect', async () => {
  const h = thumbnailHarness({ size: { width: 3000, height: 2000 } });
  await h.ThumbnailImages.load('file:///long.png', '/cache', 2, false, new h.ThumbnailRequest());
  assert.deepEqual(h.calls[0].desiredRegion, { x: 0, y: 250, size: { width: 3000, height: 1500 } });
  assert.deepEqual(h.calls[0].desiredSize, { width: 512, height: 256 });
  await h.ThumbnailImages.load('file:///long.png', '/cache', 2, true, new h.ThumbnailRequest());
  assert.deepEqual(h.calls[1].desiredRegion.size, { width: 3000, height: 2000 });
  assert.ok(Math.abs(h.calls[1].desiredSize.width / h.calls[1].desiredSize.height - 1.5) < .01);
});

test('shared thumbnail work survives one consumer leaving and discards output if everyone leaves', async () => {
  let finish;
  const h = thumbnailHarness({ decode: () => new Promise(resolve => { finish = resolve; }) });
  const a = new h.ThumbnailRequest(), b = new h.ThumbnailRequest();
  const first = h.ThumbnailImages.load('https://image/a', '/cache', 1, false, a);
  const second = h.ThumbnailImages.load('https://image/a', '/cache', 1, false, b);
  while (!finish) await Promise.resolve();
  a.cancel(); finish();
  assert.deepEqual(await first, new h.ThumbnailResult());
  const completed = await second;
  assert.ok(completed.uri.endsWith('.png'));
  assert.deepEqual({ width: completed.width, height: completed.height }, { width: 1000, height: 50000 });
  assert.equal(h.calls.filter(x => x.url).length, 1);
  assert.deepEqual(h.calls[0], {url: 'https://image/a', referer: '', cookie: '', redirectLimit: 5});
  assert.ok(![...h.files.keys()].some(p => p.endsWith('.source')));
  finish = undefined;
  const c = new h.ThumbnailRequest();
  const third = h.ThumbnailImages.load('https://image/b', '/cache', 1, false, c);
  while (!finish) await Promise.resolve();
  c.cancel(); finish();
  assert.deepEqual(await third, new h.ThumbnailResult());
  assert.equal(h.files.size, 2, 'only original and earlier completed thumbnail remain');
});
