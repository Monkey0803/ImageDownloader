import { PreviewOverlayState } from '../model/PreviewOverlayState';
import { PREVIEW_LIFECYCLE } from '../model/PreviewLifecycle';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { HdsNavDestination, HdsNavigation, HdsNavigationTitleBarStyle, HdsTabs,
  HdsTabsController, HdsTabsFloatingStyle, HdsNavigationTitleBarOptions, HdsNavigationTitleMode,
  TitleBarContentOptions,
  TitleBarStyleOptions, TextStyleMode, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { DownloadItem } from '../model/Models';
import { TAB_DISCOVER, TAB_LIBRARY, TAB_TASKS, TAB_SETTINGS } from '../model/Navigation';
import { DownloadStore } from '../service/DownloadStore';
import { LIBRARY_CATALOG } from '../service/LibraryCatalog';
import { UiPort } from '../service/UiPort';
import { ShareInbox } from '../service/ShareInbox';
import { WidgetLaunch } from '../service/WidgetLaunch';
import { DiscoverViewModel } from '../viewmodel/DiscoverViewModel';
import { DeviceViewModel } from '../viewmodel/DeviceViewModel';
import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { SettingsViewModel } from '../viewmodel/SettingsViewModel';
import { TasksViewModel } from '../viewmodel/TasksViewModel';
import { Font, Layout, Palette, Radius, Space, formatBytes } from '../theme/Tokens';
import { ScreenMetrics } from '../theme/Metrics';
import { SheetStyle } from '../theme/SheetStyle';
import { AppSheet } from '../view/AppSheet';
import { BATCH_PAGE_NAME, BatchPagePanel } from '../view/BatchPagePanel';
import { DiscoverTitleBar } from '../view/DiscoverTitleBar';
import { ToastLatch } from '../util/Toast';
import { DiscoverScreen } from '../view/screens/DiscoverScreen';
import { BrowserLibrarySheet } from '../view/BrowserLibrarySheet';
import { DiscoverPreview } from '../view/DiscoverPreview';
import { LibraryScreen } from '../view/screens/LibraryScreen';
import { SettingsScreen } from '../view/screens/SettingsScreen';
import { TasksScreen } from '../view/screens/TasksScreen';
import { GripChip, PrivacyVeil, SelectionDock, ToTopButton } from '../view/shell/Chrome';
import { Glyph } from '../view/Icons';
import { RenameDialog, TABS, TabItem, ToastPill } from '../view/Widgets';
import { SCREEN_INSETS } from '../theme/Metrics';
import { MaterialSupport } from '../service/MaterialSupport';
import { HdsShellPlan, hdsShellPlan } from '../util/HdsShellPolicy';

/**
 * 应用外壳（Index）。
 *
 * 这里**只做四件事**，页面内容全部交给四个 Screen 组件：
 *
 * 1. **壳层状态**：当前页签、Toast 文案与它的定时器、页面是否在前台；
 * 2. **装配 ViewModel**：五个 ViewModel 在这里各建一次，并共用一个 `UiPort`
 *    （提示、Context、推预览页、切页签、确认框的唯一出口，见 service/UiPort.ets）；
 * 3. **数据同步**：订阅 `DownloadStore` 的变更，把 ViewModel 拉回一致；
 * 4. **浮层与页签栏**：返回顶部按钮、选择条、握姿胶囊、防窥遮罩、Toast、改名弹窗 ——
 *    这些定位在滚动内容之外，只能由壳来画。
 *
 * 拆分前这个文件有 2393 行，四个页面加全部业务逻辑都长在同一个 `struct` 里；
 * 现在它只负责「谁在什么时候显示」。
 */
@Entry
@ComponentV2
struct Index {
  private stack: NavPathStack = new NavPathStack();
  private tabs: HdsTabsController = new HdsTabsController();
  private tabsReady: boolean = false;
  private settingsScroller: Scroller = new Scroller();
  @Local private hdsSupported: boolean = false;
  /** 页面是否在前台：图库预览页盖在上面时不要把这边的提示取走。 */
  @Local private pageVisible: boolean = true;
  /** 提示的定时器与「销毁后不再弹」的守卫都在这里，见 util/Toast.ets。 */
  private toast: ToastLatch = new ToastLatch();
  /**
   * 五个 ArkUI V2 ViewModel 由壳层持有，并通过 @Param 传给子页面。
   * @ObservedV2 / @Trace 负责把业务状态变化同步到这些页面。
   */
  @Local private discover: DiscoverViewModel = new DiscoverViewModel();
  @Local private tasks: TasksViewModel = new TasksViewModel();
  @Local private library: LibraryViewModel = new LibraryViewModel();
  @Local private settings: SettingsViewModel = new SettingsViewModel();
  @Local private device: DeviceViewModel = new DeviceViewModel();

  @Local private currentTab: number = TAB_DISCOVER;
  /** 浏览扫描是发现页首页；图片结果从“查看图片”进入。 */
  @Local private browserOpen: boolean = true;
  @Local private previewIds: string[] = [];
  @Local private previewStartId: string = '';
  @Local private previewPanels: PreviewOverlayState = new PreviewOverlayState();
  @Local private previewOpen: boolean = false;
  @Local private notice: string = '';

  @Monitor('discover.batchOpen')
  private batchRouteChanged(monitor: IMonitor): void {
    if (this.discover.batchOpen && this.stack.size() === 0) {
      this.stack.pushPath({ name: BATCH_PAGE_NAME });
    } else if (!this.discover.batchOpen && this.stack.size() > 0) {
      this.stack.pop();
    }
  }

  /**
   * 商店的刷新回调。
   *
   * 必须是**具名字段**而不是 `initialize(context, () => ...)` 里的内联箭头函数：
   * `DownloadStore.initialize` 会把它存进 `listeners`，而注销要求传同一个引用。
   * 内联写法根本拿不到那个引用，页面销毁后回调仍会被调用（往已销毁的组件上写 @State）。
   */
  private listener: () => void = (): void => {
    this.storeChanged();
  };
  private catalogListener: () => void = (): void => { this.library.catalogChanged(); };
  private foregroundListener: (visible: boolean) => void = (visible: boolean): void => {
    if (!visible) { this.library.cancelAnalysis(); this.library.cancelSimilar(); }
  };
  private sharedLinkListener: () => void = (): void => { this.consumeSharedLink(); };
  private widgetLaunchListener: () => void = (): void => { this.consumeWidgetLaunch(); };

  aboutToAppear(): void {
    this.hdsSupported = MaterialSupport.hdsImmersiveSupported();
    const context: common.UIAbilityContext = this.hostContext();
    this.toast.bind((text: string): void => {
      this.notice = text;
    });
    const port: UiPort = this.buildPort();
    this.discover.attach(port);
    this.tasks.attach(port);
    this.library.attach(port);
    this.settings.attach(port);
    this.device.attach(port);
    // 先挂听握姿和防窥，再初始化数据：initialize() 会按持久化的开关恢复订阅，订阅结果要能刷到界面。
    this.device.start();
    LIBRARY_CATALOG.subscribe(this.catalogListener);
    PREVIEW_LIFECYCLE.subscribe(this.foregroundListener);
    DownloadStore.initialize(context, this.listener);
    this.storeChanged();
    this.settings.applyTheme();
    ShareInbox.subscribe(this.sharedLinkListener);
    WidgetLaunch.subscribe(this.widgetLaunchListener);
    this.consumeSharedLink();
    this.consumeWidgetLaunch();
  }

  /**
   * 图库预览页推上来时 Index 会 onPageHide：这一页要停掉「取走商店提示」这件事。
   * 两个页面都挂了商店的刷新回调，谁先跑谁把 pendingNotice 拿走 —— 后取的那个
   * 才有机会说出口，被盖住的 Index 先抢走就等于这条提示没人看见。
   */
  onPageShow(): void {
    this.pageVisible = true;
    if (this.currentTab === TAB_LIBRARY) {
      this.library.refreshCatalog().catch((): void => this.say('图库整理信息读取失败，请重试'));
    }
    this.flushNotice();
    this.consumeSharedLink();
    this.consumeWidgetLaunch();
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.library.stopTapShare();
    this.discover.browserPanel = '';
    this.discover.cancelScan(this.previewOpen);
    this.library.cancelAnalysis();
    this.library.cancelSimilar();
  }

  onBackPress(): boolean {
    if (this.discover.batchHandling) {
      this.discover.finishBatchHandling();
      return true;
    }
    // 页级 onBackPress 优先于 NavDestination.onBackPressed，所以这里要先把批量页的返回
    // 语义接住：审核态 = 返回修改，编辑态 = 关闭批量页。
    if (this.discover.batchOpen) {
      if (this.discover.batchStage === 'review') { this.discover.cancelBatchReview(); }
      else { this.discover.setBatchPanel(false); }
      return true;
    }
    if (this.previewOpen) {
      if (this.previewPanels.dismissTop()) { return true; }
      this.closeDiscoverPreview();
      return true;
    }
    if (this.currentTab === TAB_DISCOVER && this.discover.browserPanel.length > 0) {
      this.discover.browserPanel = '';
      return true;
    }
    if (this.library.renameId.length > 0) {
      this.library.cancelRename();
      return true;
    }
    if (this.currentTab === TAB_DISCOVER && !this.browserOpen) {
      this.browserOpen = true;
      this.discover.resumeBrowser();
      return true;
    }
    return false;
  }

  /**
   * 页面销毁时把挂出去的东西都摘掉：商店回调、传感器回调、排队中的重扫、Toast 定时器。
   *
   * 重扫最多 8×500ms，页面没了还继续注入脚本是白跑；
   * 商店回调不摘的话，之后每次数据变化都会打到已经销毁的组件上。
   */
  aboutToDisappear(): void {
    this.library.stopTapShare();
    this.discover.stopBatchPages();
    this.library.cancelAnalysis();
    this.library.cancelSimilar();
    this.closeDiscoverPreview();
    LIBRARY_CATALOG.unsubscribe(this.catalogListener);
    PREVIEW_LIFECYCLE.unsubscribe(this.foregroundListener);
    DownloadStore.unsubscribe(this.listener);
    ShareInbox.unsubscribe(this.sharedLinkListener);
    WidgetLaunch.unsubscribe(this.widgetLaunchListener);
    this.device.stop();
    this.discover.cancelScan();
    // 提示的定时器与「销毁后不再弹」一起收掉。
    this.toast.release();
  }

  private consumeSharedLink(): void {
    if (!this.pageVisible) { return; }
    const problem: string = ShareInbox.takeError();
    if (problem.length > 0) { this.say(problem); }
    const link: string = ShareInbox.take();
    if (link.length === 0 || link === this.discover.pageUrl) { return; }
    this.selectTab(TAB_DISCOVER);
    this.discover.address = link;
    this.discover.visit();
  }

  private consumeWidgetLaunch(): void {
    if (!this.pageVisible || !WidgetLaunch.takeTasks()) { return; }
    this.browserOpen = true;
    this.selectTab(TAB_TASKS);
    const id: string = WidgetLaunch.takeTargetId();
    const kind: string = WidgetLaunch.takeTargetKind();
    if (id.length > 0 && (kind === 'task' || kind === 'batch')) {
      this.tasks.focusFromWidget(id, kind);
    }
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  // ------------------------------------------------------------------ 装配

  /**
   * 把 ViewModel 需要的界面能力收成一个端口交给它们。
   *
   * 用 `UiPort` 而不是五个 ViewModel 各持一堆回调，是为了让「谁能碰界面」只有一个答案；
   * 默认实现是空操作，这里逐项换成真实现。
   */
  private buildPort(): UiPort {
    const port: UiPort = new UiPort();
    port.say = (text: string): void => {
      this.say(text);
    };
    port.context = (): common.UIAbilityContext => this.hostContext();
    port.switchTab = (index: number): void => {
      this.selectTab(index);
    };
    port.showBrowser = (): void => {
      this.browserOpen = true;
    };
    port.showResults = (): void => {
      this.browserOpen = false;
    };
    port.focusLibrary = (name: string): void => {
      this.library.focus(name);
      this.selectTab(TAB_LIBRARY);
      this.library.refreshCatalog().catch((): void => this.say('图库整理信息读取失败，请重试'));
    };
    port.openViewer = (item: DownloadItem, rename: boolean, siblings: string[]): void => {
      this.openViewer(item, rename, siblings);
    };
    port.openImageEditor = (id: string): void => { this.openImageEditor(id); };
    port.confirm = (title: string, message: string, confirmText: string, onConfirm: () => void): void => {
      this.getUIContext().showAlertDialog({
        title: title,
        message: message,
        backgroundColor: SheetStyle.background(),
        systemMaterial: SheetStyle.dialogMaterial(),
        primaryButton: {
          value: '取消', action: (): void => {
          }
        },
        secondaryButton: {
          value: confirmText, action: onConfirm
        }
      });
    };
    return port;
  }

  /** 商店里的数据变了：把 ViewModel 拉回一致，再取一次攒下的提示。 */
  private storeChanged(): void {
    this.discover.syncDownloads();
    this.discover.refreshLocalPreview();
    this.tasks.sync();
    this.library.sync();
    this.settings.sync();
    this.device.sync();
    this.flushNotice();
  }

  /**
   * 打开大图预览页。
   *
   * 预览必须走 **router 新页面**，不能在 Index 上再盖一层浮层：系统返回键只认页面栈，
   * 浮层时代按返回键直接退出应用（本需求的起因）。页面自己负责取记录、改名与文件操作，
   * 这里只把「看哪一条」「给不给改名」和**可以左右滑的那一批**传过去。
   */
  private openViewer(item: DownloadItem, rename: boolean, siblings: string[]): void {
    // 先把自己标成「不在前台」再推页：pushUrl 到对面 onPageShow 之间有几毫秒，
    // 这期间若有个投递失败触发了 notify，本页会先把商店里的提示取走、弹在一个马上被盖住的
    // Toast 上，预览页再取就是空串 —— 提示等于被吞了。回来时 onPageShow 会重新置 true。
    this.pageVisible = false;
    // 用 UIContext 上的 Router，不用全局 router 模块：后者在 API 18 起已废弃。
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/Viewer',
      params: { id: item.id, rename: rename, ids: siblings }
    }).catch((error: BusinessError): void => {
      this.pageVisible = true;
      this.say('无法打开预览：' + error.message);
    });
  }

  private openImageEditor(id: string): void {
    this.library.cancelAnalysis();
    this.library.cancelSimilar();
    this.pageVisible = false;
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ImageEditor', params: { id: id } })
      .catch((error: BusinessError): void => {
        this.pageVisible = true;
        this.say('无法打开编辑页：' + error.message);
      });
  }

  private openDiscoverPreview(uid: string): void {
    const ids: string[] = this.discover.visiblePictures.map((item): string => item.uid);
    if (ids.indexOf(uid) < 0) { return; }
    this.previewPanels.reset();
    this.previewIds = ids;
    this.previewStartId = uid;
    this.previewOpen = true;
  }

  private openQuickDiscoverPreview(uid: string): void {
    if (!this.discover.pictures.some((item): boolean => item.uid === uid)) { return; }
    this.previewPanels.reset();
    this.previewIds = [uid];
    this.previewStartId = uid;
    this.previewOpen = true;
  }

  private closeDiscoverPreview(): void {
    if (!this.previewOpen) { return; }
    this.previewPanels.reset();
    this.previewOpen = false;
    this.discover.closeInspection();
    this.previewIds = [];
    this.previewStartId = '';
  }

  // ------------------------------------------------------------------ 提示

  /** 商店里攒下的提示（投递失败之类）由当前可见的那一页负责弹一次。 */
  private flushNotice(): void {
    if (!this.pageVisible) {
      return;
    }
    const text: string = DownloadStore.takeNotice();
    if (text.length > 0) {
      this.say(text);
    }
  }

  /** 弹一句提示；停留时长与定时器管理都在 ToastLatch 里。 */
  private say(text: string): void {
    this.toast.show(text);
  }

  // ------------------------------------------------------------------ 返回顶部

  /** 当前页签自己的「滚远了没有」；设置页没有列表，永远 false。 */
  private topVisible(): boolean {
    if (this.currentTab === TAB_DISCOVER && !this.browserOpen && !this.discover.batchOpen) {
      return this.discover.scrolled;
    }
    if (this.currentTab === TAB_TASKS) {
      return this.tasks.scrolled;
    }
    if (this.currentTab === TAB_LIBRARY) {
      return this.library.scrolled;
    }
    return false;
  }

  private scrollToTop(): void {
    if (this.currentTab === TAB_TASKS) {
      this.tasks.scrollToTop();
      return;
    }
    if (this.currentTab === TAB_LIBRARY) {
      this.library.scrollToTop();
      return;
    }
    this.discover.scrollToTop();
  }

  /**
   * 返回顶部按钮离底边的距离。
   *
   * 图片结果页底部还叠着握姿胶囊和选择条，按钮得排在它们上面。
   */
  private toTopBottomInset(): number {
    const extra: number = this.currentTab === TAB_DISCOVER
      ? (this.discover.selectedTotal > 0 ? 68 : 0) + (this.device.gripChipVisible() ? 40 : 0)
      : 0;
    const bottom: number = this.currentTab === TAB_DISCOVER
      ? SCREEN_INSETS.safeBottom : ScreenMetrics.tabBarSpace(SCREEN_INSETS.safeBottom);
    return bottom + Space.s12 + extra;
  }

  private browserSheetHeight(): number {
    const count: number = this.discover.browserPanel === 'bookmarks'
      ? this.discover.bookmarks.length : this.discover.history.length;
    return Math.min(ScreenMetrics.height() * 0.6,
      Math.max(200, 150 + count * 64 + SCREEN_INSETS.safeBottom));
  }

  private selectTab(index: number, fromTabs: boolean = false): void {
    if (index < TAB_DISCOVER || index > TAB_SETTINGS) { return; }
    if (this.currentTab !== index) {
      if (index !== TAB_DISCOVER) {
        this.discover.browserPanel = '';
        this.discover.cancelScan();
      }
      if (index !== TAB_LIBRARY) {
        this.library.cancelAnalysis();
        this.library.cancelSimilar();
        this.library.stopTapShare();
      }
      this.currentTab = index;
      if (index === TAB_LIBRARY) {
        this.library.refreshCatalog().catch((): void => this.say('图库整理信息读取失败，请重试'));
      }
    }
    if (!fromTabs && this.tabsReady) { this.tabs.changeIndex(index); }
  }

  private shellPlan(): HdsShellPlan {
    return hdsShellPlan(this.currentTab, this.browserOpen, this.settings.lightEffect,
      this.settings.materialType, this.hdsSupported, SCREEN_INSETS.safeBottom);
  }

  private materialType(): hdsMaterial.MaterialType {
    return this.settings.materialType === 'immersive'
      ? hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.ADAPTIVE;
  }

  private tabsStyle(): HdsTabsFloatingStyle {
    const plan: HdsShellPlan = this.shellPlan();
    const style: HdsTabsFloatingStyle = {
      barBottomMargin: plan.bottomMargin, thermoCtrl: true,
      barSideMargin: Math.max(Layout.pagePad, SCREEN_INSETS.safeLeft, SCREEN_INSETS.safeRight),
      adaptToHandedness: DownloadStore.gripEnabled
    };
    if (plan.tabMaterial) {
      style.systemMaterialEffect = {
        materialType: this.materialType(), materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      };
    } else {
      style.systemMaterialEffect = {
        materialType: hdsMaterial.MaterialType.NONE, materialLevel: hdsMaterial.MaterialLevel.SMOOTH
      };
    }
    return style;
  }

  private titleStyle(): TitleBarStyleOptions {
    const bar: HdsNavigationTitleBarStyle = {
      contentStyle: {
        titleStyle: { mainTitleColor: Palette.fontPrimary, subTitleColor: Palette.fontSecondary },
        menuStyle: { textColor: Palette.fontPrimary, iconColor: Palette.fontPrimary },
        backIconStyle: { iconColor: Palette.fontPrimary, backgroundColor: Palette.card },
        dividerStyle: { dividerColor: Palette.divider }
      }
    };
    const style: TitleBarStyleOptions = { originalStyle: bar, scrollEffectStyle: bar, thermoCtrl: true,
      scrollEffectOpts: { scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR } };
    if (this.shellPlan().titleMaterial && !this.device.peeking) {
      style.systemMaterialEffect = {
        materialType: this.materialType(), materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      };
    } else {
      bar.backgroundStyle = { backgroundColor: Palette.bg };
    }
    return style;
  }

  private titleCaption(): string {
    if (this.currentTab === TAB_TASKS) { return this.tasks.caption(); }
    if (this.currentTab === TAB_LIBRARY) {
      return this.library.isZips() ? this.library.zips.length.toString() + ' 个压缩包'
        : this.library.imageCount.toString() + ' 张图片 · ' + formatBytes(this.library.imageBytes);
    }
    return '';
  }

  private activeScrollers(): Scroller[] {
    if (this.currentTab === TAB_DISCOVER) {
      return this.browserOpen ? [] : [this.discover.scrollController()];
    }
    if (this.currentTab === TAB_TASKS) { return [this.tasks.scrollController()]; }
    if (this.currentTab === TAB_LIBRARY) { return [this.library.scrollController()]; }
    return [this.settingsScroller];
  }

  @Builder
  private discoverTitleContent() {
    DiscoverTitleBar({ discover: this.discover, browserOpen: this.browserOpen,
      onOpenBrowser: (): void => { this.browserOpen = true; this.discover.resumeBrowser(); } })
  }

  private rootTitleBar(): HdsNavigationTitleBarOptions {
    const content: TitleBarContentOptions = { menu: { value: [] } };
    if (this.device.peeking) {
      content.title = { mainTitle: $r('app.string.privacy_title_hidden') };
    } else if (this.currentTab === TAB_DISCOVER) {
      content.stackBuilder = () => this.discoverTitleContent();
    } else {
      content.title = {
        mainTitle: this.currentTab === TAB_TASKS ? '任务' : this.currentTab === TAB_LIBRARY ? '图库' : '设置',
        subTitle: this.titleCaption()
      };
      if (this.currentTab === TAB_TASKS && !this.tasks.isEmpty()) {
        content.menu = { value: [{ content: { label: '清空', type: TextStyleMode.NORMAL,
          action: (): void => { this.tasks.confirmClearAll(); } } }] };
      } else if (this.currentTab === TAB_LIBRARY) {
        content.menu = { value: [{ content: { label: this.library.selecting ? '完成' : '选择',
          type: TextStyleMode.NORMAL, action: (): void => {
            if (this.library.selecting) { this.library.endSelection(); }
            else { this.library.startSelection(); }
          } } }] };
      }
    }
    return { avoidLayoutSafeArea: true, enableComponentSafeArea: true,
      style: this.titleStyle(), content: content };
  }

  @Builder
  private tabLabel(item: TabItem, index: number) {
    Column({ space: Space.s2 }) {
      Stack({ alignContent: Alignment.Center }) {
        Glyph({ glyph: item.glyph, glyphSize: 23, glyphWeight: this.currentTab === index ? 2 : 1.7,
          glyphTone: this.currentTab === index ? Palette.tabSelected : Palette.fontPrimary })
        if (index === TAB_TASKS && this.tasks.running > 0) {
          Text(this.tasks.running > 99 ? '99' : this.tasks.running.toString())
            .fontSize(9).fontColor(Palette.white).backgroundColor(Palette.warning)
            .borderRadius(Radius.full).offset({ x: 12, y: -10 })
        }
      }.width(26).height(26)
      Text(item.label).fontSize(Font.tab)
        .fontColor(this.currentTab === index ? Palette.tabSelected : Palette.fontPrimary)
    }
    .width(64).height(Layout.tabBarHeight)
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .onClick((): void => { this.selectTab(index); })
    .accessibilityText(item.label).accessibilitySelected(this.currentTab === index)
  }

  @Builder
  private pageMap(name: string) {
    if (name === BATCH_PAGE_NAME) {
      HdsNavDestination() {
        Stack() {
          BatchPagePanel({ discover: this.discover })
          if (this.device.peeking) { PrivacyVeil({ device: this.device }) }
        }.width('100%').height('100%')
      }
      .titleBar({ avoidLayoutSafeArea: true, enableComponentSafeArea: true,
        style: this.titleStyle(),
        content: { title: {
          mainTitle: this.device.peeking ? $r('app.string.privacy_title_hidden')
            : this.discover.batchHandling ? '网页处理' : '批量链接',
          subTitle: this.device.peeking ? '' : this.discover.batchHandling ? '登录或验证后返回重试'
            : '每行一条链接，解析后选择要下载的图片'
        } } })
      .onBackPressed((): boolean => {
        if (this.discover.batchHandling) { this.discover.finishBatchHandling(); return true; }
        if (this.discover.batchStage === 'review') { this.discover.cancelBatchReview(); return true; }
        this.discover.setBatchPanel(false);
        return true;
      })
      .width('100%').height('100%').backgroundColor(Palette.bg)
    }
  }

  @Builder
  private activeSheetContent() {
    if (this.currentTab === TAB_LIBRARY && this.library.renameId.length > 0) {
      RenameDialog({ heading: '重命名压缩包', initial: this.library.renameName,
        onSave: (name: string): void => { this.library.applyZipRename(name); },
        onClose: (): void => { this.library.cancelRename(); } })
    } else {
      BrowserLibrarySheet({ discover: this.discover,
        onClose: (): void => { this.discover.browserPanel = ''; } })
    }
  }

  // ------------------------------------------------------------------ 视图

  build() {
    HdsNavigation(this.stack) {
      Stack({ alignContent: Alignment.Bottom }) {
        HdsTabs({ controller: this.tabs }) {
          TabContent() {
            Stack() {
              DiscoverScreen({ discover: this.discover, settings: this.settings, device: this.device,
                browserOpen: this.browserOpen,
                onShowResults: (): void => { this.discover.browserPanel = ''; this.browserOpen = false; },
                onOpenPreview: (uid: string): void => { this.openDiscoverPreview(uid); },
                onOpenQuickPreview: (uid: string): void => { this.openQuickDiscoverPreview(uid); } })
              if (this.device.peeking) { PrivacyVeil({ device: this.device }) }
            }.width('100%').height('100%')
          }.tabBar(this.tabLabel(TABS[TAB_DISCOVER], TAB_DISCOVER))
          TabContent() {
            Stack() {
              TasksScreen({ tasks: this.tasks })
              if (this.device.peeking) { PrivacyVeil({ device: this.device }) }
            }.width('100%').height('100%')
          }
            .tabBar(this.tabLabel(TABS[TAB_TASKS], TAB_TASKS))
          TabContent() {
            Stack() {
              LibraryScreen({ library: this.library, settings: this.settings,
                active: this.currentTab === TAB_LIBRARY })
              if (this.device.peeking) { PrivacyVeil({ device: this.device }) }
            }.width('100%').height('100%')
          }.tabBar(this.tabLabel(TABS[TAB_LIBRARY], TAB_LIBRARY))
          TabContent() {
            Stack() {
              SettingsScreen({ settings: this.settings, device: this.device,
                tasks: this.tasks, scroller: this.settingsScroller })
              if (this.device.peeking) { PrivacyVeil({ device: this.device }) }
            }.width('100%').height('100%')
          }
            .tabBar(this.tabLabel(TABS[TAB_SETTINGS], TAB_SETTINGS))
        }
        .barOverlap(true).vertical(false).barPosition(BarPosition.End)
        .scrollable(false).animationDuration(0)
        .barHeight(this.shellPlan().showTabs ? Layout.tabBarHeight : 0)
        .barFloatingStyle(this.tabsStyle())
        .onChange((index: number): void => { this.selectTab(index, true); })
        .onAppear((): void => { this.tabsReady = true; this.tabs.changeIndex(this.currentTab); })
        .width('100%').height('100%')

      // 图库预览使用独立页面；发现页预览留在 Index 中复用当前扫描状态，
      // onBackPress 会优先关闭它，避免系统返回直接退出应用。

      if (!this.device.peeking && !this.discover.batchOpen && this.topVisible()) {
        ToTopButton({
          mirror: this.device.gripLeft(),
          bottomSpace: this.toTopBottomInset(),
          onTap: (): void => {
            this.scrollToTop();
          }
        })
      }

      if (!this.device.peeking && this.currentTab === TAB_DISCOVER && !this.browserOpen && !this.discover.batchOpen
        && (this.discover.selectedTotal > 0 || this.device.gripChipVisible())) {
        Column({ space: Space.s8 }) {
          if (this.device.gripChipVisible()) {
            GripChip({ device: this.device })
          }
          if (this.discover.selectedTotal > 0) {
            SelectionDock({ discover: this.discover, device: this.device })
          }
        }
        .width('100%')
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          bottom: SCREEN_INSETS.safeBottom + Space.s12
        })
      }

      if (!this.device.peeking && this.notice.length > 0) {
        Column() {
          ToastPill({ text: this.notice })
        }
        .width('100%')
        // 没键盘时贴在页签栏上方 88（原型 .toast 的定位）。键盘弹起时窗口被压矮，
        // 页面底部就是键盘上沿 —— 这时只留 16 的间隙让 toast 压在键盘上，
        // 否则同一段 188 的内边距会把它顶到屏幕中部去（看起来像浮在内容正中）。
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          bottom: SCREEN_INSETS.keyboardHeight > 0 ? Space.s16
            : this.currentTab === TAB_DISCOVER && !this.browserOpen
              ? SCREEN_INSETS.safeBottom + Space.s16
              : ScreenMetrics.tabBarSpace(SCREEN_INSETS.safeBottom) + 88
        })
        // 这层盒子横跨整屏宽：键盘收起时它还把页签栏整个盖住。它纯粹是装饰，
        // 没有任何可点内容，所以整层退出命中测试：不设的话 toast 一出现，
        // 盖住的那条区域（页签栏、浮动下载条）在 2.6 秒里点不动，像卡死。
        .hitTestBehavior(HitTestMode.None)
      }

      if (this.previewOpen) {
        DiscoverPreview({ panels: this.previewPanels, foreground: this.pageVisible && PREVIEW_LIFECYCLE.foreground,
          discover: this.discover,
          ids: this.previewIds,
          startId: this.previewStartId,
          onClose: (): void => { this.closeDiscoverPreview(); },
          onEdit: (id: string): void => { this.closeDiscoverPreview(); this.openImageEditor(id); },
          onSourcePage: (): void => {
            this.closeDiscoverPreview();
            this.discover.resumeBrowser();
          }
        })
      }
      if (this.previewOpen && this.device.peeking) {
        PrivacyVeil({ device: this.device })
      }
      AppSheet({
        visible: !this.device.peeking && ((this.currentTab === TAB_DISCOVER && this.browserOpen
          && this.discover.browserPanel.length > 0)
          || (this.currentTab === TAB_LIBRARY && this.library.renameId.length > 0)),
        initialSize: this.library.renameId.length > 0 ? SheetSize.FIT_CONTENT : this.browserSheetHeight(),
        useMaterial: this.library.renameId.length > 0,
        opaqueBackground: this.library.renameId.length === 0,
        onDismiss: (): void => {
          this.discover.browserPanel = '';
          this.library.cancelRename();
        }
      }) {
        this.activeSheetContent()
      }
      }
      .width('100%').height('100%').backgroundColor(Palette.bg)
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar(this.rootTitleBar())
    .hideBackButton(true)
    .hideTitleBar(this.previewOpen)
    .bindToScrollable(this.activeScrollers())
    .width('100%').height('100%')
  }
}
