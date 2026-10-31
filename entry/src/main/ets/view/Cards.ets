import { PreviewOverlayState } from '../model/PreviewOverlayState';
/*
 * Cards.ets — the prototype's data-bound components.
 *
 * Ported from designs/image-downloader-ui/ui.jsx, screen-tasks.jsx and
 * screen-library.jsx. Components receive ArkUI V2 state and event callbacks;
 * screen ViewModels own queue actions and local thumbnail selection.
 */

import { fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { MovingPhotoView, MovingPhotoViewController, photoAccessHelper } from '@kit.MediaLibraryKit';
import { DownloadItem, PictureItem, ZipItem } from '../model/Models';
import { BatchView } from '../model/BatchView';
import { LivePhoto } from '../service/LivePhoto';
import { MediaFormat } from '../service/MediaFormat';
import { SheetStyle } from '../theme/SheetStyle';
import {
  Font, formatBytes, formatMoment, kindOf, Palette, percentOf, Radius, Shadow, Space
} from '../theme/Tokens';
import { Glyph } from './Icons';
import { IconButton, PillButton, ProgressBar, StatusChip } from './Widgets';
import { Thumb } from './Thumb';
import { AnimatedPreviewImage, AnimationDockActions, AnimationToolbarAction, ZoomablePreviewImage } from './ImageSurface';
import { PreviewStrip, PreviewThumbnail } from './PreviewStrip';
import { PreviewAsset, ViewerSlide } from '../model/PreviewAsset';
import { PreviewTools } from './PreviewTools';
import { PreviewCompare } from './PreviewCompare';
import { PreviewChrome, PreviewHeader } from './PreviewChrome';
export { Thumb } from './Thumb';
export { AnimatedPreviewImage, ZoomablePreviewImage, LocalPreviewImage } from './ImageSurface';
export { PreviewStrip, PreviewThumbnail } from './PreviewStrip';

/** One selectable tile of the discover image grid. */
@ComponentV2
export struct SelectTile {
  @Require @Param picture: PictureItem;
  @Param index: number = 0;
  /** 图片点击进入预览；角上的选择按钮由父组件处理。 */
  @Event onOpen: (uid: string) => void = () => {
  };
  @Event onDimensions: (url: string, width: number, height: number) => void =
    (url: string, width: number, height: number): void => {};

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
    if (MediaFormat.isLivepicStill(this.picture.url)) {
      return '实况静图';
    }
    const extension: string = MediaFormat.extensionOf(this.picture.url);
    return MediaFormat.isAnimatedExt(extension) ? extension.toUpperCase() : '';
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Thumb({ src: this.picture.url, label: kindOf(this.picture.name), badge: this.badge(),
        fallbackText: '预览不可用',
        onDimensions: (url: string, width: number, height: number): void => {
          this.onDimensions(url, width, height);
        } })

      // 图片网格不在系统材质生效区域，选择反馈使用普通静态蒙层。
      if (this.picture.selected) {
        Row().width('100%').height('100%').borderRadius(Radius.r4)
          .backgroundColor(Palette.brandSoft)
      }

      // the prototype's bottom-left index badge
      Row() {
        Text(this.picture.width > 0 && this.picture.height > 0
          ? this.picture.width.toString() + '×' + this.picture.height.toString() : '尺寸未知')
          .fontSize(9)
          .fontColor(Palette.white)
          .backgroundColor('#8C000000')
          .borderRadius(4)
          .padding({ left: 3, right: 3 })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ top: 5, right: 5 })

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
      this.onOpen(this.picture.uid);
    })
  }
}

/** One completed download in the gallery grid. */
@ComponentV2
export struct ShotTile {
  @Require @Param image: DownloadItem;
  @Param favorite: boolean = false;
  @Param tags: string[] = [];
  @Param snippet: string = '';
  /** @Prop：密度是运行时切换的（标题栏那颗九宫格按钮），普通成员刷不进来。 */
  @Param dense: boolean = false;
  @Param selecting: boolean = false;
  @Param selected: boolean = false;
  @Event onOpen: (image: DownloadItem) => void = () => {
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
    if (MediaFormat.isLivepicStill(this.image.url)) {
      return '实况静图';
    }
    if (this.image.animated) { return '动图'; }
    return this.image.hdr ? 'HDR' : '';
  }

