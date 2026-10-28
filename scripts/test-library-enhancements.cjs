#!/usr/bin/env node
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { test } = require('node:test');
const { loader } = require('./lib/arkts-test-loader.cjs');
const source = path.resolve(__dirname, '../entry/src/main/ets');
const ets = name => path.join(source, name + '.ets');
const filterArg = process.argv.find(value => value.startsWith('--filter='));
const filter = filterArg ? filterArg.slice('--filter='.length) : '';
const caseTest = (name, run) => { if (!filter || name.includes(filter)) test(name, run); };
const load = loader();

function visionHarness(config = {}) {
  const events = [];
  let active = 0;
  let maxActive = 0;
  const frame = { release: async () => events.push('frame.release') };
  const mocks = {
    canIUse: () => true,
    '@kit.AbilityKit': {},
    '@kit.ImageKit': { image: { PixelMapFormat: { RGBA_8888: 3 },
      createImageSource: () => ({
        getImageInfo: async () => ({ size: { width: 16, height: 12 }, mimeType: 'image/png' }),
        createPixelMap: async () => frame,
        release: async () => events.push('source.release')
      }) } },
    '@kit.CoreFileKit': { fileUri: {}, fileIo: { statSync: () => ({ size: 100 }) } },
    '@kit.ScanKit': { detectBarcode: {} },
    '@kit.CoreVisionKit': { textRecognition: {
      init: async () => { events.push('init'); active++; maxActive = Math.max(maxActive, active); return config.initFalse !== true; },
      recognizeText: async () => { events.push('recognize'); await new Promise(resolve => setImmediate(resolve));
        if (config.fail) throw new Error('recognition failed');
        return { value: 'Alpha', blocks: [{ lines: [{ value: 'Alpha', cornerPoints: [
          { x: 2, y: 3 }, { x: 10, y: 3 }, { x: 10, y: 7 }, { x: 2, y: 7 }
        ] }] }] }; },
      release: async () => { events.push('release'); active--; }
    } },
    [ets('service/Clipboard')]: { Clipboard: {} },
    [ets('service/FileActions')]: { exportFile: async () => ({ ok: false }) }
  };
  const tools = loader(mocks)(ets('service/ImageTools')).ImageTools;
  return { tools, events, frame, maxActiveEngines: () => maxActive, activeEngines: () => active };
}

caseTest('OCR preview and index share one native engine and convert SDK line bounds', async () => {
  const h = visionHarness();
  const [text, lines] = await Promise.all([
    h.tools.text('/a.png'), h.tools.withTextEngine(() => h.tools.textLines(h.frame))
  ]);
  assert.equal(text, 'Alpha');
  assert.deepEqual(lines.map(line => [line.text, line.x, line.y, line.width, line.height]),
    [['Alpha', 2, 3, 8, 4]]);
  assert.equal(h.maxActiveEngines(), 1);
  assert.equal(h.activeEngines(), 0);
  assert.equal(h.events.filter(x => x === 'init').length, h.events.filter(x => x === 'release').length);
});

caseTest('OCR failure and unavailable init release resources and preserve queue', async () => {
  const failed = visionHarness({ fail: true });
  await assert.rejects(failed.tools.text('/a.png'));
  assert.deepEqual(failed.events.filter(x => x === 'release'), ['release']);
  assert.ok(failed.events.includes('frame.release'));
  assert.ok(failed.events.includes('source.release'));
  const unavailable = visionHarness({ initFalse: true });
  await assert.rejects(unavailable.tools.withTextEngine(() => unavailable.tools.textLines(unavailable.frame)), /暂不可用/);
  assert.equal(unavailable.events.filter(x => x === 'recognize').length, 0);
  assert.equal(unavailable.events.filter(x => x === 'release').length, 1);
  const cancelled = visionHarness();
  await assert.rejects(cancelled.tools.withTextEngine(async () => {
    throw new Error('cancelled');
  }), /cancelled/);
  assert.equal(cancelled.events.filter(x => x === 'release').length, 1);
});

function imageReaderHarness(options = {}) {
  const events = [];
  const alphaType = options.alphaType ?? 2;
  const pixelFormat = options.pixelFormat ?? 3;
  const frame = {
    getImageInfo: async () => ({ size: { width: options.width ?? 2,
      height: options.height ?? 1 }, pixelFormat, alphaType }),
    getBytesNumberPerRow: () => options.stride ?? 8,
    getPixelBytesNumber: () => (options.stride ?? 8) * (options.height ?? 1),
    readPixelsToBuffer: async buffer => { new Uint8Array(buffer).set(options.bytes || [128, 0, 0, 128, 0, 0, 64, 64]); },
    release: async () => events.push('frame.release'),
    rotate: async angle => { events.push(['rotate', angle]); if (options.rotateFail) throw new Error('rotate failed'); },
    flip: async (horizontal, vertical) => events.push(['flip', horizontal, vertical])
  };
  const mocks = {
    '@kit.ImageKit': { image: {
      PixelMapFormat: { RGBA_8888: 3, BGRA_8888: 4 }, AlphaType: { OPAQUE: 1, PREMUL: 2, UNPREMUL: 3 },
      PropertyKey: { ORIENTATION: 'Orientation' }, CropAndScaleStrategy: { CROP_FIRST: 1 },
      createImageSource: target => { events.push(['source', target]); return {
        getImageInfo: async () => ({ size: { width: 20, height: 10 }, mimeType: 'image/jpeg' }),
        getImageProperty: async () => String(options.orientation ?? 1),
        createPixelMap: async config => { events.push(['decode', config]); return frame; },
        release: async () => events.push('source.release')
      }; }
    } },
    '@kit.CoreFileKit': { fileIo: {
      accessSync: () => true,
      statSync: () => ({ size: 100, mtime: 5, ctime: 6 })
    } }
  };
  const reader = loader(mocks)(ets('service/LibraryImageReader')).LibraryImageReader;
  return { reader, events, frame };
}

caseTest('reader selects live still, normalizes orientation and releases source', async () => {
  const { DownloadItem } = load(ets('model/Models'));
  const item = new DownloadItem();
  item.id = 'live'; item.path = '/album/a.livp'; item.stillPath = '/album/a.jpg'; item.kind = 'livephoto';
  const h = imageReaderHarness({ orientation: 6 });
  const stamp = await h.reader.stamp(item);
  assert.equal(stamp.path, '/album/a.jpg');
  assert.equal(stamp.orientation, 6);
  assert.deepEqual([stamp.bytes, stamp.modified, stamp.changed], [100, 5, 6]);
  const info = await h.reader.info(stamp);
  assert.deepEqual([info.width, info.height], [10, 20]);
  assert.equal(h.events.filter(x => x === 'source.release').length, 2);
});

caseTest('reader converts actual BGRA premultiplied pixels to nonpremultiplied RGBA', async () => {
  const h = imageReaderHarness({ pixelFormat: 4, alphaType: 2,
    bytes: [0, 0, 128, 128, 64, 0, 0, 64] });
  const rgba = await h.reader.rgba(h.frame);
  assert.deepEqual([...rgba], [255, 0, 0, 128, 0, 0, 255, 64]);
});

caseTest('reader skips pixel row padding instead of treating it as an image pixel', async () => {
  const h = imageReaderHarness({ width: 1, height: 2, stride: 8, alphaType: 3,
    bytes: [1, 2, 3, 255, 9, 9, 9, 9, 4, 5, 6, 255, 9, 9, 9, 9] });
  assert.deepEqual([...await h.reader.rgba(h.frame)], [1, 2, 3, 255, 4, 5, 6, 255]);
});

caseTest('reader inverts displayed crop into encoded coordinates and applies EXIF once', async () => {
  const { AssetStamp } = load(ets('model/LibraryAsset'));
  const { EditRect, PreviewSize } = load(ets('model/ImageEditDocument'));
  const stamp = new AssetStamp(); stamp.path = '/a.jpg'; stamp.orientation = 6;
  const rect = new EditRect(); rect.x = 2; rect.y = 4; rect.width = 3; rect.height = 5;
  const target = new PreviewSize(); target.width = 6; target.height = 10;
  const h = imageReaderHarness();
  const frame = await h.reader.decode(stamp, rect, target, true);
  assert.equal(frame, h.frame);
  const decode = h.events.find(x => Array.isArray(x) && x[0] === 'decode')[1];
  assert.deepEqual({ ...decode.desiredRegion }, { x: 4, y: 5,
    size: { width: 5, height: 3 } });
  assert.deepEqual({ ...decode.desiredSize }, { width: 10, height: 6 });
  assert.equal(decode.cropAndScaleStrategy, 1);
  assert.deepEqual(h.events.filter(x => Array.isArray(x) && x[0] === 'rotate'), [['rotate', 90]]);
  assert.equal(h.events.filter(x => x === 'source.release').length, 1);
  assert.equal(h.events.filter(x => x === 'frame.release').length, 0);
});

caseTest('reader releases source and frame if orientation transform fails', async () => {
  const { AssetStamp } = load(ets('model/LibraryAsset'));
  const { EditRect, PreviewSize } = load(ets('model/ImageEditDocument'));
  const stamp = new AssetStamp(); stamp.path = '/a.jpg'; stamp.orientation = 6;
  const rect = new EditRect(); rect.width = 10; rect.height = 20;
  const size = new PreviewSize(); size.width = 10; size.height = 20;
  const h = imageReaderHarness({ rotateFail: true });
  await assert.rejects(h.reader.decode(stamp, rect, size, false), /rotate failed/);
  assert.equal(h.events.filter(x => x === 'source.release').length, 1);
  assert.equal(h.events.filter(x => x === 'frame.release').length, 1);
});

caseTest('OCR tiles cover a long image with bounded dimensions and edge overlap', () => {
  const { LibraryText } = load(ets('util/LibraryText'));
  const tiles = LibraryText.tiles(5000, 4500);
  assert.ok(tiles.length > 4);
  for (const tile of tiles) {
    assert.ok(tile.width > 0 && tile.width <= 2048);
    assert.ok(tile.height > 0 && tile.height <= 2048);
  }
  for (const y of [0, 1023, 2047, 4000, 4499]) {
    for (const x of [0, 1023, 2047, 3500, 4999]) {
      assert.ok(tiles.some(t => x >= t.x && x < t.x + t.width &&
        y >= t.y && y < t.y + t.height), `uncovered ${x},${y}`);
    }
  }
  assert.ok(tiles.some(t => t.x + t.width === 5000 && t.y + t.height === 4500));
  assert.deepEqual(LibraryText.tiles(2049, 1).map(t => [t.x, t.width]),
    [[0, 2048], [1920, 129]]);
});

caseTest('OCR line merger removes seam duplicates but keeps repeated text elsewhere', () => {
  const { LibraryText } = load(ets('util/LibraryText'));
  const { RecognizedLine } = load(ets('model/LibraryAsset'));
  const line = (text, x, y) => { const value = new RecognizedLine();
    value.text = text; value.x = x; value.y = y; value.width = 100; value.height = 20;
    return value; };
  const merged = LibraryText.mergeLines([
    line('章 节', 10, 1900), line('章节', 13, 1902),
    line('第二行', 10, 1950), line('章节', 10, 2700)
  ]);
  assert.equal(merged, '章 节\n第二行\n章节');
});

