import { MediaFormat } from './MediaFormat';

/**
 * 文件名与扩展名的纯计算（**零 IO、零状态**）。
 *
 * 这五个函数原来长在 `service/DownloadStore.ets` 里，和下载队列、文件系统、持久化混在一个
 * 1100 行的静态类中。它们其实只做字符串处理，却被 `DownloadStore.` 这个前缀绑住 ——
 * 单测也得先把整个商店 import 进来。
 *
 * 搬出来之后：`Naming` 只依赖同样纯计算的 `MediaFormat`（扩展名白名单只有那一份），
 * 可以单独跑单测（`ohosTest` 里的五个 describe 现在直接测它），业务侧仍然只认一套实现
 * （**没有**在 DownloadStore 留一层转发壳子）。
 *
 * 注意：`uniqueName` **没有**搬进来 —— 它要查「目录里是否已有同名文件」和「下载记录里是否已占用」，
 * 那是 IO + 状态，不是纯计算。它留在商店里，见 `DownloadStore.uniqueName`。
 */
export class Naming {
  /** 文件名长度上限：留出路径余量，别撞系统的文件名限制。 */
  private static readonly MAX_LENGTH: number = 120;

  /**
   * 把任意文本洗成一个可用作文件名的字符串。
   *
   * 三件事：非法字符换成 `_`、去掉首尾的点与空格（Windows / 部分文件系统会吃掉它们，
   * 也会让 `.hidden` 这类名字变成隐藏文件）、截断到 120 字；洗不出东西时用 `fallback`。
   */
  static clean(raw: string, fallback: string): string {
    let name: string = raw.trim().replace(new RegExp('[\\\\/:*?"<>|\\x00-\\x1f]', 'g'), '_');
    name = name.replace(new RegExp('^[. ]+|[. ]+$', 'g'), '');
    if (name.length > Naming.MAX_LENGTH) {
      name = name.substring(0, Naming.MAX_LENGTH);
    }
    return name.length > 0 ? name : fallback;
  }

  /**
   * 从一个图片地址推一个文件名。
   *
   * 取路径最后一段（先去 query / fragment）、按百分号解码；解不出来或解完为空就用网页描述，
   * 描述也没有就用「图片_序号」。后缀不在白名单里（形如 `noext`、`pic.tar.gz`）就补 `.jpg`，
   * 免得落盘的文件系统认不出类型。
   */
  static suggested(url: string, description: string, index: number): string {
    const path: string = url.split('?')[0].split('#')[0];
    let leaf: string = path.substring(path.lastIndexOf('/') + 1);
    try {
      leaf = decodeURIComponent(leaf);
    } catch (error) {
    }
    const fallback: string = Naming.clean(description, '图片_' + index.toString());
    leaf = Naming.clean(leaf, fallback);
    const extension: string = leaf.substring(leaf.lastIndexOf('.') + 1).toLowerCase();
    if (!MediaFormat.keepsExtension(extension)) {
      leaf += '.jpg';
    }
    return leaf;
  }

  /** 换掉最后一个扩展名（没有就补一个）。服务器返回的 Content-Type 比 URL 后缀更可信时用它。 */
  static withExtension(raw: string, extension: string): string {
    const clean: string = Naming.clean(raw, '图片');
    const dot: number = clean.lastIndexOf('.');
    const base: string = dot > 0 ? clean.substring(0, dot) : clean;
    return base + '.' + extension;
  }

  /** Content-Type → 扩展名；不是认识的图片类型就返回空串（调用方据此决定要不要改名）。 */
  static imageExtension(contentType: string): string {
    const mime: string = contentType.toLowerCase().split(';')[0].trim();
    if (mime === 'image/png') {
      return 'png';
    }
    if (mime === 'image/webp') {
      return 'webp';
    }
    if (mime === 'image/gif') {
      return 'gif';
    }
    if (mime === 'image/heic') {
      return 'heic';
    }
    if (mime === 'image/heif') {
      return 'heif';
    }
    if (mime === 'image/avif') {
      return 'avif';
    }
    if (mime === 'image/bmp') {
      return 'bmp';
    }
    if (mime === 'image/svg+xml') {
      return 'svg';
    }
    if (mime === 'image/tiff') {
      return 'tiff';
    }
    if (mime === 'image/jpeg' || mime === 'image/jpg') {
      return 'jpg';
    }
    return '';
  }
}
