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

    it('searches_name_description_and_url_with_other_filters', 0, () => {
      const item: PictureItem = picture('https://example.com/photos/portrait.webp', 0, 0);
      item.name = 'Summer Cover.webp';
      item.description = '海边 人像';
      expect(PictureFilters.matches(item, 'webp', 2000, 2000, 'PHOTOS', '', 'summer')).assertTrue();
      expect(PictureFilters.matches(item, '', 0, 0, '', '', '人像')).assertTrue();
      expect(PictureFilters.matches(item, '', 0, 0, '', '', 'PORTRAIT')).assertTrue();
      expect(PictureFilters.matches(item, 'jpg', 0, 0, '', '', 'summer')).assertFalse();
      expect(PictureFilters.matches(item, '', 0, 0, '', '', 'missing')).assertFalse();
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

    it('records_decoded_size_only_for_the_current_picture_and_url', 0, () => {
      const first: PictureItem[] = PictureFactory.merge([], [
        { url: 'https://example.com/original.jpg', description: 'original' }
      ]);
      const uid: string = first[0].uid;
      expect(PictureFactory.recordDimensions(first, uid, first[0].url, 2400, 1600)).assertTrue();
      expect(first[0].width).assertEqual(2400);
      expect(PictureFactory.recordDimensions(first, uid, 'https://example.com/preview.jpg', 320, 200)).assertFalse();
      expect(PictureFactory.recordDimensions(first, uid, first[0].url, 0, 200)).assertFalse();
      expect(first[0].width).assertEqual(2400);

      const rescanned: PictureItem[] = PictureFactory.merge(first, [
        { url: first[0].url, description: 'original', width: 0, height: 0 }
      ]);
      expect(PictureFactory.recordDimensions(rescanned, uid, first[0].url, 2400, 1600)).assertTrue();
      const nextPage: PictureItem[] = PictureFactory.merge([], [
        { url: first[0].url, description: 'next page' }
      ]);
      expect(PictureFactory.recordDimensions(nextPage, uid, first[0].url, 2400, 1600)).assertFalse();
      expect(nextPage[0].width).assertEqual(0);
    });

    it('filters_large_and_orientation_without_hiding_unknown_sizes', 0, () => {
      const wide: PictureItem = picture('https://example.com/wide.jpg', 1600, 900);
      const tall: PictureItem = picture('https://example.com/tall.jpg', 900, 1600);
      const tiny: PictureItem = picture('https://example.com/tiny.jpg', 300, 200);
      const unknown: PictureItem = picture('https://example.com/unknown.jpg', 0, 0);
      expect(PictureFilters.matches(wide, '', 0, 0, '', 'large')).assertTrue();
      expect(PictureFilters.matches(tiny, '', 0, 0, '', 'large')).assertFalse();
      expect(PictureFilters.matches(wide, '', 0, 0, '', 'landscape')).assertTrue();
      expect(PictureFilters.matches(tall, '', 0, 0, '', 'landscape')).assertFalse();
      expect(PictureFilters.matches(tall, '', 0, 0, '', 'portrait')).assertTrue();
      expect(PictureFilters.matches(unknown, '', 0, 0, '', 'portrait')).assertTrue();
    });

    it('suggests_metadata_image_without_selecting_it', 0, () => {
      const large: PictureItem = picture('https://example.com/large.jpg', 2000, 1200);
      const featured: PictureItem = picture('https://example.com/main.jpg', 0, 0);
      featured.featured = true;
      expect(PictureFilters.suggested([large, featured])?.url).assertEqual(featured.url);
      expect(featured.selected).assertFalse();
      expect(PictureFilters.suggested([large])?.url).assertEqual(large.url);
      expect(PictureFilters.suggested([picture('https://example.com/icon.jpg', 48, 48)])).assertUndefined();
      const fromScan: PictureItem[] = PictureFactory.merge([], [
        { url: featured.url, description: 'main', featured: true }
      ]);
      expect(fromScan[0].featured).assertTrue();
      expect(fromScan[0].selected).assertFalse();
    });
  });
}
