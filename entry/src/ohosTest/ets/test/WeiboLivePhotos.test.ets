import { describe, it, expect } from '@ohos/hypium';
import { WeiboLivePhotos } from '../../../main/ets/service/WeiboLivePhotos';

export default function weiboLivePhotosTest() {
  describe('WeiboLivePhotos', () => {
    it('recognizes_weibo_detail_pages_and_their_bid', 0, () => {
      expect(WeiboLivePhotos.isWeibo('https://weibo.com/7724361954/RoU53BW2I')).assertTrue();
      expect(WeiboLivePhotos.bidOf('https://weibo.com/7724361954/RoU53BW2I')).assertEqual('RoU53BW2I');
      expect(WeiboLivePhotos.bidOf('https://m.weibo.cn/detail/RoU53BW2I')).assertEqual('RoU53BW2I');
      expect(WeiboLivePhotos.bidOf('https://weibo.com/status/RoU53BW2I?from=page')).assertEqual('RoU53BW2I');
      expect(WeiboLivePhotos.bidOf('https://weibo.com/u/7724361954')).assertEqual('');
      expect(WeiboLivePhotos.isWeibo('https://example.com/7724361954/RoU53BW2I')).assertFalse();
    });

    it('matches_still_urls_by_weibo_pid', 0, () => {
      expect(WeiboLivePhotos.stemOf('https://wx1.sinaimg.cn/mw2000/008qKDp8ly1iij6elerjdj30mi0u0aco.jpg'))
        .assertEqual('008qKDp8ly1iij6elerjdj30mi0u0aco');
      expect(WeiboLivePhotos.stemOf('https://wx1.sinaimg.cn/orj360/008qKDp8ly1iij6elerjdj30mi0u0aco.jpg?x=1'))
        .assertEqual('008qKDp8ly1iij6elerjdj30mi0u0aco');
    });
  });
}
