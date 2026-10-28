import { DownloadItem, ZipItem } from '../../model/Models';
import { LibraryText } from '../../util/LibraryText';
import { LibraryViewModel } from '../../viewmodel/LibraryViewModel';
import { SettingsViewModel } from '../../viewmodel/SettingsViewModel';
import { chunkRows, fillerCells } from '../../util/GridMath';
import { Font, formatBytes, Layout, Palette, Radius, Shadow, Space } from '../../theme/Tokens';
import { ScreenMetrics } from '../../theme/Metrics';
import { SheetStyle } from '../../theme/SheetStyle';
import { TransparentGlass } from '../../theme/TransparentGlass';
import { Glyph } from '../Icons';
import { ArchiveCard, ShotTile } from '../Cards';
import { LibraryFilterSheet } from '../LibraryFilterSheet';
import { LibraryOrganizeSheet } from '../LibraryOrganizeSheet';
import { ImageTagDialog } from '../ImageTagDialog';
import { EmptyState, IconButton, LibrarySegment, PillButton, TitleBar } from '../Widgets';
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
  @Param active: boolean = false;
  @Local private tagDialogOpen: boolean = false;
  @Local private sheet: string = '';
  private sheetMaterial: SystemUiMaterial | undefined = SheetStyle.material();

  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。
  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。

  @Builder
  private searchPill() {
    Row({ space: Space.s8 }) {
      Glyph({ glyph: 'search', glyphSize: 18, glyphTone: Palette.fontTertiary, glyphWeight: 1.7 })
      TextInput({ placeholder: this.library.isZips() ? '搜索压缩包' : '搜索图片', text: this.library.query })
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
    .layoutWeight(1)
    .height(44)
    .padding({ left: Space.s14, right: Space.s8 })
    .borderRadius(Radius.full)
    .backgroundColor(Palette.card)
    .shadow(Shadow.card())
  }

  private activeOptionCount(): number {
    let count: number = this.library.sortOrder === 'newest' ? 0 : 1;
    if (this.library.isZips()) { return count; }
    if (this.library.formatFilter.length > 0) { count++; }
    if (this.library.sourceQuery.length > 0) { count++; }
    if (this.library.favoritesOnly) { count++; }
    if (this.library.tagFilter.length > 0) { count++; }
    if (this.library.searchScope !== 'all') { count++; }
    if (this.library.density !== 2) { count++; }
    return count;
  }

  private hasImageFilter(): boolean {
    return this.library.query.length > 0 || this.library.sourceQuery.length > 0
      || this.library.formatFilter.length > 0 || this.library.favoritesOnly
      || this.library.tagFilter.length > 0;
  }

  @Builder
  private searchTools() {
    Row({ space: Space.s6 }) {
      this.searchPill()
      Stack({ alignContent: Alignment.TopEnd }) {
        IconButton({ glyph: 'sliders', diameter: 40,
          tone: this.activeOptionCount() > 0 ? Palette.brand : Palette.fontPrimary,
          accessibilityLabel: this.activeOptionCount() > 0
            ? '筛选，已启用 ' + this.activeOptionCount().toString() + ' 项' : '筛选',
          onAction: (): void => { this.sheet = 'filter'; } })
        if (this.activeOptionCount() > 0) {
          Text(this.activeOptionCount().toString())
            .fontSize(10).fontColor(Palette.fontOnPrimary).textAlign(TextAlign.Center)
            .width(16).height(16).borderRadius(Radius.full).backgroundColor(Palette.brand)
            .hitTestBehavior(HitTestMode.None)
        }
      }
      if (this.library.isZips()) {
        PillButton({ label: '导入', small: true, variant: 'ghost',
          onAction: (): void => { this.library.importZip(); } })
      } else {
        PillButton({ label: '整理', small: true, variant: 'ghost',
          onAction: (): void => { this.sheet = 'organize'; } })
      }
    }.width('100%')
  }

  private activeSheet(): string {
    if (this.library.extractZipId.length > 0) { return 'extract'; }
    if (this.tagDialogOpen) { return 'tag'; }
    return this.sheet;
  }

  @Builder
  private extractContent() {
    Column({ space: Space.s16 }) {
      Text('解压压缩包').fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(TransparentGlass.foreground())
      if (this.library.extractTarget.length === 0) {
        Text('选择解压位置').fontSize(Font.body).fontColor(TransparentGlass.secondary())
        PillButton({ label: '加入应用图库', variant: 'primary',
          onAction: (): void => { this.library.chooseExtractTarget('gallery'); } })
        PillButton({ label: '保存到系统目录', variant: 'ghost',
          onAction: (): void => { this.library.chooseExtractTarget('folder'); } })
      } else if (this.library.extractEncrypted && !this.library.extractBusy) {
        Text('此压缩包需要密码').fontSize(Font.body).fontColor(TransparentGlass.secondary())
        TextInput({ placeholder: '输入 ZIP 密码', text: this.library.extractPassword })
          .type(InputType.Password)
          .onChange((value: string): void => { this.library.extractPassword = value; })
          .onSubmit((): void => { this.library.submitExtract(); })
        PillButton({ label: '开始解压', variant: 'primary',
          onAction: (): void => { this.library.submitExtract(); } })
      } else {
        Text('正在解压，请稍候…').fontSize(Font.body).fontColor(TransparentGlass.secondary())
      }
      if (!this.library.extractBusy) {
        PillButton({ label: '取消', variant: 'ghost',
          onAction: (): void => { this.library.closeExtract(); } })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: Layout.pagePad, right: Layout.pagePad,
        top: Space.s16, bottom: SCREEN_INSETS.safeBottom + Space.s16 })
  }

  @Builder
  private sheetContent() {
    if (this.activeSheet() === 'tag') {
      ImageTagDialog({ single: false,
        onSave: (add: string[], remove: string[]): void => {
          this.library.changeSelectedTags(add, remove);
          this.tagDialogOpen = false;
        },
        onClose: (): void => { this.tagDialogOpen = false; } })
    } else if (this.activeSheet() === 'extract') {
      this.extractContent()
    } else {
      Column({ space: Space.s12 }) {
        Row({ space: Space.s8 }) {
          Text(this.sheet === 'filter' ? '筛选与排序' : '查找与整理')
            .fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(TransparentGlass.foreground())
            .layoutWeight(1)
          IconButton({ glyph: 'close', plain: true, diameter: 36, tone: TransparentGlass.foreground(),
            accessibilityLabel: '关闭面板', onAction: (): void => { this.sheet = ''; } })
        }.width('100%')
        List() {
          ListItem() {
            if (this.sheet === 'filter') {
              LibraryFilterSheet({ library: this.library })
            } else {
              LibraryOrganizeSheet({ library: this.library,
                onOpenGroup: (): void => { this.sheet = ''; } })
            }
          }.width('100%').padding({ bottom: SCREEN_INSETS.safeBottom + Space.s12 })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
        .padding({ left: Layout.pagePad, right: Layout.pagePad, top: Space.s16 })
    }
  }

  @Builder
  private selectionControls() {
    if (this.library.selecting) {
      Row({ space: Space.s8 }) {
        Text('已选 ' + this.library.visibleSelectedCount.toString())
          .fontSize(Font.aux).fontColor(TransparentGlass.secondary()).layoutWeight(1)
        PillButton({ label: '全选', variant: 'ghost', small: true,
          onAction: (): void => { this.library.selectVisible(); } })
        PillButton({ label: '清空', variant: 'ghost', small: true,
          onAction: (): void => { this.library.clearVisibleSelection(); } })
      }.width('100%')
    }
  }

  @Builder
  private selectionActions() {
    if (this.library.selecting && this.library.visibleSelectedCount > 0) {
      Column({ space: Space.s8 }) {
      Row({ space: Space.s8 }) {
        PillButton({ label: '分享', variant: 'ghost', small: true,
          onAction: (): void => { this.library.shareSelected(); } })
        PillButton({ label: '导出', variant: 'ghost', small: true,
          onAction: (): void => { this.library.exportSelected(); } })
        PillButton({ label: '删除', variant: 'danger', small: true,
          onAction: (): void => { this.library.deleteSelected(); } })
      }
      .width('100%')
      if (!this.library.isZips()) {
        Row({ space: Space.s8 }) {
          PillButton({ label: '收藏', variant: 'ghost', small: true,
            onAction: (): void => { this.library.setSelectedFavorite(true); } })
          PillButton({ label: '取消收藏', variant: 'ghost', small: true,
            onAction: (): void => { this.library.setSelectedFavorite(false); } })
          PillButton({ label: '编辑标签', variant: 'ghost', small: true,
            onAction: (): void => { this.tagDialogOpen = true; } })
        }.width('100%')
      }
      }.width('100%')
    }
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
                  favorite: this.library.entry(cell.id).favorite,
                  tags: this.library.entry(cell.id).tags,
                  snippet: this.library.query.length > 0
                    ? LibraryText.snippet(this.library.entry(cell.id).text, this.library.query, 64) : '',
                  dense: this.library.density === 3,
                  selecting: this.library.selecting,
                  selected: this.library.isSelected(cell.id),
                  // 图库进预览可以改名（任务页进来不给改），并带上当前显示的整批图片，
                  // 预览页里左右滑动就是在这批图之间换（搜索后只在结果里滑）。
                  onOpen: (item: DownloadItem): void => {
                    if (this.library.selecting) { this.library.toggleSelection(item.id); }
                    else { this.library.openImage(item); }
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
        heading: !this.library.catalogReady ? '正在读取图库信息' :
          this.hasImageFilter()
            ? '没有匹配的图片' : '图库还是空的',
        body: !this.library.catalogReady ? '图片文字与标签读取完成后可搜索。' :
          this.hasImageFilter()
            ? '换个关键词或清除筛选试试。' : '下载完成的图片会出现在这里。'
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
            onExtract: (item: ZipItem): void => { this.library.startExtract(item); },
            onRetryDelivery: (item: ZipItem): void => { this.library.retryArchiveDelivery(item); },
            selecting: this.library.selecting,
            selected: this.library.isSelected(zip.id),
            onSelect: (item: ZipItem): void => { this.library.toggleSelection(item.id); },
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
          : '可以从系统文件导入 ZIP，或在「发现」中把选中的图片打包。'
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
            materialOff: !this.settings.lightEffect || this.settings.materialType === 'none',
            onSelect: (value: string): void => {
              this.library.setSegment(value);
            }
          })

          this.searchTools()
          this.selectionControls()
          this.selectionActions()

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
        actionText: this.library.selecting ? '完成' : '选择',
        layer: Layout.tbLayerSecondary,
        onAction: (): void => {
          if (this.library.selecting) { this.library.endSelection(); }
          else { this.library.startSelection(); }
        }
      })
    }
    .width('100%')
    .height('100%')
    .bindSheet(this.active && this.activeSheet().length > 0, this.sheetContent(), {
      height: this.activeSheet() === 'organize' ? undefined
        : this.activeSheet() === 'filter' ? SheetSize.MEDIUM : SheetSize.FIT_CONTENT,
      detents: this.activeSheet() === 'organize'
        ? [SheetSize.MEDIUM, SheetSize.LARGE] : undefined,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      dragBar: true,
      showClose: false,
      backgroundColor: SheetStyle.background(),
      systemMaterial: this.sheetMaterial,
      onWillDismiss: (action: DismissSheetAction): void => {
        if (!this.library.extractBusy) { action.dismiss(); }
      },
      onDisappear: (): void => {
        this.sheet = '';
        this.tagDialogOpen = false;
        this.library.closeExtract();
      }
    })
  }
}