function analysisHarness(config = {}) {
  const base = catalogHarness();
  const { AssetStamp, AnalysisToken } = load(ets('model/LibraryAsset'));
  const token = new AnalysisToken();
  let resolveRecognition;
  let recognizing;
  const recognizingPromise = new Promise(resolve => { recognizing = resolve; });
  let visible = [];
  const events = [];
  let recognitionCount = 0;
  let resolveRgba;
  let sampling;
  const samplingPromise = new Promise(resolve => { sampling = resolve; });
  const frame = { release: async () => events.push('frame.release') };
  const reader = {
    stamp: async item => {
      const file = base.files.get(item.path);
      const stamp = new AssetStamp(); stamp.id = item.id; stamp.path = item.path;
      stamp.sourceKind = item.kind; stamp.bytes = file.data.length;
      stamp.modified = file.mtime; stamp.changed = file.ctime; stamp.orientation = 1;
      return stamp;
    },
    info: async () => ({ width: config.width ?? 20, height: 10 }),
    decode: async () => { events.push('decode'); return frame; },
    rgba: async () => { if (config.pauseRgba) {
      sampling(); return new Promise(resolve => { resolveRgba = resolve; });
    } return solidRgba(100, 120, 140); }
  };
  const textEngine = { withTextEngine: async operation => {
    if (config.serviceUnavailable) throw new Error('service unavailable');
    return operation();
  },
    textLines: async () => { recognitionCount++;
      if (config.rejectSecond && recognitionCount > 1) throw new Error('second tile should not decode');
      recognizing(); return new Promise(resolve => { resolveRecognition = resolve; }); } };
  const analysis = loader({
    [ets('service/LibraryCatalog')]: { LIBRARY_CATALOG: base.catalog },
    [ets('service/LibraryImageReader')]: { LibraryImageReader: reader },
    [ets('service/ImageTools')]: { ImageTools: textEngine }
  })(ets('service/LibraryAnalysis')).LibraryAnalysis;
  return {
    ...base, token, events, analysis,
    seedAssets: async ids => { visible = await base.seedAssets(ids); return visible; },
    visibleIds: () => visible.map(item => item.id),
    decodeCount: () => events.filter(value => value === 'decode').length,
    removeAsset: async id => { visible = visible.filter(item => item.id !== id); await base.catalog.reconcile(visible); },
    changeFile: async id => { base.changedFile(id, 'replacement-' + id, 2); await base.catalog.reconcile(visible); },
    waitUntilRecognizing: () => recognizingPromise,
    waitUntilSampling: () => samplingPromise,
    finishSampling: () => resolveRgba(solidRgba(100, 120, 140)),
    finishRecognition: value => resolveRecognition([{ text: value, x: 1, y: 1, width: 10, height: 4 }])
  };
}

caseTest('OCR unavailable service stops before processing every image', async () => {
  const h = analysisHarness({ serviceUnavailable: true });
  await h.catalog.initialize('/files');
  const items = await h.seedAssets(['a', 'b']);
  const progress = [];
  await h.analysis.ocr(items, false, h.token, value => progress.push(value));
  assert.equal(h.decodeCount(), 0);
  assert.equal(progress.at(-1).done, 0);
  assert.equal(progress.at(-1).failed, 0);
  assert.match(progress.at(-1).message, /系统文字识别服务不可用.*service unavailable/);
  assert.equal(h.catalog.getIndex('a'), undefined);
  assert.equal(h.catalog.getIndex('b'), undefined);
});

caseTest('OCR cancellation cannot overwrite new tags or resurrect a deleted asset', async () => {
  const h = analysisHarness();
  await h.catalog.initialize('/files');
  const items = await h.seedAssets(['a']);
  const running = h.analysis.ocr(items, false, h.token, () => {});
  await h.waitUntilRecognizing();
  await h.catalog.changeTags(['a'], ['新标签'], []);
  await h.removeAsset('a'); h.token.cancel(); h.finishRecognition('OLDTEXT');
  await running;
  assert.equal(h.catalog.getIndex('a'), undefined);
  assert.deepEqual(h.visibleIds(), []);
  assert.equal(h.events.filter(x => x === 'frame.release').length, 1);
});

caseTest('OCR stores completed local text and preserves a concurrent tag edit', async () => {
  const h = analysisHarness();
  await h.catalog.initialize('/files');
  const items = await h.seedAssets(['a']);
  const progress = [];
  const running = h.analysis.ocr(items, false, h.token, value => progress.push(value));
  await h.waitUntilRecognizing();
  await h.catalog.changeTags(['a'], ['票据'], []);
  h.finishRecognition('INVOICE 42');
  await running;
  assert.equal(h.catalog.getIndex('a').text, 'INVOICE 42');
  assert.equal(h.catalog.getIndex('a').ocrStatus, 'ready');
  assert.deepEqual(h.catalog.getMeta('a').tags, ['票据']);
  assert.equal(progress.at(-1).success, 1);
  assert.equal(h.events.filter(x => x === 'frame.release').length, 1);
});

caseTest('OCR rechecks a ready index after same-size same-mtime replacement', async () => {
  const h = analysisHarness();
  await h.catalog.initialize('/files');
  const items = await h.seedAssets(['a']);
  assert.equal(await h.catalog.putIndex(indexed('a', 7, 1, 'OLD')), true);
  h.changedFile('a', 'new-a!!', 1, 2);
  await h.catalog.reconcile(items);
  const running = h.analysis.ocr(items, false, h.token, () => {});
  await h.waitUntilRecognizing();
  h.finishRecognition('NEW');
  await running;
  assert.equal(h.decodeCount(), 1);
  assert.equal(h.catalog.getIndex('a')?.text, 'NEW');
});

caseTest('OCR rejects changed source after recognition without persisting stale text', async () => {
  const h = analysisHarness();
  await h.catalog.initialize('/files');
  const items = await h.seedAssets(['a']);
  const running = h.analysis.ocr(items, false, h.token, () => {});
  await h.waitUntilRecognizing();
  h.changedFile('a', 'replacement-image', 2);
  h.finishRecognition('OLD INVOICE');
  await running;
  assert.notEqual(h.catalog.getIndex('a')?.text, 'OLD INVOICE');
});

caseTest('OCR stops before a second tile when source changed during the first tile', async () => {
  const h = analysisHarness({ width: 3000, rejectSecond: true });
  await h.catalog.initialize('/files');
  const items = await h.seedAssets(['a']);
  const running = h.analysis.ocr(items, false, h.token, () => {});
  await h.waitUntilRecognizing();
  h.changedFile('a', 'replacement-image', 2);
  h.finishRecognition('OLD');
  await running;
  assert.equal(h.events.filter(x => x === 'frame.release').length, 1);
  assert.notEqual(h.catalog.getIndex('a')?.text, 'OLD');
});

caseTest('similar scan reuses valid features and recomputes a changed file', async () => {
  const h = analysisHarness();
  await h.catalog.initialize('/files');
  const items = await h.seedAssets(['a', 'b']);
  const firstGroups = await h.analysis.similar(items, h.token, () => {});
  assert.deepEqual(firstGroups.map(group => group.ids), [['a', 'b']]);
  const first = h.decodeCount();
  assert.equal(first, 2);
  await h.analysis.similar(items, h.token, () => {});
  assert.equal(h.decodeCount(), first);
  await h.catalog.clearText(['a']);
  await h.analysis.similar(items, h.token, () => {});
  assert.equal(h.decodeCount(), first);
  await h.changeFile('b');
  await h.analysis.similar(items, h.token, () => {});
  assert.equal(h.decodeCount(), first + 1);
});

caseTest('similar scan recomputes a malformed cached feature', async () => {
  const h = analysisHarness();
  await h.catalog.initialize('/files');
  const items = await h.seedAssets(['a']);
  await h.analysis.similar(items, h.token, () => {});
  const first = h.decodeCount();
  const index = h.catalog.getIndex('a');
  index.feature.lowBits = 'broken';
  assert.equal(await h.catalog.putIndex(index), true);
  await h.analysis.similar(items, h.token, () => {});
  assert.equal(h.decodeCount(), first + 1);
});

caseTest('similar cancellation releases the decoded frame without persisting a late feature', async () => {
  const h = analysisHarness({ pauseRgba: true });
  await h.catalog.initialize('/files');
  const items = await h.seedAssets(['a']);
  const pending = h.analysis.similar(items, h.token, () => {});
  await h.waitUntilSampling();
  h.token.cancel(); h.finishSampling();
  assert.deepEqual(await pending, []);
  assert.equal(h.catalog.getIndex('a'), undefined);
  assert.equal(h.events.filter(x => x === 'frame.release').length, 1);
});

caseTest('similar scan discards a paused feature after the source file is replaced', async () => {
  const h = analysisHarness({ pauseRgba: true });
  await h.catalog.initialize('/files');
  const items = await h.seedAssets(['a']);
  const pending = h.analysis.similar(items, h.token, () => {});
  await h.waitUntilSampling();
  await h.changeFile('a');
  h.finishSampling();
  await pending;
  assert.equal(h.catalog.getIndex('a'), undefined);
  assert.equal(h.events.filter(x => x === 'frame.release').length, 1);
});

caseTest('origin survives state migration', () => {
  const { DownloadItem, SavedState } = load(ets('model/Models'));
  const { StoreState } = load(ets('service/StoreState'));
  const item = new DownloadItem();
  item.id = 'edited-1'; item.origin = 'edited'; item.originalId = 'original-1';
  const state = new SavedState(); state.downloads = [item];
  const raw = StoreState.serialize(state);
  const restored = StoreState.normalized(StoreState.parse(raw));
  assert.equal(restored.downloads[0].origin, 'edited');
  assert.equal(restored.downloads[0].originalId, 'original-1');
  assert.ok(!raw.includes('__ob_'));
  assert.equal(StoreState.normalized(StoreState.parse('{"downloads":[{"id":"old"}]}')).downloads[0].origin, 'download');
});

caseTest('origin rejects unknown wire values', () => {
  const { StoreState } = load(ets('service/StoreState'));
  const restored = StoreState.normalized(StoreState.parse('{"downloads":[{"id":"x","origin":"imported","originalId":"a"}]}'));
  assert.equal(restored.downloads[0].origin, 'download');
  assert.equal(restored.downloads[0].originalId, 'a');
});

function memoryFs() {
  const files = new Map();
  const directories = new Set(['/files', '/files/images']);
  const descriptors = new Map();
  let nextFd = 1;
  let failRename = false;
  let shortWrite = false;
  let failUnlinkPath = '';
  const fs = {
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    accessSync: name => files.has(name) || directories.has(name),
    mkdirSync: name => { directories.add(name); },
    listFileSync: name => [...files.keys()]
      .filter(file => file.startsWith(name + '/') && !file.slice(name.length + 1).includes('/'))
      .map(file => path.basename(file)),
    readTextSync: name => {
      if (!files.has(name)) throw new Error('missing: ' + name);
      return files.get(name).data.toString('utf8');
    },
    openSync: name => { const fd = nextFd++; files.set(name, { data: Buffer.alloc(0), mtime: 1, ctime: 1 }); descriptors.set(fd, name); return { fd }; },
    writeSync: (fd, bytes) => {
      const name = descriptors.get(fd);
      if (!name) throw new Error('bad fd');
      const incoming = Buffer.from(bytes);
      const length = shortWrite ? Math.min(1, incoming.length) : incoming.length;
      shortWrite = false;
      files.set(name, { data: incoming.subarray(0, length), mtime: 1, ctime: 1 });
      return length;
    },
    closeSync: fd => { descriptors.delete(fd.fd ?? fd); },
    renameSync: (from, to) => {
      if (failRename) { failRename = false; throw new Error('rename failed'); }
      if (!files.has(from)) throw new Error('missing rename source');
      files.set(to, files.get(from)); files.delete(from);
    },
    unlinkSync: name => {
      if (name === failUnlinkPath) { failUnlinkPath = ''; throw new Error('unlink failed'); }
      files.delete(name);
    },
    statSync: name => {
      if (!files.has(name)) throw new Error('missing stat: ' + name);
      const value = files.get(name);
      return { size: value.data.length, mtime: value.mtime, ctime: value.ctime ?? value.mtime };
    }
  };
  return {
    fs, files,
    failNextRename: () => { failRename = true; },
    shortNextWrite: () => { shortWrite = true; },
    failNextUnlink: name => { failUnlinkPath = name; }
  };
}

