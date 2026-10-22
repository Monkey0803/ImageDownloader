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
    new Function('require', 'exports', 'module', 'ObservedV2', 'Trace', output)(
      localRequire, module.exports, module, (value) => value, () => {});
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
      assertFalse: () => assert.equal(value, false)
    })
  }
});
for (const name of ['PageExpansion', 'SaveReceipt', 'GalleryBatching', 'BatchView']) {
  fixtureLoad(path.join(root, 'entry/src/ohosTest/ets/test/' + name + '.test.ets')).default();
}

function previewHarness(response) {
  const calls = [];
  const deleted = [];
  const released = [];
  const nativeRequest = {
    destroy: () => calls.push('destroy'),
    request: async (url, options) => {
      calls.push({ url, options });
      return typeof response === 'function' ? response() : response;
    }
  };
  const load = loader({
    '@kit.NetworkKit': { http: { createHttp: () => nativeRequest,
      RequestMethod: { GET: 'GET' }, HttpDataType: { ARRAY_BUFFER: 2 } } },
    '@kit.ArkWeb': { webview: { WebCookieManager: { fetchCookieSync: () => 'session=test' } } },
    '@kit.CoreFileKit': {
      fileUri: { getUriFromPath: (value) => 'file://' + value },
      fileIo: { OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
        openSync: () => ({ fd: 1 }), closeSync: () => {}, unlinkSync: (value) => deleted.push(value) }
    },
    '@kit.ImageKit': { image: {
      createImageSource: () => ({ getImageInfo: async () => ({ size: { width: 4000, height: 2000 } }),
        createPixelMap: async (options) => {
          assert.deepEqual(options.desiredSize, { width: 1200, height: 600 });
          return { release: async () => released.push('frame') };
        }, release: async () => released.push('source') }),
      createImagePacker: () => ({ packToFile: async () => {}, release: async () => released.push('packer') })
    } }
  });
  return { preview: new (load(path.join(source, 'service/AuthenticatedPreview.ets')).AuthenticatedPreview)(),
    calls, deleted, released };
}

test('preview sends page credentials only to the requested URL and bounds memory', async () => {
  const harness = previewHarness({ responseCode: 200, result: new ArrayBuffer(10) });
  const result = await harness.preview.load('https://image.test/a.png', 'https://page.test/', '/cache');
  assert.ok(result.uri.startsWith('file:///cache/inspection-preview-'));
  const request = harness.calls.find((entry) => typeof entry === 'object');
  assert.deepEqual(request.options.header, { Cookie: 'session=test', Referer: 'https://page.test/' });
  assert.equal(request.options.maxRedirects, 0);
  assert.equal(request.options.maxLimit, 8 * 1024 * 1024);
  assert.equal(request.options.usingCache, false);
  assert.deepEqual(harness.released.sort(), ['frame', 'packer', 'source']);
  harness.preview.cancel();
  assert.ok(harness.deleted.includes(result.uri.substring('file://'.length)));
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
