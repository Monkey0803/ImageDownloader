import { describe, expect, it } from '@ohos/hypium';
import { BatchLinks } from '../../../main/ets/service/BatchLinks';
import { BatchPageGroups, BatchPageGroup, BatchPageResult, BatchPageDownload } from '../../../main/ets/service/BatchPageGroups';
import { BatchPageQueue } from '../../../main/ets/service/BatchPageQueue';

export default function batchPagesTest() {
  describe('BatchPages', () => {
    it('routes_weibo_and_html_to_page_parsing', 0, (): void => {
      const report = BatchLinks.parse('https://weibo.com/3288446905/RoKPzDSuI\n'
        + 'https://weibo.com/5571216925/RoI359Sfb\nhttps://example.test/p.html\nhttps://example.test/a.jpg');
      expect(report.pages).assertEqual(3);
      expect(report.valid).assertEqual(1);
      expect(report.invalid).assertEqual(0);
    });
    it('retains_sources_and_selections_across_partial_failure', 0, async (): Promise<void> => {
      const groups: BatchPageGroup[] = BatchPageGroups.create(BatchLinks.parse(
        'https://example.test/a.jpg\nhttps://example.test/one.html\nhttps://example.test/bad.html\nhttps://example.test/two.html'));
      await new BatchPageQueue().run(groups, async (group: BatchPageGroup): Promise<BatchPageResult> => {
        if (group.line === 3) { throw new Error('fixture failure'); }
        const result: BatchPageResult = new BatchPageResult();
        result.url = group.inputUrl; result.title = 'Page ' + group.line.toString();
        result.images = [{ url: 'https://cdn.test/a.jpg', description: '' },
          { url: 'https://cdn.test/a.jpg', description: '' }, { url: 'https://cdn.test/a.jpg?sign=b', description: '' }];
        return result;
      }, (): void => {});
      expect(groups[2].status).assertEqual('failed');
      expect(groups[3].pictures.length).assertEqual(2);
      expect(groups[1].pictures[0].selected).assertTrue();
      groups[1].pictures[0].selected = false;
      const jobs: BatchPageDownload[] = BatchPageGroups.downloads(groups);
      expect(jobs.length).assertEqual(3);
      expect(jobs[0].pageUrl).assertEqual('');
      expect(jobs[1].pageUrl).assertEqual('https://example.test/one.html');
      expect(jobs[1].pictures.length).assertEqual(1);
      expect(jobs[2].title).assertEqual('Page 4');
    });
  });
}
