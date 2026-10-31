#!/usr/bin/env node
const assert = require('node:assert/strict');
const path = require('node:path');
const { test } = require('node:test');
const { loader } = require('./lib/arkts-test-loader.cjs');

const source = path.resolve(__dirname, '../entry/src/main/ets');
const modulePath = (name) => path.join(source, name + '.ets');

function viewerHarness() {
  const listeners = new Set();
  const records = [];
  const existing = new Set();
  const store = {
    downloads: records,
    exists: (file) => existing.has(file),
    subscribe: (listener) => listeners.add(listener),
    unsubscribe: (listener) => listeners.delete(listener),
    renameDownload: (item, name) => { item.name = name; listeners.forEach((listener) => listener()); return true; },
    deleteDownload: (item) => {
      const index = records.indexOf(item);
      if (index < 0) return false;
      records.splice(index, 1);
      listeners.forEach((listener) => listener());
      return true;
    },
    saveToGallery: () => {}
  };
  const load = loader({
    '@kit.AbilityKit': { common: {} },
    '@kit.CoreFileKit': { fileUri: { getUriFromPath: (file) => 'file://' + file } },
    [modulePath('service/DownloadStore')]: { DownloadStore: store },
    [modulePath('service/FileActions')]: {
      exportFile: async () => ({ ok: true, message: '' }),
      shareFile: async () => ({ ok: true, message: '' }),
      shareLivePhoto: async () => ({ ok: true, message: '' })
    },
    [modulePath('theme/Tokens')]: { kindOf: () => '图片' }
  });
  const { ViewerViewModel } = load(modulePath('viewmodel/ViewerViewModel'));
  const make = (id) => ({ id, url: 'https://example.test/' + id, sourcePage: '', path: '/' + id,
    stillPath: '', motionPath: '', status: 'completed', kind: 'image', animated: false,
    size: 10, finishedAt: 1, name: id + '.jpg', note: '', receipt: { status: '', message: '' } });
  return { ViewerViewModel, records, existing, listeners, make };
}

test('viewer opens the requested image and keeps its order after store refresh', () => {
  const h = viewerHarness();
  h.records.push(h.make('a'), h.make('b'), h.make('c'));
  h.existing.add('/a'); h.existing.add('/b'); h.existing.add('/c');
  const vm = new h.ViewerViewModel();
  vm.start({ id: 'b', ids: ['a', 'b', 'c'], rename: true });
  assert.equal(vm.currentId(), 'b');
  assert.equal(vm.slides[1].src, 'file:///b');
  assert.equal(vm.local, true);
  vm.setIndex(2);
  assert.equal(vm.currentId(), 'c');
  vm.stop();
  assert.equal(h.listeners.size, 0);
});

test('viewer deletion prefers the next surviving image and closes after the last', () => {
  const h = viewerHarness();
  h.records.push(h.make('a'), h.make('b'), h.make('c'));
  const vm = new h.ViewerViewModel();
  vm.start({ id: 'b', ids: ['a', 'b', 'c'] });
  assert.equal(vm.deleteCurrent(), false);
  assert.equal(vm.currentId(), 'c');
  assert.equal(vm.deleteCurrent(), false);
  assert.equal(vm.currentId(), 'a');
  assert.equal(vm.deleteCurrent(), true);
  assert.equal(vm.missing, true);
  vm.stop();
});

test('viewer distinguishes a missing local file from an unfinished download', () => {
  const h = viewerHarness();
  const item = h.make('a');
  h.records.push(item);
  const vm = new h.ViewerViewModel();
  vm.start({ id: 'a' });
  assert.match(vm.localHint(), /应用内文件已不存在/);
  item.status = 'running';
  vm.refresh();
  assert.match(vm.localHint(), /还没下载完成/);
  vm.stop();
});

