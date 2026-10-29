import { webview } from '@kit.ArkWeb';
import { fileUri } from '@kit.CoreFileKit';
import { PictureItem } from '../model/Models';
import { TAB_TASKS } from '../model/Navigation';
import { DownloadStore } from '../service/DownloadStore';
import { BrowserCollection, BrowserData, BrowserEntry } from '../service/BrowserCollection';
import { BatchCheckKind, BatchLinkCheck, BatchLinks, BatchLinkReport, BatchLinkRow, BatchLinkStatus, BatchProbeToken } from '../service/BatchLinks';
import { BatchLinkProbe } from '../service/BatchLinkProbe';
import { BatchPageGroup, BatchPageGroups, BatchPageDownload } from '../service/BatchPageGroups';
import { BatchPageQueue } from '../service/BatchPageQueue';
import { BatchPageResolver } from '../service/BatchPageResolver';
import { Clipboard } from '../service/Clipboard';
import { MediaFormat } from '../service/MediaFormat';
import { PictureFactory, ScanImage } from '../service/PictureFactory';
import { PictureFilters } from '../service/PictureFilters';
import { PageScanner, ScanData, ScanEvents, ScanProtocol, ScanStrategies } from '../service/PageScanner';
import { PageExpansion, ExpansionStep } from '../service/PageExpansion';
import { ScanUpgrader } from '../service/ScanUpgrader';
import { SizeArbiter } from '../service/SizeArbiter';
import { AuthenticatedPreview, PreviewResult } from '../service/AuthenticatedPreview';
import { PreviewLoadProgress } from '../model/PreviewLoadProgress';
import { LocalPreview, LocalPreviewFile } from '../service/LocalPreview';
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
  private preview: AuthenticatedPreview = new AuthenticatedPreview();
  private inspectionGeneration: number = 0;
  private expansion: PageExpansion = new PageExpansion();
  private expansionGeneration: number = 0;
  @Trace expanding: boolean = false;
  @Trace expansionAdded: number = 0;
  @Trace expansionMessage: string = '';

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
  @Trace batchProbing: boolean = false;
  @Trace batchProbeDone: number = 0;
  @Trace batchProbeTotal: number = 0;
  @Trace batchProbeNote: string = '';
  @Trace batchChecks: BatchLinkCheck[] = [];
  /** 'edit' | 'review'：review 时只展示确认列表，不再改文本。 */
  @Trace batchStage: string = 'edit';
  @Trace batchReview: BatchLinkReport = new BatchLinkReport();
  @Trace batchReviewZip: boolean = false;
  private batchProbeGeneration: number = 0;
  private batchToken: BatchProbeToken | undefined = undefined;
  private batchQueue: BatchPageQueue = new BatchPageQueue();
  private batchResolver: BatchPageResolver = new BatchPageResolver();
  private batchResolveGeneration: number = 0;
  @Trace batchGroups: BatchPageGroup[] = [];
  @Trace batchResolving: boolean = false;
  @Trace batchHandling: boolean = false;
  @Trace inspectedUid: string = '';
  @Trace inspectionBytes: number = 0;
  @Trace inspectionLoading: boolean = false;
  @Trace previewUri: string = '';
  @Trace previewFailure: string = '';
  @Trace previewDownloadQueued: boolean = false;
  @Trace previewMessage: string = '';
  @Trace previewLoading: boolean = false;
  @Trace previewPhase: string = 'idle';
  @Trace previewReceived: number = 0;
  @Trace previewTotal: number = 0;

  @Computed
  get previewLoadTitle(): string {
    return this.previewPhase === 'decoding' ? '正在准备图片'
      : this.previewPhase === 'receiving' ? '正在加载图片' : '正在连接来源';
  }

  @Computed
  get previewLoadDetail(): string {
    if (this.previewPhase === 'decoding') { return '文件已收到，正在准备清晰画面…'; }
    if (this.previewReceived <= 0) { return '连接后将显示加载进度，可随时取消'; }
    return '已接收 ' + formatBytes(this.previewReceived)
      + (this.previewTotal > 0 ? ' / ' + formatBytes(this.previewTotal) : ' · 总大小未知');
  }

  @Computed
  get previewPercent(): number {
    return this.previewTotal > 0 ? Math.min(100, Math.floor(this.previewReceived * 100 / this.previewTotal)) : 0;
  }
  @Trace previewFromLocal: boolean = false;
  @Trace previewLocalPath: string = '';
  @Trace previewLocalAnimated: boolean = false;
  @Computed
  get batchReport(): BatchLinkReport {
    return BatchLinks.merge(BatchLinks.parse(this.batchText), this.batchChecks);
  }

  /** 编辑态的一行摘要；数量都以当前行状态为准。 */
  @Computed
  get batchSummary(): string {
    const report: BatchLinkReport = this.batchReport;
    let text: string = '可导入 ' + report.urls.length.toString() + ' 条';
    if (report.pages > 0) { text += ' · 网页 ' + report.pages.toString() + ' 条'; }
    if (report.pending > 0) {
      text += '（含待确认 ' + report.pending.toString() + ' 条）';
    }
    if (report.duplicates > 0) {
      text += ' · 重复 ' + report.duplicates.toString();
    }
    if (report.invalid > 0) {
      text += ' · 无效 ' + report.invalid.toString();
    }
    return text;
  }

  @Computed
  get batchProbeLabel(): string {
    if (this.batchProbing) {
      return '正在检查待确认链接 ' + this.batchProbeDone.toString() + '/' + this.batchProbeTotal.toString();
    }
    return this.batchProbeNote;
  }

  @Computed
  get batchReviewSummary(): string {
    const done: number = this.batchGroups.filter((group: BatchPageGroup): boolean =>
      group.status === 'ready' || group.status === 'failed').length;
    return (this.batchResolving ? '正在解析 ' + done.toString() + '/' + this.batchGroups.length.toString() + ' · ' : '')
      + '已选 ' + this.batchSelectedCount.toString() + ' 张'
      + (this.batchReviewZip ? ' · 每个网页一个 ZIP' : ' · 单图下载');
  }

  @Computed
  get batchSelectedCount(): number { return BatchPageGroups.count(this.batchGroups); }

  batchBrowser(): BatchPageResolver { return this.batchResolver; }

  private cancelBatchPages(): void {
    this.batchResolveGeneration++;
    this.batchQueue.cancel();
    if (this.batchResolving || this.batchHandling || this.batchGroups.length > 0) { this.batchResolver.clear(); }
    this.batchResolving = false; this.batchHandling = false;
    for (const group of this.batchGroups) {
      if (group.status === 'loading') { group.status = 'waiting'; group.message = '解析已停止，可重试'; }
    }
  }

  stopBatchPages(): void { this.cancelBatchPages(); }

  toggleBatchPicture(groupId: string, uid: string): void {
    const group: BatchPageGroup | undefined = this.batchGroups.find((item: BatchPageGroup): boolean => item.id === groupId);
    const picture: PictureItem | undefined = group?.pictures.find((item: PictureItem): boolean => item.uid === uid);
    if (picture !== undefined) { picture.selected = !picture.selected; }
  }

  selectBatchGroup(group: BatchPageGroup): void {
    const all: boolean = group.pictures.every((picture: PictureItem): boolean => picture.selected);
    for (const picture of group.pictures) { picture.selected = !all; }
  }

  async retryBatchPage(group: BatchPageGroup): Promise<void> {
    if (this.batchResolving) { return; }
    this.batchHandling = false;
    group.status = 'waiting';
    await this.resolveBatchPages([group]);
  }

  openBatchPage(group: BatchPageGroup): void {
    if (this.batchResolving || group.inputUrl.length === 0) { return; }
    this.batchHandling = true;
    // Keep this Web visible for human login/verification, without calling visit() or closing review.
    this.batchResolver.openForHandling(group.inputUrl);
  }

  finishBatchHandling(): void { this.batchResolver.clear(); this.batchHandling = false; }

  importPendingAsDirect(group: BatchPageGroup): void {
    if (this.batchResolving || group.kind !== 'pending') { return; }
    group.pictures = [PictureFactory.fromUrl(group.inputUrl)];
    group.kind = 'direct'; group.status = 'ready'; group.message = '类型待确认，将尝试直链下载';
  }

  private async resolveBatchPages(groups: BatchPageGroup[]): Promise<void> {
    const generation: number = ++this.batchResolveGeneration;
    this.batchResolving = true;
    const quality: string = DownloadStore.pictureQuality;
    try {
      await this.batchQueue.run(groups,
        (group: BatchPageGroup) => this.batchResolver.resolve(group, quality), (): void => {});
    } finally {
      if (generation === this.batchResolveGeneration) { this.batchResolving = false; }
    }
  }

  @Computed
  get batchReviewExcluded(): string {
    const report: BatchLinkReport = this.batchReview;
    if (report.duplicates === 0 && report.invalid === 0) {
      return '';
    }
    let text: string = '已排除';
    if (report.duplicates > 0) {
      text += '重复 ' + report.duplicates.toString() + ' 条';
    }
    if (report.invalid > 0) {
      text += (report.duplicates > 0 ? '、' : '') + '无效 ' + report.invalid.toString() + ' 条';
    }
    return text;
  }
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

  recordDimensions(uid: string, url: string, width: number, height: number): void {
    PictureFactory.recordDimensions(this.pictures, uid, url, width, height);
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
    AuthenticatedPreview.clearStale(ui.context().cacheDir);
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

  removeHistory(url: string): void {
    this.history = this.history.filter((item: BrowserEntry): boolean => item.url !== url);
    this.saveBrowserCollection();
  }

  async copyBrowserUrl(url: string): Promise<void> {
    try {
      await Clipboard.writeText(url);
      this.ui.say('已复制网址');
    } catch (error) {
      this.ui.say('复制网址失败，请重试');
    }
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
      this.setBatchText(await Clipboard.readText(this.ui.context()));
      this.setBatchPanel(true);
    } catch (error) {
      this.ui.say('读取剪贴板失败：' + String((error as BusinessError).message));
    }
  }

  /** 文本变化会作废在途探测；已经缓存的确定结论仍按 URL 复用。 */
  setBatchText(value: string): void {
    this.cancelBatchPages(); this.batchGroups = [];
    this.batchText = value;
    this.batchStage = 'edit';
    this.batchReview = new BatchLinkReport();
    this.batchReviewZip = false;
    this.cancelBatchProbe();
    this.batchProbeNote = '';
  }

  setBatchPanel(open: boolean): void {
    if (open) {
      // 批量页每次打开都会新建一块 Web 组件；控制器已随上一页解绑，必须换一个新的解析器。
      // 页面已经打开时（例如页内「粘贴多条」）不能换，否则新控制器与已挂载的 Web 对不上。
      if (!this.batchOpen) { this.batchResolver = new BatchPageResolver(); }
    } else {
      this.cancelBatchPages(); this.batchGroups = [];
      this.cancelBatchProbe();
      this.batchStage = 'edit';
      this.batchReview = new BatchLinkReport();
      this.batchReviewZip = false;
      this.batchProbeNote = '';
    }
    this.batchOpen = open;
  }

  async startBatchCheck(): Promise<void> {
    if (this.batchProbing) { return; }
    const pending: string[] = this.batchReport.rows
      .filter((row: BatchLinkRow): boolean => row.status === BatchLinkStatus.PENDING)
      .map((row: BatchLinkRow): string => row.url);
    if (pending.length === 0) {
      this.ui.say('没有待确认的链接');
      return;
    }
    await this.runBatchProbe(pending);
  }

  /**
   * 进入二次确认前按需探测待确认链接。
   *
   * 这里只准备 review 快照，不入队；真正的入队由用户再点一次完成。
   */
  async reviewBatch(): Promise<void> {
    if (this.batchProbing || this.batchResolving) { return; }
    const zipMode: boolean = this.mode === 'zip';
    let report: BatchLinkReport = this.batchReport;
    if (report.urls.length === 0) {
      this.ui.say('没有可导入的图片或网页链接');
      return;
    }
    const pending: string[] = report.rows
      .filter((row: BatchLinkRow): boolean => row.status === BatchLinkStatus.PENDING)
      .map((row: BatchLinkRow): string => row.url);
    if (pending.length > 0) {
      const completed: boolean = await this.runBatchProbe(pending);
      if (!completed) { return; }
      report = this.batchReport;
    }
    if (report.urls.length === 0) {
      this.ui.say('没有可导入的图片直链');
      return;
    }
    this.batchReview = BatchLinks.merge(BatchLinks.parse(this.batchText), this.batchChecks);
    this.batchReviewZip = zipMode;
    this.batchGroups = BatchPageGroups.create(this.batchReview);
    this.batchStage = 'review';
    await this.resolveBatchPages(this.batchGroups);
  }

  /** 用户不想等探测时保留未确认项直接进入 review；在途请求最多再等一个超时。 */
  skipBatchProbe(): void {
    if (!this.batchProbing) { return; }
    if (this.batchToken !== undefined) { this.batchToken.cancel(); }
    this.batchProbeNote = '已跳过检查，未确认链接仍会导入';
  }

  cancelBatchReview(): void {
    this.cancelBatchPages(); this.batchGroups = [];
    this.batchStage = 'edit';
    this.batchReview = new BatchLinkReport();
    this.batchReviewZip = false;
  }

  /** 二次确认后入队；使用 review 时的模式快照，避免确认期间切换模式造成不一致。 */
  confirmBatchReview(): void {
    if (this.batchResolving || this.batchHandling || this.batchStage !== 'review') { return; }
    const jobs: BatchPageDownload[] = BatchPageGroups.downloads(this.batchGroups);
    const count: number = this.batchSelectedCount;
    if (count === 0) {
      this.ui.say('没有可导入的图片直链');
      return;
    }
    for (const job of jobs) { DownloadStore.add(job.pictures, job.pageUrl, job.title, this.batchReviewZip); }
    this.cancelBatchPages(); this.batchGroups = [];
    this.batchText = '';
    this.batchChecks = [];
    this.batchStage = 'edit';
    this.batchReview = new BatchLinkReport();
    this.batchReviewZip = false;
    this.batchProbeNote = '';
    this.batchOpen = false;
    this.ui.switchTab(TAB_TASKS);
    this.ui.say('已加入 ' + count.toString() + ' 条下载任务');
  }

  private cancelBatchProbe(): void {
    this.batchProbeGeneration++;
    if (this.batchToken !== undefined) {
      this.batchToken.cancel();
      this.batchToken = undefined;
    }
    this.batchProbing = false;
    this.batchProbeDone = 0;
    this.batchProbeTotal = 0;
  }

  private async runBatchProbe(urls: string[]): Promise<boolean> {
    if (urls.length === 0) { return true; }
    this.batchProbeGeneration++;
    const generation: number = this.batchProbeGeneration;
    const token: BatchProbeToken = new BatchProbeToken();
    this.batchToken = token;
    this.batchProbing = true;
    this.batchProbeDone = 0;
    this.batchProbeTotal = urls.length;
    this.batchProbeNote = '';
    try {
      const checks: BatchLinkCheck[] = await BatchLinkProbe.check(urls, token,
        (done: number, total: number): void => {
          if (generation !== this.batchProbeGeneration) { return; }
          this.batchProbeDone = done;
          this.batchProbeTotal = total;
        });
      if (generation !== this.batchProbeGeneration) { return false; }
      this.batchChecks = this.batchChecks.concat(checks);
      this.batchProbeNote = this.probeNoteOf(checks, urls.length);
      return true;
    } finally {
      if (generation === this.batchProbeGeneration) {
        this.batchProbing = false;
        this.batchToken = undefined;
      }
    }
  }

  private probeNoteOf(checks: BatchLinkCheck[], requested: number): string {
    let image: number = 0;
    let page: number = 0;
    let unknown: number = 0;
    for (const check of checks) {
      if (check.kind === BatchCheckKind.IMAGE) {
        image++;
      } else if (check.kind === BatchCheckKind.PAGE) {
        page++;
      } else {
        unknown++;
      }
    }
    let text: string = '已检查 ' + checks.length.toString() + ' 条';
    const details: string[] = [];
    if (image > 0) { details.push('确认图片 ' + image.toString()); }
    if (page > 0) { details.push('待解析网页 ' + page.toString()); }
    if (unknown > 0) { details.push('仍待确认 ' + unknown.toString()); }
    if (details.length > 0) { text += '：' + details.join('，'); }
    const missed: number = requested - checks.length;
    if (missed > 0) { text += ' · ' + missed.toString() + ' 条未检查，仍可导入'; }
    return text;
  }

  inspect(uid: string, force: boolean = false): void {
    const picture: PictureItem | undefined = this.pictures.find((item: PictureItem): boolean => item.uid === uid);
    if (picture === undefined) { return; }
    this.closeInspection(true);
    const generation: number = this.inspectionGeneration;
    this.inspectedUid = uid;
    this.previewDownloadQueued = DownloadStore.downloads.some((item): boolean => item.url === picture.url
      && item.kind === picture.kind && ['queued', 'waiting', 'running', 'paused', 'starting'].includes(item.status));
    this.inspectionBytes = 0;
    this.inspectionLoading = true;
    const url: string = picture.url;
    const local: LocalPreviewFile | undefined = LocalPreview.find(url, picture.kind, DownloadStore.downloads);
    if (local !== undefined) {
      const displayPath: string = picture.kind === 'livephoto' ? local.stillPath : local.path;
      let uri: string = '';
      try {
        if (displayPath.length > 0) { uri = fileUri.getUriFromPath(displayPath); }
      } catch (error) {}
      if (picture.kind === 'livephoto' || uri.length > 0) {
        this.inspectionBytes = local.size;
        this.inspectionLoading = false;
        this.previewUri = uri;
        this.previewFromLocal = true;
        this.previewLocalPath = displayPath;
        this.previewLocalAnimated = local.animated;
        this.previewMessage = picture.kind === 'livephoto'
          ? '已使用本地下载文件，可在图库播放实况照片'
          : local.animated ? '本地原图 · 动图播放' : '本地原图 · 放大可查看更清晰细节';
        return;
      }
    }
    if (picture.kind === 'image') {
      this.previewLoading = true;
      this.previewPhase = 'connecting';
      this.previewMessage = '正在加载预览…';
      this.preview.load(url, this.pageUrl, this.ui.context().cacheDir, force,
        (progress: PreviewLoadProgress): void => {
          if (generation !== this.inspectionGeneration) { return; }
          this.previewPhase = progress.phase;
          this.previewReceived = progress.received;
          this.previewTotal = progress.total;
        }).then((result: PreviewResult): void => {
        if (generation !== this.inspectionGeneration) { return; }
        this.previewUri = result.uri;
        this.previewLocalPath = result.path;
        this.previewFailure = result.failure;
        this.previewLocalAnimated = result.animated;
        if (result.width > 0 && result.height > 0) {
          picture.width = result.width;
          picture.height = result.height;
        }
        this.previewMessage = result.animated && result.path.length > 0 ? '动图预览 · 可暂停或保存当前帧' : result.message;
        this.previewLoading = false;
        this.previewPhase = result.uri.length > 0 ? 'ready' : 'failed';
      }).catch((): void => {
        if (generation !== this.inspectionGeneration) { return; }
        this.previewLoading = false;
        this.previewPhase = 'failed';
        this.previewFailure = 'network';
        this.previewMessage = '预览不可用，可查看来源页或下载原文件';
      });
    } else {
      this.previewMessage = '实况照片包下载后可预览';
    }
    SizeArbiter.measure(url, this.pageUrl).then((bytes: number): void => {
      if (generation !== this.inspectionGeneration || this.inspectedPicture?.url !== url) { return; }
      this.inspectionBytes = bytes;
      this.inspectionLoading = false;
    }).catch((): void => {
      if (generation === this.inspectionGeneration) { this.inspectionLoading = false; }
    });
  }

  suspendInspection(): void {
    this.inspectionGeneration++;
    this.preview.cancelRequest();
    this.previewLoading = false;
    this.inspectionLoading = false;
  }

  cancelPreviewLoading(): void {
    if (!this.previewLoading) { return; }
    this.suspendInspection();
    this.previewPhase = 'cancelled';
    this.previewFailure = 'cancelled';
    this.previewMessage = '加载已取消，可重试或下载后查看';
  }

  closeInspection(preserveCache: boolean = false): void {
    this.inspectionGeneration++;
    this.inspectedUid = '';
    this.previewUri = '';
    this.previewFailure = '';
    this.previewDownloadQueued = false;
    this.previewMessage = '';
    this.previewLoading = false;
    this.previewPhase = 'idle';
    this.previewReceived = 0;
    this.previewTotal = 0;
    this.previewFromLocal = false;
    this.previewLocalPath = '';
    this.previewLocalAnimated = false;
    if (preserveCache) { this.preview.cancelRequest(); } else { this.preview.cancel(); }
  }

  /** A completed download replaces the preview source without changing image identity. */
  refreshLocalPreview(): void {
    const picture: PictureItem | undefined = this.inspectedPicture;
    if (picture === undefined) { return; }
    this.previewDownloadQueued = DownloadStore.downloads.some((item): boolean => item.url === picture.url
      && item.kind === picture.kind && ['queued', 'waiting', 'running', 'paused', 'starting'].includes(item.status));
    const local: LocalPreviewFile | undefined = LocalPreview.find(picture.url, picture.kind, DownloadStore.downloads);
    if (local === undefined) {
      if (this.previewFromLocal) { this.inspect(picture.uid); }
      return;
    }
    const path: string = picture.kind === 'livephoto' ? local.stillPath : local.path;
    if (this.previewFromLocal && this.previewLocalPath === path) { return; }
    let uri: string = '';
    try { if (path.length > 0) { uri = fileUri.getUriFromPath(path); } } catch (error) { return; }
    if (uri.length === 0 && picture.kind !== 'livephoto') { return; }
    this.inspectionGeneration++;
    this.preview.cancelRequest();
    this.previewUri = uri;
    this.previewLocalPath = path;
    this.previewLocalAnimated = local.animated;
    this.previewFromLocal = true;
    this.previewLoading = false;
    this.previewFailure = '';
    this.inspectionBytes = local.size;
    this.inspectionLoading = false;
    this.previewMessage = picture.kind === 'livephoto' ? '已使用本地下载文件，可在图库播放实况照片'
      : local.animated ? '本地原图 · 动图播放' : '本地原图 · 放大可查看更清晰细节';
  }

  /** Download this preview's selected range while keeping the overlay and selection intact. */
  downloadPreviewSelection(ids: string[]): void {
    const copies: PictureItem[] = [];
    const seen: string[] = [];
    let skipped: number = 0;
    for (const id of ids) {
      const picture: PictureItem | undefined = this.pictures.find((item: PictureItem): boolean => item.uid === id);
      if (picture === undefined || !picture.selected) { continue; }
      const key: string = picture.kind + ':' + picture.url;
      if (seen.includes(key)) { continue; }
      seen.push(key);
      const pending: boolean = DownloadStore.downloads.some((item): boolean => item.url === picture.url
        && item.kind === picture.kind && ['queued', 'waiting', 'running', 'paused', 'starting'].includes(item.status));
      if (pending) { skipped++; continue; }
      const copy: PictureItem = PictureFactory.fromUrl(picture.url);
      copy.name = picture.name;
      copy.kind = picture.kind;
      copy.userNamed = picture.userNamed;
      copy.description = picture.description;
      copies.push(copy);
    }
    if (copies.length === 0) {
      this.ui.say(skipped > 0 ? '所选图片已在下载任务中' : '请先选择图片');
      return;
    }
    DownloadStore.add(copies, this.pageUrl, this.pageTitle, this.mode === 'zip');
    this.refreshLocalPreview();
    this.ui.say('已加入 ' + copies.length.toString() + ' 张图片'
      + (this.mode === 'zip' ? '，普通图片将打包为 ZIP' : '')
      + (skipped > 0 ? '；已跳过 ' + skipped.toString() + ' 张正在下载的图片' : ''));
  }

  /** Explicit single-image recovery action; leave the grid selection and ZIP setting untouched. */
  downloadInspected(): void {
    const picture: PictureItem | undefined = this.inspectedPicture;
    if (picture === undefined || this.previewDownloadQueued) { return; }
    const pending: boolean = DownloadStore.downloads.some((item): boolean => item.url === picture.url
      && item.kind === picture.kind && ['queued', 'waiting', 'running', 'paused', 'starting'].includes(item.status));
    if (!pending) {
      const copy: PictureItem = PictureFactory.fromUrl(picture.url);
      copy.name = picture.name;
      copy.kind = picture.kind;
      copy.userNamed = picture.userNamed;
      copy.description = picture.description;
      DownloadStore.add([copy], this.pageUrl, this.pageTitle, false);
    }
    this.previewDownloadQueued = true;
    this.ui.say(pending ? '这张图片已在下载任务中' : '已加入下载任务，完成后可在图库查看');
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
    this.stopExpansion(false);
    this.expansionMessage = '';
    // 打开新链接要立刻作废排队中的重扫与在飞结果，否则上一页的结果会落到新页面上。
    this.scanner.invalidate();
    if (!input.startsWith('http://') && !input.startsWith('https://')) {
      input = 'https://' + input;
    }
    this.address = input;
    this.setBatchPanel(false);
    this.pageUrl = input;
    this.pictures = [];
    this.closeInspection();
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
    this.stopExpansion(false);
    this.expansionMessage = '';
    this.scanner.invalidate();
    this.scanning = true;
    this.browserProblem = '';
    this.pageUrl = '';
    this.pageTitle = '';
    this.pictures = [];
    this.closeInspection();
  }

  navigationFailed(message: string): void {
    if (this.directLinkActive) { return; }
    this.stopExpansion(false);
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
    this.stopExpansion(false);
    this.scanning = true;
    const events: ScanEvents = {
      onProgress: (data: ScanData): void => {
        if (data.url !== this.pageUrl) { this.pictures = []; this.closeInspection(); }
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
        if (total === 0) {
          this.ui.say('暂未扫描到图片，滚动页面后点刷新可再试');
        }
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
  cancelScan(preserveInspection: boolean = false): void {
    if (this.batchResolving || this.batchHandling) { this.cancelBatchPages(); }
    this.scanner.invalidate();
    this.scanning = false;
    if (preserveInspection) { this.suspendInspection(); } else { this.closeInspection(); }
    this.stopExpansion();
  }

  canExpand(): boolean {
    return !this.directLinkActive && this.pageUrl.startsWith('http')
      && !this.scanning && this.browserProblem.length === 0;
  }

  stopExpansion(announce: boolean = true): void {
    const wasRunning: boolean = this.expanding;
    this.expansion.stop();
    this.expansionGeneration++;
    this.expanding = false;
    if (wasRunning && announce) {
      this.expansionMessage = '已停止，本次新增 ' + this.expansionAdded.toString() + ' 张';
    }
  }

  loadMore(quality: string): void {
    if (this.expanding || !this.canExpand()) { return; }
    this.scanner.invalidate();
    this.closeInspection();
    this.stopExpansion(false);
    const generation: number = this.expansionGeneration;
    const url: string = this.pageUrl;
    this.expanding = true;
    this.expansionAdded = 0;
    this.expansionMessage = '正在加载，本次新增 0 张';
    this.ui.showBrowser();
    this.expansion.run(url, this.pictures.map((item: PictureItem): string => item.url),
      async (): Promise<ExpansionStep> => {
        const order: string[] = ScanStrategies.of(quality).order();
        const upgrade: boolean = ScanStrategies.of(quality).arbitrate();
        // 先采集上次滚动触发的图片，再滚动一屏；不点击链接、不切换网页。
        const raw: webview.JsMessageExt = await this.browser.runJavaScriptExt(ScanProtocol.script(order, upgrade));
        if (generation !== this.expansionGeneration) { throw new Error('cancelled'); }
        const data: ScanData = ScanProtocol.parse(raw.getString());
        if (data.url !== url) { throw new Error('page changed'); }
        if (upgrade) {
          await ScanUpgrader.apply(data.images, data.url, (): boolean => generation === this.expansionGeneration);
        }
        if (generation !== this.expansionGeneration) { throw new Error('cancelled'); }
        const scroll: webview.JsMessageExt = await this.browser.runJavaScriptExt(
          '(() => { if (location.href !== ' + JSON.stringify(url) + ') return false;'
          + ' const root = document.scrollingElement || document.documentElement;'
          + ' window.scrollBy(0, Math.max(200, window.innerHeight * 0.8));'
          + ' return root.scrollTop + window.innerHeight >= root.scrollHeight - 2; })()');
        return { data: data, bottom: scroll.getBoolean() };
      },
      (data: ScanData, added: number): void => {
        this.pictures = PictureFactory.merge(this.pictures, data.images);
        this.expansionAdded = added;
        this.expansionMessage = '正在加载，本次新增 ' + added.toString() + ' 张';
      },
      (added: number, limited: boolean): void => {
        this.expanding = false;
        this.expansionMessage = '本次新增 ' + added.toString() + ' 张'
          + (limited ? '，可再次加载更多' : '，当前页暂未发现更多图片');
        this.ui.say(this.expansionMessage);
      },
      (): void => {
        this.expanding = false;
        this.expansionMessage = '加载已停止，已找到的图片仍保留，可重试或手动浏览';
      });
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
