#!/usr/bin/env node
// Exercise production controller methods with deterministic timers. Native layout
// and Image reload behavior are covered separately by simulator acceptance.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require(process.env.ARKTS_TEST_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/tools/ohpm/node_modules/typescript');

function harness(options = {}) {
  const filename = process.env.ARKTS_PREVIEW_LOAD_SOURCE ||
    path.resolve(__dirname, '../entry/src/main/ets/view/ImageSurface.ets');
  const source = fs.readFileSync(filename, 'utf8');
  const begin = source.indexOf('export struct AnimatedPreviewImage {');
  const state = source.indexOf('  @Param active: boolean = true;', begin);
  const builders = source.indexOf('  private fitted(): PreviewSize', state);
  assert.ok(begin >= 0 && state > begin && builders > state, 'production controller boundaries');
  let controller = source.slice(begin, state) + source.slice(state, builders);
  const remote = source.indexOf('  @Builder\n  private remoteImage(', builders);
  if (remote >= 0) controller += source.slice(remote, source.indexOf('  @Builder\n  private animationCanvas()', remote));
  controller = controller.replace('export struct AnimatedPreviewImage {', 'class AnimatedPreviewImage {')
    .replace(/@Monitor\([^)]*\)\s*/g, '')
    .replace(/@(Require|Param|Event|Local|BuilderParam|Builder)\b\s*/g, '') + '\n}';
  const constants = (source.match(/^const PREVIEW_[^\n]+/gm) || []).join('\n');
  const javascript = ts.transpileModule(constants + '\n' + controller + '\nnew AnimatedPreviewImage();', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  let now = 0;
  let nextId = 1;
  const timers = new Map();
  const sessions = [];
  const requests = [];
  class Playback {
    constructor() { this.stopped = false; this.paused = false; sessions.push(this); }
    stop() { this.stopped = true; }
    pause() { this.paused = true; }
    resume() { this.paused = false; }
    run(filename, frame, failure, index) { Object.assign(this, { filename, frame, failure, index }); }
  }
  const component = vm.runInNewContext(javascript, {
    AnimationDockActions: class {}, AnimationPlayback: Playback,
    ImageFit: { Contain: 'contain' },
    Image(source, aiOptions, reloadKey) {
      const request = { source, reloadKey };
      const node = {
        width() { return node; }, height() { return node; }, objectFit() { return node; },
        translate() { return node; },
        onComplete(callback) { request.complete = callback; return node; },
        onError(callback) { request.failure = callback; return node; }
      };
      requests.push(request);
      return node;
    },
    setTimeout(callback, delay) { const id = nextId++; timers.set(id, { callback, due: now + delay }); return id; },
    clearTimeout(id) { timers.delete(id); }
  });
  Object.assign(component, { src: 'http://fixture.test/animation.gif', ...options });
  component.aboutToAppear();
  return {
    component, timers, sessions, requests,
    request() { component.remoteImage(component.loadAttempt, component.src); return requests.at(-1); },
    tick(delta) {
      const target = now + delta;
      while (true) {
        const next = [...timers.entries()].filter(([, timer]) => timer.due <= target)
          .sort((a, b) => a[1].due - b[1].due)[0];
        if (!next) break;
        now = next[1].due; timers.delete(next[0]); next[1].callback();
      }
      now = target;
    }
  };
}

const decoded = { width: 600, height: 600, loadingStatus: 1 };
const frameInfo = { width: 600, height: 600, index: 0, count: 3, transparent: false };

test('pending first frame times out at 15000ms', () => {
  const h = harness();
  h.tick(14999); assert.equal(h.component.failed, false);
  h.tick(1); assert.equal(h.component.failed, true);
  assert.equal(h.component.loaded, false);
  assert.equal(h.component.failureMessage, '图片加载超时，请重试');
  assert.equal(h.timers.size, 0);
});

test('empty source fails immediately without starting a timer', () => {
  const h = harness({ src: '  ' });
  assert.equal(h.component.failed, true);
  assert.equal(h.timers.size, 0);
  assert.equal(h.component.failureMessage, '图片源不可用，请检查文件或网络后重试');
});

test('remote metadata does not end first-frame waiting; decoded image does', () => {
  const h = harness(); const request = h.request();
  request.complete({ ...decoded, loadingStatus: 0 });
  assert.equal(h.component.loaded, false); assert.equal(h.timers.size, 1);
  request.complete(decoded);
  assert.equal(h.component.loaded, true); assert.equal(h.timers.size, 0);
  h.tick(60000); assert.equal(h.component.failed, false);
});

