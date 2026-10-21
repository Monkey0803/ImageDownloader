import { describe, it, expect } from '@ohos/hypium';
import { DownloadItem, ZipItem } from '../../../main/ets/model/Models';
import { LibraryQuery } from '../../../main/ets/service/LibraryQuery';

function image(name: string, source: string, size: number, finishedAt: number): DownloadItem {
  const item: DownloadItem = new DownloadItem();
  item.name = name;
  item.sourcePage = source;
  item.size = size;
  item.finishedAt = finishedAt;
  item.status = 'completed';
  return item;
}

export default function libraryQueryTest() {
  describe('LibraryQuery', () => {
    it('combines_name_source_and_format_filters', 0, () => {
      const first: DownloadItem = image('cat.jpg', 'https://a.example/gallery', 50, 10);
      const second: DownloadItem = image('cat.png', 'https://b.example/gallery', 70, 20);
      const result: DownloadItem[] = LibraryQuery.images([first, second], 'cat', 'A.EXAMPLE', 'jpg', 'newest');
      expect(result.length).assertEqual(1);
      expect(result[0].name).assertEqual('cat.jpg');
    });

    it('sorts_without_mutating_store_order', 0, () => {
      const first: DownloadItem = image('a.jpg', '', 20, 10);
      const second: DownloadItem = image('b.jpg', '', 80, 20);
      const source: DownloadItem[] = [first, second];
      expect(LibraryQuery.images(source, '', '', '', 'size')[0].name).assertEqual('b.jpg');
      expect(source[0].name).assertEqual('a.jpg');
      expect(LibraryQuery.images(source, '', '', '', 'oldest')[0].name).assertEqual('a.jpg');
    });

    it('sorts_archives_by_size', 0, () => {
      const small: ZipItem = new ZipItem();
      small.name = 'small.zip'; small.size = 10;
      const large: ZipItem = new ZipItem();
      large.name = 'large.zip'; large.size = 100;
      expect(LibraryQuery.archives([small, large], '', 'size')[0].name).assertEqual('large.zip');
    });

    it('keeps_combined_filters_and_order_correct_with_hundreds_of_records', 0, () => {
      const items: DownloadItem[] = [];
      for (let index: number = 0; index < 400; index++) {
        const format: string = index % 2 === 0 ? 'jpg' : 'png';
        const source: string = index % 5 === 0 ? 'https://match.example/gallery' : 'https://other.example/';
        items.push(image('item-' + index.toString() + '.' + format, source, index, index));
      }
      const result: DownloadItem[] = LibraryQuery.images(items, 'item-', 'match.example', 'jpg', 'size');
      expect(result.length).assertEqual(40);
      expect(result[0].name).assertEqual('item-390.jpg');
      expect(result[result.length - 1].name).assertEqual('item-0.jpg');
      expect(items[0].name).assertEqual('item-0.jpg');
    });
  });
}
