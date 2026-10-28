#!/usr/bin/env node
// Host-side tests for batch-link parsing and HEAD verdict merging.
// This runner does not touch the network or a HarmonyOS device.
const path = require('node:path');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { loader } = require('./lib/arkts-test-loader.cjs');

const root = path.resolve(__dirname, '..');
const source = path.join(root, 'entry/src/main/ets');
const ets = (name) => path.join(source, name + '.ets');
const filterArg = process.argv.find((value) => value.startsWith('--filter='));
const filter = filterArg ? filterArg.slice('--filter='.length) : '';
const caseTest = (name, run) => {
  if (!filter || name.includes(filter)) test(name, run);
};

const load = loader();
const { BatchLinks, BatchLinkStatus, BatchCheckKind } = load(ets('service/BatchLinks'));

function rowOf(report, line) {
  const found = report.rows.find((row) => row.line === line);
  if (found === undefined) throw new Error('missing row ' + line);
  return found;
}

function checkOf(url, kind) {
  const { BatchLinkCheck } = load(ets('service/BatchLinks'));
  const check = new BatchLinkCheck();
  check.url = url;
  check.kind = kind;
  if (kind === BatchCheckKind.IMAGE) {
    check.mime = 'image/png';
    check.detail = '已确认图片 · image/png';
  } else if (kind === BatchCheckKind.PAGE) {
    check.mime = 'text/html';
    check.detail = '已确认网页，不导入';
  } else {
    check.detail = '类型未确认，仍可导入';
  }
  return check;
}

caseTest('batch links report every row without dropping pending links', () => {
  const report = BatchLinks.parse('https://a.example/a.jpg\n'
    + 'https://a.example/b.webp?token=1\nhttps://a.example/a.jpg\n'
    + 'ftp://a.example/c.png\nhttps://a.example/page.html\n'
    + 'https://a.example/noext\nhttps://a.example/pic.php?sign=1\n'
    + 'https://a.example/photo.png\n');
  assert.equal(report.rows.length, 8);
  assert.equal(rowOf(report, 1).status, BatchLinkStatus.VALID);
  assert.equal(rowOf(report, 3).status, BatchLinkStatus.DUPLICATE);
  assert.equal(rowOf(report, 3).duplicateOf, 1);
  assert.equal(rowOf(report, 4).status, BatchLinkStatus.INVALID);
  assert.equal(rowOf(report, 5).status, 'page');
  assert.equal(rowOf(report, 6).status, BatchLinkStatus.PENDING);
  assert.equal(rowOf(report, 7).status, BatchLinkStatus.PENDING);
  assert.equal(report.valid, 3);
  assert.equal(report.pending, 2);
  assert.equal(report.invalid, 1);
  assert.equal(report.duplicates, 1);
  assert.deepEqual(report.urls, [
    'https://a.example/a.jpg',
    'https://a.example/b.webp?token=1',
    'https://a.example/page.html',
    'https://a.example/noext',
    'https://a.example/pic.php?sign=1',
    'https://a.example/photo.png'
  ]);
});

caseTest('signed extensionless links stay distinct and pending', () => {
  const report = BatchLinks.parse('https://cdn.example/image?id=42&sign=a\n'
    + 'https://cdn.example/image?id=42&sign=b\nhttps://cdn.example/dl.ashx\n'
    + 'https://cdn.example/archive.zip\n');
  assert.equal(rowOf(report, 1).status, BatchLinkStatus.PENDING);
  assert.equal(rowOf(report, 2).status, BatchLinkStatus.PENDING);
  assert.equal(rowOf(report, 3).status, BatchLinkStatus.PENDING);
  assert.equal(rowOf(report, 4).status, BatchLinkStatus.INVALID);
  assert.equal(report.duplicates, 0);
  assert.equal(report.urls.length, 3);
});