test('remote failure stops the timer and shows an unavailable-source message', () => {
  const h = harness(); h.request().failure();
  assert.equal(h.component.failed, true); assert.equal(h.timers.size, 0);
  assert.equal(h.component.failureMessage, '图片源不可用，请检查文件或网络后重试');
});

test('late remote responses cannot overwrite timeout or a newer retry', () => {
  const h = harness(); const old = h.request();
  h.tick(15000); old.complete(decoded);
  assert.equal(h.component.failed, true); assert.equal(h.component.loaded, false);
  h.component.start(); const current = h.request();
  assert.equal(current.source, old.source); assert.notEqual(current.reloadKey, old.reloadKey);
  old.failure(); old.complete(decoded);
  assert.equal(h.component.failed, false); assert.equal(h.component.loaded, false);
  current.complete(decoded);
  assert.equal(h.component.loaded, true); assert.equal(h.timers.size, 0);
});

test('a queued old timer cannot lose a new timer handle or fail an already loaded image', () => {
  const h = harness(); const oldTimeout = [...h.timers.values()][0].callback;
  h.component.start(); const currentTimer = h.component.firstFrameTimer;
  oldTimeout(); assert.equal(h.component.firstFrameTimer, currentTimer);
  const queuedTimeout = [...h.timers.values()][0].callback;
  h.request().complete(decoded); queuedTimeout();
  assert.equal(h.component.loaded, true); assert.equal(h.component.failed, false);
  assert.equal(h.timers.size, 0);
});

test('changing sources invalidates callbacks from the previous image', () => {
  const h = harness(); const old = h.request();
  h.component.src = 'http://fixture.test/other.gif'; h.component.onSourceChanged();
  const current = h.request(); old.complete(decoded); old.failure();
  assert.equal(h.component.loaded, false); assert.equal(h.component.failed, false);
  current.complete(decoded); assert.equal(h.component.loaded, true);
});

test('background and destruction cancel timers and reject stale callbacks', () => {
  const h = harness(); const old = h.request();
  h.component.active = false; h.component.onSourceChanged();
  assert.equal(h.timers.size, 0); h.tick(30000); old.complete(decoded);
  assert.equal(h.component.loaded, false); assert.equal(h.component.failed, false);
  h.component.active = true; h.component.onSourceChanged();
  assert.equal(h.timers.size, 1); const resumed = h.request();
  h.component.aboutToDisappear(); h.tick(30000); resumed.complete(decoded); resumed.failure();
  assert.equal(h.timers.size, 0); assert.equal(h.component.loaded, false);
});

test('local first frame clears the deadline and preserves pause/frame across background', () => {
  const h = harness({ localPath: '/fixture/animation.gif' });
  h.sessions[0].frame({}, { ...frameInfo, index: 2 });
  assert.equal(h.component.loaded, true); assert.equal(h.timers.size, 0);
  h.component.togglePlayback();
  h.component.active = false; h.component.onSourceChanged();
  h.component.active = true; h.component.onSourceChanged();
  const current = h.sessions.at(-1);
  assert.equal(current.paused, true); assert.equal(current.index, 2);
  current.frame({}, { ...frameInfo, index: 2 }); h.tick(60000);
  assert.equal(h.component.paused, true); assert.equal(h.component.failed, false);
});

test('local timeout stops playback and ignores a decoder frame arriving late', () => {
  const h = harness({ localPath: '/fixture/animation.gif' });
  const session = h.sessions[0]; h.tick(15000);
  assert.equal(session.stopped, true); assert.equal(h.component.failed, true);
  session.frame({}, frameInfo); session.failure();
  assert.equal(h.component.loaded, false); assert.equal(h.component.animationFrame, undefined);
  assert.equal(h.component.failureMessage, '图片加载超时，请重试');
});

test('invalid local dimensions fail immediately and stop decoding', () => {
  const h = harness({ localPath: '/fixture/animation.gif' });
  h.sessions[0].frame({}, { ...frameInfo, width: 0 });
  assert.equal(h.component.failed, true); assert.equal(h.sessions[0].stopped, true);
  assert.equal(h.timers.size, 0);
});