function journalHarness() {
  const memory = memoryFs();
  const nativeLoad = loader({ '@kit.CoreFileKit': { fileIo: memory.fs },
    '@kit.ArkTS': { util: { TextEncoder: class {
      encodeInto(value) { return Uint8Array.from(Buffer.from(value, 'utf8')); }
    } } } });
  const { EditJournal } = nativeLoad(ets('service/EditJournal'));
  return { memory, journal: EditJournal };
}

caseTest('edited registration journal recovers unregistered finalized copy without touching original', async () => {
  const h = journalHarness();
  h.memory.files.set('/files/images/original.png', { data: Buffer.from('original'), mtime: 1, ctime: 1 });
  const ticket = await h.journal.prepare('/files', 'copy_1', 'original');
  h.memory.files.set(ticket.pendingPath, { data: Buffer.from('png'), mtime: 1, ctime: 1 });
  await h.journal.finalize(ticket, { path: ticket.pendingPath, bytes: 3, width: 1, height: 1 });
  await h.journal.recover('/files', []);
  assert.equal(h.memory.files.has(ticket.finalPath), false);
  assert.equal(h.memory.files.has(ticket.journalPath), false);
  assert.equal(h.memory.files.get('/files/images/original.png').data.toString(), 'original');
});

caseTest('edited registration journal keeps registered copy and removes only its log', async () => {
  const h = journalHarness();
  const ticket = await h.journal.prepare('/files', 'copy_2', 'original');
  h.memory.files.set(ticket.pendingPath, { data: Buffer.from('png'), mtime: 1, ctime: 1 });
  await h.journal.finalize(ticket, { path: ticket.pendingPath, bytes: 3, width: 1, height: 1 });
  const unrelated = '/files/edits/user.png';
  h.memory.files.set(unrelated, { data: Buffer.from('user'), mtime: 1, ctime: 1 });
  await h.journal.recover('/files', [{ id: ticket.id, origin: 'edited', path: ticket.finalPath }]);
  assert.equal(h.memory.files.has(ticket.finalPath), true);
  assert.equal(h.memory.files.has(ticket.journalPath), false);
  assert.equal(h.memory.files.has(unrelated), true);
});

async function registrationHarness() {
  const memory = memoryFs();
  const mocks = {
    '@kit.AbilityKit': {},
    '@kit.BasicServicesKit': { request: { agent: {} }, zlib: {} },
    '@kit.CoreFileKit': { fileIo: memory.fs },
    '@kit.ArkWeb': { webview: {} },
    '@kit.ArkTS': { util: { TextEncoder: class {
      encodeInto(value) { return Uint8Array.from(Buffer.from(value, 'utf8')); }
    } } },
    [ets('service/Delivery')]: { Delivery: class {} },
    [ets('service/GripSensor')]: { GripSensor: {} },
    [ets('service/AntiPeep')]: { AntiPeep: {} },
    [ets('service/FileActions')]: {},
    [ets('service/LivePhoto')]: { LivePhoto: { removeTree: () => {} } },
    [ets('service/StillFrames')]: { StillFrames: { clear: () => {}, forget: () => {} } },
    [ets('widget/WidgetForms')]: { WidgetForms: { publish: () => {} } },
    [ets('widget/WidgetSnapshot')]: { WidgetSnapshot: { from: () => ({}) } }
  };
  const nativeLoad = loader(mocks);
  const { DownloadStore } = nativeLoad(ets('service/DownloadStore'));
  const { EditJournal } = nativeLoad(ets('service/EditJournal'));
  const { LIBRARY_CATALOG } = nativeLoad(ets('service/LibraryCatalog'));
  const { DownloadItem } = nativeLoad(ets('model/Models'));
  DownloadStore.context = { filesDir: '/files' };
  DownloadStore.listeners = [];
  DownloadStore.downloads = [];
  const original = new DownloadItem();
  original.id = 'original'; original.name = 'original.png'; original.path = '/files/images/original.png';
  original.url = 'https://example.test/original.png'; original.status = 'completed';
  original.sourcePage = 'https://example.test/page'; original.size = 8;
  memory.files.set(original.path, { data: Buffer.from('original'), mtime: 1, ctime: 1 });
  DownloadStore.downloads = [original];
  await LIBRARY_CATALOG.initialize('/files');
  await LIBRARY_CATALOG.reconcile([original]);
  DownloadStore.save();
  const hash = filename => crypto.createHash('sha256').update(memory.files.get(filename).data).digest('hex');
  const prepareCopy = async id => {
    const ticket = await EditJournal.prepare('/files', id, original.id);
    memory.files.set(ticket.pendingPath, { data: Buffer.from('new-png'), mtime: 1, ctime: 1 });
    const result = { path: ticket.pendingPath, bytes: 7, width: 2, height: 2 };
    await EditJournal.finalize(ticket, result);
    return { ticket, result };
  };
  return { memory, DownloadStore, EditJournal, LIBRARY_CATALOG, original, hash, prepareCopy, nativeLoad };
}

caseTest('edited registration failure rolls back only its new file', async () => {
  const h = await registrationHarness();
  const originalHash = h.hash(h.original.path);
  const { ticket, result } = await h.prepareCopy('copy_3');
  h.memory.shortNextWrite();
  await assert.rejects(h.DownloadStore.registerEdited(h.original.id, ticket, result));
  assert.equal(h.hash(h.original.path), originalHash);
  assert.equal(h.DownloadStore.downloads.filter(x => x.origin === 'edited').length, 0);
  assert.equal(h.memory.files.has(ticket.finalPath), false);
});

caseTest('edited registration state rename failure retains the previous saved state', async () => {
  const h = await registrationHarness();
  const before = h.memory.fs.readTextSync('/files/download-state.json');
  const originalHash = h.hash(h.original.path);
  const { ticket, result } = await h.prepareCopy('copy_8');
  h.memory.failNextRename();
  await assert.rejects(h.DownloadStore.registerEdited(h.original.id, ticket, result));
  assert.equal(h.memory.fs.readTextSync('/files/download-state.json'), before);
  assert.equal(h.hash(h.original.path), originalHash);
  assert.equal(h.memory.files.has(ticket.finalPath), false);
  assert.equal(h.memory.files.has(ticket.journalPath), false);
});

caseTest('edited registration is durable, idempotent, tagged and excluded from source preview', async () => {
  const h = await registrationHarness();
  await h.LIBRARY_CATALOG.changeTags([h.original.id], ['收藏来源'], []);
  const { ticket, result } = await h.prepareCopy('copy_4');
  const item = await h.DownloadStore.registerEdited(h.original.id, ticket, result);
  const same = await h.DownloadStore.registerEdited(h.original.id, ticket, result);
  assert.equal(same.id, item.id);
  assert.equal(item.origin, 'edited');
  assert.equal(item.originalId, h.original.id);
  assert.equal(item.url, '');
  assert.equal(item.sourcePage, h.original.sourcePage);
  assert.equal(item.taskId, '');
  assert.deepEqual(h.LIBRARY_CATALOG.getMeta(item.id).tags, ['收藏来源']);
  assert.equal(h.LIBRARY_CATALOG.getMeta(item.id).favorite, false);
  assert.equal(h.LIBRARY_CATALOG.getIndex(item.id), undefined);
  assert.equal(h.LIBRARY_CATALOG.assetForPreview(h.DownloadStore.downloads, h.original.url, 'image'), h.original.id);
  assert.equal(h.memory.files.has(ticket.finalPath), true);
  assert.equal(h.memory.files.has(ticket.journalPath), false);
  assert.equal(JSON.parse(h.memory.fs.readTextSync('/files/download-state.json')).downloads.length, 2);
});

caseTest('super-resolution copy keeps source pixels and uses a clear still-frame name', async () => {
  const h = await registrationHarness();
  const sourceHash = h.hash(h.original.path);
  const { ticket, result } = await h.prepareCopy('sr_copy');
  const stamp = { path: h.original.path, bytes: 8, modified: 1, changed: 1 };
  const item = await h.DownloadStore.registerEdited(h.original.id, ticket, result,
    '超分首帧静图', { cancelled: false }, stamp);
  assert.match(item.name, /超分首帧静图\.png$/);
  assert.equal(item.kind, 'image');
  assert.equal(item.animated, false);
  assert.equal(item.originalId, h.original.id);
  assert.equal(h.hash(h.original.path), sourceHash);
  assert.equal(h.memory.files.has(ticket.finalPath), true);
});

caseTest('super-resolution copy rejects a replaced live-photo cover and rolls back', async () => {
  const h = await registrationHarness();
  h.original.kind = 'livephoto';
  h.original.stillPath = '/files/images/cover.png';
  h.memory.files.set(h.original.stillPath, { data: Buffer.from('old-cover'), mtime: 1, ctime: 1 });
  const { ticket, result } = await h.prepareCopy('sr_stale_cover');
  const stamp = { path: h.original.stillPath, bytes: 9, modified: 1, changed: 1 };
  h.memory.files.set(h.original.stillPath, { data: Buffer.from('new-cover'), mtime: 2, ctime: 2 });
  await assert.rejects(h.DownloadStore.registerEdited(h.original.id, ticket, result,
    '超分封面静图', { cancelled: false }, stamp));
  assert.equal(h.memory.files.has(ticket.finalPath), false);
  assert.equal(h.DownloadStore.downloads.length, 1);
});

caseTest('edited registration concurrent saves keep one durable record per ticket', async () => {
  const h = await registrationHarness();
  const a = await h.prepareCopy('copy_6');
  const b = await h.prepareCopy('copy_7');
  const entries = await Promise.all([
    h.DownloadStore.registerEdited(h.original.id, a.ticket, a.result),
    h.DownloadStore.registerEdited(h.original.id, a.ticket, a.result),
    h.DownloadStore.registerEdited(h.original.id, b.ticket, b.result)
  ]);
  assert.deepEqual(entries.map(x => x.id), ['copy_6', 'copy_6', 'copy_7']);
  assert.equal(h.DownloadStore.downloads.length, 3);
  assert.equal(JSON.parse(h.memory.fs.readTextSync('/files/download-state.json')).downloads.length, 3);
});

caseTest('edited registration rejects deleted source while preserving unrelated file', async () => {
  const h = await registrationHarness();
  const { ticket, result } = await h.prepareCopy('copy_5');
  h.memory.files.set('/files/edits/user.png', { data: Buffer.from('user'), mtime: 1, ctime: 1 });
  h.memory.files.delete(h.original.path);
  await assert.rejects(h.DownloadStore.registerEdited(h.original.id, ticket, result));
  assert.equal(h.memory.files.has(ticket.finalPath), false);
  assert.equal(h.memory.files.has('/files/edits/user.png'), true);
});

caseTest('edited registration rejects source deletion during catalog write', async () => {
  const h = await registrationHarness();
  const { ticket, result } = await h.prepareCopy('copy_12');
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const reconcile = h.LIBRARY_CATALOG.reconcile.bind(h.LIBRARY_CATALOG);
  h.LIBRARY_CATALOG.reconcile = async items => { await gate; return reconcile(items); };
  const registering = h.DownloadStore.registerEdited(h.original.id, ticket, result);
  await new Promise(resolve => setImmediate(resolve));
  h.memory.files.delete(h.original.path);
  release();
  await assert.rejects(registering);
  assert.equal(h.DownloadStore.downloads.filter(x => x.origin === 'edited').length, 0);
  assert.equal(h.memory.files.has(ticket.finalPath), false);
});

