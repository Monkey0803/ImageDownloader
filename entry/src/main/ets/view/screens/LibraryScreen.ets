import { DownloadItem, ZipItem } from '../../model/Models';
import { UserAlbum } from '../../model/LibraryAsset';
import { CollectionSummary } from '../../service/CollectionGroups';
import { TrashEntry } from '../../service/TrashStore';
import { fileUri } from '@kit.CoreFileKit';
import { LibraryViewModel } from '../../viewmodel/LibraryViewModel';
import { LibraryFlowRow } from '../../viewmodel/LibraryFlowRows';
import { SettingsViewModel } from '../../viewmodel/SettingsViewModel';
import { Font, formatBytes, Layout, Palette, Radius, Space } from '../../theme/Tokens';
import { ScreenMetrics } from '../../theme/Metrics';
import { TransparentGlass } from '../../theme/TransparentGlass';
import { Glyph } from '../Icons';
import { AppSearch } from '../AppSearch';
import { AppSheet } from '../AppSheet';
import { ArchiveCard, ShotTile } from '../Cards';
import { Thumb } from '../Thumb';
import { LibraryFilterSheet } from '../LibraryFilterSheet';
import { LibraryOrganizeSheet } from '../LibraryOrganizeSheet';
import { ImageTagDialog } from '../ImageTagDialog';
import { EmptyState, IconButton, LibrarySegment, PillButton, SectionHead } from '../Widgets';
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
  @Local private albumDraft: string = '';
  @Local private albumRenameId: string = '';

  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。
  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。

  @Builder
  private searchPill() {
    AppSearch({
      placeholder: this.library.isZips() ? '搜索压缩包' : '搜索图片',
      text: this.library.query,
      pill: true,
      onChange: (value: string): void => { this.library.setQuery(value); }
    }).layoutWeight(1)
  }

  private activeOptionCount(): number {
    let count: number = this.library.sortOrder === 'newest' ? 0 : 1;
    if (this.library.collectionFilter !== '*') { count++; }
    if (this.library.albumFilter !== '*') { count++; }
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
      || this.library.collectionFilter !== '*'
      || this.library.albumFilter !== '*'
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
              onAction: (): void => { this.library.albumFilter = album.id; this.sheet = ''; } })
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
          Text(this.sheet === 'filter' ? '筛选与排序' : this.sheet === 'albums' ? '自建相册' :
            this.sheet === 'trash' ? '最近删除' : '查找与整理')
            .fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(TransparentGlass.foreground())
            .layoutWeight(1)
          IconButton({ glyph: 'close', plain: true, diameter: 36, tone: TransparentGlass.foreground(),
            accessibilityLabel: '关闭面板', onAction: (): void => { this.sheet = ''; } })
        }.width('100%')
        List() {
          ListItem() {
            if (this.sheet === 'filter') {
              LibraryFilterSheet({ library: this.library })
            } else if (this.sheet === 'albums') {
              this.albumsContent()
            } else if (this.sheet === 'trash') {
              this.trashContent()
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
      Row({ space: Space.s8 }) {
        PillButton({ label: this.library.tapSharing ? '取消碰一碰' : '碰一碰分享', variant: 'ghost', small: true,
          onAction: (): void => {
            if (this.library.tapSharing) { this.library.stopTapShare(); }
            else { this.library.startTapShare(); }
          } })
        if (this.library.tapSharing) {
          Text('轻碰接收设备').fontSize(Font.caption).fontColor(Palette.fontSecondary)
        }
      }.width('100%')
      if (!this.library.isZips()) {
        Row({ space: Space.s8 }) {
          PillButton({ label: '收藏', variant: 'ghost', small: true,
            onAction: (): void => { this.library.setSelectedFavorite(true); } })
          PillButton({ label: '取消收藏', variant: 'ghost', small: true,
            onAction: (): void => { this.library.setSelectedFavorite(false); } })
          PillButton({ label: '编辑标签', variant: 'ghost', small: true,
            onAction: (): void => { this.tagDialogOpen = true; } })
        }.width('100%')
        PillButton({ label: '加入或移出相册', variant: 'ghost', small: true,
          onAction: (): void => { this.sheet = 'albums'; } })
      }
      }.width('100%')
    }
  }

  @Builder
  private flowRow(row: LibraryFlowRow) {
    if (row.kind === 'controls') {
      this.flowControls()
    } else if (row.kind === 'heading') {
      SectionHead({ heading: row.title, meta: row.count.toString() + ' 张' })
    } else if (row.kind === 'image' && row.image !== undefined) {
      ShotTile({
        image: row.image,
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

  @Builder
  private flowControls() {
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
      if (!this.library.isZips()) {
        Scroll() {
          Row({ space: Space.s6 }) {
            PillButton({ label: this.library.favoritesOnly ? '★ 仅收藏' : '☆ 收藏', small: true,
              variant: this.library.favoritesOnly ? 'primary' : 'ghost',
              onAction: (): void => { this.library.favoritesOnly = !this.library.favoritesOnly; } })
            PillButton({ label: '相册', small: true, variant: 'ghost',
              onAction: (): void => { this.sheet = 'albums'; } })
            ForEach(this.library.collections, (group: CollectionSummary) => {
              PillButton({ label: group.name, small: true,
                variant: this.library.collectionFilter === group.id ? 'primary' : 'ghost',
                onAction: (): void => {
                  this.library.collectionFilter = this.library.collectionFilter === group.id ? '*' : group.id;
                } })
            }, (group: CollectionSummary) => group.id)
            ForEach(this.library.existingTags(), (tag: string) => {
              PillButton({ label: '#' + tag, small: true,
                variant: this.library.tagFilter === tag ? 'primary' : 'ghost',
                onAction: (): void => { this.library.tagFilter = this.library.tagFilter === tag ? '' : tag; } })
            }, (tag: string) => tag)
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      }
      Row({ space: Space.s8 }) {
        PillButton({ label: '最近删除 ' + this.library.trashEntries.length.toString(), small: true,
          variant: 'ghost', onAction: (): void => { this.library.refreshTrash(); this.sheet = 'trash'; } })
      }
      if (this.library.query.length > 0 || this.activeOptionCount() > 0 || this.library.focusedIds.length > 0) {
        Column({ space: Space.s6 }) {
          Text('当前结果 ' + (this.library.isZips() ? this.library.archives.length : this.library.images.length)
            .toString() + ' 项').fontSize(Font.caption).fontColor(Palette.fontSecondary)
          Scroll() {
            Row({ space: Space.s6 }) {
            if (this.library.query.length > 0) {
              PillButton({ label: '搜索：' + this.library.query + ' ×', small: true, variant: 'tonal',
                onAction: (): void => { this.library.setQuery(''); } })
            }
            if (this.library.collectionFilter !== '*') {
              PillButton({ label: '来源分组 ×', small: true, variant: 'tonal',
                onAction: (): void => { this.library.collectionFilter = '*'; } })
            }
            if (this.library.albumFilter !== '*') {
              PillButton({ label: '相册 ×', small: true, variant: 'tonal',
                onAction: (): void => { this.library.albumFilter = '*'; } })
            }
            if (this.library.focusedIds.length > 0) {
              PillButton({ label: '重复候选 ×', small: true, variant: 'tonal',
                onAction: (): void => { this.library.focusedIds = []; } })
            }
            if (this.library.sourceQuery.length > 0) {
              PillButton({ label: '来源网页 ×', small: true, variant: 'tonal',
                onAction: (): void => { this.library.sourceQuery = ''; } })
            }
            if (this.library.formatFilter.length > 0) {
              PillButton({ label: '格式 ×', small: true, variant: 'tonal',
                onAction: (): void => { this.library.formatFilter = ''; } })
            }
            if (this.library.favoritesOnly) {
              PillButton({ label: '仅收藏 ×', small: true, variant: 'tonal',
                onAction: (): void => { this.library.favoritesOnly = false; } })
            }
            if (this.library.tagFilter.length > 0) {
              PillButton({ label: '标签 ×', small: true, variant: 'tonal',
                onAction: (): void => { this.library.tagFilter = ''; } })
            }
            if (this.library.searchScope !== 'all') {
              PillButton({ label: '搜索范围 ×', small: true, variant: 'tonal',
                onAction: (): void => { this.library.searchScope = 'all'; } })
            }
            if (this.library.sortOrder !== 'newest') {
              PillButton({ label: '排序 ×', small: true, variant: 'tonal',
                onAction: (): void => { this.library.sortOrder = 'newest'; } })
            }
            if (this.library.density !== 2 && !this.library.isZips()) {
              PillButton({ label: '三列 ×', small: true, variant: 'tonal',
                onAction: (): void => { this.library.setDensity(2); } })
            }
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      this.selectionControls()
      this.selectionActions()

    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
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
      .contentStartOffset(ScreenMetrics.topInset(SCREEN_INSETS.safeTop, true))
      .contentEndOffset(SCREEN_INSETS.contentBottomInsetVp + Space.s12)
      .padding({
        left: ScreenMetrics.sideInset(SCREEN_INSETS.safeLeft),
        right: ScreenMetrics.sideInset(SCREEN_INSETS.safeRight),
      })
      .onDidScroll((): void => { this.library.markScrolled(); })
      .onScrollIndex((first: number, last: number): void => { this.library.markScrolled(first); })

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
          this.sheet = '';
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
