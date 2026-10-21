import { describe, it, expect } from '@ohos/hypium';
import { BatchLinks, BatchLinkReport } from '../../../main/ets/service/BatchLinks';

export default function batchLinksTest() {
  describe('BatchLinks', () => {
    it('accepts_image_links_in_order_and_reports_invalid_and_duplicate_rows', 0, () => {
      const report: BatchLinkReport = BatchLinks.parse('https://a.example/a.jpg\n'
        + 'https://a.example/b.webp?token=1\nhttps://a.example/a.jpg\n'
        + 'ftp://a.example/c.png\nhttps://a.example/page.html\n');
      expect(report.urls.join(',')).assertEqual('https://a.example/a.jpg,https://a.example/b.webp?token=1');
      expect(report.invalid).assertEqual(2);
      expect(report.duplicates).assertEqual(1);
    });

    it('keeps_live_photo_links_and_rejects_whitespace_inside_urls', 0, () => {
      const report: BatchLinkReport = BatchLinks.parse('  https://a.example/live.livp  \r\n'
        + 'https://a.example/bad name.png\n');
      expect(report.urls.length).assertEqual(1);
      expect(report.invalid).assertEqual(1);
    });
  });
}
