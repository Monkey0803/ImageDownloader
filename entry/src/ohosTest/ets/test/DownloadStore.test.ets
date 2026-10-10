import { describe, it, expect, beforeEach, afterEach } from '@ohos/hypium';
import { DownloadStore } from '../../../main/ets/service/DownloadStore';
import { DownloadItem } from '../../../main/ets/model/Models';

// 纯函数单测：不依赖 UIAbilityContext，也不访问真实文件系统。
// uniqueName 用不存在的目录，只验证与 DownloadStore.downloads 的去重逻辑。

const NO_DIR = '/__no_such_dir_for_test__';

function makeDownload(path: string): DownloadItem {
  const item = new DownloadItem();
  item.path = path;
  return item;
}

export default function downloadStoreTest() {
  describe('DownloadStore.cleanName', () => {
    it('replaces_illegal_chars', 0, () => {
      expect(DownloadStore.cleanName('a/b\\c:d*e?f"g<h>i|j', 'fb')).assertEqual('a_b_c_d_e_f_g_h_i_j');
    });

    it('strips_leading_and_trailing_dots_and_spaces', 0, () => {
      expect(DownloadStore.cleanName('  hi  ', 'fb')).assertEqual('hi');
      expect(DownloadStore.cleanName('...hi...', 'fb')).assertEqual('hi');
      expect(DownloadStore.cleanName(' .hi. ', 'fb')).assertEqual('hi');
    });

    it('falls_back_when_empty', 0, () => {
      expect(DownloadStore.cleanName('', 'fb')).assertEqual('fb');
      expect(DownloadStore.cleanName('   ', 'fb')).assertEqual('fb');
      expect(DownloadStore.cleanName('...', 'fb')).assertEqual('fb');
    });

    it('truncates_to_120_chars', 0, () => {
      const long = 'a'.repeat(130);
      expect(DownloadStore.cleanName(long, 'fb').length).assertEqual(120);
    });

    it('keeps_chinese_and_spaces_inside', 0, () => {
      expect(DownloadStore.cleanName('我的 图片', 'fb')).assertEqual('我的 图片');
    });
  });

  describe('DownloadStore.suggestedName', () => {
    it('uses_last_path_segment', 0, () => {
      expect(DownloadStore.suggestedName('https://a.com/img/pic.png', '', 1)).assertEqual('pic.png');
    });

    it('drops_query_and_fragment', 0, () => {
      expect(DownloadStore.suggestedName('https://a.com/img/pic.png?x=1', '', 1)).assertEqual('pic.png');
      expect(DownloadStore.suggestedName('https://a.com/img/pic.png#frag', '', 1)).assertEqual('pic.png');
      expect(DownloadStore.suggestedName('https://a.com/img/pic.png?x=1#frag', '', 1)).assertEqual('pic.png');
    });

    it('decodes_percent_encoding', 0, () => {
      expect(DownloadStore.suggestedName('https://a.com/img/%E4%B8%AD%E6%96%87.jpg', '', 1)).assertEqual('中文.jpg');
    });

    it('appends_jpg_when_extension_unknown', 0, () => {
      expect(DownloadStore.suggestedName('https://a.com/img/noext', 'descr', 1)).assertEqual('noext.jpg');
      expect(DownloadStore.suggestedName('https://a.com/img/pic.tar.gz', '', 1)).assertEqual('pic.tar.gz.jpg');
    });

    it('keeps_known_extensions_case_insensitively', 0, () => {
      expect(DownloadStore.suggestedName('https://a.com/PIC.PNG', '', 1)).assertEqual('PIC.PNG');
      expect(DownloadStore.suggestedName('https://a.com/pic.webp', '', 1)).assertEqual('pic.webp');
    });

    it('falls_back_to_description_then_index', 0, () => {
      expect(DownloadStore.suggestedName('https://a.com/', '我的图', 1)).assertEqual('我的图.jpg');
      expect(DownloadStore.suggestedName('https://a.com/', '', 7)).assertEqual('图片_7.jpg');
    });

    it('sanitizes_description_used_as_name', 0, () => {
      expect(DownloadStore.suggestedName('https://a.com/', 'a/b:c', 1)).assertEqual('a_b_c.jpg');
    });
  });

  describe('DownloadStore.withExtension', () => {
    it('replaces_last_extension', 0, () => {
      expect(DownloadStore.withExtension('photo.png', 'jpg')).assertEqual('photo.jpg');
      expect(DownloadStore.withExtension('a.b.c', 'webp')).assertEqual('a.b.webp');
    });

    it('appends_when_no_extension', 0, () => {
      expect(DownloadStore.withExtension('noext', 'png')).assertEqual('noext.png');
    });

    it('handles_leading_dot_and_empty', 0, () => {
      expect(DownloadStore.withExtension('.hidden', 'png')).assertEqual('hidden.png');
      expect(DownloadStore.withExtension('', 'png')).assertEqual('图片.png');
    });

    it('handles_trailing_dot', 0, () => {
      expect(DownloadStore.withExtension('trailing.', 'png')).assertEqual('trailing.png');
    });

    it('sanitizes_before_appending', 0, () => {
      expect(DownloadStore.withExtension('a/b', 'png')).assertEqual('a_b.png');
    });
  });

  describe('DownloadStore.imageExtension', () => {
    it('maps_common_image_types', 0, () => {
      expect(DownloadStore.imageExtension('image/png')).assertEqual('png');
      expect(DownloadStore.imageExtension('image/jpeg')).assertEqual('jpg');
      expect(DownloadStore.imageExtension('image/jpg')).assertEqual('jpg');
      expect(DownloadStore.imageExtension('image/webp')).assertEqual('webp');
      expect(DownloadStore.imageExtension('image/gif')).assertEqual('gif');
      expect(DownloadStore.imageExtension('image/heic')).assertEqual('heic');
      expect(DownloadStore.imageExtension('image/avif')).assertEqual('avif');
      expect(DownloadStore.imageExtension('image/bmp')).assertEqual('bmp');
      expect(DownloadStore.imageExtension('image/svg+xml')).assertEqual('svg');
      expect(DownloadStore.imageExtension('image/tiff')).assertEqual('tiff');
    });

    it('ignores_case_and_parameters', 0, () => {
      expect(DownloadStore.imageExtension('IMAGE/PNG; charset=utf-8')).assertEqual('png');
      expect(DownloadStore.imageExtension(' image/jpeg ')).assertEqual('jpg');
    });

    it('returns_empty_for_non_image', 0, () => {
      expect(DownloadStore.imageExtension('text/html')).assertEqual('');
      expect(DownloadStore.imageExtension('')).assertEqual('');
      expect(DownloadStore.imageExtension('application/octet-stream')).assertEqual('');
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
}
