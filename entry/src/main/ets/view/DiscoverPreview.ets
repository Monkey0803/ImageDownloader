import { PreviewButton } from './PreviewChrome';
import { PreviewOverlayState } from '../model/PreviewOverlayState';
import { PreviewAsset } from '../model/PreviewAsset';
import { DownloadItem } from '../model/Models';
import { DownloadStore } from '../service/DownloadStore';
import { PreviewOrientation } from '../service/PreviewOrientation';
import { fileUri } from '@kit.CoreFileKit';
import { PreviewTools } from './PreviewTools';
import { LIBRARY_CATALOG } from '../service/LibraryCatalog';
import { PreviewCompare } from './PreviewCompare';
import { PreviewNavigation } from '../util/PreviewNavigation';
import { PictureItem } from '../model/Models';
import { DiscoverViewModel } from '../viewmodel/DiscoverViewModel';
import { Font, Palette, Radius, Space } from '../theme/Tokens';
import { SheetStyle } from '../theme/SheetStyle';
import { SCREEN_INSETS } from '../theme/Metrics';
import { AnimatedPreviewImage, PreviewStrip, PreviewThumbnail, ZoomablePreviewImage } from './Cards';
import { IconButton, PictureSelectionButton } from './Widgets';

/** Full-screen inspection of a snapshot of the currently filtered results. */
@ComponentV2
export struct DiscoverPreview {
  private orientation: PreviewOrientation = new PreviewOrientation();
  private sheetMaterial: SystemUiMaterial | undefined = SheetStyle.dialogMaterial();
  @Require @Param panels: PreviewOverlayState;
  @Param foreground: boolean = true;
  @Require @Param discover: DiscoverViewModel;
  @Require @Param ids: string[];
  @Require @Param startId: string;
  @Event onClose: () => void = (): void => {};
  @Event onSourcePage: () => void = (): void => {};
  @Event onEdit: (id: string) => void = (id: string): void => {};
  @Local private currentIndex: number = 0;
  @Local private controlsShown: boolean = true;
  @Local private zoomed: boolean = false;
  @Local private actionDockHeight: number = 80;
  @Local private backgroundMode: string = 'auto';

  @Local private selectedOnly: boolean = false;
  @Local private browseIds: string[] = [];

  @Monitor('foreground')
  private onForegroundChanged(monitor: IMonitor): void {
    if (!this.foreground) { this.discover.suspendInspection(); }
    else if (this.discover.previewUri.length === 0 && this.discover.previewFailure !== 'cancelled') { this.inspectCurrent(); }
  }

  @Monitor('discover.selectedTotal')
  private onSelectionChanged(monitor: IMonitor): void {
    if (this.selectedOnly) { this.refreshRange(); }
  }

  private selectedIds(): string[] {
    return this.ids.filter((id: string): boolean =>
      this.discover.pictures.some((item: PictureItem): boolean => item.uid === id && item.selected));
  }

  private thumbnails(): PreviewThumbnail[] {
    return this.browseIds.map((id: string): PreviewThumbnail => {
      const item: PictureItem | undefined = this.discover.pictures.find((item: PictureItem): boolean => item.uid === id);
      const asset: PreviewAsset = item !== undefined ? this.asset(item) : new PreviewAsset();
      return { id: id, name: asset.name, src: asset.src, localPath: asset.localPath };
    });
  }

  private refreshRange(): void {
    const current: string = this.browseIds[this.currentIndex] ?? '';
    const next: string[] = this.selectedOnly ? this.selectedIds() : this.ids.slice();
    const index: number = PreviewNavigation.index(next, current, this.currentIndex);
    this.browseIds = next;
    this.currentIndex = index;
    this.panels.navigation = false;
    if (next.length === 0) {
      this.zoomed = false;
      this.panels.tools = false;
      this.discover.closeInspection(true);
    } else if (next[index] !== current) {
      this.zoomed = false;
      this.panels.tools = false;
      this.inspectCurrent();
    }
  }

  private setScope(selected: boolean): void {
    if (selected === this.selectedOnly) { return; }
    this.selectedOnly = selected;
    this.refreshRange();
  }

  private toggleControls(): void {
    this.controlsShown = !this.controlsShown;
    if (!this.controlsShown) { this.panels.tools = false; }
  }

  aboutToAppear(): void {
    this.orientation.enter(DownloadStore.context);
    this.browseIds = this.ids.slice();
    const at: number = this.browseIds.indexOf(this.startId);
    this.currentIndex = at >= 0 ? at : 0;
    this.inspectCurrent();
  }

