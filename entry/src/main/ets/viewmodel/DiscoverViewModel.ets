import { webview } from '@kit.ArkWeb';
import { PictureItem } from '../model/Models';
import { TAB_TASKS } from '../model/Navigation';
import { DownloadStore } from '../service/DownloadStore';
import { BrowserCollection, BrowserData, BrowserEntry } from '../service/BrowserCollection';
import { BatchLinks, BatchLinkReport } from '../service/BatchLinks';
import { Clipboard } from '../service/Clipboard';
import { MediaFormat } from '../service/MediaFormat';
import { PictureFactory, ScanImage } from '../service/PictureFactory';
import { PictureFilters } from '../service/PictureFilters';
import { PageScanner, ScanData, ScanEvents } from '../service/PageScanner';
import { SizeArbiter } from '../service/SizeArbiter';
import { UiPort } from '../service/UiPort';
import { ScreenMetrics } from '../theme/Metrics';
import { formatBytes } from '../theme/Tokens';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 「发现」页的 ViewModel：地址栏 + 内嵌浏览器 + 扫描结果 + 选择与入队。
 *
 * 这一页原来的状态与逻辑（地址、页面标题、图片列表、选中计数、扫描中、模式、以及
 * 扫描重试循环与剪贴板读取）全部散在 Index 里。现在：
 *
 * - 扫描的**重试与稳定判定**交给 `service/PageScanner`（模板方法 + 策略）；
 * - `PictureItem` 的构造与按 url 合并交给 `service/PictureFactory`（工厂方法）；
 * - 剪贴板权限流程交给 `service/Clipboard`（门面）；
 * - 这里只留「这一页此刻是什么状态、用户点了之后该变成什么」。
 *
 * `browser` 与 `scroller` 是必须**先于首次 build** 存在的对象，所以在字段上直接建；
 * 它们是普通成员而不是状态 —— 组件重建时不该换控制器（换了浏览器里的网页就白加载了）。
 */
@ObservedV2
export class DiscoverViewModel {
  private ui: UiPort = new UiPort();
  private browser: webview.WebviewController = new webview.WebviewController();
  private initialPageFinished: boolean = false;
  private pendingBrowserUrl: string = '';
  /** 直链结果显示时，忽略旧 Web 页晚到的导航/扫描回调。 */
  private directLinkActive: boolean = false;
  private scroller: Scroller = new Scroller();
  private scanner: PageScanner = new PageScanner();

  @Trace address: string = '';
  @Trace pageUrl: string = '';
  @Trace pageTitle: string = '';
  @Trace browserProblem: string = '';
  @Trace browserPanel: string = '';
  @Trace history: BrowserEntry[] = [];
  @Trace bookmarks: BrowserEntry[] = [];
  @Trace pictures: PictureItem[] = [];
  @Trace filterFormat: string = '';
  @Trace filterWidth: string = '';
  @Trace filterHeight: string = '';
  @Trace filterUrl: string = '';
  @Trace quickFilter: string = '';
  @Trace batchOpen: boolean = false;
  @Trace batchText: string = '';
  @Trace inspectedUid: string = '';
  @Trace inspectionBytes: number = 0;
  @Trace inspectionLoading: boolean = false;
  @Computed
  get batchReport(): BatchLinkReport { return BatchLinks.parse(this.batchText); }
  @Computed
  get inspectedPicture(): PictureItem | undefined {
    return this.pictures.find((item: PictureItem): boolean => item.uid === this.inspectedUid);
  }
  @Computed
  get featuredPicture(): PictureItem | undefined {
    return PictureFilters.suggested(this.visiblePictures);
  }
  @Computed
  get visiblePictures(): PictureItem[] {
    const width: number = PictureFilters.minimum(this.filterWidth);
    const height: number = PictureFilters.minimum(this.filterHeight);
    return this.pictures.filter((item: PictureItem): boolean =>
      PictureFilters.matches(item, this.filterFormat, width, height, this.filterUrl, this.quickFilter));
  }

