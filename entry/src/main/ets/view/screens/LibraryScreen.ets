import { DownloadItem, ZipItem } from '../../model/Models';
import { UserAlbum } from '../../model/LibraryAsset';
import { TrashEntry } from '../../service/TrashStore';
import { fileUri } from '@kit.CoreFileKit';
import { LibraryViewModel } from '../../viewmodel/LibraryViewModel';
import { LibraryFlowRow } from '../../viewmodel/LibraryFlowRows';
import { Font, formatBytes, Layout, Palette, Radius, Space } from '../../theme/Tokens';
import { ScreenMetrics } from '../../theme/Metrics';
import { TransparentGlass } from '../../theme/TransparentGlass';
import { Glyph } from '../Icons';
import { AppSheet } from '../AppSheet';
import { ArchiveCard, ShotTile } from '../Cards';
import { Thumb } from '../Thumb';
import { LibraryFilterSheet } from '../LibraryFilterSheet';
import { LibraryOrganizeSheet } from '../LibraryOrganizeSheet';
import { ImageTagDialog } from '../ImageTagDialog';
import { EmptyState, IconButton, PillButton, SectionHead } from '../Widgets';
import { LibrarySelectionBar } from '../LibrarySelectionBar';
import { SCREEN_INSETS } from '../../theme/Metrics';

/**
 * 「图库」页：照片流 + 详情面板。
 *
 * 分段（图片 / 压缩包）、布局与筛选图标、搜索框都挂在 HDS 标题栏里
 * （见 `view/LibraryTitleBar.ets`），这里只画照片、空态、选择条与弹层。
 * 搜索过滤与两段列表都在 `LibraryViewModel` 里预算好（`images` / `archives`），
 * 「空」和「搜不到」两种空态的区分由 `query` 是否为空决定。
 */
@ComponentV2
export struct LibraryScreen {
  @Require @Param library: LibraryViewModel;
  @Param active: boolean = false;
  @Local private tagDialogOpen: boolean = false;
  @Local private albumDraft: string = '';
  @Local private albumRenameId: string = '';

  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。

  private hasImageFilter(): boolean {
    return this.library.query.length > 0 || this.library.filterCount() > 0;
  }

