import { describe, it, expect } from '@ohos/hypium';
import { PictureItem } from '../../../main/ets/model/Models';
import { PictureFilters } from '../../../main/ets/service/PictureFilters';
import { PictureFactory, ScanImage } from '../../../main/ets/service/PictureFactory';

function picture(url: string, width: number, height: number): PictureItem {
  const item: PictureItem = new PictureItem();
  item.url = url;
  item.width = width;
  item.height = height;
  return item;
}

export default function pictureFiltersTest() {
  describe('PictureFilters', () => {
    it('filters_format_dimensions_and_url', 0, () => {
      const large: PictureItem = picture('https://example.com/photos/Large.JPG?x=1', 1600, 1200);
      const small: PictureItem = picture('https://example.com/photos/tiny.jpg', 320, 240);
      expect(PictureFilters.matches(large, 'jpg', 1000, 800, 'PHOTOS')).assertTrue();
      expect(PictureFilters.matches(small, 'jpg', 1000, 800, '')).assertFalse();
      expect(PictureFilters.matches(large, 'png', 0, 0, '')).assertFalse();
      expect(PictureFilters.matches(large, '', 0, 0, 'other')).assertFalse();
    });

    it('keeps_unknown_dimensions_visible', 0, () => {
      expect(PictureFilters.matches(picture('https://example.com/a.webp', 0, 0),
        'webp', 2000, 2000, '')).assertTrue();
      expect(PictureFilters.minimum('800')).assertEqual(800);
      expect(PictureFilters.minimum('')).assertEqual(0);
    });

    it('keeps_selection_when_rescanning_same_url', 0, () => {
      const first: ScanImage = { url: 'https://example.com/a.jpg', description: 'A', width: 800, height: 600 };
      const initial: PictureItem[] = PictureFactory.merge([], [first]);
      initial[0].selected = true;
      const rescanned: ScanImage = { url: first.url, description: 'A', width: 1200, height: 900 };
      const merged: PictureItem[] = PictureFactory.merge(initial, [rescanned]);
      expect(merged.length).assertEqual(1);
      expect(merged[0].selected).assertTrue();
      expect(merged[0].width).assertEqual(1200);
    });
  });
}