  clearFilters(): void {
    this.filterFormat = '';
    this.filterWidth = '';
    this.filterHeight = '';
    this.filterUrl = '';
    this.quickFilter = '';
  }

  hasFilters(): boolean {
    return this.filterFormat.length > 0 || this.filterWidth.length > 0
      || this.filterHeight.length > 0 || this.filterUrl.trim().length > 0 || this.quickFilter.length > 0;
  }
  /**
   * 选中的张数。头部「已选 N」、底部选择条、返回顶部按钮的落点都读它。
   *
   * 改成 `@Computed`：它纯粹是 `pictures` 里 `selected` 的数量，以前靠 `syncSelectedTotal()`
   * 在六处手动同步 —— 漏一处就是静默不刷新。
   *
   * 这里曾经有两条**真机踩出来**的 V1 结论，留作历史（V2 里两个坑都不存在了）：
   * 1. 改完选中态**不要重新赋值整个数组**：`this.pictures = this.pictures.slice()` 会把子组件
   *    `@ObjectLink` 的通知掐断，磁贴的 `@Watch` 一次都不响、蒙层根本不出现；
   * 2. 改选中态必须写「父组件自己数组里的那个引用」：从子组件回传上来的引用上写字段，
   *    值会变、计数也跟着变，但通知发不出去，磁贴的蒙层会「差一拍」。
   * V2 的 `@Trace` 按字段记录依赖、**不挑写的是哪个引用**，所以这两条自然消失。
   */
  @Computed
  get selectedTotal(): number {
    return this.selectedCount();
  }
  @Trace scanning: boolean = false;
  /** 'single' | 'zip' */
  @Trace mode: string = 'single';
  /** 这一页滚远了没有；返回顶部按钮据此出现。 */
  @Trace scrolled: boolean = false;

  attach(ui: UiPort): void {
    this.ui = ui;
    const saved: BrowserData = BrowserCollection.load(ui.context());
    this.history = saved.history;
    this.bookmarks = saved.bookmarks;
  }

  isBookmarked(): boolean {
    return this.bookmarks.some((item: BrowserEntry): boolean => item.url === this.pageUrl);
  }

  toggleBookmark(): void {
    if (!BrowserCollection.validUrl(this.pageUrl)) { this.ui.say('请先打开网页'); return; }
    if (this.isBookmarked()) {
      this.bookmarks = this.bookmarks.filter((item: BrowserEntry): boolean => item.url !== this.pageUrl);
      this.ui.say('已取消收藏');
    } else {
      this.bookmarks = BrowserCollection.remember(this.bookmarks, this.pageUrl, this.pageTitle,
        Date.now(), 1000);
      this.ui.say('已加入收藏');
    }
    this.saveBrowserCollection();
  }

  removeBookmark(url: string): void {
    this.bookmarks = this.bookmarks.filter((item: BrowserEntry): boolean => item.url !== url);
    this.saveBrowserCollection();
  }

  clearHistory(): void {
    this.ui.confirm('清空浏览记录', '将删除本机的浏览记录，收藏不会受到影响。', '清空', (): void => {
      this.history = [];
      this.saveBrowserCollection();
    });
  }

  private rememberPage(url: string, title: string): void {
    if (!BrowserCollection.validUrl(url)) { return; }
    this.history = BrowserCollection.remember(this.history, url, title, Date.now(),
      BrowserCollection.HISTORY_LIMIT);
    // 页面标题可能在跳转后才出现，同时更新已有收藏的标题。
    this.bookmarks = this.bookmarks.map((item: BrowserEntry): BrowserEntry => {
      if (item.url !== url || title.trim().length === 0) { return item; }
      const updated: BrowserEntry = new BrowserEntry();
      updated.url = item.url;
      updated.title = title;
      updated.visitedAt = item.visitedAt;
      return updated;
    });
    this.saveBrowserCollection();
  }

  private saveBrowserCollection(): void {
    const data: BrowserData = new BrowserData();
    data.history = this.history;
    data.bookmarks = this.bookmarks;
    if (!BrowserCollection.save(this.ui.context(), data)) {
      this.ui.say('浏览记录或收藏保存失败，请检查设备存储空间');
    }
  }

