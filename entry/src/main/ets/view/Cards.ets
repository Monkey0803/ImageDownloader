/*
 * Cards.ets — the prototype's data-bound components.
 *
 * Ported from designs/image-downloader-ui/ui.jsx, screen-tasks.jsx and
 * screen-library.jsx. Each struct binds to an @Observed model instance with
 * @ObjectLink so progress and selection update in place.
 */

import { fileUri } from '@kit.CoreFileKit';
import { BatchItem, DownloadItem, PictureItem, ZipItem } from '../model/Models';
import {
  Font, formatBytes, formatMoment, kindOf, Palette, percentOf, Radius, Shadow, Space
} from '../theme/Tokens';
import { Glyph } from './Icons';
import { IconButton, PillButton, ProgressBar, StatusChip } from './Widgets';

/** Image with a type-badge fallback, mirroring the prototype's <Img>. */
@Component
export struct Thumb {
  src: string = '';
  label: string = 'IMG';
  fit: ImageFit = ImageFit.Cover;

  @State private failed: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.src.length > 0 && !this.failed) {
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
  onToggle: (picture: PictureItem) => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Thumb({ src: this.picture.url, label: kindOf(this.picture.name) })

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
      this.onToggle(this.picture);
    })
  }
}

/** One completed download in the gallery grid. */
@Component
export struct ShotTile {
  @ObjectLink image: DownloadItem;
  dense: boolean = false;
  onOpen: (image: DownloadItem) => void = () => {
  };

  build() {
    Column({ space: Space.s4 }) {
      Stack() {
        Thumb({ src: fileUri.getUriFromPath(this.image.path), label: kindOf(this.image.name) })
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
  onRename: (task: DownloadItem) => void = () => {
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
              .onClick(() => {
                this.onRename(this.task);
              })
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

/**
 * A batch seen through its members: counts and status are derived, never
 * stored twice (the prototype computes batchViews the same way).
 */
export class BatchView {
  id: string = '';
  name: string = '';
  status: string = 'downloading';
  total: number = 0;
  done: number = 0;
  failed: number = 0;
  thumbs: string[] = [];
}

/** The ZIP batch in flight, with its stacked member preview. */
@Component
export struct BatchCard {
  view: BatchView = new BatchView();

  private meta(): string {
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
              .fontColor(Palette.fontTertiary)
            if (this.view.failed > 0) {
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
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      ProgressBar({
        value: this.view.status === 'packing' ? 96 : Math.round((this.view.done / Math.max(1, this.view.total)) * 100),
        striped: this.view.status === 'packing'
      })
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

/** Full-screen image preview with its action bar. */
@Component
export struct ImageViewer {
  src: string = '';
  heading: string = '';
  label: string = 'IMG';
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
        Text(this.heading)
          .fontSize(Font.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.white)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        IconButton({
          glyph: 'close', glyphSize: 20, diameter: 34, plain: true, tone: Palette.white,
          onAction: () => {
            this.onClose();
          }
        })
      }
      .width('100%')
      .padding({ left: Space.s16, right: Space.s16, top: this.safeTop + Space.s16, bottom: Space.s8 })

      Stack({ alignContent: Alignment.Center }) {
        Thumb({ src: this.src, label: this.label, fit: ImageFit.Contain })
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: Space.s16, right: Space.s16 })

      Row() {
        this.action('pencil', '重命名', false, this.onRename)
        this.action('download', '存相册', false, this.onSaveToGallery)
        this.action('share', '分享', false, this.onShare)
        this.action('export', '导出', false, this.onExport)
        this.action('trash', '删除', true, this.onDelete)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceAround)
      .padding({ top: Space.s10, bottom: this.safeBottom + Space.s16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.viewerBg)
    .backdropBlur(30)
  }
}

/** Build the derived view of a batch from its member downloads. */
export function batchViewOf(batch: BatchItem, members: DownloadItem[],
  done: number, failed: number): BatchView {
  const view: BatchView = new BatchView();
  view.id = batch.id;
  view.name = batch.name;
  view.total = members.length;
  view.done = done;
  view.failed = failed;
  view.status = members.length > 0 && (done + failed) >= members.length ? 'packing' : 'downloading';
  view.thumbs = members.slice(0, 3).map((item: DownloadItem): string => item.url);
  return view;
}
