import { PictureItem } from '../model/Models';
import { ImageCandidate } from './ImageCandidates';
import { MediaFormat } from './MediaFormat';
import { Naming } from './Naming';

/**
 * 扫描结果里一张图的最小形状。
 *
 * 单独声明而不是在 PageScanner 里定义，是为了让工厂不依赖扫描器：谁产出 `{url, description}`
 * 都能喂进来（网页 DOM、以后可能的其它来源）。扫描器的 `ScanData.images` 就是它的数组。
 *
 * `url` 是**页面当前显示的那张**（`PictureItem` 的身份键，也是失败时的兜底地址）；
 * `candidates` 是同一个 `<img>` 身上所有可能更大的地址，交给 `ScanUpgrader` 择优。
 * 为可选字段：直接粘地址进来的那条路径没有候选，也不该被迫造一个。
 */
export interface ScanImage {
  url: string;
  description: string;
  candidates?: ImageCandidate[];
  width?: number;
  height?: number;
  featured?: boolean;
  /** 实况照片的动态部分（微博等站点把静图与视频分开给）；没有就是普通图片。 */
  motion?: string;
}

/**
 * `PictureItem` 的构造与合并（**工厂方法** + **适配器**）。
 *
 * 两个来源（用户直接粘的图片地址、网页扫出来的一批图）本来各写了一段几乎一样的构造代码，
 * 都在 Index 里。现在统一在这里造，顺带把两条硬约束钉死：
 *
 * 1. `uid` 必须**在 `new` 之后**赋值，不能写进 `PictureItem` 的构造函数 —— `@Observed` 的实例
 *    是编译期包出来的代理，构造期自己写字段会绕开这层代理（真机实测：构造函数里赋 uid 的版本
 *    选中状态完全不刷新）。工厂方法天然满足这一点。
 * 2. 同一个 url 在多次扫描之间**复用旧实例**，所以选中态和用户改过的名字不会被下一次扫描冲掉。
 */
export class PictureFactory {
  /** 唯一身位号的自增源；只要求「同一批里不重复」，跨页面重复也无所谓。 */
  private static serial: number = 0;

  private static nextUid(): string {
    PictureFactory.serial++;
    return 'p' + PictureFactory.serial.toString();
  }

  /**
   * 地址栏里直接粘进来的单个文件：默认选中，让用户一点「下载」就能走。
   *
   * `kind` 由 `MediaFormat.mediaKindOf` 定：`.livp` / `.livephoto` 是实况照片包，
   * 下载层要按整包处理（不进 ZIP、下完解包），所以类型必须在这一步就带下去。
   */
  static fromUrl(url: string): PictureItem {
    const picture: PictureItem = new PictureItem();
    picture.uid = PictureFactory.nextUid();
    picture.id = url;
    picture.url = url;
    picture.selected = true;
    picture.name = Naming.suggested(url, '', 1);
    picture.kind = MediaFormat.mediaKindOf(url);
    return picture;
  }

  /** 扫描结果里的一张图；`index` 是它在页面里的序号，用来兜底生成文件名。 */
  static fromScan(image: ScanImage, index: number): PictureItem {
    const picture: PictureItem = new PictureItem();
    picture.uid = PictureFactory.nextUid();
    picture.id = image.url;
    picture.url = image.url;
    picture.description = image.description;
    picture.width = image.width ?? 0;
    picture.height = image.height ?? 0;
    picture.featured = image.featured === true;
    picture.name = Naming.suggested(image.url, image.description, index);
    if (image.motion !== undefined && image.motion.length > 0) {
      // 静图 + 视频的实况照片：下载层会打包成 .livp，名字和类型都要提前标好。
      picture.kind = 'livephoto';
      picture.motionUrl = image.motion;
      picture.name = Naming.withExtension(picture.name, 'livp');
    }
    return picture;
  }

  /**
   * 按 url 把新一轮扫描结果并进已有列表。
   *
   * 扫描是「按 url 合并」而不是整体替换：上一轮选中的图复用同一个实例，计数由调用方重算。
   * 这样刷新（右上角那颗刷新按钮）不会把用户已经勾好的选择清掉。
   */
  static merge(existing: PictureItem[], images: ScanImage[]): PictureItem[] {
    const found: Map<string, PictureItem> = new Map<string, PictureItem>();
    for (const old of existing) {
      found.set(old.url, old);
    }
    for (let i: number = 0; i < images.length; i++) {
      const image: ScanImage = images[i];
      if (found.has(image.url)) {
        const old: PictureItem = found.get(image.url)!;
        if ((image.width ?? 0) > 0 && (image.height ?? 0) > 0) {
          old.width = image.width ?? 0;
          old.height = image.height ?? 0;
        }
        old.featured = image.featured === true;
        if (image.motion !== undefined && image.motion.length > 0) {
          old.kind = 'livephoto';
          old.motionUrl = image.motion;
          if (!old.userNamed) { old.name = Naming.withExtension(old.name, 'livp'); }
        }
        continue;
      }
      found.set(image.url, PictureFactory.fromScan(image, i + 1));
    }
    return Array.from(found.values());
  }

  /** 只给当前列表中身份和地址都匹配的图片回填实际解码尺寸。 */
  static recordDimensions(items: PictureItem[], uid: string, url: string, width: number, height: number): boolean {
    if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) { return false; }
    const current: PictureItem | undefined = items.find((item: PictureItem): boolean => item.uid === uid && item.url === url);
    if (current === undefined) { return false; }
    if (current.width === width && current.height === height) { return true; }
    current.width = width;
    current.height = height;
    return true;
  }
}