  build() {
    Column({ space: Space.s4 }) {
      Stack() {
        Thumb({
          src: fileUri.getUriFromPath(this.coverPath()),
          label: kindOf(this.image.name),
          firstFramePath: this.firstFramePath(),
          badge: this.badge(),
          badgeTopLeft: true
        })
        Row()
          .width('100%')
          .height('100%')
          .borderRadius(Radius.r6)
          .border({ width: 1, color: Palette.divider, radius: Radius.r6 })
        if (this.selecting) {
          Column() {
            Stack() {
              Glyph({ glyph: this.selected ? 'checkCircle' : 'circle', glyphSize: 20,
                glyphTone: this.selected ? Palette.brand : Palette.fontPrimary })
            }
            .width(28).height(28)
            .backgroundColor(Palette.card)
            .borderRadius(Radius.full)
          }
          .width('100%').height('100%')
          .alignItems(HorizontalAlign.End)
          .justifyContent(FlexAlign.End)
          .padding({ right: Space.s6, bottom: Space.s6 })
        }
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
        if (this.favorite || this.tags.length > 0) {
          Row({ space: Space.s4 }) {
            if (this.favorite) {
              Glyph({ glyph: 'bookmarkFill', glyphSize: 12,
                glyphTone: Palette.brand, glyphWeight: 1.5 })
            }
            Text(this.tags.slice(0, 2).join(' · '))
              .fontSize(11).fontColor(Palette.fontSecondary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        if (this.snippet.length > 0) {
          Text(this.snippet).fontSize(11).fontColor(Palette.fontSecondary)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
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
@ComponentV2
export struct TaskCard {
  @Require @Param task: DownloadItem;
  @Param thumbnailSource: string = '';
  @Param firstFramePath: string = '';
  @Event onRetryDelivery: (task: DownloadItem) => void = () => {};
  @Event onPause: (task: DownloadItem) => void = () => {
  };
  @Event onResume: (task: DownloadItem) => void = () => {
  };
  @Event onCancel: (task: DownloadItem) => void = () => {
  };
  @Event onRetry: (task: DownloadItem) => void = () => {
  };
  @Event onLocate: (task: DownloadItem) => void = () => {
  };
  /**
   * 点缩略图看大图。
   *
   * 任务页不再提供改名入口（`onRename` 已删）：这里是下载队列，改名归图库 ——
   * 大图页从任务进来时也不显示「重命名」。
   */
  @Event onOpen: (task: DownloadItem) => void = () => {
  };

  private isActive(): boolean {
    return this.task.status === 'queued' || this.task.status === 'starting'
      || this.task.status === 'running' || this.task.status === 'waiting' || this.task.status === 'paused'
      || this.task.status === 'packing';
  }

  private isSettled(): boolean {
    return this.task.status === 'completed' || this.task.status === 'failed' || this.task.status === 'cancelled';
  }

  private meta(): string {
    if (this.task.status === 'running') {
      let label: string = formatBytes(this.task.processed) + ' / ' + formatBytes(this.task.total)
        + ' · ' + percentOf(this.task.processed, this.task.total).toString() + '%';
      if (this.task.speedBps > 0 && this.task.etaSeconds > 0) {
        const remaining: string = this.task.etaSeconds < 60
          ? this.task.etaSeconds.toString() + ' 秒'
          : Math.ceil(this.task.etaSeconds / 60).toString() + ' 分钟';
        label += ' · ' + formatBytes(this.task.speedBps) + '/秒 · 约 ' + remaining;
      }
      return label;
    }
    if (this.task.status === 'queued') {
      return '等待并发空位 · ' + formatBytes(this.task.total);
    }
    if (this.task.status === 'starting') {
      return '正在建立连接 · ' + formatBytes(this.task.total);
    }
    if (this.task.status === 'waiting') {
      return '等待网络或系统资源 · ' + formatBytes(this.task.processed) + ' / ' + formatBytes(this.task.total);
    }
    if (this.task.status === 'paused') {
      return '已暂停 · ' + formatBytes(this.task.processed) + ' / ' + formatBytes(this.task.total);
    }
    if (this.task.status === 'completed') {
      if (this.task.finishedAt > 0) {
        const moment: string = formatMoment(this.task.finishedAt, Date.now());
        return this.task.size > 0 ? formatBytes(this.task.size) + ' · ' + moment : moment;
      }
      return this.task.size > 0 ? formatBytes(this.task.size) : '';
    }
    if (this.task.status === 'cancelled') {
      return '已取消';
    }
    return '';
  }

  /** Delivery 的默认说明与 meta 重复，任务卡不再重复一遍。 */
  private receiptText(): string {
    return this.task.receipt.message === '原件保存在应用内' ? '' : this.task.receipt.message;
  }

  build() {
    Column() {
      Row({ space: Space.s12 }) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Thumb({ src: this.thumbnailSource, firstFramePath: this.firstFramePath,
            label: kindOf(this.task.name) })

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
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            StatusChip({ status: this.task.status })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          if (this.isActive() && this.task.total > 0) {
            ProgressBar({ value: percentOf(this.task.processed, this.task.total) })
          }

          if (this.task.recoveryMessage.length > 0 && this.isActive()) {
            Text(this.task.recoveryMessage).fontSize(Font.caption).fontColor(Palette.fontSecondary)
          }
          if (this.task.status === 'completed' && this.receiptText().length > 0) {
            Text(this.receiptText()).fontSize(Font.caption).fontColor(Palette.fontSecondary)
            if (this.task.receipt.status === 'failed' || this.task.receipt.status === 'cancelled'
              || this.task.receipt.status === 'interrupted') {
              PillButton({ label: '重试另存', variant: 'ghost', small: true,
                onAction: (): void => { this.onRetryDelivery(this.task); } })
            }
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
        .onClick((): void => {
          if (this.task.status === 'completed') { this.onOpen(this.task); }
        })

        Row({ space: Space.s2 }) {
          if (this.task.status === 'running') {
            IconButton({
              glyph: 'pause', glyphSize: 18, diameter: 38, plain: true,
              accessibilityLabel: '暂停下载',
              onAction: () => { this.onPause(this.task); }
            })
          }
          if (this.task.status === 'paused') {
            IconButton({
              glyph: 'play', glyphSize: 18, diameter: 38, plain: true,
              accessibilityLabel: '继续下载',
              onAction: () => { this.onResume(this.task); }
            })
          }
          if (this.isActive()) {
            IconButton({
              glyph: 'close', glyphSize: 18, diameter: 38, plain: true,
              accessibilityLabel: '取消下载',
              onAction: () => {
                this.onCancel(this.task);
              }
            })
          }
          if (this.task.status === 'failed' || this.task.status === 'cancelled') {
            PillButton({
              label: '重试', icon: 'retry', small: true, variant: 'tonal',
              onAction: () => {
                this.onRetry(this.task);
              }
            })
          }
          if (this.task.status === 'completed') {
            IconButton({
              glyph: 'chevronRight', glyphSize: 18, diameter: 38, plain: true,
              accessibilityLabel: '在图库中查看',
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
@ComponentV2
export struct BatchCard {
  /**
   * @Prop：批次进度（done / failed / status）是运行时变的，普通成员在 V1 下刷不进来。
   * 之前只是「碰巧」能更新 —— 外层 ForEach 的 key 里带了 done/failed，数字一变就整卡重建。
   */
  @Param view: BatchView = new BatchView();
  @Event onRetry: (view: BatchView) => void = () => {
  };
  @Event onDismiss: (view: BatchView) => void = () => {
  };
  /**
   * 点这摞缩略图看大图，入口规则和单任务卡一致（`openViewer(..., false)`：不给改名）。
   *
   * 打包卡只会出现在「还在下载 / 打包失败」这两种状态 —— 打成功的批次已经变成压缩包、
   * 从任务页消失了，那时成员图也已被删除。所以这里总是能取到至少一个成员。
   */
  @Event onOpen: (view: BatchView) => void = () => {
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
    if (this.view.status === 'waiting') {
      return '等待网络或系统资源 · ' + this.view.done.toString() + '/' + this.view.total.toString() + ' 张';
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
@ComponentV2
export struct ArchiveStack {
  /** @Param：父组件传缩略图路径列表。 */
  @Param thumbs: string[] = [];

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
@ComponentV2
export struct ArchiveCard {
  @Require @Param zip: ZipItem;
  @Event onRetryDelivery: (zip: ZipItem) => void = () => {};
  @Event onExtract: (zip: ZipItem) => void = () => {};
  @Param selecting: boolean = false;
  @Param selected: boolean = false;
  @Event onSelect: (zip: ZipItem) => void = () => {
  };
  @Event onRename: (zip: ZipItem) => void = () => {
  };
  @Event onExport: (zip: ZipItem) => void = () => {
  };
  @Event onShare: (zip: ZipItem) => void = () => {
  };
  @Event onDelete: (zip: ZipItem) => void = () => {
  };

  build() {
    Column() {
      Row({ space: Space.s12 }) {
        ArchiveStack({ thumbs: this.zip.thumbs })

        if (this.selecting) {
          Glyph({ glyph: this.selected ? 'checkCircle' : 'circle', glyphSize: 20,
            glyphTone: this.selected ? Palette.brand : Palette.fontSecondary })
        }

        Column({ space: Space.s2 }) {
          Text(this.zip.name)
            .fontSize(16)
            .lineHeight(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Palette.fontPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.zip.imageCount.toString() + (this.zip.imported ? ' 个文件 · ' : ' 张图片 · ') + formatBytes(this.zip.size))
            .fontSize(Font.aux)
            .lineHeight(Font.auxLine)
            .fontColor(Palette.fontSecondary)
          if (this.zip.receipt.message.length > 0) {
            Text(this.zip.receipt.message).fontSize(Font.caption).fontColor(Palette.fontSecondary)
          }
          if (!this.selecting && (this.zip.receipt.status === 'failed' || this.zip.receipt.status === 'interrupted')) {
            PillButton({ label: '重试另存', variant: 'ghost', small: true,
              onAction: (): void => { this.onRetryDelivery(this.zip); } })
          }
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

      if (!this.selecting) {
        Row({ space: Space.s4 }) {
          IconButton({
            glyph: 'archive', glyphSize: 20, diameter: 40, plain: true,
            accessibilityLabel: '解压',
            onAction: (): void => { this.onExtract(this.zip); }
          })
          IconButton({
            glyph: 'pencil', glyphSize: 20, diameter: 40, plain: true,
            accessibilityLabel: '重命名',
            onAction: () => {
              this.onRename(this.zip);
            }
          })
          IconButton({
            glyph: 'export', glyphSize: 20, diameter: 40, plain: true,
            accessibilityLabel: '导出',
            onAction: () => {
              this.onExport(this.zip);
            }
          })
          IconButton({
            glyph: 'share', glyphSize: 20, diameter: 40, plain: true,
            accessibilityLabel: '分享',
            onAction: () => {
              this.onShare(this.zip);
            }
          })
          Blank()
          IconButton({
            glyph: 'trash', glyphSize: 20, diameter: 40, plain: true, tone: Palette.warning,
            accessibilityLabel: '删除压缩包',
            onAction: () => {
              this.onDelete(this.zip);
            }
          })
        }
        .width('100%')
        .margin({ top: Space.s12 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Space.s12)
    .borderRadius(Radius.r8)
    .backgroundColor(Palette.card)
    .shadow(Shadow.card())
    .onClick((): void => {
      if (this.selecting) { this.onSelect(this.zip); }
    })
  }
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
@ComponentV2
export struct LivePhotoSlide {
  /** 沙箱路径，不是 URI：`LivePhoto.load` 只认路径（见 service/LivePhoto.ets）。
   *  名字避开 `motionPath` —— 那是 ArkUI 通用属性（路径动画），会报成员冲突。 */
  @Param stillFile: string = '';
  @Param motionFile: string = '';
  @Local private movingPhoto: photoAccessHelper.MovingPhoto | undefined = undefined;
  /** 动态部分装不起来时的那句说明；空串不显示。 */
  @Local private problem: string = '';
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
 * `slides` / `index` 改成 **`@Param` + `@Event onIndexChange`**（V2 没有 `@Link`）：`index` 由预览页
 * 传下来单向驱动，左右滑动由中间的 Swiper 通过 `onIndexChange` 回写，预览页据此换标题、提示与
 * 文件操作的目标；列表本身也会随商店刷新（改名、删除）而变，两边照样联动。
 * `hint` / `renameAllowed` / `actionable` 是 `@Param`。
 */
@ComponentV2
export struct ImageViewer {
  private sheetMaterial: SystemUiMaterial | undefined = SheetStyle.dialogMaterial();
  @Require @Param panels: PreviewOverlayState;
  @Param foreground: boolean = true;
  /** 可以左右滑的那一批图；只有一张时就是普通大图。 */
  @Require @Param slides: ViewerSlide[];
  /** 当前是第几张；滑动手势通过 `onIndexChange` 回写，这里只读。 */
  @Require @Param index: number;
  /** 改名只在图库里开放；从任务页进来的预览不显示这一项。 */
  @Param renameAllowed: boolean = true;
  /** 文件还没落盘（任务还在下载 / 已失败）时只放大图，不给文件操作。 */
  @Param actionable: boolean = true;
  /** 操作区被收起时的解释文案；空则不显示。 */
  @Param hint: string = '';
  @Local private controlsShown: boolean = true;
  @Local private zoomed: boolean = false;
  @Local private actionDockHeight: number = 80;
  @Local private backgroundMode: string = 'auto';
  @Local private fitCommand: string = '';
  private fitSequence: number = 0;
  @Monitor('index')
  private onCurrentIndexChanged(monitor: IMonitor): void {
    this.zoomed = false;
  }
  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。
  /** 滑动换图时把新下标交回预览页（V2 里双向数据流的标准写法）。 */
  @Event onIndexChange: (index: number) => void = () => {
  };
  @Event onClose: () => void = () => {
  };
  @Event onRename: () => void = () => {
  };
  @Event onSaveToGallery: () => void = () => {
  };
  @Event onShare: () => void = () => {
  };
  @Event onExport: () => void = () => {
  };
  @Event onDelete: () => void = () => {
  };
  @Event onEdit: (id: string) => void = (id: string): void => {};

  /** 当前这一页；列表为空或索引越界时返回 undefined（调用处用 ?? 兜底）。 */
  private current(): ViewerSlide | undefined {
    if (this.index < 0 || this.index >= this.slides.length) {
      return undefined;
    }
    return this.slides[this.index];
  }

  private thumbnails(): PreviewThumbnail[] {
    return this.slides.map((slide: ViewerSlide): PreviewThumbnail => {
      return { id: slide.id, src: slide.src, name: slide.name, localPath: slide.localPath };
    });
  }

  /** 头部的「第几张 / 共几张」；只有一张时不占位置。 */
  private slideCounter(): string {
    if (this.slides.length <= 1) {
      return '';
    }
    return (this.index + 1).toString() + ' / ' + this.slides.length.toString();
  }

  private requestFit(mode: string): void {
    this.fitSequence++;
    this.fitCommand = mode + ':' + this.fitSequence.toString();
  }

  @Builder
  private action(glyph: string, label: string, danger: boolean, act: () => void): void {
    Button({ type: ButtonType.Normal }) {
    Column({ space: Space.s6 }) {
      Glyph({
        glyph: glyph,
        glyphSize: 21,
        glyphTone: danger ? '#F2826E' : '#E6FFFFFF',
        glyphWeight: 1.7
      })
      Text(label)
        .fontSize(11).minFontSize(9).maxFontSize(11).maxLines(1)
        .fontColor(danger ? '#F2826E' : '#E6FFFFFF')
    }
    .padding({ top: Space.s6, bottom: Space.s6 })
    }
    .layoutWeight(1).height(52).padding({ left: 2, right: 2 }).backgroundColor(Color.Transparent)
    .accessibilityText(label).borderRadius(Radius.r6)
    .onClick(() => {
      act();
    })
  }

  @Builder
  private toolsContent() {
    if (this.current() !== undefined) {
      PreviewTools({ asset: this.current()!, backgroundMode: this.backgroundMode,
        onEdit: (id: string): void => { this.panels.tools = false; this.onEdit(id); },
        onBackground: (mode: string): void => { this.backgroundMode = mode; },
        onCompare: (): void => { this.panels.tools = false; this.panels.comparison = true; },
        onClose: (): void => { this.panels.tools = false; } })
    }
  }

  private animationDocked(): boolean {
    const slide: ViewerSlide | undefined = this.current();
    return slide !== undefined && slide.animated
      && !(slide.stillPath.length > 0 && slide.motionPath.length > 0);
  }

  @Builder
  private actionDock(actions: AnimationDockActions) {
    Column() {
      if (actions.notice.length > 0 || this.hint.length > 0) {
        Text(actions.notice.length > 0 ? actions.notice : this.hint)
          .fontSize(Font.aux)
          .lineHeight(Font.auxLine)
          .fontColor('#B3FFFFFF')
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ left: Space.s24, right: Space.s24, top: Space.s10 })
      }
      if (this.actionable) {
        Row() {
          if (this.current()?.localPath && !this.current()?.animated && !this.current()?.stillPath) {
            this.action('scan', '适合屏幕', false, (): void => { this.requestFit('screen'); })
            this.action('image', '原始像素', false, (): void => { this.requestFit('native'); })
          }
          if (this.renameAllowed) {
            this.action('pencil', '重命名', false, this.onRename)
          }
          if (actions.available) {
            if (actions.canPause) {
              AnimationToolbarAction({ actions: actions }).layoutWeight(1)
            }
            AnimationToolbarAction({ actions: actions, frameAction: true }).layoutWeight(1)
          }
          this.action('download', '存相册', false, this.onSaveToGallery)
          this.action('share', '分享', false, this.onShare)
          this.action('export', '导出', false, this.onExport)
          this.action('trash', '删除', true, this.onDelete)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceAround)
        .padding({ top: Space.s10, bottom: Space.s24 })
      } else {
        Column().height(Space.s24)
      }
    }.width('100%')
      .onSizeChange((oldSize: SizeOptions, newSize: SizeOptions): void => {
        // 底部渐变层额外留了 24vp 渐隐头，缩放控件要一起让开。
        this.actionDockHeight = Number(newSize.height) + Space.s24;
      })
  }

  private detailsMaterialAllowed(): boolean {
    const slide: ViewerSlide | undefined = this.current();
    return slide !== undefined && slide.downloaded && slide.localPath.length > 0
      && !slide.animated && slide.motionPath.length === 0;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Swiper() {
        ForEach(this.slides, (slide: ViewerSlide, slideIndex: number) => {
          Stack({ alignContent: Alignment.Center }) {
            if (slide.stillPath.length > 0 && slide.motionPath.length > 0) {
              LivePhotoSlide({ stillFile: slide.stillPath, motionFile: slide.motionPath })
            } else if (slide.localPath.length > 0 && !slide.animated) {
              ZoomablePreviewImage({ imageId: slide.id, path: slide.localPath, fallbackUri: slide.src,
                readingKey: 'local:' + slide.id, allowDismiss: !this.panels.tools && !this.panels.navigation,
                onDismiss: this.onClose,
                label: slide.label, active: this.foreground && slideIndex === this.index && !this.panels.comparison, controlsVisible: this.controlsShown && !this.panels.tools, controlsBottom: this.actionDockHeight,
                showFitControls: false, fitCommand: this.fitCommand,
                backgroundMode: this.backgroundMode,
                onTapImage: (): void => { this.controlsShown = !this.controlsShown; },
                onZoomChange: (value: boolean): void => { this.zoomed = value; } })
            } else {
              AnimatedPreviewImage({ onTapImage: (): void => { this.controlsShown = !this.controlsShown; }, src: slide.src, localPath: slide.localPath, name: slide.name, controlsVisible: this.controlsShown && !this.panels.tools, controlsBottom: this.actionDockHeight, backgroundMode: this.backgroundMode, active: this.foreground && slideIndex === this.index && !this.panels.comparison,
                allowDismiss: !this.panels.tools && !this.panels.navigation, onDismiss: this.onClose,
                dockedControls: slide.animated,
                bottomActions: (actions: AnimationDockActions): void => { this.actionDock(actions); } })
                .width('100%').height('100%')
            }
          }
          .width('100%').height('100%')
          .parallelGesture(TapGesture({ count: 1 }).onAction((): void => {
            if (slide.stillPath.length > 0 && slide.motionPath.length > 0) {
              this.controlsShown = !this.controlsShown;
            }
          }))
        }, (slide: ViewerSlide) => slide.id)
      }
      .width('100%').height('100%')
      .index(this.index).loop(false).indicator(false).cachedCount(1)
      .disableSwipe(this.zoomed)
      .onChange((value: number): void => {
        this.zoomed = false;
        this.onIndexChange(value);
      })

      if (this.controlsShown) {
        Column() {
          Column() {
            PreviewHeader({ title: this.current()?.name ?? '', counter: this.slideCounter(),
              showCounter: this.slideCounter().length > 0, emphasized: true,
              detailsLabel: '图片详情与工具',
              onNavigation: (): void => { this.panels.navigation = !this.panels.navigation; },
              onDetails: (): void => { this.panels.tools = true; },
              onClose: (): void => { this.onClose(); } })
          }
          .width('100%')
          .padding({ bottom: Space.s24 })
          .linearGradient(PreviewChrome.topGradient())
          .hitTestBehavior(HitTestMode.None)
          if (this.panels.navigation) {
            PreviewStrip({ items: this.thumbnails(), currentIndex: this.index,
              onJump: (next: number): void => { this.panels.navigation = false; this.onIndexChange(next); },
              onClose: (): void => { this.panels.navigation = false; } })
          }
          Column().layoutWeight(1).hitTestBehavior(HitTestMode.None)

          if (!this.animationDocked()) {
            Column() {
              this.actionDock(new AnimationDockActions())
            }.width('100%')
              .padding({ top: Space.s24 })
              .linearGradient(PreviewChrome.bottomGradient())
              .hitTestBehavior(HitTestMode.None)
          }
        }
        .width('100%').height('100%')
        .hitTestBehavior(HitTestMode.None)
      }
      if (this.foreground && this.panels.comparison && this.current() !== undefined) {
        PreviewCompare({ assets: this.slides, currentId: this.current()!.id, backgroundMode: this.backgroundMode,
          onClose: (): void => { this.panels.comparison = false; } })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .bindSheet(this.panels.tools && this.current() !== undefined, this.toolsContent(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      dragBar: true,
      showClose: false,
      backgroundColor: this.detailsMaterialAllowed() ? SheetStyle.background() : Palette.card,
      systemMaterial: this.detailsMaterialAllowed() ? this.sheetMaterial : undefined,
      onDisappear: (): void => { this.panels.tools = false; }
    })
  }
}