caseTest('merge routes HTML to page parsing without losing signed links', () => {
  const parsed = BatchLinks.parse('https://a.example/noext\n'
    + 'https://a.example/page\nhttps://a.example/unknown\nhttps://a.example/a.jpg\n');
  const merged = BatchLinks.merge(parsed, [
    checkOf('https://a.example/noext', BatchCheckKind.IMAGE),
    checkOf('https://a.example/page', BatchCheckKind.PAGE),
    checkOf('https://a.example/unknown', BatchCheckKind.UNKNOWN),
    checkOf('https://a.example/a.jpg', BatchCheckKind.PAGE)
  ]);
  assert.equal(rowOf(merged, 1).status, BatchLinkStatus.VALID);
  assert.equal(rowOf(merged, 1).probed, true);
  assert.equal(rowOf(merged, 2).status, 'page');
  assert.equal(rowOf(merged, 3).status, BatchLinkStatus.PENDING);
  assert.equal(rowOf(merged, 4).status, BatchLinkStatus.VALID);
  assert.deepEqual(merged.urls, [
    'https://a.example/noext',
    'https://a.example/page',
    'https://a.example/unknown',
    'https://a.example/a.jpg'
  ]);
  assert.equal(merged.valid, 2);
  assert.equal(merged.pending, 1);
  assert.equal(merged.pages, 1);
  assert.equal(merged.invalid, 0);
});

caseTest('stale checks are ignored and inputs are not mutated', () => {
  const parsed = BatchLinks.parse('https://a.example/noext\n');
  const before = parsed.rows[0].status;
  const merged = BatchLinks.merge(parsed, [
    checkOf('https://a.example/gone', BatchCheckKind.PAGE)
  ]);
  assert.equal(parsed.rows[0].status, before);
  assert.equal(merged.rows[0].status, BatchLinkStatus.PENDING);
  assert.equal(merged.urls.length, 1);
});

caseTest('HEAD verdicts never treat unknown failures as invalid', () => {
  const image = BatchLinks.checkOf('https://a.example/a', 200, 'image/png; charset=utf-8', false);
  assert.equal(image.kind, BatchCheckKind.IMAGE);
  assert.equal(image.mime, 'image/png');
  const page = BatchLinks.checkOf('https://a.example/p', 200, 'text/html', false);
  assert.equal(page.kind, BatchCheckKind.PAGE);
  const binary = BatchLinks.checkOf('https://a.example/b', 200, 'application/octet-stream', false);
  assert.equal(binary.kind, BatchCheckKind.UNKNOWN);
  const missing = BatchLinks.checkOf('https://a.example/m', 200, '', false);
  assert.equal(missing.kind, BatchCheckKind.UNKNOWN);
  const headUnsupported = BatchLinks.checkOf('https://a.example/h', 405, '', false);
  assert.equal(headUnsupported.kind, BatchCheckKind.UNKNOWN);
  assert.equal(headUnsupported.detail, '服务器不支持预检，仍可导入');
  const forbidden = BatchLinks.checkOf('https://a.example/f', 403, '', false);
  assert.equal(forbidden.kind, BatchCheckKind.UNKNOWN);
  const redirect = BatchLinks.checkOf('https://a.example/r', 302, '', false);
  assert.equal(redirect.kind, BatchCheckKind.UNKNOWN);
  const serverError = BatchLinks.checkOf('https://a.example/s', 500, '', false);
  assert.equal(serverError.kind, BatchCheckKind.UNKNOWN);
  const failed = BatchLinks.checkOf('https://a.example/x', 0, '', true);
  assert.equal(failed.kind, BatchCheckKind.UNKNOWN);
  assert.equal(failed.detail, '连接失败，仍可导入');
});

caseTest('duplicates and invalid rows never enter the import list', () => {
  const report = BatchLinks.parse('https://a.example/noext\n'
    + 'https://a.example/noext\nhttps://a.example/noext?sign=1\n'
    + 'https://a.example/video.mp4\nhttps://a.example/doc.pdf\n');
  assert.deepEqual(report.urls, [
    'https://a.example/noext',
    'https://a.example/noext?sign=1'
  ]);
  assert.equal(report.pending, 2);
  assert.equal(report.duplicates, 1);
  assert.equal(report.invalid, 2);
  assert.equal(rowOf(report, 2).duplicateOf, 1);
});