caseTest('edited registration does not resurrect another deleted record across catalog await', async () => {
  const h = await registrationHarness();
  const { DownloadItem } = h.nativeLoad(ets('model/Models'));
  const other = new DownloadItem();
  other.id = 'other'; other.name = 'other.png'; other.path = '/files/images/other.png';
  other.status = 'completed';
  h.memory.files.set(other.path, { data: Buffer.from('other'), mtime: 1, ctime: 1 });
  h.DownloadStore.downloads.push(other);
  const copy = await h.prepareCopy('copy_15');
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const reconcile = h.LIBRARY_CATALOG.reconcile.bind(h.LIBRARY_CATALOG);
  h.LIBRARY_CATALOG.reconcile = async items => { await gate; return reconcile(items); };
  const registering = h.DownloadStore.registerEdited(h.original.id, copy.ticket, copy.result);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(h.DownloadStore.deleteDownload(other), true);
  release();
  await registering;
  assert.deepEqual(h.DownloadStore.downloads.map(x => x.id).sort(), ['copy_15', 'original']);
  assert.deepEqual(JSON.parse(h.memory.fs.readTextSync('/files/download-state.json')).downloads
    .map(x => x.id).sort(), ['copy_15', 'original']);
});

caseTest('edited registration failed commit preserves a concurrent deletion', async () => {
  const h = await registrationHarness();
  const { DownloadItem } = h.nativeLoad(ets('model/Models'));
  const other = new DownloadItem();
  other.id = 'other'; other.path = '/files/images/other.png'; other.status = 'completed';
  h.memory.files.set(other.path, { data: Buffer.from('other'), mtime: 1, ctime: 1 });
  h.DownloadStore.downloads.push(other);
  const copy = await h.prepareCopy('copy_16');
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const reconcile = h.LIBRARY_CATALOG.reconcile.bind(h.LIBRARY_CATALOG);
  h.LIBRARY_CATALOG.reconcile = async items => { await gate; return reconcile(items); };
  const registering = h.DownloadStore.registerEdited(h.original.id, copy.ticket, copy.result);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(h.DownloadStore.deleteDownload(other), true);
  h.memory.shortNextWrite();
  release();
  await assert.rejects(registering);
  assert.deepEqual(h.DownloadStore.downloads.map(x => x.id), ['original']);
  assert.equal(h.memory.files.has(copy.ticket.finalPath), false);
});

caseTest('edited registration keeps copies out of download task lists and badges', () => {
  const original = { id: 'original', origin: 'download', batchId: '', status: 'completed' };
  const edited = { id: 'copy', origin: 'edited', batchId: '', status: 'completed' };
  const nativeLoad = loader({
    [ets('service/DownloadStore')]: { DownloadStore: { downloads: [edited, original], batches: [], concurrency: 3 } },
    [ets('service/UiPort')]: { UiPort: class {} },
    [ets('theme/Metrics')]: { ScreenMetrics: {} }
  });
  const { TasksViewModel } = nativeLoad(ets('viewmodel/TasksViewModel'));
  const vm = new TasksViewModel();
  vm.sync();
  assert.deepEqual(vm.settled.map(x => x.id), ['original']);
  assert.equal(vm.running, 0);
  assert.equal(vm.downloads.some(x => x.id === 'copy'), false);
});

caseTest('edited copy survives clearing downloads and remains independently deletable', async () => {
  const h = await registrationHarness();
  const { ticket, result } = await h.prepareCopy('copy_9');
  const copy = await h.DownloadStore.registerEdited(h.original.id, ticket, result);
  h.DownloadStore.clearAll();
  assert.deepEqual(h.DownloadStore.downloads.map(x => x.id), [copy.id]);
  assert.equal(copy.status, 'completed');
  assert.equal(h.memory.files.has(copy.path), true);
  assert.equal(h.memory.files.has(h.original.path), false);
  assert.equal(JSON.parse(h.memory.fs.readTextSync('/files/download-state.json')).downloads.length, 1);
});

caseTest('edited copy and original can be deleted independently', async () => {
  const first = await registrationHarness();
  const one = await first.prepareCopy('copy_13');
  const copyOne = await first.DownloadStore.registerEdited(first.original.id, one.ticket, one.result);
  assert.equal(first.DownloadStore.deleteDownload(first.original), true);
  assert.equal(first.memory.files.has(copyOne.path), true);
  assert.deepEqual(first.DownloadStore.downloads.map(x => x.id), [copyOne.id]);

  const second = await registrationHarness();
  const two = await second.prepareCopy('copy_14');
  const copyTwo = await second.DownloadStore.registerEdited(second.original.id, two.ticket, two.result);
  assert.equal(second.DownloadStore.deleteDownload(copyTwo), true);
  assert.equal(second.memory.files.has(second.original.path), true);
  assert.deepEqual(second.DownloadStore.downloads.map(x => x.id), [second.original.id]);
});

caseTest('clear downloads retains a file whose removal failed so retry can delete it', async () => {
  const h = await registrationHarness();
  const { ticket, result } = await h.prepareCopy('copy_11');
  const copy = await h.DownloadStore.registerEdited(h.original.id, ticket, result);
  h.memory.failNextUnlink(h.original.path);
  h.DownloadStore.clearAll();
  assert.deepEqual(h.DownloadStore.downloads.map(x => x.id).sort(), [copy.id, h.original.id].sort());
  assert.equal(h.original.status, 'completed');
  assert.equal(h.memory.files.has(h.original.path), true);
  h.DownloadStore.clearAll();
  assert.deepEqual(h.DownloadStore.downloads.map(x => x.id), [copy.id]);
  assert.equal(h.memory.files.has(h.original.path), false);
});

caseTest('edited catalog index follows a known rename without losing text', async () => {
  const h = await registrationHarness();
  const { ticket, result } = await h.prepareCopy('copy_10');
  const copy = await h.DownloadStore.registerEdited(h.original.id, ticket, result);
  const { LibraryIndex } = h.nativeLoad(ets('model/LibraryAsset'));
  const index = new LibraryIndex();
  index.id = copy.id;
  index.stamp = { id: copy.id, path: copy.path, sourceKind: 'image',
    bytes: result.bytes, modified: 1, changed: 1, orientation: 1 };
  index.text = 'known rename'; index.ocrStatus = 'ready';
  assert.equal(await h.LIBRARY_CATALOG.putIndex(index), true);
  assert.equal(h.DownloadStore.renameDownload(copy, 'new-copy'), true);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(h.LIBRARY_CATALOG.getIndex(copy.id).stamp.path, copy.path);
  assert.equal(h.LIBRARY_CATALOG.getIndex(copy.id).text, 'known rename');
});

function editorHarness() {
  const { ImageEditorViewModel } = load(ets('viewmodel/ImageEditorViewModel'));
  const vm = new ImageEditorViewModel();
  let registerCount = 0;
  let fail = false;
  const errors = [];
  const finished = [];
  vm.attach({
    source: async id => ({ id, path: '/files/images/a.png', bytes: 8, modified: 1, changed: 1 }),
    info: async () => ({ width: 40, height: 30 }),
    exportAndRegister: async () => {
      if (fail) { fail = false; throw new Error('disk full'); }
      registerCount++;
      return { id: 'edit-' + registerCount };
    },
    showError: message => errors.push(message),
    finish: id => finished.push(id)
  });
  return { vm, errors, finished, registerCount: () => registerCount, failNextExport: () => { fail = true; } };
}

caseTest('editor saves once and keeps draft after export failure', async () => {
  const h = editorHarness();
  await h.vm.load('a');
  h.vm.rotate();
  h.failNextExport();
  await h.vm.save();
  assert.equal(h.vm.hasChanges, true);
  assert.equal(h.registerCount(), 0);
  await Promise.all([h.vm.save(), h.vm.save()]);
  assert.equal(h.registerCount(), 1);
  assert.deepEqual(h.finished, ['edit-1']);
  assert.equal(h.errors.length, 1);
});

caseTest('editor saves no unchanged draft and cancel prevents registration', async () => {
  const h = editorHarness();
  await h.vm.load('a');
  assert.equal(h.vm.hasChanges, false);
  await h.vm.save();
  assert.equal(h.registerCount(), 0);
  h.vm.rotate();
  h.vm.cancel();
  await h.vm.save();
  assert.equal(h.registerCount(), 0);
});

caseTest('editor crop and strokes use undo snapshots without mutating older drafts', async () => {
  const h = editorHarness();
  await h.vm.load('a');
  const first = h.vm.document;
  h.vm.setAspect(1);
  assert.equal(h.vm.document.crop.width, h.vm.document.crop.height);
  h.vm.rotate();
  const rotated = h.vm.document;
  h.vm.addStroke({ kind: 'rect', color: '#FF0000', width: 4,
    points: [{ x: 3, y: 4 }, { x: 12, y: 13 }] });
  assert.equal(rotated.strokes.length, 0);
  h.vm.undo();
  assert.equal(h.vm.document.strokes.length, 0);
  h.vm.undo();
  assert.equal(h.vm.document.turns, 0);
  h.vm.undo();
  assert.equal(h.vm.hasChanges, false);
  assert.equal(first.crop.width, 40);
  assert.equal(first.crop.height, 30);
});

function catalogHarness() {
  const memory = memoryFs();
  const nativeMocks = {
    '@kit.CoreFileKit': { fileIo: memory.fs },
    '@kit.ArkTS': { util: { TextEncoder: class {
      encodeInto(value) { return Uint8Array.from(Buffer.from(value, 'utf8')); }
    } } }
  };
  function makeCatalog() {
    const nativeLoad = loader(nativeMocks);
    const { LibraryCatalog } = nativeLoad(ets('service/LibraryCatalog'));
    return new LibraryCatalog();
  }
  const catalog = makeCatalog();
  return {
    catalog, files: memory.files,
    failNextRename: memory.failNextRename,
    shortNextWrite: memory.shortNextWrite,
    reload: makeCatalog,
    changedFile: (id, data, mtime, ctime = mtime) => {
      memory.files.set('/files/images/' + id + '.png', { data: Buffer.from(data), mtime, ctime });
    },
    seedAssets: async ids => {
      const { DownloadItem } = load(ets('model/Models'));
      const items = ids.map(id => {
        const item = new DownloadItem();
        item.id = id; item.name = id + '.png'; item.path = '/files/images/' + item.name;
        item.status = 'completed'; item.kind = 'image';
        memory.files.set(item.path, { data: Buffer.from('image-' + id), mtime: 1, ctime: 1 });
        return item;
      });
      await catalog.reconcile(items);
      return items;
    }
  };
}

caseTest('catalog failed rename preserves prior favorite', async () => {
  const h = catalogHarness();
  await h.catalog.initialize('/files');
  await h.seedAssets(['a']);
  await h.catalog.setFavorite(['a'], true);
  h.failNextRename();
  await assert.rejects(h.catalog.setFavorite(['a'], false));
  const restored = h.reload();
  await restored.initialize('/files');
  assert.equal(restored.getMeta('a').favorite, true);
  assert.equal(h.catalog.getMeta('a').favorite, true);
});

function indexed(id, bytes, modified, text) {
  const { LibraryIndex, AssetStamp } = load(ets('model/LibraryAsset'));
  const index = new LibraryIndex();
  index.id = id; index.text = text; index.ocrStatus = 'ready';
  const stamp = new AssetStamp();
  stamp.id = id; stamp.path = '/files/images/' + id + '.png';
  stamp.bytes = bytes; stamp.modified = modified; stamp.changed = 1;
  index.stamp = stamp;
  return index;
}