  /** 只在真的筛过东西时出现：一行说清「筛了几项、还剩几条」，并给一键复位。 */
  @Builder
  private filterSummary() {
    if (this.library.filterCount() > 0 || this.library.query.length > 0) {
      Row({ space: Space.s8 }) {
        Text('已筛选 ' + (this.library.filterCount() + (this.library.query.length > 0 ? 1 : 0)).toString()
          + ' 项 · ' + (this.library.isZips() ? this.library.archives.length : this.library.images.length).toString()
          + ' 个结果')
          .fontSize(Font.caption).fontColor(Palette.fontSecondary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        PillButton({ label: '清除全部', small: true, variant: 'ghost',
          onAction: (): void => { this.library.clearFilters(); } })
      }.width('100%')
    }
  }

  private activeSheet(): string {
    if (this.library.extractZipId.length > 0) { return 'extract'; }
    if (this.tagDialogOpen) { return 'tag'; }
    return this.library.sheet;
  }

  @Builder
  private albumsContent() {
    Column({ space: Space.s12 }) {
      Text('自建相册只保存归类，不移动或复制图片。')
        .fontSize(Font.caption).fontColor(TransparentGlass.secondary())
      Row({ space: Space.s8 }) {
        TextInput({ placeholder: this.albumRenameId.length > 0 ? '新的相册名' : '新建相册名称', text: this.albumDraft })
          .layoutWeight(1).onChange((value: string): void => { this.albumDraft = value; })
        PillButton({ label: this.albumRenameId.length > 0 ? '保存改名' : '创建', small: true,
          onAction: (): void => {
            if (this.albumRenameId.length > 0) { this.library.renameAlbum(this.albumRenameId, this.albumDraft); }
            else { this.library.createAlbum(this.albumDraft); }
            this.albumDraft = ''; this.albumRenameId = '';
          } })
      }.width('100%')
      ForEach(this.library.albums, (album: UserAlbum) => {
        Column({ space: Space.s6 }) {
          Row({ space: Space.s6 }) {
            Text(album.name).fontSize(Font.body).fontColor(TransparentGlass.foreground()).layoutWeight(1)
            PillButton({ label: '查看', small: true, variant: 'tonal',
              onAction: (): void => { this.library.albumFilter = album.id; this.library.sheet = ''; } })
            PillButton({ label: '改名', small: true, variant: 'ghost',
              onAction: (): void => { this.albumRenameId = album.id; this.albumDraft = album.name; } })
            PillButton({ label: '删除', small: true, variant: 'ghost',
              onAction: (): void => { this.library.deleteAlbum(album.id); } })
          }.width('100%')
          if (this.library.selecting && this.library.visibleSelectedCount > 0) {
            Row({ space: Space.s8 }) {
              PillButton({ label: '将已选加入', small: true, variant: 'tonal',
                onAction: (): void => { this.library.setSelectedAlbum(album.id, true); } })
              PillButton({ label: '将已选移出', small: true, variant: 'ghost',
                onAction: (): void => { this.library.setSelectedAlbum(album.id, false); } })
            }.width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }, (album: UserAlbum) => album.id)
      if (this.library.albums.length === 0) {
        Text('还没有自建相册').fontSize(Font.caption).fontColor(TransparentGlass.secondary())
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private trashContent() {
    Column({ space: Space.s12 }) {
      Text(this.library.trashEntries.length.toString() + ' 项 · ' + formatBytes(this.library.trashEntries.reduce(
        (bytes: number, entry: TrashEntry): number => bytes + entry.bytes, 0)) + ' · 保留 30 天')
        .fontSize(Font.caption).fontColor(TransparentGlass.secondary())
      if (this.library.trashEntries.length > 0) {
        PillButton({ label: '清空最近删除', small: true, variant: 'danger',
          onAction: (): void => { this.library.clearTrash(); } })
      }
      ForEach(this.library.trashEntries, (entry: TrashEntry) => {
        Row({ space: Space.s8 }) {
          if (entry.kind === 'image' && entry.previewPath.length > 0) {
            Thumb({ src: fileUri.getUriFromPath(entry.previewPath), label: '图片' })
              .width(48).height(48).borderRadius(Radius.r6)
          } else {
            Glyph({ glyph: 'archive', glyphSize: 28, glyphTone: TransparentGlass.secondary() })
              .width(48).height(48)
          }
          Text((entry.kind === 'zip' ? 'ZIP · ' : '图片 · ') + entry.name)
            .fontSize(Font.body).fontColor(TransparentGlass.foreground()).layoutWeight(1)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          PillButton({ label: '恢复', small: true, variant: 'tonal',
            onAction: (): void => { this.library.restoreTrash(entry.id); } })
          PillButton({ label: '永久删除', small: true, variant: 'ghost',
            onAction: (): void => { this.library.permanentlyDeleteTrash(entry.id); } })
        }.width('100%')
      }, (entry: TrashEntry) => entry.id)
      if (this.library.trashEntries.length === 0) {
        Text('最近删除是空的').fontSize(Font.caption).fontColor(TransparentGlass.secondary())
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
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
          Text(this.library.sheet === 'filter' ? '筛选与整理' : this.library.sheet === 'albums' ? '自建相册' :
            this.library.sheet === 'trash' ? '最近删除' : '查找与整理')
            .fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(TransparentGlass.foreground())
            .layoutWeight(1)
          IconButton({ glyph: 'close', plain: true, diameter: 36, tone: TransparentGlass.foreground(),
            accessibilityLabel: '关闭面板', onAction: (): void => { this.library.sheet = ''; } })
        }.width('100%')
        List() {
          ListItem() {
            if (this.library.sheet === 'filter') {
              LibraryFilterSheet({ library: this.library,
                onOpenAlbums: (): void => { this.library.sheet = 'albums'; },
                onOpenTrash: (): void => { this.library.refreshTrash(); this.library.sheet = 'trash'; },
                onOpenOrganize: (): void => { this.library.sheet = 'organize'; } })
            } else if (this.library.sheet === 'albums') {
              this.albumsContent()
            } else if (this.library.sheet === 'trash') {
              this.trashContent()
            } else {
              LibraryOrganizeSheet({ library: this.library,
                onOpenGroup: (): void => { this.library.sheet = ''; } })
            }
          }.width('100%').padding({ bottom: SCREEN_INSETS.safeBottom + Space.s12 })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
        .padding({ left: Layout.pagePad, right: Layout.pagePad, top: Space.s16 })
    }
  }

  @Builder
  private flowRow(row: LibraryFlowRow) {
    if (row.kind === 'summary') {
      this.filterSummary()
    } else if (row.kind === 'heading') {
      SectionHead({ heading: row.title, meta: row.count.toString() + ' 张' })
    } else if (row.kind === 'image' && row.image !== undefined) {
      ShotTile({
        image: row.image,
        square: this.library.squareTiles(),
        selecting: this.library.selecting,
        selected: this.library.isSelected(row.image.id),
        onOpen: (item: DownloadItem): void => {
          if (this.library.selecting) { this.library.toggleSelection(item.id); }
          else { this.library.openImage(item); }
        }
      })
    } else if (row.kind === 'archive' && row.archive !== undefined) {
      ArchiveCard({
        zip: row.archive,
        onExtract: (item: ZipItem): void => { this.library.startExtract(item); },
        onRetryDelivery: (item: ZipItem): void => { this.library.retryArchiveDelivery(item); },
        selecting: this.library.selecting,
        selected: this.library.isSelected(row.archive.id),
        onSelect: (item: ZipItem): void => { this.library.toggleSelection(item.id); },
        onRename: (item: ZipItem): void => { this.library.startZipRename(item); },
        onExport: (item: ZipItem): void => { this.library.exportZip(item); },
        onShare: (item: ZipItem): void => { this.library.shareZip(item); },
        onDelete: (item: ZipItem): void => { this.library.confirmDeleteZip(item); }
      })
    } else if (row.kind === 'empty' && this.library.isZips()) {
      EmptyState({
        glyph: 'archive',
        heading: this.library.query.length > 0 ? '没有匹配的压缩包' : '还没有压缩包',
        body: this.library.query.length > 0 ? '换一个关键词试试。'
          : '可以从系统文件导入 ZIP，或在「发现」中把选中的图片打包。'
      })
    } else if (row.kind === 'empty') {
      EmptyState({
        glyph: 'image',
        heading: !this.library.catalogReady ? '正在读取图库信息' :
          this.hasImageFilter() ? '没有匹配的图片' : '图库还是空的',
        body: !this.library.catalogReady ? '图片文字与标签读取完成后可搜索。' :
          this.hasImageFilter() ? '换个关键词或清除筛选试试。' : '下载完成的图片会出现在这里。'
      })
    }
  }

  /** 底部渐隐：让浮动页签栏压在照片上时仍能看清图标与文字。 */
  @Builder
  private bottomFade() {
    Column()
      .width('100%')
      .height(SCREEN_INSETS.contentBottomInsetVp + Space.s24)
      .linearGradient({ angle: 180, colors: [[Color.Transparent, 0], [Palette.bg, 1]] })
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      WaterFlow({ scroller: this.library.scrollController(),
        layoutMode: WaterFlowLayoutMode.SLIDING_WINDOW, sections: this.library.flowSections }) {
        LazyForEach(this.library.flowRows, (row: LibraryFlowRow) => {
          FlowItem() {
            this.flowRow(row)
          }.width('100%')
        }, (row: LibraryFlowRow) => row.key)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .contentStartOffset(ScreenMetrics.topInsetWithHeader(SCREEN_INSETS.safeTop, Layout.tbLibraryHeader))
      .contentEndOffset(SCREEN_INSETS.contentBottomInsetVp + (this.library.selecting ? 76 : Space.s12))
      .padding({
        left: ScreenMetrics.sideInset(SCREEN_INSETS.safeLeft),
        right: ScreenMetrics.sideInset(SCREEN_INSETS.safeRight),
      })
      .onDidScroll((): void => { this.library.markScrolled(); })
      .onScrollIndex((first: number, last: number): void => { this.library.markScrolled(first); })

      this.bottomFade()

      if (this.active && this.library.selecting) {
        LibrarySelectionBar({
          library: this.library,
          bottomSpace: ScreenMetrics.tabBarSpace(SCREEN_INSETS.safeBottom) + Space.s12,
          onEditTags: (): void => { this.tagDialogOpen = true; },
          onOpenAlbums: (): void => { this.library.sheet = 'albums'; }
        })
      }

      AppSheet({
        visible: this.active && this.activeSheet().length > 0,
        initialSize: this.activeSheet() === 'organize' || this.activeSheet() === 'albums'
          || this.activeSheet() === 'trash' || this.activeSheet() === 'filter'
          ? SheetSize.MEDIUM : SheetSize.FIT_CONTENT,
        scrollSizeMode: ScrollSizeMode.CONTINUOUS,
        onWillDismiss: (action: DismissSheetAction): void => {
          if (!this.library.extractBusy) { action.dismiss(); }
        },
        onDismiss: (): void => {
          this.library.sheet = '';
          this.tagDialogOpen = false;
          this.library.closeExtract();
        }
      }) {
        this.sheetContent()
      }
    }
    .width('100%')
    .height('100%')
  }
}
