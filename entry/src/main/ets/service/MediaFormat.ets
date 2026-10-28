/*
 * MediaFormat.ets — 媒体格式判定，**纯函数、零 IO**。
 *
 * 这里只做字符串与字节的判断，不碰 fs / 任何 kit：所以它能被 ohosTest 直接单测，
 * 也能同时被 service 与 view 引用（Naming 的命名、DiscoverViewModel 的直链识别、
 * Delivery 的相册投递、Thumb 的首帧与角标都走同一份表，避免三处各写一份扩展名白名单
 * 而慢慢漂移）。
 *
 * 两条判定链：
 *   1. 名字 / 地址 → 类型：`mediaKindOf()` 用扩展名区分 image / livephoto / video；
 *   2. 字节 → 是否动图：`gifLooksAnimated()` / `webpLooksAnimated()` 只看文件头特征 ——
 *      ArkUI 的 Image 没有「只播首帧」的开关，网格要不要静态首帧全看这个判定。
 *
 * 以类而不是「一堆导出函数」组织：与 `Naming` / `StoreState` 一致，调用点写
 * `MediaFormat.extensionOf(...)` 一眼能看出判据来自哪一层。
 */
export class MediaFormat {
  /** Apple 实况照片包：`.livp` 是内含 HEIC/JPEG + MOV 的 ZIP，`.livephoto` 是同一形态的别名。 */
  static readonly LIVE_PHOTO_EXTENSIONS: string[] = ['livp', 'livephoto'];

  /** 会动的图片格式。其余图片格式都当静态处理。 */
  static readonly ANIMATED_EXTENSIONS: string[] = ['gif', 'webp'];

  /** 网页上直接当图片下载的扩展名（与 `Naming.suggested` 的白名单是同一份）。 */
  static readonly IMAGE_EXTENSIONS: string[] =
    ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif', 'avif', 'bmp', 'svg', 'tif', 'tiff'];

  /** 实况照片包里的静图，**按优先级排序**（HEIC 优先，其次通用格式）。 */
  static readonly STILL_EXTENSIONS: string[] =
    ['heic', 'heif', 'jpg', 'jpeg', 'png', 'avif', 'bmp', 'tif', 'tiff', 'webp'];

  /** 实况照片包里的动态部分，MOV 优先（Apple 原生），其次 MP4。 */
  static readonly MOTION_EXTENSIONS: string[] = ['mov', 'mp4', 'm4v'];

  /** 去掉 query / fragment 后的末段：URL 取最后一段路径，文件名原样返回。 */
  static leafOf(nameOrUrl: string): string {
    let text: string = nameOrUrl.trim();
    const hash: number = text.indexOf('#');
    if (hash >= 0) {
      text = text.substring(0, hash);
    }
    const query: number = text.indexOf('?');
    if (query >= 0) {
      text = text.substring(0, query);
    }
    const slash: number = text.lastIndexOf('/');
    return slash >= 0 ? text.substring(slash + 1) : text;
  }

  /** 小写扩展名；取不到时返回空串（`noext` / `pic.` 都算取不到）。 */
  static extensionOf(nameOrUrl: string): string {
    const leaf: string = MediaFormat.leafOf(nameOrUrl);
    const dot: number = leaf.lastIndexOf('.');
    if (dot <= 0 || dot === leaf.length - 1) {
      return '';
    }
    return leaf.substring(dot + 1).toLowerCase();
  }

  static isLivePhotoName(nameOrUrl: string): boolean {
    return MediaFormat.LIVE_PHOTO_EXTENSIONS.includes(MediaFormat.extensionOf(nameOrUrl));
  }

  static isAnimatedName(nameOrUrl: string): boolean {
    return MediaFormat.ANIMATED_EXTENSIONS.includes(MediaFormat.extensionOf(nameOrUrl));
  }

  static isImageName(nameOrUrl: string): boolean {
    return MediaFormat.IMAGE_EXTENSIONS.includes(MediaFormat.extensionOf(nameOrUrl));
  }

  static isAnimatedExt(extension: string): boolean {
    return MediaFormat.ANIMATED_EXTENSIONS.includes(extension);
  }

  static isStillExt(extension: string): boolean {
    return MediaFormat.STILL_EXTENSIONS.includes(extension);
  }

