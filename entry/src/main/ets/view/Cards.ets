/*
 * Cards.ets — the prototype's data-bound components.
 *
 * Ported from designs/image-downloader-ui/ui.jsx, screen-tasks.jsx and
 * screen-library.jsx. Each struct binds to an @Observed model instance with
 * @ObjectLink so progress and selection update in place.
 */

import { fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { MovingPhotoView, MovingPhotoViewController, photoAccessHelper } from '@kit.MediaLibraryKit';
import { DownloadItem, PictureItem, ZipItem } from '../model/Models';
import { BatchView } from '../model/BatchView';
import { LivePhoto } from '../service/LivePhoto';
import { MediaFormat } from '../service/MediaFormat';
import { StillFrames } from '../service/StillFrames';
import {
  Font, formatBytes, formatMoment, kindOf, Palette, percentOf, Radius, Shadow, Space
} from '../theme/Tokens';
import { Glyph } from './Icons';
import { IconButton, PillButton, ProgressBar, StatusChip } from './Widgets';

/** Image with a type-badge fallback, mirroring the prototype's <Img>. */
@Component
export struct Thumb {
  /**
   * @Prop：预览页改名后路径会变，普通成员在 V1 下刷不进子组件（见 AGENT.md 坑 3）。
   * @Watch：**换 src 必须把 failed 复位**。任务页进预览时 src 先是远程地址
   * （那一张不带 Referer/Cookie，防盗链站会 onError），落盘后 src 换成沙箱文件 URI；
   * 不复位的话组件被复用、`failed` 粘在 true 上，大图永远停在那个「IMG」文字块上。
   */
  @Prop @Watch('onSourceChanged') src: string = '';
  @Prop label: string = 'IMG';
  /**
   * 非空时只画这个本地文件的**第 0 帧**。
   *
   * ArkUI 的 Image 会自己播放 GIF / WebP 动图，没有「只播首帧」的开关：图库里几十个格子
   * 同时动画既费电又晃眼。所以动图格子把解码好的首帧交给这里静态绘制（见 service/StillFrames）。
   */
  @Prop @Watch('onFirstFrameChanged') firstFramePath: string = '';
  /** 右下角角标（「动图」「实况」「GIF」…）；空串不画。 */
  @Prop badge: string = '';
  fit: ImageFit = ImageFit.Cover;

  @State private failed: boolean = false;
  @State private frame: image.PixelMap | undefined = undefined;

  aboutToAppear(): void {
    this.loadFrame();
  }

  private onSourceChanged(): void {
    this.failed = false;
  }

  private onFirstFrameChanged(): void {
    this.loadFrame();
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
      if (frame !== undefined && path === this.firstFramePath) {
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
      } else if (this.src.length > 0 && !this.failed) {
        Image(this.src)
          .width('100%')
          .height('100%')
          .objectFit(this.fit)
          .onError(() => {
            this.failed = true;
          })
      } else {
        Text(this.label)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.fontTertiary)
      }

      if (this.badge.length > 0) {
        // 右下角：左下角留给发现页的序号角标（见 SelectTile）。
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
        .alignItems(HorizontalAlign.End)
        .justifyContent(FlexAlign.End)
        .padding({ right: 5, bottom: 5 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.cardSunken)
  }
}

/** One selectable tile of the discover image grid. */
@Component
export struct SelectTile {
  @ObjectLink picture: PictureItem;
  index: number = 0;
  /**
   * 回调只传 **uid**，不把 `this.picture` 这个引用交出去。
   *
   * 这是真机实测踩出来的：父组件拿到子组件回传的引用后直接写 `selected`，**这次写会绕过
   * `@Observed` 代理** —— 值确实变了（父组件重算计数能看到），但 `@ObjectLink` 的通知不发，
   * 于是磁贴自己的已选蒙层「差一拍」：点一下取消勾选，勾还在（要等下一次别的写入才刷掉）。
   * 对比：父组件从自己的 `pictures` 里取出元素写（「全选 / 反选 / 清空」走的就是这条），蒙层会立刻刷新。
   *
   * 所以子组件只报「哪一个」（uid），由父组件回到自己的列表里再取一次那个引用去写。
   */
  onToggle: (uid: string) => void = () => {
  };

  /**
   * 发现页的角标：实况照片包写「实况」，GIF / WebP 写格式名。
   *
   * 这里只能读**远程地址的扩展名**（图片还没下载，拿不到字节），所以只说「这是 GIF」，
   * 不断言「它会动」—— 是否动图要下完读文件头才知道，图库那边标的才是「动图」。
   */
  private badge(): string {
    if (this.picture.kind === 'livephoto') {
      return '实况';
    }
    const extension: string = MediaFormat.extensionOf(this.picture.url);
    return MediaFormat.isAnimatedExt(extension) ? extension.toUpperCase() : '';
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Thumb({ src: this.picture.url, label: kindOf(this.picture.name), badge: this.badge() })

      // selection veil: a brand ring plus a wash
      if (this.picture.selected) {
        Row()
          .width('100%')
          .height('100%')
          .borderRadius(Radius.r4)
          .backgroundColor(Palette.brandSoft)
          .border({ width: 3, color: Palette.brand, radius: Radius.r4 })
      }

      if (this.picture.selected) {
        Stack({ alignContent: Alignment.Center }) {
          Glyph({ glyph: 'check', glyphSize: 13, glyphTone: Palette.white, glyphWeight: 2.6 })
        }
        .width(21)
        .height(21)
        .borderRadius(Radius.full)
        .backgroundColor(Palette.brand)
        .margin({ top: 5, left: 5 })
      }

      // the prototype's bottom-left index badge
      Column() {
        Text((this.index + 1) < 10 ? '0' + (this.index + 1).toString() : (this.index + 1).toString())
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
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.End)
      .padding({ left: 5, bottom: 5 })
    }
    .width('100%')
    .aspectRatio(1)
    .borderRadius(Radius.r4)
    .clip(true)
    .onClick(() => {
      this.onToggle(this.picture.uid);
    })
  }
}

/** One completed download in the gallery grid. */
@Component
export struct ShotTile {
  @ObjectLink image: DownloadItem;
  /** @Prop：密度是运行时切换的（标题栏那颗九宫格按钮），普通成员刷不进来。 */
  @Prop dense: boolean = false;
  onOpen: (image: DownloadItem) => void = () => {
  };

  /**
   * 画哪张图。
   *
   * 实况照片的记录里 `path` 是原始 `.livp` 包（Image 画不出来），封面要用解包出来的静图；
   * 解包失败时退回包名占位（Thumb 会显示「LIVP」文字块），至少不是一片空白。
   */
  private coverPath(): string {
    if (this.image.kind === 'livephoto' && this.image.stillPath.length > 0) {
      return this.image.stillPath;
    }
    return this.image.path;
  }

  /** 动图交给 Thumb 画首帧；实况照片的静图本身是静态的，不需要。 */
  private firstFramePath(): string {
    if (this.image.kind === 'livephoto' || !this.image.animated) {
      return '';
    }
    return this.image.path;
  }

  private badge(): string {
    if (this.image.kind === 'livephoto') {
      return '实况';
    }
    return this.image.animated ? '动图' : '';
  }

  build() {
    Column({ space: Space.s4 }) {
      Stack() {
        Thumb({
          src: fileUri.getUriFromPath(this.coverPath()),
          label: kindOf(this.image.name),
          firstFramePath: this.firstFramePath(),
          badge: this.badge()
        })
        Row()
          .width('100%')
          .height('100%')
          .borderRadius(Radius.r6)
          .border({ width: 1, color: Palette.divider, radius: Radius.r6 })
      }
      .width('100%')
      .aspectRatio(1)
      .borderRadius(Radius.r6)
      .clip(true)
      .onClick(() => {
        this.onOpen(this.image);
      })

      Column({ space: 1 }) {
        Text(this.image.name)
          .fontSize(this.dense ? 11 : Font.aux)
          .lineHeight(this.dense ? 15 : Font.auxLine)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.fontPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (!this.dense) {
          Text(formatBytes(this.image.size) + ' · ' + formatMoment(this.image.finishedAt, Date.now()))
            .fontSize(11)
            .lineHeight(16)
            .fontColor(Palette.fontTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: Space.s2, right: Space.s2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/** One single (non-batch) download task. */
@Component
export struct TaskCard {
  @ObjectLink task: DownloadItem;
  onCancel: (task: DownloadItem) => void = () => {
  };
  onRetry: (task: DownloadItem) => void = () => {
  };
  onLocate: (task: DownloadItem) => void = () => {
  };
  /**
   * 点缩略图看大图。
   *
   * 任务页不再提供改名入口（`onRename` 已删）：这里是下载队列，改名归图库 ——
   * 大图页从任务进来时也不显示「重命名」。
   */
  onOpen: (task: DownloadItem) => void = () => {
  };

  private isActive(): boolean {
    return this.task.status === 'queued' || this.task.status === 'starting'
      || this.task.status === 'running' || this.task.status === 'packing';
  }

  private isSettled(): boolean {
    return this.task.status === 'completed' || this.task.status === 'failed' || this.task.status === 'cancelled';
  }

  private meta(): string {
    if (this.task.status === 'running') {
      return formatBytes(this.task.processed) + ' / ' + formatBytes(this.task.total)
        + ' · ' + percentOf(this.task.processed, this.task.total).toString() + '%';
    }
    if (this.task.status === 'queued') {
      return '等待并发空位 · ' + formatBytes(this.task.total);
    }
    if (this.task.status === 'starting') {
      return '正在建立连接 · ' + formatBytes(this.task.total);
    }
    if (this.task.status === 'completed') {
      return '已保存 · ' + formatBytes(this.task.size);
    }
    if (this.task.status === 'cancelled') {
      return '已取消';
    }
    return '';
  }

  build() {
    Column() {
      Row({ space: Space.s12 }) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Thumb({ src: this.task.url, label: kindOf(this.task.name) })

          Text(kindOf(this.task.name))
            .fontSize(9)
            .lineHeight(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(Palette.white)
            .backgroundColor('#8C000000')
            .borderRadius(4)
            .padding({ left: 4, right: 4 })
            .margin({ right: 3, bottom: 3 })
        }
        .width(52)
        .height(52)
        .borderRadius(Radius.r6)
        .clip(true)
        .onClick(() => {
          this.onOpen(this.task);
        })

        Column({ space: Space.s6 }) {
          Row({ space: Space.s8 }) {
            Text(this.task.name)
              .fontSize(Font.body)
              .lineHeight(Font.bodyLine)
              .fontWeight(FontWeight.Medium)
              .fontColor(Palette.fontPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            StatusChip({ status: this.task.status })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.isActive() && this.task.total > 0) {
            ProgressBar({ value: percentOf(this.task.processed, this.task.total) })
          }

          if (this.meta().length > 0 || this.task.error.length > 0) {
            Row({ space: Space.s8 }) {
              if (this.meta().length > 0) {
                Text(this.meta())
                  .fontSize(Font.caption)
                  .lineHeight(Font.captionLine)
                  .fontColor(Palette.fontTertiary)
              }
              if (this.meta().length > 0 && this.task.error.length > 0) {
                Text('·')
                  .fontSize(Font.caption)
                  .fontColor(Palette.fontTertiary)
              }
              if (this.task.error.length > 0) {
                Text(this.task.error)
                  .fontSize(Font.caption)
                  .lineHeight(Font.captionLine)
                  .fontColor(Palette.warning)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
            }
            .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row({ space: Space.s2 }) {
          if (this.isActive()) {
            IconButton({
              glyph: 'close', glyphSize: 18, diameter: 34, plain: true,
              onAction: () => {
                this.onCancel(this.task);
              }
            })
          }
          if (this.task.status === 'failed' || this.task.status === 'cancelled') {
            IconButton({
              glyph: 'retry', glyphSize: 18, diameter: 34, plain: true,
              onAction: () => {
                this.onRetry(this.task);
              }
            })
          }
          if (this.task.status === 'completed') {
            IconButton({
              glyph: 'chevronRight', glyphSize: 18, diameter: 34, plain: true,
              onAction: () => {
                this.onLocate(this.task);
              }
            })
          }
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding(Space.s12)
    }
    .width('100%')
    .borderRadius(Radius.r8)
    .backgroundColor(Palette.card)
    .shadow(Shadow.card())
  }
}


/** The ZIP batch in flight, with its stacked member preview. */
@Component
export struct BatchCard {
  /**
   * @Prop：批次进度（done / failed / status）是运行时变的，普通成员在 V1 下刷不进来。
   * 之前只是「碰巧」能更新 —— 外层 ForEach 的 key 里带了 done/failed，数字一变就整卡重建。
   */
  @Prop view: BatchView = new BatchView();
  onRetry: (view: BatchView) => void = () => {
  };
  onDismiss: (view: BatchView) => void = () => {
  };
  /**
   * 点这摞缩略图看大图，入口规则和单任务卡一致（`openViewer(..., false)`：不给改名）。
   *
   * 打包卡只会出现在「还在下载 / 打包失败」这两种状态 —— 打成功的批次已经变成压缩包、
   * 从任务页消失了，那时成员图也已被删除。所以这里总是能取到至少一个成员。
   */
  onOpen: (view: BatchView) => void = () => {
  };

  /** A failed batch explains itself instead of showing a progress line. */
  private failed(): boolean {
    return this.view.status === 'failed' && this.view.error.length > 0;
  }

  private meta(): string {
    if (this.failed()) {
      return this.view.error;
    }
    if (this.view.status === 'packing') {
      return '正在压缩为 ZIP…';
    }
    return '正在下载 · ' + this.view.done.toString() + '/' + this.view.total.toString() + ' 张';
  }

  build() {
    Column({ space: Space.s10 }) {
      Row({ space: Space.s12 }) {
        Stack({ alignContent: Alignment.TopStart }) {
          ForEach(this.view.thumbs, (thumb: string, index: number) => {
            Stack() {
              Thumb({ src: thumb })
            }
            .width(42)
            .height(42)
            .borderRadius(Radius.r4)
            .clip(true)
            .border({ width: 1.5, color: Palette.card, radius: Radius.r4 })
            .offset({ x: index * 7, y: index * 7 })
          }, (thumb: string, index: number) => thumb + index.toString())

          Text(this.view.total.toString())
            .fontSize(11)
            .lineHeight(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Palette.white)
            .textAlign(TextAlign.Center)
            .constraintSize({ minWidth: 22 })
            .height(22)
            .padding({ left: 5, right: 5 })
            .borderRadius(Radius.full)
            .backgroundColor(Palette.brand)
            .border({ width: 2, color: Palette.card, radius: Radius.full })
            .offset({ x: 42, y: 40 })
        }
        .width(56)
        .height(56)
        .onClick(() => {
          this.onOpen(this.view);
        })

        Column({ space: Space.s6 }) {
          Row({ space: Space.s8 }) {
            Text(this.view.name)
              .fontSize(Font.body)
              .lineHeight(Font.bodyLine)
              .fontWeight(FontWeight.Medium)
              .fontColor(Palette.fontPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            StatusChip({ status: this.view.status })
          }
          .width('100%')

          Row({ space: Space.s8 }) {
            Text(this.meta())
              .fontSize(Font.caption)
              .lineHeight(Font.captionLine)
              .fontColor(this.failed() ? Palette.warning : Palette.fontTertiary)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.view.failed > 0 && !this.failed()) {
              Text('·')
                .fontSize(Font.caption)
                .fontColor(Palette.fontTertiary)
              Text(this.view.failed.toString() + ' 张失败')
                .fontSize(Font.caption)
                .lineHeight(Font.captionLine)
                .fontColor(Palette.warning)
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // A failed batch is the only dead end in this list, so it carries its
        // own way out: retry the whole batch, or dissolve it and let its
        // images fall back to the task list.
        if (this.view.status === 'failed') {
          Row({ space: Space.s2 }) {
            IconButton({
              glyph: 'retry', glyphSize: 18, diameter: 34, plain: true,
              onAction: () => {
                this.onRetry(this.view);
              }
            })
            IconButton({
              glyph: 'close', glyphSize: 18, diameter: 34, plain: true,
              onAction: () => {
                this.onDismiss(this.view);
              }
            })
          }
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.view.status !== 'failed') {
        ProgressBar({
          value: this.view.status === 'packing' ? 96 : Math.round((this.view.done / Math.max(1, this.view.total)) * 100),
          striped: this.view.status === 'packing'
        })
      }
    }
    .width('100%')
    .padding(Space.s12)
    .borderRadius(Radius.r8)
    .backgroundColor(Palette.card)
    .shadow(Shadow.card())
  }
}

/** Stacked preview of an archive's members. */
@Component
export struct ArchiveStack {
  thumbs: string[] = [];

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.thumbs, (thumb: string, index: number) => {
        Stack() {
          Thumb({ src: thumb })
        }
        .width(42)
        .height(42)
        .borderRadius(Radius.r4)
        .clip(true)
        .border({ width: 1.5, color: Palette.card, radius: Radius.r4 })
        .offset({ x: index * 7, y: index * 7 })
      }, (thumb: string, index: number) => thumb + index.toString())

      if (this.thumbs.length === 0) {
        Stack() {
          Glyph({ glyph: 'archive', glyphSize: 20, glyphTone: Palette.fontTertiary, glyphWeight: 1.7 })
        }
        .width(42)
        .height(42)
        .borderRadius(Radius.r4)
        .backgroundColor(Palette.cardSunken)
      }
    }
    .width(56)
    .height(56)
  }
}

/** One ZIP archive. */
@Component
export struct ArchiveCard {
  @ObjectLink zip: ZipItem;
  onRename: (zip: ZipItem) => void = () => {
  };
  onExport: (zip: ZipItem) => void = () => {
  };
  onShare: (zip: ZipItem) => void = () => {
  };
  onDelete: (zip: ZipItem) => void = () => {
  };

  build() {
    Column() {
      Row({ space: Space.s12 }) {
        ArchiveStack({ thumbs: this.zip.thumbs })

        Column({ space: Space.s2 }) {
          Text(this.zip.name)
            .fontSize(16)
            .lineHeight(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Palette.fontPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.zip.imageCount.toString() + ' 张图片 · ' + formatBytes(this.zip.size))
            .fontSize(Font.aux)
            .lineHeight(Font.auxLine)
            .fontColor(Palette.fontSecondary)
          Row({ space: Space.s4 }) {
            Text(formatMoment(this.zip.createdAt, Date.now()))
              .fontSize(Font.aux)
              .lineHeight(Font.auxLine)
              .fontColor(Palette.fontSecondary)
            if (this.zip.failedCount > 0) {
              Text('· ' + this.zip.failedCount.toString() + ' 张下载失败未打包')
                .fontSize(Font.aux)
                .lineHeight(Font.auxLine)
                .fontColor(Palette.warning)
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row({ space: Space.s4 }) {
        PillButton({
          label: '重命名', variant: 'ghost', icon: 'pencil', small: true,
          onAction: () => {
            this.onRename(this.zip);
          }
        })
        PillButton({
          label: '导出', variant: 'ghost', icon: 'export', small: true,
          onAction: () => {
            this.onExport(this.zip);
          }
        })
        PillButton({
          label: '分享', variant: 'ghost', icon: 'share', small: true,
          onAction: () => {
            this.onShare(this.zip);
          }
        })
        Blank()
        IconButton({
          glyph: 'trash', glyphSize: 18, diameter: 34, plain: true, tone: Palette.warning,
          onAction: () => {
            this.onDelete(this.zip);
          }
        })
      }
      .width('100%')
      .margin({ top: Space.s12 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Space.s12)
    .borderRadius(Radius.r8)
    .backgroundColor(Palette.card)
    .shadow(Shadow.card())
  }
}

/**
 * 大图预览里「一页」需要的全部内容。
 *
 * 由预览页（pages/Viewer.ets）按当前要看的图片列表算好：`src` 是本地文件 URI 或远程地址，
 * `label` 是取不到图时兜底的类型角标。组件只负责画，不自己去商店取记录 ——
 * 这样翻页只换数据，不和下载队列的状态纠缠。
 */
export interface ViewerSlide {
  /** 下载记录 id，同时当 ForEach 的 key。 */
  id: string;
  src: string;
  name: string;
  label: string;
  /** 实况照片解出来的静图沙箱路径；普通图片是空串。 */
  stillPath: string;
  /** 实况照片解出来的视频沙箱路径；普通图片是空串。 */
  motionPath: string;
}

/**
 * 实况照片的一页：优先用系统的动态照片组件播放，装不起来就退回收到的静图。
 *
 * **为什么由组件自己加载**：`photoAccessHelper.MovingPhoto` 是原生句柄，既不能用 @Prop
 * 传（对象类型会走深拷贝，句柄会被拷坏），也不能靠普通成员刷新（V1 不把新值刷进无装饰器
 * 成员，见 AGENT.md 坑 3）。而这一页的数据（`stillFile` / `motionFile`）是 @Prop、随列表刷新变，
 * 组件按 ForEach 的 key 重建，加载一次就够。
 *
 * 失败不是错误：MOV/HEVC 能不能解，取决于设备解码器；能看的封面图一定会画出来。
 */
@Component
export struct LivePhotoSlide {
  /** 沙箱路径，不是 URI：`LivePhoto.load` 只认路径（见 service/LivePhoto.ets）。
   *  名字避开 `motionPath` —— 那是 ArkUI 通用属性（路径动画），会报成员冲突。 */
  @Prop stillFile: string = '';
  @Prop motionFile: string = '';
  @State private movingPhoto: photoAccessHelper.MovingPhoto | undefined = undefined;
  /** 动态部分装不起来时的那句说明；空串不显示。 */
  @State private problem: string = '';
  /**
   * 播放控制器。
   *
   * 不能只靠 `.autoPlay(true)`：真机（PLR-AL00，HarmonyOS 7）实测它不会自己开播，
   * 画面停在封面上，用户以为这是个静态图。资源准备好之后显式 `startPlayback()`
   * 才真的动起来；点一下画面也能重新播放。
   */
  private controller: MovingPhotoViewController = new MovingPhotoViewController();

  aboutToAppear(): void {
    const still: string = this.stillFile;
    const motion: string = this.motionFile;
    if (still.length === 0 || motion.length === 0) {
      this.problem = '这个实况照片包没有解出静图与视频';
      return;
    }
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    LivePhoto.load(context, still, motion)
      .then((moving: photoAccessHelper.MovingPhoto | undefined): void => {
        if (moving !== undefined) {
          this.movingPhoto = moving;
          return;
        }
        this.problem = '本机无法播放这段实况视频，已显示封面图';
      });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.movingPhoto !== undefined) {
        MovingPhotoView({ movingPhoto: this.movingPhoto, controller: this.controller })
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .muted(false)
          .autoPlay(true)
          .repeatPlay(true)
          .onPrepared((): void => {
            this.controller.startPlayback();
          })
          .onError((): void => {
            this.problem = '本机无法播放这段实况视频，已显示封面图';
          })
          .onClick((): void => {
            this.controller.startPlayback();
          })
      } else {
        Thumb({ src: fileUri.getUriFromPath(this.stillFile), fit: ImageFit.Contain })
      }

      if (this.problem.length > 0) {
        Column() {
          Text(this.problem)
            .fontSize(Font.aux)
            .lineHeight(Font.auxLine)
            .fontColor('#B3FFFFFF')
            .textAlign(TextAlign.Center)
            .padding({ left: Space.s12, right: Space.s12, top: Space.s6, bottom: Space.s6 })
            .borderRadius(Radius.r8)
            .backgroundColor('#66000000')
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.End)
        .padding({ left: Space.s16, right: Space.s16, bottom: Space.s16 })
      }
    }
    .width('100%')
    .height('100%')
  }
}

/**
 * Full-screen image preview with its action bar.
 *
 * 由独立的预览页（pages/Viewer.ets）使用：**不要在 Index 里当浮层用** —— 那样系统返回键
 * 会直接退出应用（页面栈里只有 Index），需求就是为此改成推一个新页面。
 *
 * `slides` / `index` 用 @Link：左右滑动由中间的 Swiper 驱动 index，预览页据此换标题、
 * 提示与文件操作的目标；列表本身也会随商店刷新（改名、删除）而变，所以两边都要联动。
 * `hint` / `renameAllowed` / `actionable` 仍是 @Prop（见 AGENT.md 坑 3）。
 */
@Component
export struct ImageViewer {
  /** 可以左右滑的那一批图；只有一张时就是普通大图。 */
  @Link slides: ViewerSlide[];
  /** 当前是第几张，滑动手势会写回来。 */
  @Link index: number;
  /** 改名只在图库里开放；从任务页进来的预览不显示这一项。 */
  @Prop renameAllowed: boolean = true;
  /** 文件还没落盘（任务还在下载 / 已失败）时只放大图，不给文件操作。 */
  @Prop actionable: boolean = true;
  /** 操作区被收起时的解释文案；空则不显示。 */
  @Prop hint: string = '';
  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;
  onClose: () => void = () => {
  };
  onRename: () => void = () => {
  };
  onSaveToGallery: () => void = () => {
  };
  onShare: () => void = () => {
  };
  onExport: () => void = () => {
  };
  onDelete: () => void = () => {
  };

  /** 当前这一页；列表为空或索引越界时返回 undefined（调用处用 ?? 兜底）。 */
  private current(): ViewerSlide | undefined {
    if (this.index < 0 || this.index >= this.slides.length) {
      return undefined;
    }
    return this.slides[this.index];
  }

  /** 头部的「第几张 / 共几张」；只有一张时不占位置。 */
  private slideCounter(): string {
    if (this.slides.length <= 1) {
      return '';
    }
    return (this.index + 1).toString() + ' / ' + this.slides.length.toString();
  }

  @Builder
  private action(glyph: string, label: string, danger: boolean, act: () => void): void {
    Column({ space: Space.s6 }) {
      Glyph({
        glyph: glyph,
        glyphSize: 21,
        glyphTone: danger ? '#F2826E' : '#E6FFFFFF',
        glyphWeight: 1.7
      })
      Text(label)
        .fontSize(11)
        .fontColor(danger ? '#F2826E' : '#E6FFFFFF')
    }
    .padding({ left: Space.s10, right: Space.s10, top: Space.s6, bottom: Space.s6 })
    .borderRadius(Radius.r6)
    .onClick(() => {
      act();
    })
  }

  build() {
    Column() {
      Row({ space: Space.s4 }) {
        Text(this.current()?.name ?? '')
          .fontSize(Font.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.white)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.slideCounter().length > 0) {
          Text(this.slideCounter())
            .fontSize(Font.aux)
            .lineHeight(Font.auxLine)
            .fontColor('#B3FFFFFF')
            .margin({ right: Space.s4 })
        }
        IconButton({
          glyph: 'close', glyphSize: 20, diameter: 34, plain: true, tone: Palette.white,
          onAction: () => {
            this.onClose();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: Space.s16, right: Space.s16, top: this.safeTop + Space.s16, bottom: Space.s8 })

      Stack({ alignContent: Alignment.Center }) {
        // Swiper 负责左右滑动换图：slide 的增减只换 ForEach 的 key，Swiper 自身不会被重建。
        // `.index()` 受 index 驱动，用户滑完 onChange 把值写回，两边始终一致。
        Swiper() {
          ForEach(this.slides, (slide: ViewerSlide) => {
            Stack({ alignContent: Alignment.Center }) {
              if (slide.stillPath.length > 0 && slide.motionPath.length > 0) {
                // 实况照片：这一页自己装动态照片并播放，装不起来就画静图。
                LivePhotoSlide({ stillFile: slide.stillPath, motionFile: slide.motionPath })
              } else {
                Thumb({ src: slide.src, label: slide.label, fit: ImageFit.Contain })
              }
            }
            .width('100%')
            .height('100%')
          }, (slide: ViewerSlide) => slide.id)
        }
        .width('100%')
        .height('100%')
        .index(this.index)
        .loop(false)
        // 点状指示器会在图片下缘压一行小点；张数改在头部用「3 / 12」说明。
        .indicator(false)
        .cachedCount(1)
        .onChange((value: number): void => {
          this.index = value;
        })
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: Space.s16, right: Space.s16 })

      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(Font.aux)
          .lineHeight(Font.auxLine)
          .fontColor('#B3FFFFFF')
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ left: Space.s24, right: Space.s24, top: Space.s10 })
      }

      if (this.actionable) {
        Row() {
          if (this.renameAllowed) {
            this.action('pencil', '重命名', false, this.onRename)
          }
          this.action('download', '存相册', false, this.onSaveToGallery)
          this.action('share', '分享', false, this.onShare)
          this.action('export', '导出', false, this.onExport)
          this.action('trash', '删除', true, this.onDelete)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceAround)
        .padding({ top: Space.s10, bottom: this.safeBottom + Space.s16 })
      } else {
        Column()
          .height(this.safeBottom + Space.s16)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.viewerBg)
    .backdropBlur(30)
  }
}