caseTest('catalog stale OCR cannot revive a replaced image or deleted ID', async () => {
  const h = catalogHarness();
  await h.catalog.initialize('/files');
  const items = await h.seedAssets(['a']);
  const old = indexed('a', 7, 1, '旧文字');
  assert.equal(await h.catalog.putIndex(old), true);
  h.changedFile('a', 'changed-image', 2);
  assert.equal(await h.catalog.putIndex(old), false);
  await h.catalog.reconcile(items);
  assert.equal(h.catalog.getIndex('a'), undefined);
  await h.catalog.reconcile([]);
  assert.equal(await h.catalog.putIndex(old), false);
});

caseTest('catalog rejects same-size same-mtime replacement via change time', async () => {
  const h = catalogHarness();
  await h.catalog.initialize('/files');
  const items = await h.seedAssets(['a']);
  const old = indexed('a', 7, 1, '旧文字');
  assert.equal(await h.catalog.putIndex(old), true);
  h.changedFile('a', 'other-a', 1, 2);
  assert.equal(await h.catalog.putIndex(old), false);
  await h.catalog.reconcile(items);
  assert.equal(h.catalog.getIndex('a'), undefined);
});

caseTest('catalog known rename keeps tags and recognized text', async () => {
  const h = catalogHarness();
  await h.catalog.initialize('/files');
  const items = await h.seedAssets(['a']);
  await h.catalog.changeTags(['a'], ['收据'], []);
  assert.equal(await h.catalog.putIndex(indexed('a', 7, 1, '订单')), true);
  const moved = h.files.get('/files/images/a.png');
  h.files.delete('/files/images/a.png');
  h.files.set('/files/images/renamed.png', { data: moved.data, mtime: 1, ctime: 2 });
  items[0].path = '/files/images/renamed.png';
  await h.catalog.relocate('a', '/files/images/a.png', items[0].path);
  await h.catalog.reconcile(items);
  assert.deepEqual(h.catalog.getMeta('a').tags, ['收据']);
  assert.equal(h.catalog.getIndex('a').text, '订单');
});

caseTest('catalog accepts codec orientation on unchanged source bytes', async () => {
  const h = catalogHarness();
  await h.catalog.initialize('/files');
  await h.seedAssets(['a']);
  const index = indexed('a', 7, 1, '方向文字');
  index.stamp.orientation = 6;
  assert.equal(await h.catalog.putIndex(index), true);
  assert.equal(h.catalog.getIndex('a').stamp.orientation, 6);
});

caseTest('catalog OCR write never overwrites a newer tag change', async () => {
  const h = catalogHarness();
  await h.catalog.initialize('/files');
  await h.seedAssets(['a']);
  const result = indexed('a', 7, 1, '订单');
  const writing = h.catalog.putIndex(result);
  const tagging = h.catalog.changeTags(['a'], ['发票'], []);
  await Promise.all([writing, tagging]);
  assert.equal(h.catalog.getIndex('a').text, '订单');
  assert.deepEqual(h.catalog.getMeta('a').tags, ['发票']);
  const reloaded = h.reload();
  await reloaded.initialize('/files');
  assert.equal(reloaded.getIndex('a').text, '订单');
  assert.deepEqual(reloaded.getMeta('a').tags, ['发票']);
});

caseTest('catalog rejects a cancelled OCR write while it waits for the mutation queue', async () => {
  const h = catalogHarness();
  await h.catalog.initialize('/files');
  await h.seedAssets(['a']);
  const index = indexed('a', Buffer.byteLength('image-a'), 1, 'late result');
  const { AnalysisToken } = load(ets('model/LibraryAsset'));
  const token = new AnalysisToken();
  const pending = h.catalog.putIndex(index, () => !token.cancelled);
  token.cancel();
  assert.equal(await pending, false);
  assert.equal(h.catalog.getIndex('a'), undefined);
});

caseTest('catalog corrupt shard does not hide another image', async () => {
  const h = catalogHarness();
  await h.catalog.initialize('/files');
  await h.seedAssets(['a', 'b']);
  assert.equal(await h.catalog.putIndex(indexed('a', 7, 1, '甲')), true);
  assert.equal(await h.catalog.putIndex(indexed('b', 7, 1, '乙')), true);
  h.files.set('/files/library-index/a.json', { data: Buffer.from('{broken'), mtime: 1 });
  const reloaded = h.reload();
  await reloaded.initialize('/files');
  assert.equal(reloaded.getIndex('a'), undefined);
  assert.equal(reloaded.getIndex('b').text, '乙');
});

caseTest('catalog unknown schema preserves original file and reports failure', async () => {
  const h = catalogHarness();
  const source = Buffer.from('{"version":99,"metas":[]}');
  h.files.set('/files/library-catalog.json', { data: source, mtime: 1, ctime: 1 });
  await assert.rejects(h.catalog.initialize('/files'));
  assert.equal(h.catalog.loadError.length > 0, true);
  assert.deepEqual(h.files.get('/files/library-catalog.json').data, source);
  h.files.set('/files/library-catalog.json', {
    data: Buffer.from('{"version":1,"metas":[]}'), mtime: 2, ctime: 2
  });
  await h.catalog.initialize('/files');
  assert.equal(h.catalog.loadError, '');
});

caseTest('catalog returned metadata cannot mutate stored favorite and tags', async () => {
  const h = catalogHarness();
  await h.catalog.initialize('/files');
  await h.seedAssets(['a']);
  await h.catalog.setFavorite(['a'], true);
  await h.catalog.changeTags(['a'], ['常用'], []);
  const leaked = h.catalog.getMeta('a');
  leaked.favorite = false; leaked.tags.push('误写');
  assert.equal(h.catalog.getMeta('a').favorite, true);
  assert.deepEqual(h.catalog.getMeta('a').tags, ['常用']);
});

caseTest('catalog large index load remains observable until complete', async () => {
  const h = catalogHarness();
  for (let index = 0; index < 65; index++) {
    const id = 'image-' + index;
    const value = indexed(id, 7, 1, '词');
    h.files.set('/files/library-index/' + id + '.json',
      { data: Buffer.from(JSON.stringify(value)), mtime: 1, ctime: 1 });
  }
  const pending = h.catalog.initialize('/files');
  assert.equal(h.catalog.loading, true);
  await pending;
  assert.equal(h.catalog.loading, false);
  assert.equal(h.catalog.getIndex('image-64').text, '词');
});

caseTest('catalog short write preserves old tags', async () => {
  const h = catalogHarness();
  await h.catalog.initialize('/files');
  await h.seedAssets(['a']);
  await h.catalog.changeTags(['a'], ['常用'], []);
  h.shortNextWrite();
  await assert.rejects(h.catalog.changeTags(['a'], ['错误'], []));
  assert.deepEqual(h.catalog.getMeta('a').tags, ['常用']);
  const restored = h.reload();
  await restored.initialize('/files');
  assert.deepEqual(restored.getMeta('a').tags, ['常用']);
});

caseTest('catalog tag keys deduplicate and remove without altering display text', async () => {
  const h = catalogHarness();
  await h.catalog.initialize('/files');
  await h.seedAssets(['a']);
  await h.catalog.changeTags(['a'], [' Work ', 'work', '收据'], []);
  assert.deepEqual(h.catalog.getMeta('a').tags, ['Work', '收据']);
  await h.catalog.changeTags(['a'], [], [' WORK ']);
  assert.deepEqual(h.catalog.getMeta('a').tags, ['收据']);
});

caseTest('catalog refuses favorite and tag success for missing local assets', async () => {
  const h = catalogHarness();
  await h.catalog.initialize('/files');
  await assert.rejects(h.catalog.setFavorite(['missing'], true));
  await assert.rejects(h.catalog.changeTags(['missing'], ['重要'], []));
  assert.equal(h.catalog.getMeta('missing').favorite, false);
});

function completed(id, name) {
  const { DownloadItem } = load(ets('model/Models'));
  const item = new DownloadItem();
  item.id = id; item.name = name; item.path = '/files/images/' + name;
  item.status = 'completed'; item.finishedAt = id === 'a' ? 100 : 200;
  item.batchId = '';
  return item;
}

function searchEntry(id, favorite, tags, text) {
  const { LibrarySearchEntry } = load(ets('model/LibraryAsset'));
  const entry = new LibrarySearchEntry();
  entry.id = id; entry.favorite = favorite; entry.tags = tags.slice();
  entry.text = text; entry.ocrStatus = 'ready';
  return entry;
}

caseTest('gallery and ZIP search sort by both directions with stable size ties', () => {
  const { LibrarySearchOptions } = load(ets('model/LibraryAsset'));
  const { LibraryQuery } = load(ets('service/LibraryQuery'));
  const { ZipItem } = load(ets('model/Models'));
  const a = completed('a', 'match-a.jpg'), b = completed('b', 'match-b.jpg');
  const c = completed('c', 'match-c.jpg');
  a.size = 10; b.size = 20; c.size = 20;
  a.finishedAt = 10; b.finishedAt = 20; c.finishedAt = 30;
  const images = [c, a, b, completed('other', 'other.jpg')];
  const archives = [c, a, b].map(item => {
    const zip = new ZipItem();
    zip.name = item.name.replace('.jpg', '.zip');
    zip.size = item.size; zip.createdAt = item.finishedAt;
    return zip;
  });
  const options = new LibrarySearchOptions(); options.query = 'match';
  const expected = {
    newest: ['c', 'b', 'a'], oldest: ['a', 'b', 'c'],
    name: ['a', 'b', 'c'], nameDesc: ['c', 'b', 'a'],
    size: ['b', 'c', 'a'], sizeAsc: ['a', 'b', 'c']
  };
  for (const order of Object.keys(expected)) {
    options.order = order;
    assert.deepEqual(LibraryQuery.search(images, [], options).map(item => item.id), expected[order]);
    assert.deepEqual(LibraryQuery.archives(archives, 'match', order)
      .map(item => item.name[6]), expected[order]);
  }
  assert.deepEqual(images.map(item => item.id), ['c', 'a', 'b', 'other']);
});

caseTest('search combines OCR favorite and tag without changing order', () => {
  const { LibrarySearchOptions } = load(ets('model/LibraryAsset'));
  const { LibraryQuery } = load(ets('service/LibraryQuery'));
  const a = completed('a', 'receipt-a.png'), b = completed('b', 'receipt-b.png');
  const entries = [searchEntry('a', true, ['工作'], 'INVOICEALPHA'),
    searchEntry('b', false, ['工作'], 'INVOICEBETA')];
  const options = new LibrarySearchOptions();
  options.scope = 'text'; options.query = 'alpha'; options.favoritesOnly = true; options.tag = '工作';
  assert.deepEqual(LibraryQuery.search([a, b], entries, options).map(x => x.id), ['a']);
  options.query = ''; options.favoritesOnly = false;
  assert.deepEqual(LibraryQuery.search([a, b], entries, options).map(x => x.id), ['b', 'a']);
});

caseTest('search scope distinguishes filename OCR and tags', () => {
  const { LibrarySearchOptions } = load(ets('model/LibraryAsset'));
  const { LibraryQuery } = load(ets('service/LibraryQuery'));
  const item = completed('a', 'receipt.png');
  const entries = [searchEntry('a', false, ['重要'], '开发\n计划')];
  const options = new LibrarySearchOptions();
  options.query = '开发计划'; options.scope = 'text';
  assert.deepEqual(LibraryQuery.search([item], entries, options).map(x => x.id), ['a']);
  options.scope = 'name';
  assert.deepEqual(LibraryQuery.search([item], entries, options).map(x => x.id), []);
  options.scope = 'tags'; options.query = '重要';
  assert.deepEqual(LibraryQuery.search([item], entries, options).map(x => x.id), ['a']);
});