  static isMotionExt(extension: string): boolean {
    return MediaFormat.MOTION_EXTENSIONS.includes(extension);
  }

  /** 命名时**保留**的扩展名：图片格式 + 实况照片包，取到别的后缀才补 `.jpg`。 */
  static keepsExtension(extension: string): boolean {
    return MediaFormat.IMAGE_EXTENSIONS.includes(extension)
      || MediaFormat.LIVE_PHOTO_EXTENSIONS.includes(extension);
  }

  /**
   * 一个名字 / URL 属于哪一类：`'livephoto' | 'image' | 'video' | ''`。
   *
   * 地址栏拿它决定「这是实况照片包」「这是图片」还是「这是一个网页，去扫描」——
   * 三档判断只此一处，不再散落在各处的正则里。
   */
  static mediaKindOf(nameOrUrl: string): string {
    const extension: string = MediaFormat.extensionOf(nameOrUrl);
    if (MediaFormat.LIVE_PHOTO_EXTENSIONS.includes(extension)) {
      return 'livephoto';
    }
    if (MediaFormat.IMAGE_EXTENSIONS.includes(extension)) {
      return 'image';
    }
    if (MediaFormat.MOTION_EXTENSIONS.includes(extension)) {
      return 'video';
    }
    return '';
  }

  /**
   * 酷安等站点把实况照片的静图放在普通图片地址里，文件名带 `-livepic` / `_livepic`。
   *
   * 网页只提供这一张静图，视频部分不在公开页面里；界面据此标注“实况静图”，
   * 不把它误当成可播放的 `.livp` 包，也不承诺动态内容。
   */
  static isLivepicStill(nameOrUrl: string): boolean {
    if (MediaFormat.mediaKindOf(nameOrUrl) !== 'image') {
      return false;
    }
    return /(^|[-_])livepic(?:[-_.@]|$)/i.test(MediaFormat.leafOf(nameOrUrl));
  }

  /** 头部字节是否是 ZIP（`PK`）：实况照片包必须是 ZIP，否则只当普通文件保留。 */
  static isZipSignature(bytes: Uint8Array): boolean {
    return bytes.length >= 2 && bytes[0] === 0x50 && bytes[1] === 0x4b;
  }

  /**
   * GIF 是否动图。
   *
   * 判据取自文件头：出现 `NETSCAPE2.0` 应用扩展块（循环播放标记，动画 GIF 基本都有），
   * 或出现两次以上图形控制扩展 `21 F9`（多帧的硬证据）。单帧 GIF 两个条件都不满足。
   */
  static gifLooksAnimated(bytes: Uint8Array): boolean {
    let controls: number = 0;
    for (let i: number = 0; i + 2 < bytes.length; i++) {
      if (bytes[i] === 0x21 && bytes[i + 1] === 0xf9) {
        controls += 1;
        if (controls >= 2) {
          return true;
        }
        continue;
      }
      if (bytes[i] === 0x21 && bytes[i + 1] === 0xff && bytes[i + 2] === 0x0b
        && MediaFormat.matchesAscii(bytes, i + 3, 'NETSCAPE2.0')) {
        return true;
      }
    }
    return false;
  }

  /**
   * WebP 是否动图。
   *
   * RIFF 容器里带 `VP8X` 扩展块、且 flags 字节的 ANIMATION 位（0x02）置位即为动图；
   * `VP8 `（有损）/`VP8L`（无损）都是单帧静态图。
   */
  static webpLooksAnimated(bytes: Uint8Array): boolean {
    if (bytes.length < 21) {
      return false;
    }
    if (!MediaFormat.matchesAscii(bytes, 0, 'RIFF') || !MediaFormat.matchesAscii(bytes, 8, 'WEBP')) {
      return false;
    }
    if (!MediaFormat.matchesAscii(bytes, 12, 'VP8X')) {
      return false;
    }
    return (bytes[20] & 0x02) !== 0;
  }

  private static matchesAscii(bytes: Uint8Array, offset: number, text: string): boolean {
    if (offset + text.length > bytes.length) {
      return false;
    }
    for (let i: number = 0; i < text.length; i++) {
      if (bytes[offset + i] !== text.charCodeAt(i)) {
        return false;
      }
    }
    return true;
  }
}
