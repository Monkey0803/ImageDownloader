#!/usr/bin/env node
const path = require('node:path');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const vm = require('node:vm');
const { loader } = require('./lib/arkts-test-loader.cjs');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const load = loader();
const get = (p) => load(path.join(root, p + '.ets'));
const { BatchLinks } = get('service/BatchLinks');

test('Weibo detail URLs are pages, never image download candidates', () => {
  const r = BatchLinks.parse('https://weibo.com/3288446905/RoKPzDSuI\n'
    + 'https://weibo.com/5571216925/RoI359Sfb\nhttps://a.test/p.html\nhttps://a.test/x.jpg');
  assert.deepEqual(r.rows.map(x => x.status), ['page', 'page', 'page', 'valid']);
  assert.equal(r.pages, 3);
});

// A queue that accidentally aborts on one page, reorders groups or commits after cancellation
// breaks these outcome assertions. Only the browser boundary is replaced.
test('page queue preserves sources, isolates failures and defaults images to selected', async () => {
  const { BatchPageGroups, BatchPageResult } = get('service/BatchPageGroups');
  const { BatchPageQueue } = get('service/BatchPageQueue');
  const groups = BatchPageGroups.create(BatchLinks.parse(
    'https://a.test/a.jpg\nhttps://a.test/one.html\nhttps://a.test/bad.html\nhttps://a.test/two.html'));
  const queue = new BatchPageQueue();
  await queue.run(groups, async (group) => {
    if (group.inputUrl.includes('bad')) throw new Error('fixture failed');
    const r = new BatchPageResult();
    r.url = group.inputUrl + '?final=1'; r.title = 'title ' + group.line;
    r.images = [{ url: 'https://cdn.test/shared.jpg', description: '' },
      { url: 'https://cdn.test/shared.jpg', description: '' },
      { url: 'https://cdn.test/shared.jpg?sign=b', description: '' }];
    return r;
  }, () => {});
  assert.equal(groups.length, 4);
  assert.equal(groups[2].status, 'failed');
  assert.equal(groups[3].status, 'ready');
  assert.equal(groups[1].pictures.length, 2);
  assert.equal(groups[3].pictures.length, 2); // dedupe within a source only
  assert.ok(groups[1].pictures.every(x => x.selected));
  groups[1].pictures[0].selected = false;
  const jobs = BatchPageGroups.downloads(groups);
  assert.deepEqual(jobs.map(x => [x.pageUrl, x.title, x.pictures.length]), [
    ['', '批量链接', 1], ['https://a.test/one.html?final=1', 'title 2', 1],
    ['https://a.test/two.html?final=1', 'title 4', 2]
  ]);
});

test('closing or replacing input discards late page results and skips remaining pages', async () => {
  const { BatchPageGroups, BatchPageResult } = get('service/BatchPageGroups');
  const { BatchPageQueue } = get('service/BatchPageQueue');
  const groups = BatchPageGroups.create(BatchLinks.parse('https://a.test/one.html\nhttps://a.test/two.html'));
  const queue = new BatchPageQueue();
  let finish;
  const pending = queue.run(groups, () => new Promise(r => { finish = r; }), () => {});
  queue.cancel();
  const result = new BatchPageResult(); result.images = [{ url: 'https://a.test/stale.jpg', description: '' }];
  finish(result); await pending;
  assert.equal(groups[0].pictures.length, 0);
  assert.equal(groups[1].status, 'waiting');
  assert.equal(BatchPageGroups.downloads(groups).length, 0);
});

test('retrying one failed page retains selections on other sources', async () => {
  const { BatchPageGroups, BatchPageResult } = get('service/BatchPageGroups');
  const { BatchPageQueue } = get('service/BatchPageQueue');
  const groups = BatchPageGroups.create(BatchLinks.parse('https://a.test/one.html\nhttps://a.test/two.html'));
  const queue = new BatchPageQueue();
  await queue.run(groups, async (g) => {
    if (g.line === 2) throw new Error('login');
    const r = new BatchPageResult(); r.images = [{ url: 'https://a.test/a.jpg', description: '' }]; return r;
  }, () => {});
  groups[0].pictures[0].selected = false;
  await queue.run([groups[1]], async () => {
    const r = new BatchPageResult(); r.url = 'https://a.test/two.html';
    r.images = [{ url: 'https://a.test/b.jpg', description: '' }]; return r;
  }, () => {});
  assert.equal(groups[0].pictures[0].selected, false);
  assert.equal(BatchPageGroups.downloads(groups).length, 1);
  assert.equal(BatchPageGroups.downloads(groups)[0].pageUrl, 'https://a.test/two.html');
});