caseTest('search source and format stay combined with OCR results', () => {
  const { LibrarySearchOptions } = load(ets('model/LibraryAsset'));
  const { LibraryQuery } = load(ets('service/LibraryQuery'));
  const a = completed('a', 'one.jpg'), b = completed('b', 'two.png');
  a.sourcePage = 'https://site.example/a'; b.sourcePage = 'https://other.example/b';
  const entries = [searchEntry('a', false, [], 'ALPHA'), searchEntry('b', false, [], 'ALPHA')];
  const options = new LibrarySearchOptions();
  options.scope = 'text'; options.query = 'alpha'; options.source = 'site.example'; options.format = 'jpg';
  assert.deepEqual(LibraryQuery.search([a, b], entries, options).map(x => x.id), ['a']);
});

caseTest('search tag normalization and literal OCR snippet keep visible position', () => {
  const { LibraryText } = load(ets('util/LibraryText'));
  assert.deepEqual(LibraryText.tags([' 工作 ', '工作', '', '收据']), ['工作', '收据']);
  assert.equal(LibraryText.textKey('开发\n计划'), '开发计划');
  const text = '封面说明\n订单 (ALPHA). 已处理';
  assert.ok(LibraryText.snippet(text, '(alpha).', 20).includes('(ALPHA).'));
});

function libraryVmHarness(config = {}) {
  const h = catalogHarness();
  const sourceFile = name => ets(name);
  class FakeStore {
    static downloads = [];
    static zips = [];
  }
  class FakePort {
    messages = [];
    confirmations = [];
    viewerCalls = [];
    say = value => { this.messages.push(value); };
    confirm = (title, message, label, action) => { this.confirmations.push({ title, message, label, action }); };
    openViewer = (item, rename, ids) => { this.viewerCalls.push({ id: item.id, rename, ids }); };
  }
  const ocrCalls = [];
  const similarCalls = [];
  class FakeAnalysis {
    static ocr = async (items, force, token, progress) => {
      ocrCalls.push({ ids: items.map(item => item.id), force, token });
      if (config.ocrGate) { await config.ocrGate(); }
      if (config.lateIndex && items.length > 0) {
        await h.catalog.putIndex(indexed(items[0].id, 7, 1, 'LATE'), () => !token.cancelled);
      }
      progress({ kind: 'ocr', done: items.length, total: items.length,
        success: items.length, empty: 0, failed: 0, message: '' });
    };
    static similar = async (items, token, progress) => {
      similarCalls.push(items.map(item => item.id));
      if (config.similarGate) { await config.similarGate(); }
      progress({ kind: 'similar', done: items.length, total: items.length,
        success: items.length, empty: 0, failed: 0, message: '' });
      return [{ representativeId: items[0].id, ids: items.map(item => item.id) }];
    };
  }
  class ScanResult {}
  class FakeDuplicateFinder {
    static completed(items) { return items.filter(item => item.status === 'completed'); }
    static sameUrl() { return []; }
    static sameSourceName() { return []; }
  }
  const mocks = {
    [sourceFile('service/DownloadStore')]: { DownloadStore: FakeStore },
    [sourceFile('service/LibraryCatalog')]: { LIBRARY_CATALOG: h.catalog },
    [sourceFile('service/LibraryAnalysis')]: { LibraryAnalysis: FakeAnalysis },
    [sourceFile('service/ZipArchiveService')]: { ZipArchiveService: class {}, ZipExtractResult: class {} },
    [sourceFile('service/FileActions')]: {},
    [sourceFile('service/UiPort')]: { UiPort: FakePort },
    [sourceFile('service/DuplicateFinder')]: {
      ContentScanResult: ScanResult, DuplicateFinder: FakeDuplicateFinder, DuplicateGroup: class {}
    },
    [sourceFile('theme/Metrics')]: { ScreenMetrics: { scrollThreshold: () => 100 } }
  };
  const vmLoad = loader(mocks);
  const { LibraryViewModel } = vmLoad(sourceFile('viewmodel/LibraryViewModel'));
  const vm = new LibraryViewModel();
  const port = new FakePort();
  vm.attach(port);
  return { h, vm, port, store: FakeStore, ocrCalls, similarCalls };
}

caseTest('similar view model snapshots current scope and opens only the chosen group', async () => {
  const v = libraryVmHarness();
  await v.h.catalog.initialize('/files');
  await v.h.seedAssets(['a', 'b']);
  v.store.downloads = [completed('a', 'a.png'), completed('b', 'b.png')];
  v.vm.sync();
  v.vm.query = 'a.png';
  v.vm.startSimilar('current');
  assert.ok(v.port.confirmations[0].message.includes('1'));
  v.vm.query = '';
  v.port.confirmations[0].action();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(v.similarCalls[0], ['a']);
  assert.equal(v.port.viewerCalls.length, 0);
  v.vm.openSimilarGroup({ representativeId: 'a', ids: ['a', 'b'] });
  assert.deepEqual(v.port.viewerCalls[0], { id: 'a', rename: true, ids: ['a', 'b'] });
  v.vm.similarGroups = [{ representativeId: 'a', ids: ['a', 'b'] }];
  v.vm.similarChecked = true;
  v.store.downloads = [completed('b', 'b.png')];
  v.vm.sync();
  assert.equal(v.vm.similarChecked, false);
  assert.deepEqual(v.vm.similarGroups, []);
});

caseTest('leaving a completed similar group keeps its success notice', async () => {
  const v = libraryVmHarness();
  await v.h.catalog.initialize('/files');
  await v.h.seedAssets(['a', 'b']);
  v.store.downloads = [completed('a', 'a.png'), completed('b', 'b.png')];
  v.vm.sync();
  v.vm.startSimilar('all');
  v.port.confirmations[0].action();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(v.vm.similarAnalyzing, false);
  assert.equal(v.vm.similarChecked, true);
  const notice = v.vm.similarNotice;
  v.vm.cancelSimilar();
  assert.equal(v.vm.similarNotice, notice);
});

caseTest('similar result is ignored when a source is deleted before completion', async () => {
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const v = libraryVmHarness({ similarGate: () => gate });
  await v.h.catalog.initialize('/files');
  await v.h.seedAssets(['a', 'b']);
  v.store.downloads = [completed('a', 'a.png'), completed('b', 'b.png')];
  v.vm.sync();
  v.vm.startSimilar('all');
  v.port.confirmations[0].action();
  await new Promise(resolve => setImmediate(resolve));
  v.store.downloads = [completed('b', 'b.png')];
  v.vm.sync();
  release();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(v.vm.similarGroups, []);
  assert.equal(v.vm.similarChecked, false);
});

caseTest('OCR current scope snapshots visible assets before confirmation', async () => {
  const v = libraryVmHarness();
  await v.h.catalog.initialize('/files');
  await v.h.seedAssets(['a', 'b']);
  v.store.downloads = [completed('a', 'a.png'), completed('b', 'b.png')];
  v.vm.sync();
  v.vm.query = 'a.png';
  v.vm.startOcr('current', false);
  assert.ok(v.port.confirmations[0].message.includes('1'));
  v.vm.query = 'b.png';
  v.port.confirmations[0].action();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(v.ocrCalls[0].ids, ['a']);
  assert.equal(v.vm.ocrProgress.done, 1);
});

caseTest('background cancellation ignores late analysis while keeping confirmed entries', async () => {
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const v = libraryVmHarness({ ocrGate: () => gate, lateIndex: true });
  await v.h.catalog.initialize('/files');
  await v.h.seedAssets(['a', 'b']);
  assert.equal(await v.h.catalog.putIndex(indexed('a', 7, 1, 'FIRST')), true);
  v.store.downloads = [completed('a', 'a.png'), completed('b', 'b.png')];
  v.vm.sync();
  v.vm.query = 'b.png';
  v.vm.startOcr('current');
  v.port.confirmations[0].action();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(v.vm.ocrAnalyzing, true);
  v.vm.cancelAnalysis();
  release();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(v.h.catalog.getIndex('a').text, 'FIRST');
  assert.equal(v.h.catalog.getIndex('b'), undefined);
  assert.equal(v.vm.ocrAnalyzing, false);
});

caseTest('OCR cancellation before first result clears the running notice', async () => {
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const v = libraryVmHarness({ ocrGate: () => gate });
  await v.h.catalog.initialize('/files');
  await v.h.seedAssets(['a']);
  v.store.downloads = [completed('a', 'a.png')];
  v.vm.sync();
  v.vm.startOcr('all');
  v.port.confirmations[0].action();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(v.vm.ocrAnalyzing, true);
  assert.equal(v.vm.ocrProgress.done, 0);
  v.vm.cancelAnalysis();
  assert.equal(v.vm.ocrAnalyzing, false);
  assert.equal(v.vm.ocrNotice, '已取消；已完成的图片仍保留索引');
  release();
});

caseTest('background lifecycle notifies only active listeners', () => {
  const { PreviewLifecycle } = load(ets('model/PreviewLifecycle'));
  const lifecycle = new PreviewLifecycle();
  const values = [];
  const listener = value => values.push(value);
  lifecycle.subscribe(listener);
  lifecycle.setForeground(false);
  lifecycle.setForeground(false);
  lifecycle.unsubscribe(listener);
  lifecycle.setForeground(true);
  assert.deepEqual(values, [false]);
});

function solidRgba(red, green, blue, alpha = 255) {
  const output = new Uint8Array(32 * 32 * 4);
  for (let i = 0; i < output.length; i += 4) {
    output[i] = red; output[i + 1] = green; output[i + 2] = blue; output[i + 3] = alpha;
  }
  return output;
}

function patternedRgba(noise = 0) {
  const output = new Uint8Array(32 * 32 * 4);
  for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) {
    const offset = (y * 32 + x) * 4;
    const variation = noise === 0 ? 0 : ((x * 13 + y * 17) % 5 - 2) * noise;
    output[offset] = Math.max(0, Math.min(255, 30 + x * 5 + variation));
    output[offset + 1] = Math.max(0, Math.min(255, 40 + y * 4 + variation));
    output[offset + 2] = Math.max(0, Math.min(255, 100 + ((x + y) % 8) * 9 + variation));
    output[offset + 3] = 255;
  }
  return output;
}

caseTest('similar feature keeps resized or lightly recompressed samples together', () => {
  const { PerceptualHash } = load(ets('util/PerceptualHash'));
  const pixels = patternedRgba();
  const original = PerceptualHash.feature(pixels, 32, 32);
  const changed = PerceptualHash.feature(patternedRgba(1), 32, 32);
  const resizedPixels = new Uint8Array(pixels.length);
  for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) {
    const x0 = Math.floor(x / 2) * 2; const y0 = Math.floor(y / 2) * 2;
    const target = (y * 32 + x) * 4;
    for (let channel = 0; channel < 3; channel++) {
      let sum = 0;
      for (let dy = 0; dy < 2; dy++) for (let dx = 0; dx < 2; dx++) {
        sum += pixels[((y0 + dy) * 32 + x0 + dx) * 4 + channel];
      }
      resizedPixels[target + channel] = Math.round(sum / 4 / 4) * 4;
    }
    resizedPixels[target + 3] = 255;
  }
  const resized = PerceptualHash.feature(resizedPixels, 32, 32);
  original.width = changed.width = 800;
  original.height = changed.height = 600;
  resized.width = 800; resized.height = 600;
  assert.equal(original.lowBits.length, 64);
  assert.equal(original.edgeBits.length, 64);
  assert.equal(PerceptualHash.matches(original, changed), true);
  assert.equal(PerceptualHash.matches(original, resized), true);
});

