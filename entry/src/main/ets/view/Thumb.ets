import { image } from '@kit.ImageKit';
import { StillFrames } from '../service/StillFrames';
import { ThumbnailImages, ThumbnailRequest } from '../service/ThumbnailImages';
import { Palette, Radius, Space } from '../theme/Tokens';

/** Image with a type-badge fallback, mirroring the prototype's <Img>. */
@ComponentV2
export struct Thumb {
  /**
   * @Param：预览页改名后路径会变，裸成员在 V2 里既传不进来也不刷新。
   * @Monitor（V2 的 @Watch，注意它装饰的是**处理方法**、监听 `src`）：**换 src 必须把 failed 复位**。
   * 任务页进预览时 src 先是远程地址（那一张不带 Referer/Cookie，防盗链站会 onError），
   * 落盘后 src 换成沙箱文件 URI；不复位的话组件被复用、`failed` 粘在 true 上，
   * 大图永远停在那个「IMG」文字块上。
   */
  @Param src: string = '';
  @Param label: string = 'IMG';
  /** 远程缩略图被站点拒绝时显示明确状态，原文件仍可下载。 */
  @Param fallbackText: string = '';
  /**
   * 非空时只画这个本地文件的**第 0 帧**。
   *
   * ArkUI 的 Image 会自己播放 GIF / WebP 动图，没有「只播首帧」的开关：图库里几十个格子
   * 同时动画既费电又晃眼。所以动图格子把解码好的首帧交给这里静态绘制（见 service/StillFrames）。
   */
  @Param firstFramePath: string = '';
  /** 类型角标（「动图」「实况」「GIF」…）；空串不画。 */
  @Param badge: string = '';
  /** 图库将类型角标放在左上角，其他缩略图保持原位置。 */
  @Param badgeTopLeft: boolean = false;
  @Param fit: ImageFit = ImageFit.Cover;
  @Local private thumbnail: string = '';
  private generation: number = 0;
  private alive: boolean = false;
  private aspect: number = 1;
  private request: ThumbnailRequest | undefined = undefined;

  @Local private failed: boolean = false;
  @Local private sourceFailed: boolean = false;
  @Local private frame: image.PixelMap | undefined = undefined;

  aboutToAppear(): void {
    this.alive = true;
    this.loadFrame();
    this.loadThumbnail();
  }

  aboutToDisappear(): void { this.alive = false; this.generation++; this.request?.cancel(); }

  @Monitor('src', 'fit')
  private onSourceChanged(monitor: IMonitor): void { this.loadThumbnail(); }

  private async loadThumbnail(): Promise<void> {
    this.request?.cancel();
    const request: ThumbnailRequest = new ThumbnailRequest();
    this.request = request;
    const token: number = ++this.generation;
    this.failed = false;
    this.sourceFailed = false;
    this.thumbnail = '';
    if (this.firstFramePath.length > 0) { return; }
    const cacheDir: string = this.getUIContext().getHostContext()?.cacheDir ?? '';
    const uri: string = await ThumbnailImages.load(this.src, cacheDir, this.aspect, this.fit === ImageFit.Contain, request);
    if (!this.alive || token !== this.generation) { return; }
    this.thumbnail = uri;
    this.failed = uri.length === 0;
  }

  @Monitor('firstFramePath')
  private onFirstFrameChanged(monitor: IMonitor): void {
    this.loadFrame();
    this.loadThumbnail();
  }

  /**
   * 取首帧：命中缓存就直接画，否则异步解码一次。
   *
   * 解码回来时**再确认一次路径没变**：网格滚动会复用组件，晚到的结果不能画到别的图上。
   */
  private loadFrame(): void {
    if (this.firstFramePath.length === 0) {
      this.frame = undefined;
      return;
    }
    const cached: image.PixelMap | undefined = StillFrames.cachedFrame(this.firstFramePath);
    if (cached !== undefined) {
      this.frame = cached;
      return;
    }
    const path: string = this.firstFramePath;
    StillFrames.stillFrame(path).then((frame: image.PixelMap | undefined): void => {
      if (this.alive && frame !== undefined && path === this.firstFramePath) {
        this.frame = frame;
      }
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.frame !== undefined) {
        Image(this.frame)
          .width('100%')
          .height('100%')
          .objectFit(this.fit)
      } else if (this.thumbnail.length > 0 && !this.failed) {
        Image(this.thumbnail)
          .width('100%')
          .height('100%')
          .objectFit(this.fit)
          .onError(() => {
            this.failed = true;
          })
      } else if (this.src.startsWith('file://') && !this.sourceFailed && this.firstFramePath.length === 0) {
        // Show a bounded decode immediately while the cropped grid thumbnail is prepared.
        Image(this.src)
          .width('100%')
          .height('100%')
          .sourceSize({ width: 512, height: 512 })
          .objectFit(this.fit)
          .onError(() => {
            this.sourceFailed = true;
          })
      } else {
        Text(this.fallbackText.length > 0 ? this.fallbackText : this.label)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.fontTertiary)
      }

      if (this.badge.length > 0) {
        Column() {
          Text(this.badge)
            .fontSize(10)
            .lineHeight(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Palette.white)
            .height(17)
            .padding({ left: Space.s6, right: Space.s6 })
            .borderRadius(Radius.full)
            .backgroundColor('#6B000000')
        }
        .width('100%')
        .height('100%')
        .alignItems(this.badgeTopLeft ? HorizontalAlign.Start : HorizontalAlign.End)
        .justifyContent(this.badgeTopLeft ? FlexAlign.Start : FlexAlign.End)
        .padding(this.badgeTopLeft ? { left: 5, top: 5 } : { right: 5, bottom: 5 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.cardSunken)
    .onSizeChange((oldSize: SizeOptions, newSize: SizeOptions): void => {
      const width: number = Number(newSize.width);
      const height: number = Number(newSize.height);
      if (width > 0 && height > 0 && Math.abs(width / height - this.aspect) > 0.02) {
        this.aspect = width / height;
        this.loadThumbnail();
      }
    })
  }
}