  /** 交给 `Web({ controller })`；控制器必须自始至终是同一个实例。 */
  browserController(): webview.WebviewController {
    return this.browser;
  }

  browserPageEnded(quality: string): void {
    const firstBlank: boolean = !this.initialPageFinished
      && this.pendingBrowserUrl.length === 0 && this.pageUrl.length === 0;
    this.initialPageFinished = true;
    if (firstBlank) { this.scanning = false; return; }
    if (this.directLinkActive) { return; }
    if (this.browserProblem.length > 0) { return; }
    if (this.pendingBrowserUrl.length === 0) {
      this.scan(quality);
      return;
    }
    const url: string = this.pendingBrowserUrl;
    this.pendingBrowserUrl = '';
    try {
      this.browser.loadUrl(url);
    } catch (error) {
      this.scanning = false;
      this.ui.say('无法打开该链接：' + String(error));
    }
  }

  /** 交给 `Scroll(scroller)`。 */
  scrollController(): Scroller {
    return this.scroller;
  }

  // ------------------------------------------------------------------ 返回顶部

  /**
   * 记下这一页滚远了没有。
   *
   * **不要读 `onDidScroll` 回调给的那两个 offset**：它们不是「当前总偏移」，而是这一帧的增量
   * （真机实测一次滑动里回调出 0.37 / 0.36 / 0.33… 这种小数值，直接拿去比阈值永远是 false，
   * 按钮就永远不出现）。总偏移只能从 Scroller 上取。
   */
  markScrolled(): void {
    this.scrolled = this.scroller.currentOffset().yOffset > ScreenMetrics.scrollThreshold();
  }

  scrollToTop(): void {
    this.scroller.scrollTo({
      xOffset: 0,
      yOffset: 0,
      animation: { duration: 320, curve: Curve.FastOutSlowIn }
    });
  }

  resumeBrowser(): void {
    this.directLinkActive = false;
    this.ui.showBrowser();
  }

  // ------------------------------------------------------------------ 浏览

  /**
   * 把剪贴板里的链接填进地址栏，并直接打开——这一步和用户在地址栏里
   * 手输/回车完全等价，所以复用 `visit()`，不再单独写一套加载逻辑。
   */
  async pasteAddress(): Promise<void> {
    let text: string = '';
    try {
      text = await Clipboard.readText(this.ui.context());
    } catch (error) {
      this.ui.say('读取剪贴板失败：' + String((error as BusinessError).message));
      return;
    }
    const link: string = text.trim();
    if (link.length === 0) {
      this.ui.say('剪贴板里没有文字');
      return;
    }
    this.address = link;
    this.visit();
  }

  async pasteBatch(): Promise<void> {
    try {
      this.batchText = await Clipboard.readText(this.ui.context());
      this.batchOpen = true;
    } catch (error) {
      this.ui.say('读取剪贴板失败：' + String((error as BusinessError).message));
    }
  }

  /** 多链接不改变当前网页和扫描结果，用户确认后才入队。 */
  enqueueBatch(): void {
    const report: BatchLinkReport = this.batchReport;
    if (report.urls.length === 0) { this.ui.say('请逐行输入图片直链'); return; }
    const count: number = report.urls.length;
    const detail: string = '有效 ' + count.toString() + ' 条；无效 '
      + report.invalid.toString() + ' 条，重复 ' + report.duplicates.toString() + ' 条。';
    this.ui.confirm('导入图片链接', detail, '加入任务', (): void => {
      const images: PictureItem[] = report.urls.map((url: string): PictureItem => PictureFactory.fromUrl(url));
      DownloadStore.add(images, '', '批量链接', this.mode === 'zip');
      this.batchText = '';
      this.batchOpen = false;
      this.ui.switchTab(TAB_TASKS);
      this.ui.say('已加入 ' + count.toString() + ' 条下载任务');
    });
  }

