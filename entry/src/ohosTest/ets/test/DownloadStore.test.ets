import { describe, it, expect, beforeEach, afterEach } from '@ohos/hypium';
import { request } from '@kit.BasicServicesKit';
import { DownloadStore } from '../../../main/ets/service/DownloadStore';
import { Naming } from '../../../main/ets/service/Naming';
import { StoreState } from '../../../main/ets/service/StoreState';
import { normalizeEditQuality, normalizeLocation, normalizeQuality } from '../../../main/ets/model/SettingsOptions';
import { DownloadItem, SavedState } from '../../../main/ets/model/Models';

// 纯函数单测：不依赖 UIAbilityContext，也不访问真实文件系统。
// 命名 / 扩展名那几组现在测的是 service/Naming（零 IO、零状态）；
// uniqueName 仍属于商店 —— 它要查「磁盘上有没有」和「记录里占没占」，所以用一个不存在的
// 目录隔离掉文件系统那一半，只验证与 DownloadStore.downloads 的去重逻辑。

const NO_DIR = '/__no_such_dir_for_test__';

function makeDownload(path: string): DownloadItem {
  const item = new DownloadItem();
  item.path = path;
  return item;
}

export default function downloadStoreTest() {
  describe('DownloadStore.acceptsAgentEvent', () => {
    it('ignores_old_attempt_and_terminal_callbacks', 0, () => {
      const item: DownloadItem = makeDownload('/staging/retry.png');
      item.taskId = 'new-task';
      item.status = 'running';
      expect(DownloadStore.acceptsAgentEvent(item, '')).assertFalse();
      expect(DownloadStore.acceptsAgentEvent(item, 'old-task')).assertFalse();
      expect(DownloadStore.acceptsAgentEvent(item, 'new-task')).assertTrue();
      item.status = 'cancelled';
      expect(DownloadStore.acceptsAgentEvent(item, 'new-task')).assertFalse();
      item.status = 'failed';
      expect(DownloadStore.acceptsAgentEvent(item, 'new-task')).assertFalse();
      item.status = 'completed';
      expect(DownloadStore.acceptsAgentEvent(item, 'new-task')).assertFalse();
    });
  });

  describe('DownloadStore.agentStatus', () => {
    it('shows_system_wait_and_recovers_when_running', 0, () => {
      expect(DownloadStore.agentStatus('running', request.agent.State.WAITING)).assertEqual('waiting');
      expect(DownloadStore.agentStatus('starting', request.agent.State.PAUSED)).assertEqual('waiting');
      expect(DownloadStore.agentStatus('waiting', request.agent.State.RUNNING)).assertEqual('running');
      expect(DownloadStore.agentStatus('waiting', request.agent.State.RETRYING)).assertEqual('running');
      expect(DownloadStore.agentStatus('running', request.agent.State.PAUSED, true)).assertEqual('paused');
    });

    it('keeps_manual_pause_and_settled_states', 0, () => {
      expect(DownloadStore.agentStatus('paused', request.agent.State.RUNNING)).assertEqual('paused');
      expect(DownloadStore.agentStatus('cancelled', request.agent.State.WAITING)).assertEqual('cancelled');
      expect(DownloadStore.agentStatus('cancelled', request.agent.State.PAUSED, true)).assertEqual('cancelled');
      expect(DownloadStore.agentStatus('completed', request.agent.State.PAUSED)).assertEqual('completed');
    });
  });

  describe('DownloadStore.prepareRetry', () => {
    it('resets_failed_and_cancelled_members_without_touching_completed_sibling', 0, () => {
      const failed: DownloadItem = makeDownload('/staging/failed.png');
      failed.status = 'failed'; failed.error = 'HTTP 503'; failed.processed = 120;
      failed.total = 200; failed.taskId = 'old-task'; failed.speedBps = 40; failed.etaSeconds = 2;
      const cancelled: DownloadItem = makeDownload('/staging/cancelled.png');
      cancelled.status = 'cancelled'; cancelled.error = '已取消'; cancelled.taskId = 'stopped-task';
      const completed: DownloadItem = makeDownload('/staging/good.png');
      completed.status = 'completed'; completed.processed = 200; completed.total = 200;

      expect(DownloadStore.prepareRetry(failed)).assertTrue();
      expect(DownloadStore.prepareRetry(cancelled)).assertTrue();
      expect(DownloadStore.prepareRetry(completed)).assertFalse();
      expect(DownloadStore.retry(completed)).assertFalse();
      expect(failed.status).assertEqual('queued');
      expect(failed.error).assertEqual('');
      expect(failed.processed).assertEqual(0);
      expect(failed.total).assertEqual(0);
      expect(failed.taskId).assertEqual('');
      expect(failed.speedBps).assertEqual(0);
      expect(failed.etaSeconds).assertEqual(0);
      expect(cancelled.status).assertEqual('queued');
      expect(cancelled.taskId).assertEqual('');
      expect(completed.status).assertEqual('completed');
      expect(completed.processed).assertEqual(200);
      expect(completed.path).assertEqual('/staging/good.png');
    });
  });

  describe('Naming.clean', () => {
    it('replaces_illegal_chars', 0, () => {
      expect(Naming.clean('a/b\\c:d*e?f"g<h>i|j', 'fb')).assertEqual('a_b_c_d_e_f_g_h_i_j');
    });

    it('strips_leading_and_trailing_dots_and_spaces', 0, () => {
      expect(Naming.clean('  hi  ', 'fb')).assertEqual('hi');
      expect(Naming.clean('...hi...', 'fb')).assertEqual('hi');
      expect(Naming.clean(' .hi. ', 'fb')).assertEqual('hi');
    });

    it('falls_back_when_empty', 0, () => {
      expect(Naming.clean('', 'fb')).assertEqual('fb');
      expect(Naming.clean('   ', 'fb')).assertEqual('fb');
      expect(Naming.clean('...', 'fb')).assertEqual('fb');
    });

    it('truncates_to_120_chars', 0, () => {
      const long = 'a'.repeat(130);
      expect(Naming.clean(long, 'fb').length).assertEqual(120);
    });

    it('keeps_chinese_and_spaces_inside', 0, () => {
      expect(Naming.clean('我的 图片', 'fb')).assertEqual('我的 图片');
    });
  });

  describe('Naming.suggested', () => {
    it('uses_last_path_segment', 0, () => {
      expect(Naming.suggested('https://a.com/img/pic.png', '', 1)).assertEqual('pic.png');
    });

    it('drops_query_and_fragment', 0, () => {
      expect(Naming.suggested('https://a.com/img/pic.png?x=1', '', 1)).assertEqual('pic.png');
      expect(Naming.suggested('https://a.com/img/pic.png#frag', '', 1)).assertEqual('pic.png');
      expect(Naming.suggested('https://a.com/img/pic.png?x=1#frag', '', 1)).assertEqual('pic.png');
    });

    it('decodes_percent_encoding', 0, () => {
      expect(Naming.suggested('https://a.com/img/%E4%B8%AD%E6%96%87.jpg', '', 1)).assertEqual('中文.jpg');
    });

    it('appends_jpg_when_extension_unknown', 0, () => {
      expect(Naming.suggested('https://a.com/img/noext', 'descr', 1)).assertEqual('noext.jpg');
      expect(Naming.suggested('https://a.com/img/pic.tar.gz', '', 1)).assertEqual('pic.tar.gz.jpg');
    });

    it('keeps_known_extensions_case_insensitively', 0, () => {
      expect(Naming.suggested('https://a.com/PIC.PNG', '', 1)).assertEqual('PIC.PNG');
      expect(Naming.suggested('https://a.com/pic.webp', '', 1)).assertEqual('pic.webp');
    });

    it('keeps_live_photo_package_extensions', 0, () => {
      // 实况照片包要按整包落盘、下完解包：名字补上 .jpg 的话扩展名与实际内容不符，
      // 用户导出后也认不出这是什么。
      expect(Naming.suggested('https://a.com/IMG_1234.livp', '', 1)).assertEqual('IMG_1234.livp');
      expect(Naming.suggested('https://a.com/IMG_1234.LIVEPHOTO', '', 1)).assertEqual('IMG_1234.LIVEPHOTO');
    });

    it('falls_back_to_description_then_index', 0, () => {
      expect(Naming.suggested('https://a.com/', '我的图', 1)).assertEqual('我的图.jpg');
      expect(Naming.suggested('https://a.com/', '', 7)).assertEqual('图片_7.jpg');
    });

    it('sanitizes_description_used_as_name', 0, () => {
      expect(Naming.suggested('https://a.com/', 'a/b:c', 1)).assertEqual('a_b_c.jpg');
    });
  });

  describe('Naming.withExtension', () => {
    it('replaces_last_extension', 0, () => {
      expect(Naming.withExtension('photo.png', 'jpg')).assertEqual('photo.jpg');
      expect(Naming.withExtension('a.b.c', 'webp')).assertEqual('a.b.webp');
    });

    it('appends_when_no_extension', 0, () => {
      expect(Naming.withExtension('noext', 'png')).assertEqual('noext.png');
    });

    it('handles_leading_dot_and_empty', 0, () => {
      expect(Naming.withExtension('.hidden', 'png')).assertEqual('hidden.png');
      expect(Naming.withExtension('', 'png')).assertEqual('图片.png');
    });

    it('handles_trailing_dot', 0, () => {
      expect(Naming.withExtension('trailing.', 'png')).assertEqual('trailing.png');
    });

    it('sanitizes_before_appending', 0, () => {
      expect(Naming.withExtension('a/b', 'png')).assertEqual('a_b.png');
    });
  });

  describe('Naming.editedName', () => {
    it('keeps_the_stem_and_follows_the_real_container', 0, () => {
      expect(Naming.editedName('photo.webp', '编辑', 'jpg')).assertEqual('photo-编辑.jpg');
      expect(Naming.editedName('photo.png', '编辑', 'png')).assertEqual('photo-编辑.png');
      expect(Naming.editedName('a.b.c', '超分', 'jpg')).assertEqual('a.b-超分.jpg');
    });

    it('appends_when_the_source_has_no_extension', 0, () => {
      expect(Naming.editedName('noext', '编辑', 'jpg')).assertEqual('noext-编辑.jpg');
      expect(Naming.editedName('', '编辑', 'png')).assertEqual('图片-编辑.png');
    });

    it('sanitizes_before_appending', 0, () => {
      expect(Naming.editedName('a/b', '编辑', 'jpg')).assertEqual('a_b-编辑.jpg');
    });
  });

  describe('Naming.imageExtension', () => {
    it('maps_common_image_types', 0, () => {      expect(Naming.imageExtension('image/png')).assertEqual('png');
      expect(Naming.imageExtension('image/jpeg')).assertEqual('jpg');
      expect(Naming.imageExtension('image/jpg')).assertEqual('jpg');
      expect(Naming.imageExtension('image/webp')).assertEqual('webp');
      expect(Naming.imageExtension('image/gif')).assertEqual('gif');
      expect(Naming.imageExtension('image/heic')).assertEqual('heic');
      expect(Naming.imageExtension('image/avif')).assertEqual('avif');
      expect(Naming.imageExtension('image/bmp')).assertEqual('bmp');
      expect(Naming.imageExtension('image/svg+xml')).assertEqual('svg');
      expect(Naming.imageExtension('image/tiff')).assertEqual('tiff');
    });

    it('ignores_case_and_parameters', 0, () => {
      expect(Naming.imageExtension('IMAGE/PNG; charset=utf-8')).assertEqual('png');
      expect(Naming.imageExtension(' image/jpeg ')).assertEqual('jpg');
    });

    it('returns_empty_for_non_image', 0, () => {
      expect(Naming.imageExtension('text/html')).assertEqual('');
      expect(Naming.imageExtension('')).assertEqual('');
      expect(Naming.imageExtension('application/octet-stream')).assertEqual('');
    });
  });

  describe('DownloadStore.uniqueName', () => {
    beforeEach(() => {
      DownloadStore.downloads = [];
    });

    afterEach(() => {
      DownloadStore.downloads = [];
    });

    it('keeps_name_when_free', 0, () => {
      expect(DownloadStore.uniqueName('a.png', NO_DIR)).assertEqual('a.png');
    });

    it('numbers_duplicates', 0, () => {
      DownloadStore.downloads = [makeDownload(NO_DIR + '/a.png')];
      expect(DownloadStore.uniqueName('a.png', NO_DIR)).assertEqual('a (2).png');
    });

    it('increments_past_existing_numbers', 0, () => {
      DownloadStore.downloads = [
        makeDownload(NO_DIR + '/a.png'),
        makeDownload(NO_DIR + '/a (2).png')
      ];
      expect(DownloadStore.uniqueName('a.png', NO_DIR)).assertEqual('a (3).png');
    });

    it('handles_names_without_extension', 0, () => {
      DownloadStore.downloads = [makeDownload(NO_DIR + '/plain')];
      expect(DownloadStore.uniqueName('plain', NO_DIR)).assertEqual('plain (2)');
    });

    it('only_considers_same_directory', 0, () => {
      DownloadStore.downloads = [makeDownload('/other/a.png')];
      expect(DownloadStore.uniqueName('a.png', NO_DIR)).assertEqual('a.png');
    });
  });

  // adopt() 会写静态字段，所以放在最后一段：前面的用例都只调纯函数、不读这些字段。
  describe('DownloadStore.antiPeepEnabled', () => {
    it('defaults_to_off_when_the_state_file_predates_it', 0, () => {
      DownloadStore.adopt(new SavedState());
      expect(DownloadStore.antiPeepEnabled).assertFalse();
    });

    it('keeps_the_persisted_value', 0, () => {
      const state: SavedState = new SavedState();
      state.antiPeepEnabled = true;
      DownloadStore.adopt(state);
      expect(DownloadStore.antiPeepEnabled).assertTrue();
    });
  });

  describe('SettingsOptions.normalizeLocation', () => {
    it('keeps_known_locations', 0, () => {
      expect(normalizeLocation('app', '')).assertEqual('app');
      expect(normalizeLocation('gallery', '')).assertEqual('gallery');
      expect(normalizeLocation('custom', 'file://docs/x')).assertEqual('custom');
    });

    it('falls_back_to_app_without_a_directory', 0, () => {
      // 「自定义目录」没有记住 URI 时必须退回应用文件，否则每次下载都往空 URI 上拷。
      expect(normalizeLocation('custom', '')).assertEqual('app');
    });

    it('falls_back_to_app_for_unknown_values', 0, () => {
      expect(normalizeLocation('', 'file://docs/x')).assertEqual('app');
      expect(normalizeLocation('downloads', 'file://docs/x')).assertEqual('app');
    });
  });

  describe('DownloadStore.downloadLocation', () => {
    it('defaults_to_app_when_the_state_file_predates_it', 0, () => {
      DownloadStore.adopt(new SavedState());
      expect(DownloadStore.downloadLocation).assertEqual('app');
      expect(DownloadStore.customDirUri).assertEqual('');
    });

    it('keeps_gallery', 0, () => {
      const state: SavedState = new SavedState();
      state.downloadLocation = 'gallery';
      DownloadStore.adopt(state);
      expect(DownloadStore.downloadLocation).assertEqual('gallery');
    });

    it('keeps_custom_with_its_directory', 0, () => {
      const state: SavedState = new SavedState();
      state.downloadLocation = 'custom';
      state.customDirUri = 'file://docs/storage/Users/currentUser/Download';
      state.customDirName = 'Download';
      DownloadStore.adopt(state);
      expect(DownloadStore.downloadLocation).assertEqual('custom');
      expect(DownloadStore.customDirName).assertEqual('Download');
    });

    it('drops_custom_when_the_uri_is_gone', 0, () => {
      const state: SavedState = new SavedState();
      state.downloadLocation = 'custom';
      DownloadStore.adopt(state);
      expect(DownloadStore.downloadLocation).assertEqual('app');
    });
  });

  describe('SettingsOptions.normalizeQuality', () => {
    it('keeps_the_two_explicit_modes', 0, () => {
      expect(normalizeQuality('original')).assertEqual('original');
      expect(normalizeQuality('display')).assertEqual('display');
    });

    it('keeps_all_as_is', 0, () => {
      expect(normalizeQuality('all')).assertEqual('all');
    });

    it('falls_back_to_the_default_for_unknown_values', 0, () => {
      // 脏值退回的是**设置表里的默认档**（'original'），不是某个写死的旧档位：
      // 表里那一个 default 同时决定了「首次启动给什么」和「认不出时退回什么」。
      expect(normalizeQuality('')).assertEqual('original');
      expect(normalizeQuality('high')).assertEqual('original');
      expect(normalizeQuality('ORIGINAL')).assertEqual('original');
    });
  });

  describe('DownloadStore.pictureQuality', () => {
    it('defaults_to_the_table_default_when_the_state_file_predates_it', 0, () => {
      DownloadStore.adopt(new SavedState());
      expect(DownloadStore.pictureQuality).assertEqual('original');
    });

    it('keeps_a_persisted_mode', 0, () => {
      // 特意存一个**不是默认档**的值：默认档改了之后，用 'original' 会给出一条
      // 无论字段有没有读进来都成立的假绿。
      const state: SavedState = new SavedState();
      state.pictureQuality = 'display';
      DownloadStore.adopt(state);
      expect(DownloadStore.pictureQuality).assertEqual('display');
    });

    it('falls_back_to_the_default_for_a_dirty_value', 0, () => {
      const state: SavedState = new SavedState();
      state.pictureQuality = 'thumbnail';
      DownloadStore.adopt(state);
      expect(DownloadStore.pictureQuality).assertEqual('original');
    });
  });

  describe('SettingsOptions.normalizeEditQuality', () => {
    it('keeps_the_three_explicit_modes', 0, () => {
      expect(normalizeEditQuality('high')).assertEqual('high');
      expect(normalizeEditQuality('compact')).assertEqual('compact');
      expect(normalizeEditQuality('lossless')).assertEqual('lossless');
    });

    it('falls_back_to_the_default_for_unknown_values', 0, () => {
      expect(normalizeEditQuality('')).assertEqual('high');
      expect(normalizeEditQuality('png')).assertEqual('high');
      expect(normalizeEditQuality('HIGH')).assertEqual('high');
    });
  });

  describe('DownloadStore.editQuality', () => {
    it('defaults_to_the_table_default_when_the_state_file_predates_it', 0, () => {
      DownloadStore.adopt(new SavedState());
      expect(DownloadStore.editQuality).assertEqual('high');
    });

    it('keeps_a_persisted_mode', 0, () => {
      // 与 pictureQuality 同一个理由：故意存非默认档，才能证明字段真的被读进来。
      const state: SavedState = new SavedState();
      state.editQuality = 'compact';
      DownloadStore.adopt(state);
      expect(DownloadStore.editQuality).assertEqual('compact');
    });

    it('falls_back_to_the_default_for_a_dirty_value', 0, () => {
      const state: SavedState = new SavedState();
      state.editQuality = 'png';
      DownloadStore.adopt(state);
      expect(DownloadStore.editQuality).assertEqual('high');
    });
  });

  // 这一段是这次拆出持久化层**新拿到的覆盖**：解码规则原来埋在 adopt() 里，而走到它必须
  // 先有一个 UIAbilityContext（initialize）—— 也就是「读到老版本 / 被改坏的状态文件会怎样」
  // 根本没法测。现在 parse / normalized 都是纯函数，直接喂字符串即可。
  describe('StoreState', () => {
    it('parse_returns_undefined_for_broken_json', 0, () => {
      expect(StoreState.parse('') === undefined).assertTrue();
      expect(StoreState.parse('{oops') === undefined).assertTrue();
    });

    it('parse_reads_a_valid_state', 0, () => {
      const parsed: SavedState | undefined = StoreState.parse('{"concurrency":7}');
      expect(parsed !== undefined).assertTrue();
    });

    /*
     * 「写出去再读回来」必须一个字都不差。
     *
     * 这条是被真机咬出来的：`@ObservedV2` 的 `@Trace` 字段在观察代理上**不是普通可枚举属性**，
     * 直接 `JSON.stringify` 会把字段名写成 `__ob_id` / `__ob_name` 这类前缀，而读侧读的是
     * `id` / `name` —— 记录会在下次启动时静默变成空白（名字空、大小 0）。
     * 现在写盘走 `StoreState.serialize()`（显式线格式），这条用例专门盯着它别再被改回去。
     */
    it('serialize_then_parse_keeps_every_field', 0, () => {
      const state: SavedState = new SavedState();
      const item: DownloadItem = new DownloadItem();
      item.id = 'p1';
      item.origin = 'edited';
      item.originalId = 'original-p0';
      item.url = 'https://example.com/a.png';
      item.name = 'still_color.jpg';
      item.path = '/data/files/images/still_color.jpg';
      item.status = 'completed';
      item.size = 10138;
      item.kind = 'livephoto';
      item.animated = true;
      item.hdr = true;
      item.stillPath = '/data/files/images/p1.jpg';
      item.auxSize = 4096;
      item.note = '解包成功';
      state.downloads = [item];
      state.wifiOnly = true;
      state.hdrEnabled = false;
      state.editQuality = 'compact';

      const raw: string = StoreState.serialize(state);
      // 线格式里出现代理痕迹，即代表有人又直接 stringify 了模型实例。
      expect(raw.includes('__ob_')).assertFalse();

      const back: SavedState = StoreState.normalized(StoreState.parse(raw) as SavedState);
      expect(back.downloads.length).assertEqual(1);
      expect(back.downloads[0].name).assertEqual('still_color.jpg');
      expect(back.downloads[0].origin).assertEqual('edited');
      expect(back.downloads[0].originalId).assertEqual('original-p0');
      expect(back.downloads[0].status).assertEqual('completed');
      expect(back.downloads[0].size).assertEqual(10138);
      expect(back.downloads[0].kind).assertEqual('livephoto');
      expect(back.downloads[0].animated).assertTrue();
      expect(back.downloads[0].hdr).assertTrue();
      expect(back.downloads[0].auxSize).assertEqual(4096);
      expect(back.downloads[0].stillPath).assertEqual('/data/files/images/p1.jpg');
      expect(back.downloads[0].note).assertEqual('解包成功');
      expect(back.wifiOnly).assertTrue();
      expect(back.hdrEnabled).assertFalse();
      expect(back.editQuality).assertEqual('compact');
    });

    it('normalized_fills_missing_fields_of_an_old_file', 0, () => {
      const safe: SavedState = StoreState.normalized(StoreState.parse('{}') as SavedState);
      expect(safe.downloads.length).assertEqual(0);
      expect(safe.zips.length).assertEqual(0);
      expect(safe.batches.length).assertEqual(0);
      expect(safe.concurrency).assertEqual(3);
      expect(safe.wifiOnly).assertFalse();
      expect(safe.themeMode).assertEqual('system');
      expect(safe.materialType).assertEqual('adaptive');
      expect(safe.materialLevel).assertEqual('adaptive');
      expect(safe.lightEffect).assertTrue();
      expect(safe.hdrEnabled).assertTrue();
      expect(safe.pictureQuality).assertEqual('original');
      expect(safe.editQuality).assertEqual('high');
      expect(safe.downloadLocation).assertEqual('app');
    });

    it('normalized_treats_explicit_null_as_missing', 0, () => {
      const raw = '{"downloads":[{"id":"a","url":"u","name":null,"processed":null,'
        + '"createdAt":5,"finishedAt":null}],"zips":[{"id":"z","thumbs":null}],'
        + '"concurrency":null,"themeMode":null,"lightEffect":null,'
        + '"downloadLocation":"custom","customDirUri":null}';
      const safe: SavedState = StoreState.normalized(StoreState.parse(raw) as SavedState);
      expect(safe.downloads[0].name).assertEqual('');
      expect(safe.downloads[0].origin).assertEqual('download');
      expect(safe.downloads[0].processed).assertEqual(0);
      // finishedAt 丢了就退回 createdAt，否则图库会显示成 1970 年。
      expect(safe.downloads[0].finishedAt).assertEqual(5);
      expect(safe.zips[0].thumbs.length).assertEqual(0);
      expect(safe.concurrency).assertEqual(3);
      expect(safe.themeMode).assertEqual('system');
      expect(safe.lightEffect).assertTrue();
      // 选了自定义目录但没记住 URI：必须退回应用文件，否则每次下载都往空 URI 上拷。
      expect(safe.downloadLocation).assertEqual('app');
    });

    it('normalized_clamps_concurrency_and_dirty_modes', 0, () => {
      const safe: SavedState = StoreState.normalized(
        StoreState.parse('{"concurrency":99,"pictureQuality":"thumbnail",'
          + '"editQuality":"png","downloadLocation":"downloads"}') as SavedState);
      expect(safe.concurrency).assertEqual(10);
      expect(safe.pictureQuality).assertEqual('original');
      expect(safe.editQuality).assertEqual('high');
      expect(safe.downloadLocation).assertEqual('app');
    });

    it('normalized_defaults_the_animated_and_live_photo_fields', 0, () => {
      // 老状态文件没有这些字段（也可能被手工写成 null）：一律兜成默认值，
      // 否则界面拿到 undefined 后 `animated` / `kind` 的比较全部落空。
      const safe: SavedState = StoreState.normalized(StoreState.parse(
        '{"downloads":[{"id":"a","path":"/p/a.livp","kind":null,"animated":null,'
        + '"stillPath":null,"motionPath":null,"auxSize":null,"note":null}]}') as SavedState);
      const item: DownloadItem = safe.downloads[0];
      expect(item.kind).assertEqual('image');
      expect(item.animated).assertFalse();
      expect(item.stillPath).assertEqual('');
      expect(item.motionPath).assertEqual('');
      expect(item.auxSize).assertEqual(0);
      expect(item.note).assertEqual('');
    });

    it('normalized_keeps_the_live_photo_content', 0, () => {
      const safe: SavedState = StoreState.normalized(StoreState.parse(
        '{"downloads":[{"id":"a","path":"/p/a.livp","kind":"livephoto","animated":false,'
        + '"stillPath":"/p/a.heic","motionPath":"/p/a.mov","auxSize":42,"note":"解包失败"}]}') as SavedState);
      const item: DownloadItem = safe.downloads[0];
      expect(item.kind).assertEqual('livephoto');
      expect(item.stillPath).assertEqual('/p/a.heic');
      expect(item.motionPath).assertEqual('/p/a.mov');
      expect(item.auxSize).assertEqual(42);
      expect(item.note).assertEqual('解包失败');
    });
  });
}
