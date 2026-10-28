import { describe, it, expect } from '@ohos/hypium';
import { MediaFormat } from '../../../main/ets/service/MediaFormat';

// MediaFormat 是纯计算：不碰 fs、不碰 kit，所以可以拿手搓的字节数直接测判定逻辑。
// 动图那两个判定值得测：图库「画静止首帧」完全依赖它们，误判只会表现为「格子不动了」，
// 界面上看不出来是哪一步错了。

function asciiAt(bytes: Uint8Array, offset: number, text: string): void {
  for (let i: number = 0; i < text.length; i++) {
    bytes[offset + i] = text.charCodeAt(i);
  }
}

/** 一个最小 WebP 头：RIFF + WEBP + 指定的第一块 fourCC + flags 字节。 */
function webpHeader(fourCC: string, flags: number): Uint8Array {
  const bytes: Uint8Array = new Uint8Array(24);
  asciiAt(bytes, 0, 'RIFF');
  asciiAt(bytes, 8, 'WEBP');
  asciiAt(bytes, 12, fourCC);
  bytes[20] = flags;
  return bytes;
}

export default function mediaFormatTest() {
  describe('MediaFormat.extensionOf', () => {
    it('reads_the_last_path_segment', 0, () => {
      expect(MediaFormat.extensionOf('https://a.com/img/pic.PNG')).assertEqual('png');
      expect(MediaFormat.extensionOf('/data/x/photo.jpeg')).assertEqual('jpeg');
      expect(MediaFormat.extensionOf('photo.webp')).assertEqual('webp');
    });

    it('drops_query_and_fragment', 0, () => {
      expect(MediaFormat.extensionOf('https://a.com/pic.webp?w=100&h=100')).assertEqual('webp');
      expect(MediaFormat.extensionOf('https://a.com/pic.gif#top')).assertEqual('gif');
      expect(MediaFormat.extensionOf('https://a.com/IMG_1.livp?token=abc')).assertEqual('livp');
      // 扩展名只在 query 里（`?name=x.livp`）不算：那不是这个地址的后缀。
      expect(MediaFormat.extensionOf('https://a.com/download?id=1&name=x.livp')).assertEqual('');
    });

    it('returns_empty_when_there_is_none', 0, () => {
      expect(MediaFormat.extensionOf('https://a.com/img/noext')).assertEqual('');
      expect(MediaFormat.extensionOf('https://a.com/img/trailing.')).assertEqual('');
      expect(MediaFormat.extensionOf('')).assertEqual('');
    });
  });

  describe('MediaFormat.mediaKindOf', () => {
    it('recognises_live_photo_packages', 0, () => {
      expect(MediaFormat.mediaKindOf('https://a.com/IMG_1234.livp')).assertEqual('livephoto');
      expect(MediaFormat.mediaKindOf('https://a.com/IMG_1234.LIVEPHOTO?x=1')).assertEqual('livephoto');
    });

    it('recognises_images_including_animated_ones', 0, () => {
      expect(MediaFormat.mediaKindOf('https://a.com/a.jpg')).assertEqual('image');
      expect(MediaFormat.mediaKindOf('https://a.com/a.webp')).assertEqual('image');
      expect(MediaFormat.mediaKindOf('https://a.com/a.gif')).assertEqual('image');
      expect(MediaFormat.mediaKindOf('https://a.com/a.heic')).assertEqual('image');
    });

    it('recognises_videos_but_leaves_unknown_empty', 0, () => {
      expect(MediaFormat.mediaKindOf('https://a.com/clip.mov')).assertEqual('video');
      expect(MediaFormat.mediaKindOf('https://a.com/clip.mp4')).assertEqual('video');
      expect(MediaFormat.mediaKindOf('https://a.com/page.html')).assertEqual('');
      expect(MediaFormat.mediaKindOf('https://a.com/')).assertEqual('');
    });
  });

  describe('MediaFormat.isLivepicStill', () => {
    it('marks_only_the_still_image_of_a_livepic_post', 0, () => {
      expect(MediaFormat.isLivepicStill(
        'https://image.coolapk.com/feed/2026/1010/10/a-livepic@1440x2560.jpg')).assertTrue();
      expect(MediaFormat.isLivepicStill(
        'https://image.coolapk.com/feed/2026/1027/03/a-livepic-uhdr@2494x3325.jpg')).assertTrue();
      expect(MediaFormat.isLivepicStill('https://a.com/livepic.jpg')).assertTrue();
      expect(MediaFormat.isLivepicStill('https://a.com/a_livepic.webp')).assertTrue();
      expect(MediaFormat.isLivepicStill('https://a.com/livepicture.jpg')).assertFalse();
      expect(MediaFormat.isLivepicStill('https://a.com/notlivepic.jpg')).assertFalse();
      expect(MediaFormat.isLivepicStill('https://a.com/a.livp')).assertFalse();
      expect(MediaFormat.isLivepicStill('https://a.com/a-livepic.mp4')).assertFalse();
    });
  });

  describe('MediaFormat.keepsExtension', () => {
    it('keeps_images_and_live_photo_packages', 0, () => {
      expect(MediaFormat.keepsExtension('png')).assertTrue();
      expect(MediaFormat.keepsExtension('livp')).assertTrue();
      expect(MediaFormat.keepsExtension('livephoto')).assertTrue();
    });

    it('rejects_anything_else', 0, () => {
      expect(MediaFormat.keepsExtension('zip')).assertFalse();
      expect(MediaFormat.keepsExtension('tar')).assertFalse();
      expect(MediaFormat.keepsExtension('')).assertFalse();
    });
  });

  describe('MediaFormat.gifLooksAnimated', () => {
    it('treats_a_plain_header_as_static', 0, () => {
      const bytes: Uint8Array = new Uint8Array(6);
      asciiAt(bytes, 0, 'GIF89a');
      expect(MediaFormat.gifLooksAnimated(bytes)).assertFalse();
    });

    it('detects_the_netscape_loop_block', 0, () => {
      const bytes: Uint8Array = new Uint8Array(20);
      bytes[0] = 0x21;
      bytes[1] = 0xff;
      bytes[2] = 0x0b;
      asciiAt(bytes, 3, 'NETSCAPE2.0');
      expect(MediaFormat.gifLooksAnimated(bytes)).assertTrue();
    });

    it('detects_two_graphic_control_blocks', 0, () => {
      const bytes: Uint8Array = new Uint8Array(6);
      bytes[0] = 0x21;
      bytes[1] = 0xf9;
      bytes[3] = 0x21;
      bytes[4] = 0xf9;
      expect(MediaFormat.gifLooksAnimated(bytes)).assertTrue();
    });

    it('treats_a_single_control_block_as_static', 0, () => {
      const bytes: Uint8Array = new Uint8Array(5);
      bytes[0] = 0x21;
      bytes[1] = 0xf9;
      expect(MediaFormat.gifLooksAnimated(bytes)).assertFalse();
    });
  });

  describe('MediaFormat.webpLooksAnimated', () => {
    it('detects_the_vp8x_animation_flag', 0, () => {
      expect(MediaFormat.webpLooksAnimated(webpHeader('VP8X', 0x02))).assertTrue();
      expect(MediaFormat.webpLooksAnimated(webpHeader('VP8X', 0x12))).assertTrue();
    });

    it('treats_vp8x_without_the_flag_as_static', 0, () => {
      expect(MediaFormat.webpLooksAnimated(webpHeader('VP8X', 0x00))).assertFalse();
      expect(MediaFormat.webpLooksAnimated(webpHeader('VP8X', 0x10))).assertFalse();
    });

    it('treats_lossy_and_lossless_webp_as_static', 0, () => {
      expect(MediaFormat.webpLooksAnimated(webpHeader('VP8 ', 0x02))).assertFalse();
      expect(MediaFormat.webpLooksAnimated(webpHeader('VP8L', 0x02))).assertFalse();
    });

    it('rejects_short_or_foreign_data', 0, () => {
      expect(MediaFormat.webpLooksAnimated(new Uint8Array(4))).assertFalse();
      const png: Uint8Array = new Uint8Array(24);
      asciiAt(png, 0, 'PNG');
      expect(MediaFormat.webpLooksAnimated(png)).assertFalse();
    });
  });

  describe('MediaFormat.isZipSignature', () => {
    it('accepts_the_pk_magic', 0, () => {
      const bytes: Uint8Array = new Uint8Array(4);
      bytes[0] = 0x50;
      bytes[1] = 0x4b;
      bytes[2] = 0x03;
      bytes[3] = 0x04;
      expect(MediaFormat.isZipSignature(bytes)).assertTrue();
    });

    it('rejects_short_and_other_data', 0, () => {
      const one: Uint8Array = new Uint8Array(1);
      one[0] = 0x50;
      expect(MediaFormat.isZipSignature(one)).assertFalse();
      const other: Uint8Array = new Uint8Array(2);
      other[0] = 0x50;
      other[1] = 0x4c;
      expect(MediaFormat.isZipSignature(other)).assertFalse();
    });
  });
}