  inspect(uid: string): void {
    const picture: PictureItem | undefined = this.pictures.find((item: PictureItem): boolean => item.uid === uid);
    if (picture === undefined) { return; }
    this.inspectedUid = uid;
    this.inspectionBytes = 0;
    this.inspectionLoading = true;
    const url: string = picture.url;
    SizeArbiter.measure(url, this.pageUrl).then((bytes: number): void => {
      if (this.inspectedUid !== uid || this.inspectedPicture?.url !== url) { return; }
      this.inspectionBytes = bytes;
      this.inspectionLoading = false;
    }).catch((): void => {
      if (this.inspectedUid === uid) { this.inspectionLoading = false; }
    });
  }

  inspectionSizeLabel(): string {
    return this.inspectionLoading ? '查询中…'
      : (this.inspectionBytes > 0 ? formatBytes(this.inspectionBytes) + '（已测得）' : '未知');
  }

  /**
   * 打开地址栏里的链接。
   *
   * 三档判断只看 `MediaFormat.mediaKindOf`（扩展名白名单与命名共用一份）：
   * 实况照片包（`.livp` / `.livephoto`）和图片直链都直接建成一张选中的卡片，
   * 其余交给内嵌浏览器扫描 —— 原来这里写死了一条正则，`.livp`、`.bmp`、`.heif`
   * 这些地址都会被当成网页去 load，用户看到的是浏览器解析不了的二进制。
   */
  visit(): void {
    let input: string = this.address.trim();
    if (input.length === 0) {
      return;
    }
    // 打开新链接要立刻作废排队中的重扫与在飞结果，否则上一页的结果会落到新页面上。
    this.scanner.invalidate();
    if (!input.startsWith('http://') && !input.startsWith('https://')) {
      input = 'https://' + input;
    }
    this.address = input;
    this.batchOpen = false;
    this.pageUrl = input;
    this.pictures = [];
    this.inspectedUid = '';
    this.pendingBrowserUrl = '';
    const kind: string = MediaFormat.mediaKindOf(input);
    if (kind === 'livephoto') {
      this.directLinkActive = true;
      this.scanning = false;
      this.ui.showResults();
      this.pictures = [PictureFactory.fromUrl(input)];
      this.pageTitle = '实况照片';
      this.ui.say('这是一个实况照片包，下载后可在应用内播放');
      this.rememberPage(input, this.pageTitle);
      return;
    }
    if (kind === 'image') {
      this.directLinkActive = true;
      this.scanning = false;
      this.ui.showResults();
      this.pictures = [PictureFactory.fromUrl(input)];
      this.pageTitle = '图片';
      this.ui.say('这是一个图片地址');
      this.rememberPage(input, this.pageTitle);
      return;
    }
    this.pageTitle = '';
    this.directLinkActive = false;
    this.browserProblem = '';
    this.scanning = true;
    this.ui.showBrowser();
    if (!this.initialPageFinished) {
      this.pendingBrowserUrl = input;
      return;
    }
    try {
      this.browser.loadUrl(input);
    } catch (error) {
      this.scanning = false;
      this.ui.say('无法打开该链接：' + String(error));
    }
  }

  navigateBack(): void {
    try {
      if (this.browser.accessBackward()) { this.browser.backward(); }
    } catch (error) { this.ui.say('无法返回上一页'); }
  }

  navigateForward(): void {
    try {
      if (this.browser.accessForward()) { this.browser.forward(); }
    } catch (error) { this.ui.say('无法前进到下一页'); }
  }

  reload(): void {
    try {
      this.browserProblem = '';
      this.browser.refresh();
    } catch (error) { this.ui.say('无法重新加载网页'); }
  }

  navigationStarted(): void {
    if (this.directLinkActive) { return; }
    this.scanner.invalidate();
    this.scanning = true;
    this.browserProblem = '';
    this.pageUrl = '';
    this.pageTitle = '';
    this.pictures = [];
    this.inspectedUid = '';
  }

  navigationFailed(message: string): void {
    if (this.directLinkActive) { return; }
    this.scanner.invalidate();
    this.scanning = false;
    this.browserProblem = message.length > 0 ? message : '网页加载失败，请检查链接或网络后重试';
  }

