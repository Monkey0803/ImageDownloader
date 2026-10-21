import { describe, it, expect } from '@ohos/hypium';
import { Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { ShareInbox } from '../../../main/ets/service/ShareInbox';

export default function shareInboxTest() {
  describe('ShareInbox', () => {
    it('accepts_single_http_or_https_link', 0, () => {
      expect(ShareInbox.validUrl(' https://example.com/page?x=1 ')).assertEqual('https://example.com/page?x=1');
      expect(ShareInbox.validUrl('http://example.com/image.png')).assertEqual('http://example.com/image.png');
    });

    it('rejects_non_links_and_multiple_links', 0, () => {
      expect(ShareInbox.validUrl('')).assertEqual('');
      expect(ShareInbox.validUrl('hello world')).assertEqual('');
      expect(ShareInbox.validUrl('ftp://example.com/image.png')).assertEqual('');
      expect(ShareInbox.validUrl('https:///missing-host')).assertEqual('');
      expect(ShareInbox.validUrl('https://a.example https://b.example')).assertEqual('');
    });

    it('rejects_shared_plain_text_without_replacing_the_current_link', 0, async () => {
      const first: systemShare.SharedData = new systemShare.SharedData({
        utd: 'general.hyperlink', content: 'https://example.com/page'
      });
      const firstWant: Want = await systemShare.getWant(first);
      firstWant.action = 'ohos.want.action.sendData';
      await ShareInbox.receive(firstWant);

      const invalid: systemShare.SharedData = new systemShare.SharedData({
        utd: 'general.plain-text', content: 'ftp://example.com/file.jpg'
      });
      const invalidWant: Want = await systemShare.getWant(invalid);
      invalidWant.action = 'ohos.want.action.sendData';
      await ShareInbox.receive(invalidWant);
      expect(ShareInbox.take()).assertEqual('');
      expect(ShareInbox.takeError()).assertEqual('分享内容不是单个网页或图片链接');
    });
  });
}
