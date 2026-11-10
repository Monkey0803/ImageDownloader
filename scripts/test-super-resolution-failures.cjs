#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require(process.env.ARKTS_TEST_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/tools/ohpm/node_modules/typescript');

function harness(problem) {
  const events = [];
  const stamp = { path: '/qa/original.png', bytes: 100, modified: 1, changed: 0, orientation: 1 };
  const input = { getImageInfo: async () => ({ size: { width: 10, height: 10 } }),
    release: async () => { events.push('release input'); } };
  const filename = path.join(__dirname, '../entry/src/main/ets/service/ImageSuperResolution.ets');
  const mocks = {
    '@kit.CoreVisionKit': { imageSuperResolution: { ImageSRAnalyzer: { create: async () => ({
      process: async () => { events.push('process'); throw new Error(problem); },
      destroy: async () => { events.push('destroy analyzer'); }
    }) } }, visionBase: {} },
    '@kit.BasicServicesKit': { deviceInfo: { productModel: 'phone' } },
    '@kit.ImageKit': { image: {} },
    '@kit.CoreFileKit': { fileIo: {} },
    '../model/ImageEditDocument': { EditRect: class { width = 0; height = 0; } },
    './DownloadStore': { DownloadStore: { downloads: [
      { id: 'qa', status: 'completed', path: stamp.path }
    ], exists: () => true } },
    './EditJournal': { EditJournal: { prepare: async () => { events.push('prepare'); } } },
    './LibraryImageReader': { LibraryImageReader: { stamp: async () => stamp,
      info: async () => ({ width: 10, height: 10 }), decode: async () => input } },
    './SuperResolutionGeometry': { SuperResolutionGeometry: { decodeSize: () => ({ width: 10, height: 10 }) } }
  };
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS,
      experimentalDecorators: true }
  }).outputText;
  const module = { exports: {} };
  new Function('require', 'exports', 'module', 'canIUse', output)(
    (name) => {
      if (!Object.hasOwn(mocks, name)) throw new Error('Unmocked: ' + name);
      return mocks[name];
    }, module.exports, module, () => true);
  return { ImageSuperResolution: module.exports.ImageSuperResolution, events };
}

for (const [nativeMessage, userMessage] of [
  ['service is abnormal', '超分服务暂不可用，请稍后重试'],
  ['timed out', '超分服务超时，请重试']
]) {
  test('super-resolution failure releases resources: ' + nativeMessage, async () => {
    const h = harness(nativeMessage);
    for (let attempt = 0; attempt < 2; attempt++) {
      await assert.rejects(h.ImageSuperResolution.createCopy('qa', { cancelled: false }),
        (error) => { assert.equal(error.message, userMessage); return true; });
    }
    assert.deepEqual(h.events, [
      'process', 'release input', 'destroy analyzer',
      'process', 'release input', 'destroy analyzer'
    ]);
  });
}
