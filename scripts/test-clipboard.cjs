#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require(process.env.ARKTS_TEST_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/tools/ohpm/node_modules/typescript');

function clipboardHarness(options = {}) {
  const calls = [];
  const board = {
    hasData: async () => { calls.push('hasData'); return options.empty ? false : true; },
    getData: async () => {
      calls.push('getData');
      if (options.getError) throw { code: options.getError };
      return {
        getPrimaryText: () => options.text || '',
        hasMimeType: (mime) => mime === 'text/plain' && options.nonText !== true
      };
    }
  };
  const mocks = {
    '@kit.BasicServicesKit': { pasteboard: {
      getSystemPasteboard: () => board, MIMETYPE_TEXT_PLAIN: 'text/plain'
    } }
  };
  const filename = path.join(__dirname, '../entry/src/main/ets/service/Clipboard.ets');
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const module = { exports: {} };
  new Function('require', 'exports', 'module', output)((name) => mocks[name], module.exports, module);
  return { Clipboard: module.exports.Clipboard, calls };
}

test('paste reads text after the security button authorized this click', async () => {
  const h = clipboardHarness({ text: 'https://example.com/a.jpg' });
  assert.equal(await h.Clipboard.readText(), 'https://example.com/a.jpg');
  assert.deepEqual(h.calls, ['hasData', 'getData']);
});

test('paste handles empty and non-text data separately', async () => {
  const empty = clipboardHarness({ empty: true });
  assert.equal(await empty.Clipboard.readText(), '');
  assert.deepEqual(empty.calls, ['hasData']);
  const blankText = clipboardHarness();
  assert.equal(await blankText.Clipboard.readText(), '');
  const nonText = clipboardHarness({ nonText: true });
  await assert.rejects(nonText.Clipboard.readText(), (error) => {
    assert.equal(nonText.Clipboard.readProblemMessage(error), '剪贴板内容不是文字');
    return true;
  });
});

test('paste classifies expired authorization and native busy errors', async () => {
  const permission = clipboardHarness({ getError: 201 });
  await assert.rejects(permission.Clipboard.readText(), (error) => {
    assert.equal(permission.Clipboard.readProblemMessage(error), '剪贴板授权已失效，请再次点击粘贴');
    return true;
  });
  const busy = clipboardHarness({ getError: 27787277 });
  await assert.rejects(busy.Clipboard.readText(), (error) => {
    assert.equal(busy.Clipboard.readProblemMessage(error), '剪贴板暂时无法读取，请重试');
    return true;
  });
});