caseTest('similar feature rejects different flat colors and malformed inputs', () => {
  const { PerceptualHash } = load(ets('util/PerceptualHash'));
  const red = PerceptualHash.feature(solidRgba(255, 0, 0), 32, 32);
  const blue = PerceptualHash.feature(solidRgba(0, 0, 255), 32, 32);
  red.width = blue.width = 800; red.height = blue.height = 600;
  assert.equal(PerceptualHash.matches(red, blue), false);
  assert.ok(PerceptualHash.distance('101', '101') > 64);
  assert.throws(() => PerceptualHash.feature(new Uint8Array(8), 32, 32));
});

caseTest('similar feature composites transparent pixels but rejects line layout and aspect changes', () => {
  const { PerceptualHash } = load(ets('util/PerceptualHash'));
  const clearRed = PerceptualHash.feature(solidRgba(255, 0, 0, 0), 32, 32);
  const clearBlue = PerceptualHash.feature(solidRgba(0, 0, 255, 0), 32, 32);
  assert.equal(PerceptualHash.matches(clearRed, clearBlue), true);
  const vertical = solidRgba(255, 255, 255);
  const horizontal = solidRgba(255, 255, 255);
  for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) {
    if (x >= 13 && x <= 18) {
      const p = (y * 32 + x) * 4; vertical[p] = vertical[p + 1] = vertical[p + 2] = 0;
    }
    if (y >= 13 && y <= 18) {
      const p = (y * 32 + x) * 4; horizontal[p] = horizontal[p + 1] = horizontal[p + 2] = 0;
    }
  }
  const a = PerceptualHash.feature(vertical, 32, 32);
  const b = PerceptualHash.feature(horizontal, 32, 32);
  assert.equal(PerceptualHash.matches(a, b), false);
  const thinVertical = solidRgba(255, 255, 255);
  const thinHorizontal = solidRgba(255, 255, 255);
  for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) {
    if (x === 15 || x === 16) {
      const p = (y * 32 + x) * 4;
      thinVertical[p] = thinVertical[p + 1] = thinVertical[p + 2] = 0;
    }
    if (y === 15 || y === 16) {
      const p = (y * 32 + x) * 4;
      thinHorizontal[p] = thinHorizontal[p + 1] = thinHorizontal[p + 2] = 0;
    }
  }
  assert.equal(PerceptualHash.matches(PerceptualHash.feature(thinVertical, 32, 32),
    PerceptualHash.feature(thinHorizontal, 32, 32)), false);
  const c = PerceptualHash.feature(vertical, 32, 32);
  c.width = 800; c.height = 400;
  assert.equal(PerceptualHash.matches(a, c), false);
  c.version = 99;
  assert.equal(PerceptualHash.matches(c, c), false);
});

caseTest('similar groups require every member to match the representative', () => {
  const { PerceptualHash } = load(ets('util/PerceptualHash'));
  const { VisualFeature } = load(ets('model/LibraryAsset'));
  const make = bits => { const value = new VisualFeature();
    value.lowBits = bits; value.edgeBits = '0'.repeat(64);
    value.red = value.green = value.blue = 100; value.alpha = 255;
    value.width = 800; value.height = 600; return value; };
  const features = new Map([
    ['a', make('0'.repeat(64))],
    ['b', make('1'.repeat(7) + '0'.repeat(57))],
    ['c', make('1'.repeat(14) + '0'.repeat(50))]
  ]);
  assert.equal(PerceptualHash.matches(features.get('a'), features.get('b')), true);
  assert.equal(PerceptualHash.matches(features.get('b'), features.get('c')), true);
  assert.equal(PerceptualHash.matches(features.get('a'), features.get('c')), false);
  const groups = PerceptualHash.groups(['a', 'b', 'c'], features);
  assert.deepEqual(groups.map(group => [group.representativeId, group.ids]), [['a', ['a', 'b']]]);
});

caseTest('edit geometry crop then clockwise turn follows independent pixel oracle', () => {
  const { ImageEditGeometry } = load(ets('util/ImageEditGeometry'));
  const doc = ImageEditGeometry.create(800, 600);
  doc.crop.x = 100; doc.crop.y = 50; doc.crop.width = 400; doc.crop.height = 300; doc.turns = 1;
  assert.deepEqual({ ...ImageEditGeometry.outputSize(doc) }, { width: 300, height: 400 });
  assert.deepEqual({ ...ImageEditGeometry.toOutput({ x: 200, y: 150 }, doc) }, { x: 199, y: 100 });
  assert.deepEqual({ ...ImageEditGeometry.toSource({ x: 259, y: 40 }, doc) }, { x: 140, y: 90 });
});

caseTest('edit geometry handles all quarter turns and reversible crop edges', () => {
  const { ImageEditGeometry } = load(ets('util/ImageEditGeometry'));
  const doc = ImageEditGeometry.create(20, 10);
  doc.crop = { x: 3, y: 2, width: 8, height: 5 };
  const source = { x: 4, y: 3 };
  const expected = [[1, 1], [3, 1], [6, 3], [1, 6]];
  for (let turns = 0; turns < 4; turns++) {
    doc.turns = turns;
    const output = ImageEditGeometry.toOutput(source, doc);
    assert.deepEqual([output.x, output.y], expected[turns]);
    const restored = ImageEditGeometry.toSource(output, doc);
    assert.deepEqual([restored.x, restored.y], [4, 3]);
  }
  assert.deepEqual({ ...ImageEditGeometry.constrainCrop({ x: 12, y: 7, width: -9, height: -5 }, 20, 10) },
    { x: 3, y: 2, width: 9, height: 5 });
  assert.deepEqual({ ...ImageEditGeometry.constrainCrop({ x: -50, y: -50, width: 1, height: 1 }, 20, 10) },
    { x: 0, y: 0, width: 1, height: 1 });
});

caseTest('edit geometry aspect crop and history preserve source-space strokes', () => {
  const { ImageEditGeometry } = load(ets('util/ImageEditGeometry'));
  const { EditHistory, EditStroke } = load(ets('model/ImageEditDocument'));
  const original = ImageEditGeometry.create(800, 600);
  original.crop = { x: 100, y: 50, width: 400, height: 300 };
  const square = ImageEditGeometry.aspectCrop(original, 1);
  assert.deepEqual({ ...square }, { x: 150, y: 50, width: 300, height: 300 });
  const history = new EditHistory(); history.reset(original);
  const changed = ImageEditGeometry.copy(original);
  const stroke = new EditStroke(); stroke.points = [{ x: 200, y: 150 }];
  changed.strokes.push(stroke); changed.turns = 1;
  history.commit(changed);
  stroke.points[0].x = 999;
  assert.equal(history.canUndo(), true);
  const previous = history.undo();
  assert.equal(previous.turns, 0);
  assert.deepEqual(previous.strokes, []);
  assert.equal(history.canUndo(), false);
  assert.deepEqual({ ...ImageEditGeometry.aspectCrop(original, 0) },
    { x: 100, y: 50, width: 400, height: 300 });
  assert.deepEqual({ ...ImageEditGeometry.aspectCrop(original, 4 / 3) },
    { x: 100, y: 50, width: 400, height: 300 });
  const reset = ImageEditGeometry.copy(changed);
  reset.crop = { x: 0, y: 0, width: 800, height: 600 };
  assert.deepEqual([reset.strokes[0].points[0].x, reset.strokes[0].points[0].y],
    [changed.strokes[0].points[0].x, changed.strokes[0].points[0].y]);
});

caseTest('edit geometry view mapping excludes letterbox and keeps source document fixed', () => {
  const { ImageEditGeometry } = load(ets('util/ImageEditGeometry'));
  const doc = ImageEditGeometry.create(800, 600);
  const before = ImageEditGeometry.copy(doc);
  const viewport = { x: 0, y: 0, width: 600, height: 600 };
  assert.deepEqual({ ...ImageEditGeometry.viewRect(doc, viewport) },
    { x: 0, y: 75, width: 600, height: 450 });
  assert.equal(ImageEditGeometry.viewToSource({ x: 300, y: 20 }, doc, viewport), undefined);
  const center = ImageEditGeometry.viewToSource({ x: 300, y: 300 }, doc, viewport);
  assert.ok(Math.abs(center.x - 399.5) < 0.01);
  assert.ok(Math.abs(center.y - 299.5) < 0.01);
  assert.deepEqual(doc, before);
});

caseTest('edit geometry crop preview keeps full source reachable after a smaller crop', () => {
  const { ImageEditGeometry } = load(ets('util/ImageEditGeometry'));
  const doc = ImageEditGeometry.create(800, 600);
  doc.crop = { x: 200, y: 150, width: 400, height: 300 };
  doc.turns = 1;
  doc.strokes = [{ kind: 'pen', points: [{ x: 210, y: 160 }] }];
  const display = ImageEditGeometry.forCropPreview(doc);
  assert.equal(display.strokes.length, 0);
  assert.equal(doc.strokes.length, 1);
  assert.deepEqual({ ...display.crop }, { x: 0, y: 0, width: 800, height: 600 });
  assert.deepEqual({ ...doc.crop }, { x: 200, y: 150, width: 400, height: 300 });
  const viewport = { x: 0, y: 0, width: 600, height: 800 };
  const outside = { x: 100, y: 100 };
  const point = ImageEditGeometry.sourceToView(outside, display, viewport);
  const recovered = ImageEditGeometry.viewToSource(point, display, viewport);
  assert.ok(Math.abs(recovered.x - outside.x) < 0.01);
  assert.ok(Math.abs(recovered.y - outside.y) < 0.01);
});

caseTest('edit geometry rejects malformed dimensions and history snapshots are independent', () => {
  const { ImageEditGeometry } = load(ets('util/ImageEditGeometry'));
  const { EditHistory, EditStroke } = load(ets('model/ImageEditDocument'));
  assert.throws(() => ImageEditGeometry.create(0, 10));
  assert.throws(() => ImageEditGeometry.create(Number.NaN, 10));
  assert.deepEqual({ ...ImageEditGeometry.constrainCrop(
    { x: Number.NaN, y: 0, width: 10, height: 10 }, 30, 20) },
    { x: 0, y: 0, width: 30, height: 20 });
  assert.deepEqual({ ...ImageEditGeometry.constrainCrop(
    { x: 29, y: 19, width: 0, height: 0 }, 30, 20) },
    { x: 29, y: 19, width: 1, height: 1 });
  const initial = ImageEditGeometry.create(30, 20);
  const history = new EditHistory(); history.reset(initial);
  const withStroke = ImageEditGeometry.copy(initial);
  const stroke = new EditStroke(); stroke.points = [{ x: 7, y: 8 }];
  withStroke.strokes = [stroke];
  history.commit(withStroke);
  stroke.points[0].x = 999;
  const turned = ImageEditGeometry.copy(withStroke); turned.turns = 1;
  history.commit(turned);
  const restored = history.undo();
  assert.deepEqual([restored.strokes[0].points[0].x, restored.strokes[0].points[0].y], [7, 8]);
  restored.strokes[0].points[0].x = 123;
  assert.deepEqual([history.undo().strokes.length, history.canUndo()], [0, false]);
});

function oracleDocument() {
  const { ImageEditGeometry } = load(ets('util/ImageEditGeometry'));
  const doc = ImageEditGeometry.create(800, 600);
  doc.crop.x = 100; doc.crop.y = 50; doc.crop.width = 400; doc.crop.height = 300;
  doc.turns = 1;
  return doc;
}

