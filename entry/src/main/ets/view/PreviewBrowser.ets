import { PreviewAsset, ViewerSlide } from '../model/PreviewAsset';
import { PreviewOverlayState } from '../model/PreviewOverlayState';
import { AppSheet } from './AppSheet';
import { PreviewChrome, PreviewHeader } from './PreviewChrome';
import { PreviewCompare } from './PreviewCompare';
import { PreviewStrip, PreviewThumbnail } from './PreviewStrip';
import { PreviewTools } from './PreviewTools';
import { Space } from '../theme/Tokens';

/**
 * 预览外壳共享的交互状态。
 *
 * 两个宿主（已下载图片的 Viewer 与发现页浮层）对“控件显隐 / 缩放 / 背景 / 适配命令 /
 * 底部操作区高度”的语义完全一致，所以统一放在这里；图片内容与底部按钮仍由宿主提供。
 * 状态对象按项目现有约定用 @ObservedV2 + @Trace，通过 @BuilderParam 交给宿主读取，
 * 与 ImageSurface 的 AnimationDockActions 是同一种用法。
 */
@ObservedV2
export class PreviewShellState {
  @Trace controlsVisible: boolean = true;
  @Trace zoomed: boolean = false;
  @Trace backgroundMode: string = 'auto';
  @Trace fitCommand: string = '';
  @Trace dockHeight: number = 80;
  private fitSequence: number = 0;

  requestFit(mode: string): void {
    this.fitSequence++;
    this.fitCommand = mode + ':' + this.fitSequence.toString();
  }

  toggleControls(panels: PreviewOverlayState): void {
    this.controlsVisible = !this.controlsVisible;
    if (!this.controlsVisible) { panels.tools = false; }
  }
}

/**
 * 大图预览的共享外壳：Swiper 浏览、头部、缩略图导航、详情工具、双图对比与控件状态。
 *
 * 只负责“壳”。每种图片来源的差异通过两个 builder 注入：
 * - slideContent：每页画什么（静图 / 动图 / 实况 / 海报 / 加载态）；
 * - bottomDock：底部操作区（文件操作或下载/选择操作）及其高度测量。
 *
 * 生命周期（SystemBars、横竖屏、路由 / 浮层的进出）仍由宿主负责，避免把独立页面和
 * Index 浮层两种形态强行合并。
 */
@ComponentV2
export struct PreviewBrowser {
  @Require @Param panels: PreviewOverlayState;
  @Param foreground: boolean = true;
  @Require @Param slides: ViewerSlide[];
  @Require @Param index: number;
  @Param showTitle: boolean = true;
  @Param emphasized: boolean = false;
  @Param showCounter: boolean = true;
  @Param livePhoto: boolean = false;
  @Param detailsLabel: string = '图片详情';
  @Param detailsToggle: boolean = false;
  @Param detailsMaterialAllowed: boolean = false;
  @Param showFitInTools: boolean = false;
  @Param showBrowseScope: boolean = false;
  @Param allCount: number = 0;
  @Param selectedCount: number = 0;
  @Param selectedOnly: boolean = false;
  @Param compareAssets: PreviewAsset[] = [];

  @Event onIndexChange: (index: number) => void = (index: number): void => {};
  @Event onClose: () => void = (): void => {};
  @Event onEdit: (id: string) => void = (id: string): void => {};
  @Event onScopeChange: (selected: boolean) => void = (selected: boolean): void => {};

  @BuilderParam slideContent: (slide: ViewerSlide, slideIndex: number, state: PreviewShellState) => void =
    this.emptySlideContent;
  @BuilderParam bottomDock: (state: PreviewShellState) => void = this.emptyBottomDock;
  @BuilderParam centerOverlay: () => void = this.emptyCenterOverlay;
  @Local private shellState: PreviewShellState = new PreviewShellState();

  @Builder
  private emptySlideContent(slide: ViewerSlide, slideIndex: number, state: PreviewShellState) {}

  @Builder
  private emptyBottomDock(state: PreviewShellState) {}

  @Builder
  private emptyCenterOverlay() {}

  private current(): ViewerSlide | undefined {
    if (this.index < 0 || this.index >= this.slides.length) {
      return undefined;
    }
    return this.slides[this.index];
  }

  private currentId(): string {
    const slide: ViewerSlide | undefined = this.current();
    return slide === undefined ? '' : slide.id;
  }

