import { DownloadItem, ZipItem } from '../../model/Models';
import { LibraryViewModel } from '../../viewmodel/LibraryViewModel';
import { SettingsViewModel } from '../../viewmodel/SettingsViewModel';
import { chunkRows, fillerCells } from '../../util/GridMath';
import { Font, formatBytes, Layout, Palette, Radius, Shadow, Space } from '../../theme/Tokens';
import { ScreenMetrics } from '../../theme/Metrics';
import { Glyph } from '../Icons';
import { ArchiveCard, ShotTile } from '../Cards';
import { EmptyState, LibrarySegment, TitleBar } from '../Widgets';
import { SCREEN_INSETS } from '../../theme/Metrics';

/**
 * 「图库」页：图片 / 压缩包分段 + 搜索 + 密度切换。
 *
 * 从 Index 的 `libraryScreen()` 及其四个子 @Builder 搬过来。搜索过滤与两段列表都在
 * `LibraryViewModel` 里预算好（`images` / `archives`），这里只负责画；
 * 「空」和「搜不到」两种空态的区分由 `query` 是否为空决定。
 */
@ComponentV2
export struct LibraryScreen {
  @Require @Param library: LibraryViewModel;
  @Require @Param settings: SettingsViewModel;

  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。
  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。

  @Builder
  private searchPill() {
    Row({ space: Space.s8 }) {
      Glyph({ glyph: 'search', glyphSize: 18, glyphTone: Palette.fontTertiary, glyphWeight: 1.7 })
      TextInput({ placeholder: '搜索文件名', text: this.library.query })
        .placeholderColor(Palette.fontSecondary)
        .caretColor(Palette.brand)
        .fontSize(Font.body)
        .fontColor(Palette.fontPrimary)
        .backgroundColor(Color.Transparent)
        .padding(0)
        .height(36)
        .layoutWeight(1)
        .onChange((value: string): void => {
          this.library.setQuery(value);
        })
      // 有输入才出现的清除按钮：点一下把关键词清空，列表回到全部。
      if (this.library.query.length > 0) {
        Glyph({
          glyph: 'xCircle', glyphSize: 19, glyphTone: Palette.fontTertiary, glyphWeight: 1.7
        })
          .onClick((): void => {
            this.library.setQuery('');
          })
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: Space.s14, right: Space.s8 })
    .borderRadius(Radius.full)
    .backgroundColor(Palette.card)
    .shadow(Shadow.card())
  }

  @Builder
  private galleryGrid() {
    Column({ space: Space.s12 }) {
      ForEach(chunkRows<DownloadItem>(this.library.images, this.library.density),
        (row: DownloadItem[], rowIndex: number) => {
          Row({ space: this.library.density === 3 ? Space.s6 : Space.s12 }) {
            ForEach(row, (cell: DownloadItem, colIndex: number) => {
              Column() {
                ShotTile({
                  image: cell,
                  dense: this.library.density === 3,
                  // 图库进预览可以改名（任务页进来不给改），并带上当前显示的整批图片，
                  // 预览页里左右滑动就是在这批图之间换（搜索后只在结果里滑）。
                  onOpen: (item: DownloadItem): void => {
                    this.library.openImage(item);
                  }
                })
              }
              .layoutWeight(1)
            }, (cell: DownloadItem) => cell.id)

            ForEach(fillerCells(row.length, this.library.density), (pad: number) => {
              Column().layoutWeight(1)
            }, (pad: number) => 'pad' + pad.toString())
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (row: DownloadItem[], rowIndex: number) => rowIndex.toString()
          + ':' + row.map((cell: DownloadItem): string => cell.id).join(','))
    }
    .width('100%')
  }

  /** 图片段：网格，空态区分「库是空的」和「搜不到」。 */
  @Builder
  private libraryImages() {
    if (this.library.images.length > 0) {
      this.galleryGrid()
    } else {
      EmptyState({
        glyph: 'image',
        heading: this.library.query.length > 0 ? '没有匹配的图片' : '图库还是空的',
        body: this.library.query.length > 0 ? '换一个关键词试试。' : '下载完成的图片会出现在这里。'
      })
    }
  }

  /** 压缩包段：卡片列表，空态同样区分「还没有」和「搜不到」。 */
  @Builder
  private libraryArchives() {
    if (this.library.archives.length > 0) {
      Column({ space: Space.s12 }) {
        ForEach(this.library.archives, (zip: ZipItem) => {
          ArchiveCard({
            zip: zip,
            onRename: (item: ZipItem): void => {
              this.library.startZipRename(item);
            },
            onExport: (item: ZipItem): void => {
              this.library.exportZip(item);
            },
            onShare: (item: ZipItem): void => {
              this.library.shareZip(item);
            },
            onDelete: (item: ZipItem): void => {
              this.library.confirmDeleteZip(item);
            }
          })
        }, (zip: ZipItem) => zip.id)
      }
      .width('100%')
    } else {
      EmptyState({
        glyph: 'archive',
        heading: this.library.query.length > 0 ? '没有匹配的压缩包' : '还没有压缩包',
        body: this.library.query.length > 0
          ? '换一个关键词试试。'
          : '在「发现」里打开 ZIP 模式，把选中的图片打包成一个压缩包。'
      })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll(this.library.scrollController()) {
        Column({ space: Space.s16 }) {
          // 图片 / 压缩包：用系统的 CapsuleSegmentButtonV2，背景板走系统材质
          // （文档 SegmentButtonV2 → 示例6）；材质由 LibrarySegment 自己按这个布尔量决定
          // —— 本机不支持沉浸式材质时它同样会退回不透明胶囊。
          LibrarySegment({
            selected: this.library.segment,
            materialOff: this.settings.materialType === 'none',
            onSelect: (value: string): void => {
              this.library.setSegment(value);
            }
          })

          this.searchPill()

          if (this.library.isZips()) {
            this.libraryArchives()
          } else {
            this.libraryImages()
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: ScreenMetrics.height() })
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          top: ScreenMetrics.topInset(SCREEN_INSETS.safeTop, true),
          bottom: ScreenMetrics.bottomInset(SCREEN_INSETS.safeBottom, 0)
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onDidScroll((): void => {
        this.library.markScrolled();
      })

      TitleBar({
        heading: '图库',
        caption: this.library.isZips()
          ? this.library.zips.length.toString() + ' 个压缩包'
          : this.library.imageCount.toString() + ' 张图片 · ' + formatBytes(this.library.imageBytes),
        // 密度切换只对图片网格有意义，压缩包段不显示这个按钮。
        actionGlyph: this.library.isZips() ? '' : 'grid',
        layer: Layout.tbLayerSecondary,
        onAction: (): void => {
          this.library.setDensity(this.library.density === 2 ? 3 : 2);
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