  /**
   * 扫描浏览器当前页面的图片。
   *
   * `quality` 由调用方从设置里取（DiscoverScreen 直接读 SettingsViewModel）——
   * 扫描器只认档位 id，不认「谁存的档位」。
   */
  scan(quality: string): void {
    this.scanning = true;
    const events: ScanEvents = {
      onProgress: (data: ScanData): void => {
        if (data.url !== this.pageUrl) { this.pictures = []; this.inspectedUid = ''; }
        this.pageUrl = data.url;
        this.address = data.url;
        this.pageTitle = data.title;
        if (data.url !== this.history[0]?.url || data.title !== this.history[0]?.title) {
          this.rememberPage(data.url, data.title);
        }
        this.pictures = PictureFactory.merge(this.pictures, data.images);
        // 扫描是「按 url 合并」的：上一轮选中的图会被复用，计数要跟着重算。
        },
      onSettled: (total: number): void => {
        this.scanning = false;
        this.ui.say(total === 0
          ? '暂未扫描到图片，滚动页面后点刷新可再试'
          : '找到 ' + this.pictures.length.toString() + ' 张图片');
      },
      onAborted: (): void => {
        this.scanning = false;
      },
      onError: (message: string): void => {
        this.scanning = false;
        this.ui.say(message);
      }
    };
    this.scanner.start(this.browser, quality, events);
  }

  /** 页面销毁 / 换页时停掉排队中的重扫（页面没了还继续注入脚本是白跑）。 */
  cancelScan(): void {
    this.scanner.cancel();
  }

  // ------------------------------------------------------------------ 选择

  private selectedCount(): number {
    return this.pictures.filter((item: PictureItem): boolean => item.selected).length;
  }

  /**
   * 切换一张图的选中态。
   *
   * 参数是 **uid 而不是 `PictureItem`**：这条在 V1 下是必须的 —— 从子组件回传上来的引用上
   * 写字段会绕过 `@Observed` 代理，通知发不出去（真机实测：点一下取消勾选，勾还留在屏幕上）。
   * V2 的 `@Trace` 不挑写的是哪个引用，但这里**仍然保留 uid 形式**：回调只传「哪一个」，
   * 由持有列表的一方去查、去改，边界更清楚，也不把模型引用递来递去。
   */
  togglePicture(uid: string): void {
    const target: PictureItem | undefined =
      this.pictures.find((item: PictureItem): boolean => item.uid === uid);
    if (target === undefined) {
      return;
    }
    target.selected = !target.selected;
  }

  selectAll(selected: boolean): void {
    for (const item of this.visiblePictures) {
      item.selected = selected;
    }
  }

  invertSelection(): void {
    if (this.visiblePictures.length === 0) {
      this.ui.say('还没有扫描到图片');
      return;
    }
    for (const item of this.visiblePictures) {
      item.selected = !item.selected;
    }
    this.ui.say('已反选，选中 ' + this.selectedTotal.toString() + ' 张');
  }

  // ------------------------------------------------------------------ 入队

  /** 把选中的图片交给下载队列；ZIP 模式只是换个打包方式，入队走同一条路。 */
  enqueue(): void {
    if (this.selectedCount() === 0) {
      this.ui.say('请先选择图片');
      return;
    }
    const zipMode: boolean = this.mode === 'zip';
    // 实况照片包不能进 ZIP：打包后剩下的只是一个压缩包，解包、播放、存相册全都无从谈起，
    // 所以 add() 会把它们按单文件走，这里的文案要跟着说清楚。
    const liveSelected: boolean = this.pictures.some((item: PictureItem): boolean =>
      item.selected && item.kind === 'livephoto');
    DownloadStore.add(this.pictures, this.pageUrl, this.pageTitle, zipMode);
    this.ui.switchTab(TAB_TASKS);
    if (zipMode && liveSelected) {
      this.ui.say('已加入任务；实况照片包按单文件下载，不参与打包');
      return;
    }
    this.ui.say(zipMode ? '已把所选图片加入打包队列' : '已加入下载任务');
  }
}