test('Weibo extractor verifies the requested post and ignores avatars and retweeted pictures', async () => {
  const protocolLoad = loader({ '@kit.ArkWeb': { webview: {} }, '@kit.NetworkKit': { http: {} } });
  const { BatchPageProtocol } = protocolLoad(path.join(root, 'service/BatchPageProtocol.ets'));
  const context = {
    window: {}, URL,
    location: { href: 'https://weibo.com/3288446905/RoKPzDSuI', hostname: 'weibo.com', pathname: '/3288446905/RoKPzDSuI' },
    document: { title: '微博正文', body: { innerText: '' }, querySelector: () => null, querySelectorAll: () => [] },
    fetch: async () => ({ ok: true, json: async () => ({ mblogid: 'RoKPzDSuI', text_raw: '正文标题',
      user: { avatar_large: 'https://cdn.test/avatar.jpg' },
      pic_ids: ['p1'], pic_infos: { p1: { thumbnail: { url: 'https://cdn.test/small.jpg' },
        large: { url: 'https://cdn.test/original.jpg', width: 1600, height: 2400 } } },
      retweeted_status: { pics: [{ url: 'https://cdn.test/retweet.jpg' }] }
    }) })
  };
  const script = BatchPageProtocol.script(context.location.href, 'original');
  vm.runInNewContext(script, context);
  await new Promise(r => setImmediate(r));
  const result = JSON.parse(vm.runInNewContext(script, context));
  assert.equal(result.scopeFound, true);
  assert.deepEqual(result.images.map(x => x.url), ['https://cdn.test/original.jpg']);
  assert.equal(result.title, '正文标题');
  context.fetch = async () => ({ ok: true, json: async () => ({ mblogid: 'wrong', pics: [{ url: 'https://cdn.test/wrong.jpg' }] }) });
  context.window = {};
  vm.runInNewContext(script, context); await new Promise(r => setImmediate(r));
  const wrong = JSON.parse(vm.runInNewContext(script, context));
  assert.equal(wrong.images.length, 0);
  assert.ok(wrong.error.includes('目标微博'));
});

test('Weibo visitor pages stay pending for the credential redirect without collecting images', () => {
  const protocolLoad = loader({ '@kit.ArkWeb': { webview: {} }, '@kit.NetworkKit': { http: {} } });
  const { BatchPageProtocol } = protocolLoad(path.join(root, 'service/BatchPageProtocol.ets'));
  const result = JSON.parse(vm.runInNewContext(BatchPageProtocol.script('https://weibo.com/1/RoKPzDSuI', 'display'), {
    window: {}, URL, location: { href: 'https://passport.weibo.com/visitor/visitor', hostname: 'passport.weibo.com', pathname: '/visitor/visitor' },
    document: { title: 'Sina Visitor System', body: { innerText: '' } }
  }));
  assert.equal(result.images.length, 0);
  assert.equal(result.pending, true);
  assert.equal(result.error, '');
});

function viewModelHarness() {
  const file = path.join(root, 'viewmodel/DiscoverViewModel.ets');
  const mocks = {};
  for (const match of fs.readFileSync(file, 'utf8').matchAll(/import \{([^}]+)\} from '([^']+)'/g)) {
    const id = match[2].startsWith('.') ? path.resolve(path.dirname(file), match[2] + '.ets') : match[2];
    mocks[id] = Object.fromEntries(match[1].split(',').map(n => [n.trim(), class {}]));
  }
  mocks['@kit.ArkWeb'] = { webview: { WebviewController: class {} } };
  const { DownloadAdmission } = get('service/DownloadAdmission');
  mocks[path.join(root, 'service/DownloadAdmission.ets')] = { DownloadAdmission };
  for (const module of ['BatchLinks', 'BatchPageGroups', 'BatchPageQueue', 'PictureFactory']) {
    mocks[path.join(root, 'service/' + module + '.ets')] = get('service/' + module);
  }
  mocks[path.join(root, 'service/BatchLinkProbe.ets')] = { BatchLinkProbe: { check: async () => [] } };
  const queued = [];
  const downloads = [];
  mocks[path.join(root, 'service/DownloadStore.ets')] = { DownloadStore: {
    downloads, exists: () => false,
    add: (pictures, url, title, zip) => {
      const plan = DownloadAdmission.plan(pictures, downloads, () => false);
      if (plan.result.added > 0) {
        queued.push([plan.items, url, title, zip]);
        for (const picture of plan.items) {
          downloads.push({ url: picture.url, kind: picture.kind, status: 'queued', path: '' });
        }
      }
      return plan.result;
    }
  } };
  const { DiscoverViewModel } = loader(mocks)(file);
  const model = new DiscoverViewModel();
  model.ui = { say: () => {}, switchTab: () => {} };
  return { model, queued };
}

