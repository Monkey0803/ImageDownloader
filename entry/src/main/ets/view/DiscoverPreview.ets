import { PreviewChrome, PreviewButton } from './PreviewChrome';
import { PreviewOverlayState } from '../model/PreviewOverlayState';
import { PreviewAsset, ViewerSlide } from '../model/PreviewAsset';
import { common } from '@kit.AbilityKit';
import { PreviewOrientation } from '../service/PreviewOrientation';
import { SystemBars } from '../service/SystemBars';
import { PreviewNavigation } from '../util/PreviewNavigation';
import { PictureItem } from '../model/Models';
import { DiscoverViewModel } from '../viewmodel/DiscoverViewModel';
import { ThumbnailImages } from '../service/ThumbnailImages';
import { Font, Palette, Radius, Space } from '../theme/Tokens';
import { AnimatedPreviewImage, LivePhotoSlide, ZoomablePreviewImage } from './Cards';
import { PictureSelectionButton } from './Widgets';
import { PreviewBrowser, PreviewShellState } from './PreviewBrowser';

/** Full-screen inspection of a snapshot of the currently filtered results. */
@ComponentV2
export struct DiscoverPreview {
  private orientation: PreviewOrientation = new PreviewOrientation();
  @Require @Param panels: PreviewOverlayState;
  @Param foreground: boolean = true;
  @Require @Param discover: DiscoverViewModel;
  @Require @Param ids: string[];
  @Require @Param startId: string;
  @Event onClose: () => void = (): void => {};
  @Event onSourcePage: () => void = (): void => {};
  @Event onEdit: (id: string) => void = (id: string): void => {};
  @Local private currentIndex: number = 0;
  @Local private selectedOnly: boolean = false;
  @Local private browseIds: string[] = [];
  @Local private slides: ViewerSlide[] = [];
  @Local private posterUri: string = '';
  private posterUid: string = '';
  private posterTimer: number = -1;

  private clearPosterTimer(): void {
    if (this.posterTimer >= 0) { clearTimeout(this.posterTimer); this.posterTimer = -1; }
  }

  private hidePosterAfterReveal(uid: string): void {
    if (uid !== this.posterUid || this.posterUri.length === 0) { return; }
    this.clearPosterTimer();
    const uri: string = this.posterUri;
    this.posterTimer = setTimeout((): void => {
      this.posterTimer = -1;
      if (uid !== this.posterUid || uri !== this.posterUri) { return; }
      this.posterUri = '';
      ThumbnailImages.release(uri);
    }, 220);
  }

  private showPoster(uid: string): void {
    if (uid === this.posterUid) { return; }
    this.clearPosterTimer();
    const uri: string = this.discover.thumbnailFor(uid);
    const next: string = uri.length > 0 && ThumbnailImages.retain(uri) ? uri : '';
    if (this.posterUri.length > 0) { ThumbnailImages.release(this.posterUri); }
    this.posterUid = uid;
    this.posterUri = next;
  }

  @Monitor('foreground')
  private onForegroundChanged(monitor: IMonitor): void {
    if (!this.foreground) { this.discover.suspendInspection(); }
    else if (this.discover.previewUri.length === 0 && this.discover.previewFailure !== 'cancelled') { this.inspectCurrent(); }
  }

  @Monitor('discover.selectedTotal')
  private onSelectionChanged(monitor: IMonitor): void {
    if (this.selectedOnly) { this.refreshRange(); }
  }

  @Monitor('discover.previewUri', 'discover.previewLocalPath', 'discover.previewMotionPath',
    'discover.previewLocalAnimated', 'discover.previewLoading', 'discover.previewFailure')
  private onPreviewChanged(monitor: IMonitor): void {
    this.refreshSlides();
  }

  private selectedIds(): string[] {
    return this.ids.filter((id: string): boolean =>
      this.discover.pictures.some((item: PictureItem): boolean => item.uid === id && item.selected));
  }