  private thumbnails(): PreviewThumbnail[] {
    return this.slides.map((slide: ViewerSlide): PreviewThumbnail => {
      return { id: slide.id, src: slide.src, name: slide.name, localPath: slide.localPath };
    });
  }

  private counterText(): string {
    if (this.slides.length === 0) { return '0 / 0'; }
    return (this.index + 1).toString() + ' / ' + this.slides.length.toString();
  }

  @Monitor('index')
  private onCurrentIndexChanged(monitor: IMonitor): void {
    this.shellState.zoomed = false;
  }

  private toggleDetails(): void {
    this.panels.tools = this.detailsToggle ? !this.panels.tools : true;
  }

  @Builder
  private header() {
    PreviewHeader({
      title: this.current()?.name ?? '',
      counter: this.counterText(),
      showCounter: this.showCounter,
      showTitle: this.showTitle,
      emphasized: this.emphasized,
      showLivePhoto: this.livePhoto,
      counterActive: this.slides.length > 0,
      detailsLabel: this.detailsLabel,
      onNavigation: (): void => { this.panels.navigation = !this.panels.navigation; },
      onDetails: (): void => { this.toggleDetails(); },
      onClose: (): void => { this.onClose(); }
    })
  }

  @Builder
  private navigationStrip() {
    PreviewStrip({
      items: this.thumbnails(),
      currentIndex: this.index,
      showBrowseScope: this.showBrowseScope,
      allCount: this.allCount,
      selectedCount: this.selectedCount,
      selectedOnly: this.selectedOnly,
      onJump: (next: number): void => {
        this.panels.navigation = false;
        this.onIndexChange(next);
      },
      onScopeChange: (selected: boolean): void => { this.onScopeChange(selected); },
      onClose: (): void => { this.panels.navigation = false; }
    })
  }

  @Builder
  private toolsContent() {
    PreviewTools({
      asset: this.current() ?? new ViewerSlide(),
      backgroundMode: this.shellState.backgroundMode,
      showFitActions: this.showFitInTools,
      onFit: (mode: string): void => {
        this.panels.tools = false;
        this.shellState.requestFit(mode);
      },
      onBackground: (mode: string): void => { this.shellState.backgroundMode = mode; },
      onCompare: (): void => {
        this.panels.tools = false;
        this.panels.comparison = true;
      },
      onEdit: (id: string): void => {
        this.panels.tools = false;
        this.onEdit(id);
      },
      onClose: (): void => { this.panels.tools = false; }
    })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Swiper() {
        ForEach(this.slides, (slide: ViewerSlide, slideIndex: number) => {
          Stack({ alignContent: Alignment.Center }) {
            this.slideContent(slide, slideIndex, this.shellState)
          }
          .width('100%')
          .height('100%')
        }, (slide: ViewerSlide): string => slide.id)
      }
      .width('100%')
      .height('100%')
      .index(this.index)
      .loop(false)
      .indicator(false)
      .cachedCount(1)
      .disableSwipe(this.shellState.zoomed)
      .onChange((next: number): void => { this.onIndexChange(next); })

      if (this.shellState.controlsVisible) {
        Column() {
          Column() {
            this.header()
          }
          .width('100%')
          .padding({ bottom: this.emphasized ? Space.s24 : Space.s12 })
          .linearGradient(PreviewChrome.topGradient())
          .hitTestBehavior(HitTestMode.None)

          if (this.panels.navigation) {
            this.navigationStrip()
          }

          Column() {
            this.centerOverlay()
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ left: Space.s24, right: Space.s24 })
          .hitTestBehavior(HitTestMode.None)

          this.bottomDock(this.shellState)
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      }

      if (this.foreground && this.panels.comparison && this.current() !== undefined) {
        PreviewCompare({
          assets: this.compareAssets,
          currentId: this.currentId(),
          backgroundMode: this.shellState.backgroundMode,
          onClose: (): void => { this.panels.comparison = false; }
        })
      }

      AppSheet({
        visible: this.panels.tools && this.current() !== undefined,
        initialSize: SheetSize.MEDIUM,
        scrollSizeMode: ScrollSizeMode.CONTINUOUS,
        useMaterial: this.detailsMaterialAllowed,
        opaqueBackground: !this.detailsMaterialAllowed,
        onDismiss: (): void => { this.panels.tools = false; }
      }) {
        this.toolsContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