test('preview tools ignore metadata from a previously selected image', async () => {
  const pending = new Map();
  const listeners = new Set();
  class ImageMetadata { constructor() { this.width = 0; this.height = 0; } }
  const load = loader({
    [modulePath('model/LibraryAsset')]: { AnalysisToken: class { cancel() {} } },
    [modulePath('service/DownloadStore')]: { DownloadStore: { downloads: [], exists: () => false } },
    [modulePath('service/ImageTools')]: { ImageMetadata, ImageTools: {
      metadata: (file) => new Promise((resolve) => pending.set(file, resolve)),
      copy: async () => {}, link: () => '', open: async () => {}
    } },
    [modulePath('service/ImageSuperResolution')]: { ImageSuperResolution: {
      available: () => false, unavailableHint: () => '不可用'
    } },
    [modulePath('service/LibraryCatalog')]: { LIBRARY_CATALOG: {
      subscribe: (listener) => listeners.add(listener),
      unsubscribe: (listener) => listeners.delete(listener),
      getMeta: () => ({ favorite: false, tags: [] })
    } },
    [modulePath('service/LibraryAnalysis')]: { LibraryAnalysis: {} },
    [modulePath('service/MediaFormat')]: { MediaFormat: { isLivepicStill: () => false } }
  });
  const { PreviewToolsViewModel } = load(modulePath('viewmodel/PreviewToolsViewModel'));
  const vm = new PreviewToolsViewModel();
  vm.start({ id: 'first', localPath: '/first', libraryId: '', width: 0, height: 0 });
  vm.load({ id: 'second', localPath: '/second', libraryId: '', width: 0, height: 0 });
  pending.get('/first')({ width: 100, height: 100 });
  await Promise.resolve();
  assert.equal(vm.metadata.width, 0);
  pending.get('/second')({ width: 200, height: 300 });
  await Promise.resolve();
  assert.equal(vm.dimensions(), '200 × 300');
  vm.stop();
  assert.equal(listeners.size, 0);
});

test('comparison pane discards a late response after the source changes', async () => {
  const pending = new Map();
  class AuthenticatedPreview {
    cancel() {}
    load(url) { return new Promise((resolve) => pending.set(url, resolve)); }
  }
  const load = loader({
    [modulePath('service/AuthenticatedPreview')]: { AuthenticatedPreview },
    [modulePath('service/DownloadStore')]: { DownloadStore: { context: { cacheDir: '/cache' } } },
    [modulePath('service/ImageTools')]: { ImageTools: { link: (url) => url } }
  });
  const { ComparisonPaneViewModel } = load(modulePath('viewmodel/ComparisonPaneViewModel'));
  const vm = new ComparisonPaneViewModel();
  vm.start({ id: 'first', localPath: '', url: 'https://first', sourcePage: '' });
  vm.load({ id: 'second', localPath: '', url: 'https://second', sourcePage: '' });
  pending.get('https://first')({ path: '/first', uri: 'file:///first', message: '' });
  await Promise.resolve();
  assert.equal(vm.uriValue, '');
  pending.get('https://second')({ path: '/second', uri: 'file:///second', message: '' });
  await Promise.resolve();
  assert.equal(vm.uriValue, 'file:///second');
  vm.stop();
});

test('frame save keeps the selected frame and ignores completion after reset', async () => {
  const saved = [];
  let finish;
  const load = loader({
    [modulePath('service/DownloadStore')]: { DownloadStore: { context: {} } },
    [modulePath('service/ImageTools')]: { ImageTools: { saveFrame: async (_context, file, name, index, destination) => {
      saved.push({ file, name, index, destination });
      return await new Promise((resolve) => { finish = resolve; });
    } } },
    [modulePath('service/FileActions')]: {}
  });
  const { FrameSaveViewModel } = load(modulePath('viewmodel/FrameSaveViewModel'));
  const vm = new FrameSaveViewModel();
  vm.start();
  const saving = vm.save('/animation.gif', 'animation.gif', 3, async () => 'album');
  await Promise.resolve();
  assert.deepEqual(saved, [{ file: '/animation.gif', name: 'animation.gif', index: 3, destination: 'album' }]);
  assert.equal(vm.exporting, true);
  vm.reset();
  finish({ ok: true, message: '已保存' });
  await saving;
  assert.equal(vm.notice, '');
  assert.equal(vm.exporting, false);
  vm.stop();
});