  private buildSlides(): ViewerSlide[] {
    return this.browseIds.map((uid: string): ViewerSlide => {
      const slide: ViewerSlide = new ViewerSlide();
      slide.id = uid;
      const item: PictureItem | undefined = this.discover.pictures.find((value: PictureItem): boolean => value.uid === uid);
      if (item === undefined) { return slide; }
      const asset: PreviewAsset = this.discover.previewAsset(item);
      const inspected: boolean = this.discover.inspectedPicture?.uid === uid;
      slide.libraryId = asset.libraryId;
      slide.src = inspected && this.discover.previewUri.length > 0 ? this.discover.previewUri : asset.src;
      slide.localPath = inspected ? this.discover.previewLocalPath : asset.localPath;
      slide.name = asset.name;
      slide.url = asset.url;
      slide.sourcePage = asset.sourcePage;
      slide.bytes = asset.bytes;
      slide.downloaded = asset.downloaded;
      slide.downloadedAt = asset.downloadedAt;
      slide.width = asset.width;
      slide.height = asset.height;
      slide.animated = inspected ? (this.discover.previewLocalAnimated || asset.animated) : asset.animated;
      slide.label = item.kind === 'livephoto' ? '实况' : 'IMG';
      slide.stillPath = inspected && this.discover.previewMotionPath.length > 0 ? this.discover.previewLocalPath : '';
      slide.motionPath = inspected ? this.discover.previewMotionPath : '';
      return slide;
    });
  }

  private refreshSlides(): void {
    this.slides = this.buildSlides();
  }

  private refreshRange(): void {
    const current: string = this.browseIds[this.currentIndex] ?? '';
    const next: string[] = this.selectedOnly ? this.selectedIds() : this.ids.slice();
    const index: number = PreviewNavigation.index(next, current, this.currentIndex);
    this.browseIds = next;
    this.currentIndex = index;
    this.panels.navigation = false;
    if (next.length === 0) {
      this.showPoster('');
      this.panels.tools = false;
      this.discover.closeInspection(true);
    } else if (next[index] !== current) {
      this.panels.tools = false;
      this.showPoster(next[index]);
      this.inspectCurrent();
    }
    this.refreshSlides();
  }

  private setScope(selected: boolean): void {
    if (selected === this.selectedOnly) { return; }
    this.selectedOnly = selected;
    this.refreshRange();
  }

  private toggleCurrentSelection(): void {
    const item: PictureItem | undefined = this.current();
    if (item === undefined) { return; }
    this.discover.togglePicture(item.uid);
    if (this.selectedOnly) { this.refreshRange(); }
  }

  aboutToAppear(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.orientation.enter(context);
    SystemBars.enter('discover-preview', context);
    this.browseIds = this.ids.slice();
    const at: number = this.browseIds.indexOf(this.startId);
    this.currentIndex = at >= 0 ? at : 0;
    this.showPoster(this.browseIds[this.currentIndex] ?? '');
    this.inspectCurrent();
    this.refreshSlides();
  }