test('review creates no tasks and confirmation snapshots ZIP and the selected per-page sources', async () => {
  const { model, queued } = viewModelHarness();
  const { BatchPageResult } = get('service/BatchPageGroups');
  model.batchResolver = { cancel: () => {}, clear: () => {}, resolve: async group => {
    const r = new BatchPageResult(); r.url = group.inputUrl; r.title = '网页 ' + group.line;
    r.images = [{ url: 'https://cdn.test/a.jpg', description: '' }, { url: 'https://cdn.test/b.jpg', description: '' }]; return r;
  } };
  model.mode = 'zip';
  model.setBatchText('https://a.test/one.html\nhttps://a.test/two.html');
  await model.reviewBatch();
  assert.equal(queued.length, 0);
  assert.equal(model.batchSelectedCount, 4);
  model.toggleBatchPicture(model.batchGroups[0].id, model.batchGroups[0].pictures[1].uid);
  model.mode = 'single';
  assert.equal(model.batchEligibleCount, 2);
  model.confirmBatchReview();
  assert.deepEqual(queued.map(([pictures, url, title, zip]) => [pictures.length, url, title, zip]), [
    [1, 'https://a.test/one.html', '网页 1', true], [1, 'https://a.test/two.html', '网页 2', true]
  ]);
});

test('typing in an idle editor does not navigate the hidden Web or disturb input focus', () => {
  const { model } = viewModelHarness();
  let navigations = 0;
  model.batchResolver = { clear: () => { navigations++; } };
  model.setBatchText('h'); model.setBatchText('ht'); model.setBatchText('https://example.test/');
  assert.equal(navigations, 0);
});

test('resolver accepts browser URL normalization and ignores the preceding blank document', async () => {
  const { BatchPageGroup } = get('service/BatchPageGroups');
  let resolver;
  let injections = 0;
  class Controller {
    stop() {}
    getUrl() { return this.url; }
    loadUrl(value) {
      if (value === 'about:blank') { this.url = value; resolver.pageEnded(value); return; }
      this.url = 'https://example.test/';
      resolver.pageBegan('https://example.test/'); resolver.pageEnded('https://example.test/');
    }
    async runJavaScriptExt() {
      injections++;
      return { getString: () => JSON.stringify({ url: 'https://example.test/', title: '',
        images: [{ url: 'https://example.test/image.png', description: '' }], bottom: true,
        direct: true, scopeFound: true, error: '' }) };
    }
  }
  const nativeLoad = loader({ '@kit.ArkTS': { url: { URL } },
    '@kit.ArkWeb': { webview: { WebviewController: Controller } }, '@kit.NetworkKit': { http: {} } });
  const { BatchPageResolver } = nativeLoad(path.join(root, 'service/BatchPageResolver.ets'));
  resolver = new BatchPageResolver(); resolver.ready();
  const group = new BatchPageGroup(); group.inputUrl = 'https://EXAMPLE.test:443';
  const pending = resolver.resolve(group, 'display');
  await Promise.resolve(); await Promise.resolve();
  if (!injections) resolver.cancel(); // don't wait 20 seconds for a regression
  assert.equal(injections, 1);
  assert.equal((await pending).images.length, 1);
});

test('public gallery is collected even when its comment box asks the visitor to login', () => {
  const protocolLoad = loader({ '@kit.ArkWeb': { webview: {} }, '@kit.NetworkKit': { http: {} } });
  const { BatchPageProtocol } = protocolLoad(path.join(root, 'service/BatchPageProtocol.ets'));
  const picture = { currentSrc: 'https://example.test/a.jpg', src: 'https://example.test/a.jpg',
    alt: '', title: '', getAttribute: () => '', complete: true, naturalWidth: 400, naturalHeight: 300 };
  const result = JSON.parse(vm.runInNewContext(BatchPageProtocol.script('https://example.test/gallery', 'display'), {
    window: { scrollY: 0, innerHeight: 800, scrollBy: () => {} }, URL,
    location: { href: 'https://example.test/gallery', hostname: 'example.test', pathname: '/gallery' },
    document: { title: '公开图库', baseURI: 'https://example.test/gallery', images: [picture],
      body: { innerText: '评论请先登录', scrollHeight: 600 }, documentElement: { scrollHeight: 600 }, querySelector: () => null }
  }));
  assert.equal(result.error, '');
  assert.equal(result.images[0].url, 'https://example.test/a.jpg');
});

