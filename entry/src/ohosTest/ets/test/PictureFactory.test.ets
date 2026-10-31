import { describe, it, expect } from '@ohos/hypium';
import { PictureFactory } from '../../../main/ets/service/PictureFactory';
import { PictureItem } from '../../../main/ets/model/Models';

export default function pictureFactoryTest() {
  describe('PictureFactory', () => {
    it('marks_scanned_live_photo_with_its_motion', 0, () => {
      const picture: PictureItem = PictureFactory.fromScan({
        url: 'https://wx1.sinaimg.cn/large/008qKDp8ly1iij6elerjdj30mi0u0aco.jpg',
        description: '实况',
        motion: 'https://video.weibo.com/media/play?livephoto=008qKDp8.mov'
      }, 1);
      expect(picture.kind).assertEqual('livephoto');
      expect(picture.motionUrl).assertEqual('https://video.weibo.com/media/play?livephoto=008qKDp8.mov');
      expect(picture.name.toLowerCase().endsWith('.livp')).assertTrue();
    });

    it('keeps_plain_image_without_motion', 0, () => {
      const picture: PictureItem = PictureFactory.fromScan({
        url: 'https://a.example/b.jpg',
        description: ''
      }, 1);
      expect(picture.kind).assertEqual('image');
      expect(picture.motionUrl).assertEqual('');
      expect(picture.name).assertEqual('b.jpg');
    });
  });
}
