import { describe, it, expect } from '@ohos/hypium';
import { DownloadItem } from '../../../main/ets/model/Models';
import { DuplicateFinder } from '../../../main/ets/service/DuplicateFinder';
import { fileIo as fs } from '@kit.CoreFileKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';

function item(url: string, name: string): DownloadItem {
  const value: DownloadItem = new DownloadItem();
  value.url = url;
  value.name = name;
  value.path = '/tmp/' + name;
  value.status = 'completed';
  return value;
}

export default function duplicateFinderTest() {
  describe('DuplicateFinder', () => {
    it('keeps_full_url_and_source_filename_as_separate_evidence', 0, () => {
      const first: DownloadItem = item('https://a.example/img/cat.jpg?v=1', 'cat.jpg');
      const second: DownloadItem = item('https://a.example/img/cat.jpg?v=2', 'cat (2).jpg');
      const third: DownloadItem = item('https://a.example/img/cat.jpg?v=1', 'cat (3).jpg');
      expect(DuplicateFinder.sameUrl([first, second, third]).length).assertEqual(1);
      expect(DuplicateFinder.sameUrl([first, second, third])[0].items.length).assertEqual(2);
      expect(DuplicateFinder.sameSourceName([first, second, third])[0].items.length).assertEqual(3);
    });

    it('ignores_incomplete_records_and_empty_source_names', 0, () => {
      const first: DownloadItem = item('https://a.example/', 'one.jpg');
      const second: DownloadItem = item('https://a.example/', 'two.jpg');
      second.status = 'failed';
      expect(DuplicateFinder.sameUrl([first, second]).length).assertEqual(0);
      expect(DuplicateFinder.sameSourceName([first, second]).length).assertEqual(0);
    });

    it('groups_equal_file_bytes_without_treating_equal_size_as_equal_content', 0, async () => {
      const root: string = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir;
      const prefix: string = root + '/duplicate-test-' + Date.now().toString();
      const paths: string[] = [prefix + '-a', prefix + '-b', prefix + '-c'];
      const values: string[] = ['same-data', 'same-data', 'diff-data'];
      try {
        for (let index: number = 0; index < paths.length; index++) {
          const file: fs.File = fs.openSync(paths[index], fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          fs.writeSync(file.fd, values[index]);
          fs.closeSync(file);
        }
        const items: DownloadItem[] = paths.map((path: string, index: number): DownloadItem => {
          const value: DownloadItem = item('https://a.example/' + index.toString() + '.jpg',
            index.toString() + '.jpg');
          value.path = path;
          return value;
        });
        const result = await DuplicateFinder.sameContent(items, (done: number, total: number): void => {});
        expect(result.candidates).assertEqual(3);
        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].items.length).assertEqual(2);
        expect(result.failures).assertEqual(0);
      } finally {
        for (const path of paths) {
          try { fs.unlinkSync(path); } catch (error) {}
        }
      }
    });
  });
}