function oracleBlueStroke() {
  const { EditStroke } = load(ets('model/ImageEditDocument'));
  const stroke = new EditStroke(); stroke.kind = 'pen'; stroke.color = '#0000FF';
  stroke.width = 3; stroke.points = [{ x: 200, y: 150 }];
  return stroke;
}

caseTest('edit BGRA paint changes red source to blue only on stroke', () => {
  const { EditRasterizer } = load(ets('util/EditRasterizer'));
  const doc = oracleDocument(); doc.strokes = [oracleBlueStroke()];
  const tile = { x: 198, y: 99, width: 3, height: 3 };
  const pixels = new Uint8Array(36);
  for (let i = 0; i < 36; i += 4) { pixels[i + 2] = 255; pixels[i + 3] = 255; }
  EditRasterizer.paintBgra(pixels, tile, doc, true);
  assert.deepEqual([...pixels.slice(16, 20)], [255, 0, 0, 255]);
});

caseTest('edit BGRA paint preserves untouched transparent bytes and blends a soft edge', () => {
  const { EditRasterizer } = load(ets('util/EditRasterizer'));
  const doc = oracleDocument(); doc.strokes = [oracleBlueStroke()];
  const tile = { x: 197, y: 98, width: 5, height: 5 };
  const pixels = new Uint8Array(100);
  for (let i = 0; i < pixels.length; i += 4) {
    pixels[i] = 7; pixels[i + 1] = 3; pixels[i + 2] = 128; pixels[i + 3] = 128;
  }
  const before = pixels.slice(0, 4);
  EditRasterizer.paintBgra(pixels, tile, doc, true);
  assert.deepEqual([...pixels.slice(0, 4)], [...before]);
  const center = (2 * 5 + 2) * 4;
  assert.deepEqual([...pixels.slice(center, center + 4)], [255, 0, 0, 255]);
  const edge = (3 * 5 + 3) * 4;
  assert.ok(pixels[edge] > 100 && pixels[edge] < 255);
  assert.ok(pixels[edge + 2] > 0 && pixels[edge + 2] < 128);
  assert.ok(pixels[edge + 3] > 128 && pixels[edge + 3] < 255);
});

caseTest('edit BGRA rectangle paints border while retaining red interior', () => {
  const { EditRasterizer } = load(ets('util/EditRasterizer'));
  const { EditStroke } = load(ets('model/ImageEditDocument'));
  const { ImageEditGeometry } = load(ets('util/ImageEditGeometry'));
  const doc = ImageEditGeometry.create(9, 9);
  const rectangle = new EditStroke(); rectangle.kind = 'rect'; rectangle.color = '#000000';
  rectangle.width = 1; rectangle.points = [{ x: 1, y: 1 }, { x: 7, y: 7 }];
  doc.strokes = [rectangle];
  const tile = { x: 0, y: 0, width: 9, height: 9 };
  const pixels = new Uint8Array(9 * 9 * 4);
  for (let i = 0; i < pixels.length; i += 4) { pixels[i + 2] = 255; pixels[i + 3] = 255; }
  EditRasterizer.paintBgra(pixels, tile, doc, false);
  const at = (x, y) => [...pixels.slice((y * 9 + x) * 4, (y * 9 + x) * 4 + 4)];
  assert.deepEqual(at(4, 1), [0, 0, 0, 255]);
  assert.deepEqual(at(4, 4), [0, 0, 255, 255]);
  assert.deepEqual(at(0, 0), [0, 0, 255, 255]);
});

function editExportHarness(config = {}) {
  const events = [];
  const files = new Map([['/original.png', 123]]);
  if (config.existing) files.set('/pending.png', 77);
  const { AssetStamp, AnalysisToken } = load(ets('model/LibraryAsset'));
  const { ImageEditGeometry } = load(ets('util/ImageEditGeometry'));
  const stamp = new AssetStamp(); stamp.id = 'a'; stamp.path = '/original.png';
  const token = new AnalysisToken();
  const doc = ImageEditGeometry.create(9, 9);
  const frame = {
    rotate: async angle => events.push(['rotate', angle]),
    getImageInfo: async () => ({ size: { width: 9, height: 9 }, alphaType: 2, pixelFormat: 3 }),
    readPixels: async area => { events.push(['read', area.region]);
      const bytes = new Uint8Array(area.pixels);
      for (let i = 0; i < bytes.length; i += 4) { bytes[i + 2] = 255; bytes[i + 3] = 255; }
      if (config.cancelAfterRead) token.cancel();
    },
    writePixels: async area => events.push(['write', [...new Uint8Array(area.pixels)]]),
    release: async () => events.push('frame.release')
  };
  const fs = {
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    accessSync: name => files.has(name),
    openSync: name => { files.set(name, 0); events.push(['open', name]); return { fd: 1 }; },
    closeSync: () => events.push('close'),
    statSync: name => ({ size: files.get(name) ?? 0 }),
    unlinkSync: name => { events.push(['unlink', name]); files.delete(name); }
  };
  const image = {
    PixelMapFormat: { RGBA_8888: 3 }, AlphaType: { PREMUL: 2, UNPREMUL: 3 },
    createImagePacker: () => ({
      packToFile: async (_frame, fd, options) => { events.push(['pack', options.format]);
        if (config.failPack) throw new Error('pack failed');
        files.set('/pending.png', 99);
      },
      release: async () => events.push('packer.release')
    }),
    createImageSource: name => ({ getImageInfo: async () => ({ size: { width: 9, height: 9 }, mimeType: 'image/png' }),
      release: async () => events.push('verify.release') })
  };
  const reader = { info: async () => ({ width: 9, height: 9 }),
    decode: async () => frame };
  const Export = loader({
    '@kit.ImageKit': { image }, '@kit.CoreFileKit': { fileIo: fs },
    [ets('service/LibraryImageReader')]: { LibraryImageReader: reader }
  })(ets('service/EditExport')).EditExport;
  return { Export, stamp, token, doc, events, files };
}

caseTest('edit export writes an independent PNG, verifies dimensions and preserves original', async () => {
  const h = editExportHarness();
  const { EditStroke } = load(ets('model/ImageEditDocument'));
  const stroke = new EditStroke(); stroke.kind = 'pen'; stroke.color = '#0000FF';
  stroke.width = 3; stroke.points = [{ x: 4, y: 4 }];
  h.doc.strokes = [stroke];
  const result = await h.Export.render(h.stamp, h.doc, '/pending.png', h.token);
  assert.deepEqual([result.path, result.width, result.height, result.bytes], ['/pending.png', 9, 9, 99]);
  assert.equal(h.files.get('/original.png'), 123);
  assert.deepEqual(h.events.filter(x => Array.isArray(x) && x[0] === 'pack').map(x => x[1]), ['image/png']);
  assert.ok(h.events.includes('close'));
  assert.ok(h.events.includes('frame.release'));
  assert.ok(h.events.includes('packer.release'));
  assert.ok(h.events.includes('verify.release'));
  assert.ok(h.events.some(x => Array.isArray(x) && x[0] === 'write'));
});

caseTest('edit export removes only its own pending file on failure or cancellation', async () => {
  const failed = editExportHarness({ failPack: true });
  await assert.rejects(failed.Export.render(failed.stamp, failed.doc, '/pending.png', failed.token));
  assert.equal(failed.files.has('/pending.png'), false);
  assert.equal(failed.files.get('/original.png'), 123);
  assert.ok(failed.events.includes('frame.release'));
  assert.ok(failed.events.includes('packer.release'));
  const existing = editExportHarness({ existing: true });
  await assert.rejects(existing.Export.render(existing.stamp, existing.doc, '/pending.png', existing.token));
  assert.equal(existing.files.get('/pending.png'), 77);
  const cancelled = editExportHarness({ cancelAfterRead: true });
  const stroke = oracleBlueStroke(); stroke.points = [{ x: 4, y: 4 }];
  cancelled.doc.strokes = [stroke];
  await assert.rejects(cancelled.Export.render(cancelled.stamp, cancelled.doc, '/pending.png', cancelled.token));
  assert.equal(cancelled.files.has('/pending.png'), false);
});

caseTest('search view model preserves filters while toggling real image favorite', async () => {
  const v = libraryVmHarness();
  await v.h.catalog.initialize('/files');
  await v.h.seedAssets(['a']);
  v.store.downloads = [completed('a', 'a.png')];
  v.vm.sync();
  v.vm.searchScope = 'text'; v.vm.query = '订单'; v.vm.tagFilter = '收据';
  await v.vm.toggleFavorite('a');
  assert.equal(v.h.catalog.getMeta('a').favorite, true);
  assert.equal(v.vm.searchScope, 'text');
  assert.equal(v.vm.query, '订单');
  assert.equal(v.vm.tagFilter, '收据');
  assert.deepEqual(v.port.messages, []);
});

caseTest('gallery refresh drops stale text after same-path same-size source replacement', async () => {
  const v = libraryVmHarness();
  await v.h.catalog.initialize('/files');
  await v.h.seedAssets(['a']);
  assert.equal(await v.h.catalog.putIndex(indexed('a', 7, 1, 'OLD')), true);
  v.store.downloads = [completed('a', 'a.png')];
  v.vm.sync();
  await v.vm.refreshCatalog();
  assert.equal(v.vm.entry('a').text, 'OLD');
  v.h.changedFile('a', 'new-a!!', 1, 2);
  await v.vm.refreshCatalog();
  assert.equal(v.vm.entry('a').text, '');
  assert.equal(v.vm.entry('a').ocrStatus, 'unindexed');
});

caseTest('search view model batch tags and favorite affect selected images only', async () => {
  const v = libraryVmHarness();
  await v.h.catalog.initialize('/files');
  await v.h.seedAssets(['a', 'b']);
  v.store.downloads = [completed('a', 'a.png'), completed('b', 'b.png')];
  v.vm.sync();
  v.vm.toggleSelection('a');
  await v.vm.changeSelectedTags([' 收据 ', '收据'], []);
  await v.vm.setSelectedFavorite(true);
  assert.deepEqual(v.h.catalog.getMeta('a').tags, ['收据']);
  assert.equal(v.h.catalog.getMeta('a').favorite, true);
  assert.deepEqual(v.h.catalog.getMeta('b').tags, []);
  assert.equal(v.h.catalog.getMeta('b').favorite, false);
});

caseTest('search preview identity resolves only a completed original URL', async () => {
  const h = catalogHarness();
  await h.catalog.initialize('/files');
  const items = await h.seedAssets(['a', 'b']);
  items[0].url = 'https://example.test/image.png';
  items[1].url = '';
  items[1].origin = 'edited'; items[1].originalId = 'a';
  await h.catalog.reconcile(items);
  assert.equal(h.catalog.assetForPreview(items, items[0].url, 'image'), 'a');
  assert.equal(h.catalog.assetForPreview(items, 'https://other.test/image.png', 'image'), '');
  assert.equal(h.catalog.assetForPreview(items, '', 'image'), '');
});

caseTest('search view model offers retry after catalog load failure', async () => {
  const v = libraryVmHarness();
  v.h.files.set('/files/library-catalog.json', {
    data: Buffer.from('{"version":99,"metas":[]}'), mtime: 1, ctime: 1
  });
  await assert.rejects(v.h.catalog.initialize('/files'));
  v.vm.catalogChanged();
  assert.equal(v.vm.catalogReady, false);
  v.h.files.set('/files/library-catalog.json', {
    data: Buffer.from('{"version":1,"metas":[]}'), mtime: 2, ctime: 2
  });
  await v.vm.retryCatalog();
  assert.equal(v.vm.catalogReady, true);
});