  aboutToDisappear(): void { this.orientation.leave(); }

  private current(): PictureItem | undefined {
    const uid: string = this.browseIds[this.currentIndex] ?? '';
    return this.discover.pictures.find((item: PictureItem): boolean => item.uid === uid);
  }

  private inspectCurrent(force: boolean = false): void {
    const uid: string = this.browseIds[this.currentIndex] ?? '';
    if (uid.length > 0) {
      this.discover.inspect(uid, force);
    }
  }

  private pageChanged(next: number): void {
    if (next < 0 || next >= this.browseIds.length) { return; }
    if (next === this.currentIndex && this.discover.inspectedPicture?.uid === this.browseIds[next]) { return; }
    this.zoomed = false;
    this.currentIndex = next;
    this.panels.tools = false;
    this.inspectCurrent();
  }

  private hasSourcePage(item: PictureItem): boolean {
    return this.discover.pageUrl.startsWith('http') && this.discover.pageUrl !== item.url;
  }

  @Builder
  private unavailableState(item: PictureItem) {
    Column({ space: Space.s12 }) {
      if (this.discover.previewLoading) {
        LoadingProgress().width(28).height(28).color(Palette.white)
      }
      Text(this.discover.previewLoading ? this.discover.previewLoadTitle
        : this.discover.previewFailure === 'cancelled' ? '已取消加载' : item.kind === 'livephoto' ? (this.discover.previewFromLocal
          ? '实况照片已下载' : '下载后查看实况照片') : '暂时无法预览')
        .fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(Palette.white)
        .textAlign(TextAlign.Center)
      Text(this.discover.previewLoading ? this.discover.previewLoadDetail
        : item.kind === 'livephoto' ? (this.discover.previewFromLocal
          ? this.discover.previewMessage : '实况照片包下载后可在图库播放。')
          : this.discover.previewMessage.length > 0 ? this.discover.previewMessage
            : '可重试预览或查看来源页。')
        .fontSize(Font.caption).fontColor('#CCFFFFFF').textAlign(TextAlign.Center)
        .width('100%')
      if (this.discover.previewLoading && this.discover.previewPhase === 'receiving' && this.discover.previewTotal > 0) {
        Progress({ value: this.discover.previewPercent, total: 100, type: ProgressType.Linear })
          .width('100%').color('#409CFF').backgroundColor('#44FFFFFF')
          .accessibilityText('加载进度 ' + this.discover.previewPercent.toString() + '%')
        Text(this.discover.previewPercent.toString() + '%').fontSize(Font.aux).fontColor(Palette.white)
      }
      if (this.discover.previewLoading) {
        PreviewButton({ label: '取消加载', variant: 'tonal', onAction: (): void => { this.discover.cancelPreviewLoading(); } })
      }
      if (!this.discover.previewLoading && item.kind === 'image') {
        Text('预览失败不会更改原图下载地址。')
          .fontSize(Font.aux).fontColor('#99FFFFFF').textAlign(TextAlign.Center)
      }
      if (!this.discover.previewLoading && item.kind === 'image') {
        PreviewButton({ label: '重试预览',
          variant: ['size', 'decode'].includes(this.discover.previewFailure) ? 'ghost' : 'primary',
          onAction: (): void => { this.inspectCurrent(true); } })
      }
      if (!this.discover.previewLoading && !this.discover.previewFromLocal) {
        PreviewButton({ label: this.discover.previewDownloadQueued ? '已加入下载任务' : '下载原文件',
          variant: ['size', 'decode'].includes(this.discover.previewFailure) ? 'primary' : 'tonal',
          active: !this.discover.previewDownloadQueued,
          onAction: (): void => { this.discover.downloadInspected(); } })
      }
      if (!this.discover.previewLoading && this.hasSourcePage(item)) {
        PreviewButton({ label: this.discover.previewFailure === 'login' ? '前往来源页确认登录' : '查看来源页', variant: 'tonal',
          onAction: (): void => { this.onSourcePage(); } })
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .constraintSize({ maxWidth: 340 })
    .padding(Space.s20)
    .borderRadius(Radius.r8)
    .backgroundColor('#E6222222')
    .hitTestBehavior(HitTestMode.Default)
  }

  private asset(item: PictureItem): PreviewAsset {
    const result: PreviewAsset = new PreviewAsset();
    result.id = item.uid;
    result.name = item.name;
    result.url = item.url;
    result.src = item.url;
    result.sourcePage = this.discover.pageUrl;
    result.width = item.width;
    result.height = item.height;
    const local: DownloadItem | undefined = DownloadStore.downloads.find((value: DownloadItem): boolean =>
      value.url === item.url && value.kind === item.kind && value.status === 'completed' && DownloadStore.exists(value.path));
    if (local !== undefined) {
      result.localPath = item.kind === 'livephoto' ? local.stillPath : local.path;
      result.src = result.localPath.length > 0 ? fileUri.getUriFromPath(result.localPath) : '';
      result.bytes = local.size;
      result.downloaded = true;
      result.downloadedAt = local.finishedAt;
      result.animated = local.animated;
      result.libraryId = LIBRARY_CATALOG.assetForPreview(DownloadStore.downloads, item.url, item.kind);
    }
    if (item.uid === this.discover.inspectedPicture?.uid) {
      result.src = this.discover.previewUri || item.url;
      result.localPath = this.discover.previewLocalPath;
      result.bytes = this.discover.inspectionBytes;
      if (local === undefined || result.localPath !== (item.kind === 'livephoto' ? local.stillPath : local.path)) {
        result.libraryId = '';
      }
    }
    return result;
  }

  private comparisonAssets(): PreviewAsset[] {
    return this.discover.pictures.filter((item: PictureItem): boolean => this.browseIds.includes(item.uid))
      .map((item: PictureItem): PreviewAsset => this.asset(item));
  }

  @Builder
  private toolsContent() {
    if (this.current() !== undefined) {
      PreviewTools({ asset: this.asset(this.current()!), backgroundMode: this.backgroundMode,
        onEdit: (id: string): void => { this.panels.tools = false; this.onEdit(id); },
        onBackground: (mode: string): void => { this.backgroundMode = mode; },
        onCompare: (): void => { this.panels.tools = false; this.panels.comparison = true; },
        onClose: (): void => { this.panels.tools = false; } })
    }
  }

  private detailsMaterialAllowed(): boolean {
    const item: PictureItem | undefined = this.current();
    if (item === undefined || item.kind === 'livephoto') { return false; }
    // 远程预览可能尚未获得真实动图元数据；仅已落盘且确认为静态的图片启用材质。
    const asset: PreviewAsset = this.asset(item);
    return asset.downloaded && !asset.animated;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Swiper() {
        ForEach(this.browseIds, (uid: string, slideIndex: number) => {
          Stack({ alignContent: Alignment.Center }) {
            if (slideIndex === this.currentIndex && this.discover.previewUri.length > 0) {
              if (!this.discover.previewLocalAnimated) {
                ZoomablePreviewImage({ imageId: uid, path: this.discover.previewLocalPath,
                  readingKey: 'web:' + this.discover.pageUrl.length.toString() + ':' + this.discover.pageUrl + (this.current()?.url ?? uid),
                  allowDismiss: !this.panels.tools && !this.panels.navigation, onDismiss: this.onClose,
                  fallbackUri: this.discover.previewUri,
                  active: this.foreground && slideIndex === this.currentIndex && !this.panels.comparison, backgroundMode: this.backgroundMode, controlsVisible: this.controlsShown && !this.panels.tools, controlsBottom: this.actionDockHeight,
                  onTapImage: (): void => { this.toggleControls(); },
                  onZoomChange: (value: boolean): void => { this.zoomed = value; } })
                  .width('100%').height('100%')
              } else {
                AnimatedPreviewImage({ onTapImage: (): void => { this.toggleControls(); }, src: this.discover.previewUri, localPath: this.discover.previewLocalPath, name: this.current()?.name ?? '图片', controlsVisible: this.controlsShown && !this.panels.tools, controlsBottom: this.actionDockHeight, active: this.foreground && !this.panels.comparison, backgroundMode: this.backgroundMode,
                  allowDismiss: !this.panels.tools && !this.panels.navigation, onDismiss: this.onClose })
                  .width('100%').height('100%')
              }
            }
          }
          .width('100%').height('100%')
          .parallelGesture(TapGesture({ count: 1 }).onAction((): void => {
            if (this.discover.previewUri.length === 0) {
              this.toggleControls();
            }
          }))
        }, (uid: string) => uid)
      }
      .width('100%').height('100%')
      .index(this.currentIndex).loop(false).indicator(false).cachedCount(1)
      .disableSwipe(this.zoomed)
      .onChange((next: number): void => { this.pageChanged(next); })

      if (this.controlsShown) {
        Column() {
          Row({ space: Space.s8 }) {
            Text(this.current()?.name ?? '')
              .fontSize(Font.body).fontColor(Palette.white).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Text((this.browseIds.length > 0 ? this.currentIndex + 1 : 0).toString() + ' / ' + this.browseIds.length.toString())
              .fontSize(Font.aux).fontColor(Palette.white).padding(Space.s8).constraintSize({ minHeight: 40 })
              .accessibilityText('打开缩略图导航')
              .onClick((): void => { if (this.browseIds.length > 0) { this.panels.navigation = !this.panels.navigation; } })
            IconButton({ glyph: 'info', glyphSize: 20, diameter: 40, plain: true,
              tone: Palette.white, accessibilityLabel: '图片详情',
              onAction: (): void => { this.panels.tools = !this.panels.tools; } })
            IconButton({ glyph: 'close', glyphSize: 20, diameter: 40, plain: true,
              tone: Palette.white, accessibilityLabel: '关闭图片预览', onAction: this.onClose })
          }
          .width('100%').padding({ left: Space.s16, right: Space.s16,
            top: SCREEN_INSETS.safeTop + Space.s12, bottom: Space.s12 })
          .backgroundColor('#99000000')
          Row({ space: Space.s8 }) {
            PreviewButton({ label: '全部 ' + this.ids.length.toString(), small: true,
              variant: !this.selectedOnly ? 'primary' : 'tonal', onAction: (): void => { this.setScope(false); } })
            PreviewButton({ label: '已选 ' + this.selectedIds().length.toString(), small: true,
              variant: this.selectedOnly ? 'primary' : 'tonal', onAction: (): void => { this.setScope(true); } })
          }.width('100%').justifyContent(FlexAlign.Center).padding(Space.s8).backgroundColor('#99000000')
          if (this.panels.navigation) {
            PreviewStrip({ items: this.thumbnails(), currentIndex: this.currentIndex,
              onJump: (next: number): void => { this.panels.navigation = false; this.pageChanged(next); },
              onClose: (): void => { this.panels.navigation = false; } })
          }
          Column() {
            if (this.browseIds.length === 0) {
              Text('还没有选中的图片').fontSize(Font.body).fontColor(Palette.white)
              PreviewButton({ label: '浏览全部图片', variant: 'tonal',
                onAction: (): void => { this.setScope(false); } })
            }
            if (this.current() !== undefined) {
              if (!this.panels.tools && this.discover.previewUri.length === 0) {
                this.unavailableState(this.current()!)
              }
            }
          }
          .width('100%').layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ left: Space.s24, right: Space.s24 })
          .hitTestBehavior(HitTestMode.None)
          Column() {
          if (this.current() !== undefined) {
            Row({ space: Space.s12 }) {
              PreviewButton({ label: this.discover.previewFromLocal ? '已下载'
                : this.discover.previewDownloadQueued ? '已加入任务' : '下载当前',
                icon: 'download', small: true, variant: 'tonal',
                active: !this.discover.previewFromLocal && !this.discover.previewDownloadQueued,
                onAction: (): void => { this.discover.downloadInspected(); } })
              PictureSelectionButton({ selected: this.current()!.selected, diameter: 44,
                onAction: (): void => {
                  const item: PictureItem | undefined = this.current();
                  if (item !== undefined) {
                    this.discover.togglePicture(item.uid);
                    if (this.selectedOnly) { this.refreshRange(); }
                  }
                } })
              if (this.selectedIds().length > 0) {
                PreviewButton({ label: (this.discover.mode === 'zip' ? '打包已选 ' : '下载已选 ')
                  + this.selectedIds().length.toString(), small: true, variant: 'tonal',
                  onAction: (): void => { this.discover.downloadPreviewSelection(this.ids); } })
              }
            }.width('100%').justifyContent(FlexAlign.Center).backgroundColor('#99000000')
          }
          Row().height(SCREEN_INSETS.safeBottom + Space.s16).width('100%').backgroundColor('#99000000')
          }.width('100%').padding({ top: 8 }).backgroundColor('#E61C1C1E')
            .onSizeChange((oldSize: SizeOptions, newSize: SizeOptions): void => {
              this.actionDockHeight = Number(newSize.height);
            })
        }
        .width('100%').height('100%')
        .hitTestBehavior(HitTestMode.None)
      }
      if (this.foreground && this.panels.comparison && this.current() !== undefined) {
        PreviewCompare({ assets: this.comparisonAssets(), currentId: this.current()!.uid, backgroundMode: this.backgroundMode,
          onClose: (): void => { this.panels.comparison = false; } })
      }
    }
    .width('100%').height('100%')
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