test('a short link redirected to Weibo never falls back to generic whole-page collection', async () => {
  const protocolLoad = loader({ '@kit.ArkWeb': { webview: {} }, '@kit.NetworkKit': { http: {} } });
  const { BatchPageProtocol } = protocolLoad(path.join(root, 'service/BatchPageProtocol.ets'));
  const context = { window: {}, URL,
    location: { href: 'https://weibo.com/3288446905/RoKPzDSuI', hostname: 'weibo.com', pathname: '/3288446905/RoKPzDSuI' },
    document: { title: '微博', images: [], body: { innerText: '' }, querySelector: () => null, querySelectorAll: () => [] },
    fetch: async () => ({ ok: true, json: async () => ({ mblogid: 'RoKPzDSuI',
      pics: [{ url: 'https://cdn.test/body.jpg' }], user: { avatar_large: 'https://cdn.test/avatar.jpg' } }) }) };
  const script = BatchPageProtocol.script('https://t.cn/fixture', 'display');
  vm.runInNewContext(script, context); await new Promise(r => setImmediate(r));
  const result = JSON.parse(vm.runInNewContext(script, context));
  assert.equal(result.scopeFound, true);
  assert.deepEqual(result.images.map(x => x.url), ['https://cdn.test/body.jpg']);
});

test('a page that never completes navigation times out without publishing pictures', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  class Controller { stop() {} loadUrl() {} }
  const nativeLoad = loader({ '@kit.ArkTS': { url: { URL } },
    '@kit.ArkWeb': { webview: { WebviewController: Controller } }, '@kit.NetworkKit': { http: {} } });
  const { BatchPageResolver } = nativeLoad(path.join(root, 'service/BatchPageResolver.ets'));
  const { BatchPageGroup } = get('service/BatchPageGroups');
  const resolver = new BatchPageResolver(); resolver.ready();
  const group = new BatchPageGroup(); group.inputUrl = 'https://example.test/slow';
  const pending = resolver.resolve(group, 'display');
  const rejected = assert.rejects(pending, /网页加载超时/);
  t.mock.timers.tick(20000);
  await rejected;
  assert.equal(group.pictures.length, 0);
});

test('redirected navigation starts from a blank barrier and accepts only the current final document', async () => {
  const { BatchPageGroup } = get('service/BatchPageGroups');
  let resolver;
  let injections = 0;
  const history = [];
  class Controller {
    stop() {}
    getUrl() { return this.url; }
    loadUrl(value) {
      history.push(value); this.url = value;
      if (value === 'about:blank') { resolver.pageEnded(value); return; }
      this.url = 'https://m.weibo.cn/status/RoKPzDSuI';
      resolver.pageBegan(this.url); resolver.pageEnded(this.url);
    }
    async runJavaScriptExt() {
      injections++;
      return { getString: () => JSON.stringify({ url: this.url, title: '',
        images: [{ url: 'https://cdn.test/body.png', description: '' }], bottom: true,
        direct: true, scopeFound: true, error: '' }) };
    }
  }
  const nativeLoad = loader({ '@kit.ArkTS': { url: { URL } },
    '@kit.ArkWeb': { webview: { WebviewController: Controller } }, '@kit.NetworkKit': { http: {} } });
  const { BatchPageResolver } = nativeLoad(path.join(root, 'service/BatchPageResolver.ets'));
  resolver = new BatchPageResolver(); resolver.ready();
  const group = new BatchPageGroup(); group.inputUrl = 'https://weibo.com/3288446905/RoKPzDSuI';
  const pending = resolver.resolve(group, 'display');
  await Promise.resolve(); await Promise.resolve();
  if (!injections) { resolver.cancel(); await assert.rejects(pending); }
  assert.equal(injections, 1);
  assert.deepEqual(history, ['about:blank', group.inputUrl]);
  assert.equal((await pending).url, 'https://m.weibo.cn/status/RoKPzDSuI');
});