  aboutToDisappear(): void {
    this.showPoster('');
    this.orientation.leave();
    SystemBars.leave('discover-preview', this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

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
    this.currentIndex = next;
    this.panels.tools = false;
    this.showPoster(this.browseIds[next]);
    this.inspectCurrent();
    this.refreshSlides();
  }

  private hasSourcePage(item: PictureItem): boolean {
    return this.discover.pageUrl.startsWith('http') && this.discover.pageUrl !== item.url;
  }

  private canPreviewStill(item: PictureItem): boolean {
    return item.kind === 'image' || (item.kind === 'livephoto' && item.motionUrl.length > 0);
  }

  @Builder
  private unavailableState(item: PictureItem) {
    Column({ space: Space.s12 }) {
      if (this.discover.previewLoading) {
        LoadingProgress().width(28).height(28).color(Palette.white)
      }
      Text(this.discover.previewLoading ? this.discover.previewLoadTitle
        : this.discover.previewFailure === 'cancelled' ? '已取消加载'
          : this.canPreviewStill(item) ? '暂时无法预览' : '下载后查看实况照片')
        .fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(Palette.white)
        .textAlign(TextAlign.Center)
      Text(this.discover.previewLoading ? this.discover.previewLoadDetail
        : item.kind === 'livephoto' && !this.canPreviewStill(item)
          ? this.discover.previewMessage.length > 0 ? this.discover.previewMessage
            : '实况照片包下载后可在图库播放。'
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
      if (!this.discover.previewLoading && this.canPreviewStill(item)) {
        Text('预览失败不会更改原图下载地址。')
          .fontSize(Font.aux).fontColor('#99FFFFFF').textAlign(TextAlign.Center)
      }
      if (!this.discover.previewLoading && this.canPreviewStill(item)) {
        PreviewButton({ label: '重试预览',
          variant: ['size', 'decode'].includes(this.discover.previewFailure) ? 'ghost' : 'primary',
          onAction: (): void => { this.inspectCurrent(true); } })
      }
      if (!this.discover.previewLoading && !this.discover.previewFromLocal) {
        PreviewButton({ label: this.discover.downloadState(item) === 'active' ? '已加入下载任务'
          : this.discover.downloadState(item) === 'completed' ? '重新下载原文件' : '下载原文件',
          variant: ['size', 'decode'].includes(this.discover.previewFailure) ? 'primary' : 'tonal',
          active: this.discover.downloadState(item) !== 'active',
          onAction: (): void => { this.discover.requestInspectedDownload(); } })
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

  private comparisonAssets(): PreviewAsset[] {
    return this.discover.pictures.filter((item: PictureItem): boolean => this.browseIds.includes(item.uid))
      .map((item: PictureItem): PreviewAsset => this.discover.previewAsset(item));
  }

  private detailsMaterialAllowed(): boolean {
    const item: PictureItem | undefined = this.current();
    if (item === undefined || item.kind === 'livephoto') { return false; }
    const asset: PreviewAsset = this.discover.previewAsset(item);
    if (asset.downloaded) { return !asset.animated; }
    // 远程图完成预览解码后才知道是否为动图；静态图无需先下载即可显示玻璃面板。
    return this.discover.inspectedPicture?.uid === item.uid
      && this.discover.previewUri.length > 0
      && !this.discover.previewLocalAnimated
      && this.discover.previewMotionPath.length === 0;
  }

  @Builder
  private centerOverlay() {
    if (this.browseIds.length === 0) {
      Text('还没有选中的图片').fontSize(Font.body).fontColor(Palette.white)
      PreviewButton({ label: '浏览全部图片', variant: 'tonal',
        onAction: (): void => { this.setScope(false); } })
    }
    if (this.current() !== undefined) {
      if (!this.panels.tools && this.discover.previewUri.length === 0
        && (!this.discover.previewLoading || this.posterUri.length === 0)) {
        this.unavailableState(this.current()!)
      }
    }
  }

  @Builder
  private slideContent(slide: ViewerSlide, slideIndex: number, state: PreviewShellState) {
    Stack({ alignContent: Alignment.Center }) {
      if (slideIndex === this.currentIndex && this.posterUid === slide.id && this.posterUri.length > 0) {
        Image(this.posterUri).width('100%').height('100%').objectFit(ImageFit.Contain)
          .hitTestBehavior(HitTestMode.None)
          .onError((): void => { if (this.posterUid === slide.id) { this.showPoster(''); } })
      }
      if (slideIndex === this.currentIndex && this.discover.previewUri.length > 0) {
        if (this.discover.previewMotionPath.length > 0) {
          LivePhotoSlide({ stillFile: this.discover.previewLocalPath,
            motionFile: this.discover.previewMotionPath,
            posterUri: this.posterUid === slide.id ? this.posterUri : '',
            onReady: (): void => { this.hidePosterAfterReveal(slide.id); } })
        } else if (!this.discover.previewLocalAnimated) {
          ZoomablePreviewImage({ imageId: slide.id, path: this.discover.previewLocalPath,
            readingKey: 'web:' + this.discover.pageUrl.length.toString() + ':' + this.discover.pageUrl
              + (slide.url.length > 0 ? slide.url : slide.id),
            allowDismiss: !this.panels.tools && !this.panels.navigation, onDismiss: this.onClose,
            fallbackUri: this.discover.previewUri,
            posterUri: this.posterUid === slide.id ? this.posterUri : '',
            active: this.foreground && slideIndex === this.currentIndex && !this.panels.comparison,
            backgroundMode: state.backgroundMode,
            controlsVisible: state.controlsVisible && !this.panels.tools,
            controlsBottom: state.dockHeight,
            showFitControls: false, compactFitControls: true, fitCommand: state.fitCommand,
            onTapImage: (): void => { state.toggleControls(this.panels); },
            onReady: (): void => { this.hidePosterAfterReveal(slide.id); },
            onZoomChange: (value: boolean): void => { state.zoomed = value; } })
            .width('100%').height('100%')
        } else {
          AnimatedPreviewImage({ onTapImage: (): void => { state.toggleControls(this.panels); },
            onReady: (): void => { this.hidePosterAfterReveal(slide.id); },
            src: this.discover.previewUri, localPath: this.discover.previewLocalPath,
            posterUri: this.posterUid === slide.id ? this.posterUri : '',
            name: this.current()?.name ?? '图片',
            controlsVisible: state.controlsVisible && !this.panels.tools,
            controlsBottom: state.dockHeight,
            active: this.foreground && !this.panels.comparison,
            backgroundMode: state.backgroundMode,
            allowDismiss: !this.panels.tools && !this.panels.navigation, onDismiss: this.onClose })
            .width('100%').height('100%')
        }
      }
    }
    .width('100%').height('100%')
    .parallelGesture(TapGesture({ count: 1 }).onAction((): void => {
      if (this.discover.previewUri.length === 0) {
        state.toggleControls(this.panels);
      }
    }))
  }

  @Builder
  private bottomDock(state: PreviewShellState) {
    Column({ space: Space.s8 }) {
      if (this.current() !== undefined) {
        Row({ space: Space.s16 }) {
          PreviewButton({ label: this.discover.downloadState(this.current()!) === 'active' ? '已加入任务'
            : this.discover.downloadState(this.current()!) === 'completed' ? '重新下载' : '下载当前',
            icon: 'download', small: true,
            variant: this.discover.downloadState(this.current()!) === 'active' ? 'tonal' : 'primary',
            active: this.discover.downloadState(this.current()!) !== 'active',
            onAction: (): void => { this.discover.requestInspectedDownload(); } })
          Row({ space: Space.s6 }) {
            PictureSelectionButton({ selected: this.current()!.selected, diameter: 44,
              onAction: (): void => { this.toggleCurrentSelection(); } })
            Text(this.current()!.selected ? '已选入批量' : '选入批量')
              .fontSize(Font.caption).fontColor(Palette.white)
              .onClick((): void => { this.toggleCurrentSelection(); })
          }.alignItems(VerticalAlign.Center)
        }.width('100%').justifyContent(FlexAlign.Center)
        if (this.discover.previewEligibleCount(this.ids) > 0) {
          PreviewButton({ label: (this.discover.mode === 'zip' ? '打包已选 ' : '下载已选 ')
            + this.discover.previewEligibleCount(this.ids).toString(), small: true, variant: 'tonal',
            onAction: (): void => { this.discover.downloadPreviewSelection(this.ids); } })
        } else if (this.selectedIds().length > 0) {
          Text('所选图片已下载或正在下载')
            .fontSize(Font.aux).fontColor('#B3FFFFFF')
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Center)
      .padding({ top: Space.s12, bottom: Space.s12 })
      .linearGradient(PreviewChrome.bottomGradient())
      .hitTestBehavior(HitTestMode.None)
      .onSizeChange((oldSize: SizeOptions, newSize: SizeOptions): void => {
        state.dockHeight = Number(newSize.height);
      })
  }

  build() {
    PreviewBrowser({
      panels: this.panels,
      foreground: this.foreground,
      slides: this.slides,
      index: this.currentIndex,
      showTitle: false,
      emphasized: false,
      showCounter: true,
      livePhoto: this.current()?.kind === 'livephoto'
        || (this.discover.inspectedPicture?.uid === this.current()?.uid && this.discover.previewLocalAnimated),
      detailsLabel: '图片详情',
      detailsToggle: true,
      detailsMaterialAllowed: this.detailsMaterialAllowed(),
      showFitInTools: this.discover.previewUri.length > 0 && !this.discover.previewLocalAnimated
        && this.discover.previewMotionPath.length === 0,
      showBrowseScope: true,
      allCount: this.ids.length,
      selectedCount: this.selectedIds().length,
      selectedOnly: this.selectedOnly,
      compareAssets: this.comparisonAssets(),
      onIndexChange: (next: number): void => { this.pageChanged(next); },
      onClose: (): void => { this.onClose(); },
      onEdit: (id: string): void => { this.onEdit(id); },
      onScopeChange: (selected: boolean): void => { this.setScope(selected); },
      slideContent: (slide: ViewerSlide, slideIndex: number, state: PreviewShellState): void => {
        this.slideContent(slide, slideIndex, state);
      },
      bottomDock: (state: PreviewShellState): void => { this.bottomDock(state); },
      centerOverlay: (): void => { this.centerOverlay(); }
    })
  }
}
