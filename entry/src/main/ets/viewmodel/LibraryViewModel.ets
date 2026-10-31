import { DownloadItem, ZipItem } from '../model/Models';
import { LIBRARY_IMAGES, LIBRARY_ZIPS } from '../model/Navigation';
import { DownloadStore } from '../service/DownloadStore';
import { ActionOutcome, ExportEntry, exportFile, exportFiles, shareFile, shareFiles } from '../service/FileActions';
import { UiPort } from '../service/UiPort';
import { LibraryQuery } from '../service/LibraryQuery';
import { AnalysisProgress, AnalysisToken, LibrarySearchEntry, LibrarySearchOptions, SimilarGroup } from '../model/LibraryAsset';
import { LIBRARY_CATALOG } from '../service/LibraryCatalog';
import { LibraryAnalysis } from '../service/LibraryAnalysis';
import { LibraryText } from '../util/LibraryText';
import { ContentScanResult, DuplicateFinder, DuplicateGroup } from '../service/DuplicateFinder';
import { ScreenMetrics } from '../theme/Metrics';
import { ZipArchiveService, ZipExtractResult } from '../service/ZipArchiveService';
import { CollectionGroups, CollectionSummary } from '../service/CollectionGroups';

/**
 * 「图库」页的 ViewModel：图片网格 + 压缩包列表 + 搜索 + 分段 + 密度。
 *
 * 与任务页同一个理由：原先把 `galleryItems()` / `libraryZips()` 写在 Index 的方法里，
 * 而它们在一次 build 里会被调用五六次（网格要它、空态判断要它、`onOpen` 还要再 map 一遍），
 * 每次都带一遍 `toLowerCase()` 的搜索过滤。现在搜索结果与两段列表都是**派生字段**，
 * 只在「数据变了」或「关键词变了」时重算。
 *
 * 图片改名跟着大图预览页走（图库进预览可以改、任务页进预览不给改），所以这里只剩压缩包的改名。
 */
@ObservedV2
export class LibraryViewModel {
  private ui: UiPort = new UiPort();
  private scroller: Scroller = new Scroller();

  @Trace downloads: DownloadItem[] = [];
  @Trace zips: ZipItem[] = [];
  @Trace query: string = '';
  @Trace searchScope: string = 'all';
  @Trace favoritesOnly: boolean = false;
  @Trace tagFilter: string = '';
  @Trace catalogReady: boolean = false;
  @Trace catalogError: string = '';
  @Trace catalogEntries: LibrarySearchEntry[] = [];
  @Trace ocrScope: string = 'current';
  @Trace ocrAnalyzing: boolean = false;
  @Trace ocrProgress: AnalysisProgress = new AnalysisProgress();
  @Trace ocrNotice: string = '';
  @Trace similarScope: string = 'current';
  @Trace similarAnalyzing: boolean = false;
  @Trace similarChecked: boolean = false;
  @Trace similarProgress: AnalysisProgress = new AnalysisProgress();
  @Trace similarGroups: SimilarGroup[] = [];
  @Trace similarNotice: string = '';
  @Trace sourceQuery: string = '';
  @Trace collectionFilter: string = '*';
  @Trace formatFilter: string = '';
  @Trace sortOrder: string = 'newest';
  @Trace density: number = 2;
  /** 'images' | 'zips' */
  @Trace segment: string = LIBRARY_IMAGES;
  @Trace extractZipId: string = '';
  @Trace extractTarget: string = '';
  @Trace extractEncrypted: boolean = false;
  @Trace extractPassword: string = '';
  @Trace extractBusy: boolean = false;
  @Trace scrolled: boolean = false;
  @Trace selecting: boolean = false;
  @Trace selectedIds: string[] = [];
  @Trace duplicateOpen: boolean = false;
  @Trace contentAnalyzing: boolean = false;
  @Trace contentChecked: boolean = false;
  @Trace contentProgress: string = '';
  @Trace contentReport: ContentScanResult = new ContentScanResult();
  private contentScanId: number = 0;
  private catalogSignature: string = '';
  private analysisToken: AnalysisToken | undefined = undefined;
  private analysisGeneration: number = 0;
  private similarToken: AnalysisToken | undefined = undefined;
  private similarGeneration: number = 0;

  startSimilar(scope: string = 'current'): void {
    if (this.similarAnalyzing) { return; }
    const snapshot: DownloadItem[] = this.ocrItems(scope).slice();
    if (snapshot.length === 0) { this.ui.say('当前范围没有可检查的图片'); return; }
    this.ui.confirm('查找相似图片', '将检查 ' + snapshot.length.toString() +
      ' 张图片并列出候选组，不会删除文件。', '开始检查', (): void => {
      this.runSimilar(snapshot);
    });
  }

  private async runSimilar(snapshot: DownloadItem[]): Promise<void> {
    this.cancelSimilar();
    const token: AnalysisToken = new AnalysisToken();
    this.similarToken = token;
    const generation: number = ++this.similarGeneration;
    this.similarAnalyzing = true;
    this.similarChecked = false;
    this.similarGroups = [];
    this.similarNotice = '正在检查相似图片…';
    try {
      await this.refreshCatalog();
      if (token.cancelled || generation !== this.similarGeneration) { return; }
      const groups: SimilarGroup[] = await LibraryAnalysis.similar(snapshot, token,
        (value: AnalysisProgress): void => {
          if (generation === this.similarGeneration) { this.similarProgress = value; }
        });
      if (generation === this.similarGeneration && !token.cancelled) {
        this.similarGroups = groups;
        this.similarChecked = true;
        this.similarNotice = groups.length > 0 ? '找到 ' + groups.length.toString() + ' 组相似候选' :
          '未发现相似候选';
        this.catalogChanged();
      }
    } catch (error) {
      if (generation === this.similarGeneration) { this.similarNotice = '相似图片检查失败，请重试'; }
    } finally {
      if (generation === this.similarGeneration) {
        this.similarAnalyzing = false;
        this.similarToken = undefined;
      }
    }
  }

  cancelSimilar(): void {
    const wasRunning: boolean = this.similarAnalyzing;
    this.similarToken?.cancel();
    this.similarToken = undefined;
    this.similarGeneration++;
    this.similarAnalyzing = false;
    if (wasRunning) { this.similarNotice = '已取消相似图片检查'; }
  }

  openSimilarGroup(group: SimilarGroup): void {
    const valid: DownloadItem[] = this.downloads.filter((item: DownloadItem): boolean =>
      group.ids.includes(item.id) && item.status === 'completed');
    if (valid.length === 0) { this.ui.say('这组图片已不在图库'); return; }
    const first: DownloadItem = valid.find((item: DownloadItem): boolean =>
      item.id === group.representativeId) ?? valid[0];
    this.ui.openViewer(first, true, group.ids.filter((id: string): boolean =>
      valid.some((item: DownloadItem): boolean => item.id === id)));
  }

  similarItem(id: string): DownloadItem | undefined {
    return this.downloads.find((item: DownloadItem): boolean =>
      item.id === id && item.status === 'completed');
  }

  similarSize(id: string): string {
    const feature = LIBRARY_CATALOG.getIndex(id)?.feature;
    return feature === undefined ? '尺寸待读取' :
      feature.width.toString() + ' × ' + feature.height.toString();
  }

  private ocrItems(scope: string): DownloadItem[] {
    const source: DownloadItem[] = scope === 'all' ? this.downloads : this.images;
    return source.filter((item: DownloadItem): boolean => item.status === 'completed' &&
      item.batchId.length === 0 && (scope !== 'selected' || this.selectedIds.includes(item.id)));
  }

  ocrFailureReason(): string {
    for (const entry of this.catalogEntries) {
      if (entry.ocrStatus !== 'failed') { continue; }
      const reason: string = LIBRARY_CATALOG.getIndex(entry.id)?.ocrError ?? '';
      if (reason.length > 0) { return reason; }
    }
    return '';
  }

  startOcr(scope: string = 'current', force: boolean = false): void {
    if (this.ocrAnalyzing) { return; }
    const snapshot: DownloadItem[] = this.ocrItems(scope).slice();
    if (snapshot.length === 0) { this.ui.say('当前范围没有可识别的图片'); return; }
    const action: string = force ? '重新建立' : '建立';
    this.ui.confirm(action + '文字索引', '将为 ' + snapshot.length.toString() +
      ' 张图片' + action + '本地文字索引，可随时取消。', action, (): void => {
      this.runOcr(snapshot, force);
    });
  }

  private async runOcr(snapshot: DownloadItem[], force: boolean): Promise<void> {
    this.cancelAnalysis();
    const token: AnalysisToken = new AnalysisToken();
    this.analysisToken = token;
    const generation: number = ++this.analysisGeneration;
    this.ocrAnalyzing = true;
    this.ocrNotice = '正在识别图片文字…';
    try {
      await this.refreshCatalog();
      if (token.cancelled || generation !== this.analysisGeneration) { return; }
      await LibraryAnalysis.ocr(snapshot, force, token, (value: AnalysisProgress): void => {
        if (generation === this.analysisGeneration) { this.ocrProgress = value; }
      });
      if (generation === this.analysisGeneration) {
        this.ocrNotice = token.cancelled ? '已取消；已完成的图片仍保留索引' :
          this.ocrProgress.message.startsWith('系统文字识别服务不可用') ?
            this.ocrProgress.message :
            '识别完成：' + this.ocrProgress.success.toString() + ' 张有文字，' +
            this.ocrProgress.empty.toString() + ' 张无文字，' +
            this.ocrProgress.failed.toString() + ' 张失败' +
            (this.ocrProgress.failed > 0 && this.ocrProgress.message.length > 0 ?
              '。首个错误：' + this.ocrProgress.message : '');
        this.catalogChanged();
      }
    } catch (error) {
      if (generation === this.analysisGeneration) { this.ocrNotice = '识别失败，请重试'; }
    } finally {
      if (generation === this.analysisGeneration) {
        this.ocrAnalyzing = false;
        this.analysisToken = undefined;
      }
    }
  }

  cancelAnalysis(): void {
    const wasRunning: boolean = this.ocrAnalyzing;
    this.analysisToken?.cancel();
    this.analysisToken = undefined;
    this.analysisGeneration++;
    this.ocrAnalyzing = false;
    if (wasRunning) { this.ocrNotice = '已取消；已完成的图片仍保留索引'; }
  }

  retryFailedOcr(): void {
    const failed: Set<string> = new Set(this.catalogEntries.filter((entry: LibrarySearchEntry): boolean =>
      entry.ocrStatus === 'failed').map((entry: LibrarySearchEntry): string => entry.id));
    const snapshot: DownloadItem[] = this.downloads.filter((item: DownloadItem): boolean =>
      failed.has(item.id) && item.status === 'completed');
    if (snapshot.length === 0) { this.ui.say('没有识别失败的图片'); return; }
    this.ui.confirm('重试文字识别', '将重试 ' + snapshot.length.toString() + ' 张图片。', '重试',
      (): void => { this.runOcr(snapshot, true); });
  }

  clearTextIndex(): void {
    const snapshot: DownloadItem[] = this.ocrItems(this.ocrScope).slice();
    if (snapshot.length === 0) { this.ui.say('当前范围没有图片'); return; }
    this.ui.confirm('清空文字索引', '将清空 ' + snapshot.length.toString() +
      ' 张图片的本地识别文字，可重新识别。', '清空', (): void => {
      this.cancelAnalysis();
      LIBRARY_CATALOG.clearText(snapshot.map((item: DownloadItem): string => item.id))
        .then((): void => { this.catalogChanged(); this.ocrNotice = '文字索引已清空'; })
        .catch((): void => { this.ui.say('文字索引清空失败，请重试'); });
    });
  }

  catalogChanged(): void {
    this.catalogReady = !LIBRARY_CATALOG.loading && LIBRARY_CATALOG.loadError.length === 0;
    this.catalogError = LIBRARY_CATALOG.loadError;
    this.catalogEntries = LIBRARY_CATALOG.entries(this.downloads);
  }

  async refreshCatalog(): Promise<void> {
    await LIBRARY_CATALOG.reconcile(this.downloads.slice());
    this.catalogChanged();
    if (this.similarChecked && this.similarGroups.some((group: SimilarGroup): boolean =>
      group.ids.some((id: string): boolean => LIBRARY_CATALOG.getIndex(id)?.feature === undefined))) {
      this.similarChecked = false;
      this.similarGroups = [];
    }
  }

  async retryCatalog(): Promise<void> {
    try {
      await LIBRARY_CATALOG.retry();
      await LIBRARY_CATALOG.reconcile(this.downloads);
      this.catalogChanged();
    } catch (error) {
      this.catalogChanged();
      this.ui.say('图库整理信息仍无法读取，请稍后重试');
    }
  }

  entry(id: string): LibrarySearchEntry {
    const found: LibrarySearchEntry | undefined = this.catalogEntries.find(
      (value: LibrarySearchEntry): boolean => value.id === id);
    return found === undefined ? new LibrarySearchEntry() : found;
  }

  async toggleFavorite(id: string): Promise<void> {
    const item: DownloadItem | undefined = this.downloads.find((value: DownloadItem): boolean =>
      value.id === id && value.status === 'completed');
    if (item === undefined) { this.ui.say('图片尚未保存，下载后可收藏'); return; }
    try {
      await LIBRARY_CATALOG.setFavorite([id], !LIBRARY_CATALOG.getMeta(id).favorite);
      this.catalogChanged();
    } catch (error) { this.ui.say('收藏保存失败，请重试'); }
  }

  async changeSelectedTags(add: string[], remove: string[]): Promise<void> {
    const ids: string[] = this.images.filter((item: DownloadItem): boolean =>
      this.isSelected(item.id)).map((item: DownloadItem): string => item.id);
    if (ids.length === 0) { return; }
    try {
      await LIBRARY_CATALOG.changeTags(ids, LibraryText.tags(add), LibraryText.tags(remove));
      this.catalogChanged();
    } catch (error) { this.ui.say('标签保存失败，请重试'); }
  }

  async setSelectedFavorite(value: boolean): Promise<void> {
    const ids: string[] = this.images.filter((item: DownloadItem): boolean =>
      this.isSelected(item.id)).map((item: DownloadItem): string => item.id);
    if (ids.length === 0) { return; }
    try {
      await LIBRARY_CATALOG.setFavorite(ids, value);
      this.catalogChanged();
    } catch (error) { this.ui.say('收藏保存失败，请重试'); }
  }

  clearFilters(): void {
    this.query = ''; this.sourceQuery = ''; this.formatFilter = '';
    this.collectionFilter = '*';
    this.searchScope = 'all'; this.favoritesOnly = false; this.tagFilter = '';
  }

  /** 重置次级筛选与布局，保留首页搜索框里的关键词。 */
  resetOptions(): void {
    if (this.isZips()) {
      this.sortOrder = 'newest';
      this.collectionFilter = '*';
      return;
    }
    this.sourceQuery = '';
    this.collectionFilter = '*';
    this.formatFilter = '';
    this.searchScope = 'all';
    this.favoritesOnly = false;
    this.tagFilter = '';
    this.sortOrder = 'newest';
    this.density = 2;
  }

  @Computed
  get sameUrlGroups(): DuplicateGroup[] {
    return DuplicateFinder.sameUrl(this.downloads);
  }

  @Computed
  get sameSourceNameGroups(): DuplicateGroup[] {
    return DuplicateFinder.sameSourceName(this.downloads);
  }

  private duplicateSignature(items: DownloadItem[]): string {
    return DuplicateFinder.completed(items).map((item: DownloadItem): string =>
      item.id + ':' + item.path + ':' + item.size.toString()).join('|');
  }

  async analyzeContent(): Promise<void> {
    if (this.contentAnalyzing) { return; }
    const snapshot: DownloadItem[] = this.downloads.slice();
    const signature: string = this.duplicateSignature(snapshot);
    const scanId: number = ++this.contentScanId;
    this.contentAnalyzing = true;
    this.contentChecked = false;
    this.contentReport = new ContentScanResult();
    this.contentProgress = '正在检查文件…';
    try {
      const report: ContentScanResult = await DuplicateFinder.sameContent(snapshot,
        (done: number, total: number): void => {
          if (this.contentScanId === scanId) {
            this.contentProgress = '已检查 ' + done.toString() + ' / ' + total.toString();
          }
        });
      if (this.contentScanId !== scanId) { return; }
      if (this.duplicateSignature(this.downloads) !== signature) {
        this.ui.say('图库在检查期间发生变化，请重新检查');
        return;
      }
      this.contentReport = report;
      this.contentChecked = true;
    } catch (error) {
      this.ui.say('文件内容检查失败：' + String(error));
    } finally {
      if (this.contentScanId === scanId) {
        this.contentAnalyzing = false;
        this.contentProgress = '';
      }
    }
  }

  /**
   * 以下四个是**派生**状态，改成 `@Computed`（原来在 sync() / setQuery() 里手写重算）：
   * `images` / `archives` 跟着 downloads / zips / query 走，`imageCount` / `imageBytes` 只跟着 downloads 走。
   */
  @Computed
  get images(): DownloadItem[] {
    const options: LibrarySearchOptions = new LibrarySearchOptions();
    options.scope = this.searchScope; options.query = this.query;
    options.source = this.sourceQuery; options.format = this.formatFilter;
    options.order = this.sortOrder; options.favoritesOnly = this.favoritesOnly;
    options.tag = this.tagFilter;
    return LibraryQuery.search(this.downloads, this.catalogEntries, options).filter((item: DownloadItem): boolean =>
      this.collectionFilter === '*' || item.collectionId === this.collectionFilter);
  }

  @Computed
  get archives(): ZipItem[] {
    return LibraryQuery.archives(this.zips, this.query, this.sortOrder).filter((item: ZipItem): boolean =>
      this.collectionFilter === '*' || item.collectionId === this.collectionFilter);
  }

  @Computed
  get collections(): CollectionSummary[] {
    return CollectionGroups.summaries(this.downloads.filter((item: DownloadItem): boolean =>
      item.status === 'completed' && item.batchId.length === 0), this.zips, [], []);
  }

  @Computed
  get visibleSelectedCount(): number {
    const ids: string[] = this.isZips()
      ? this.archives.map((item: ZipItem): string => item.id)
      : this.images.map((item: DownloadItem): string => item.id);
    return ids.filter((id: string): boolean => this.selectedIds.includes(id)).length;
  }

  /**
   * 标题上的张数与占用**不受搜索影响**，所以从 downloads 单独统计一遍。
   * 实况照片占两份空间：原始包（size）+ 解出来的静图与视频（auxSize），
   * 与设置页那行的 `DownloadStore.usedBytes()` 口径保持一致。
   */
  @Computed
  get imageCount(): number {
    return this.downloads.filter((item: DownloadItem): boolean => item.status === 'completed'
      && item.batchId.length === 0).length;
  }

  @Computed
  get imageBytes(): number {
    let bytes: number = 0;
    for (const item of this.downloads) {
      if (item.status === 'completed' && item.batchId.length === 0) {
        bytes += item.size + item.auxSize;
      }
    }
    return bytes;
  }

  /** 压缩包改名弹窗：renameId 非空时显示。 */
  @Trace renameId: string = '';
  @Trace renameName: string = '';

  attach(ui: UiPort): void {
    this.ui = ui;
  }

  scrollController(): Scroller {
    return this.scroller;
  }

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

  sync(): void {
    const before: string = this.duplicateSignature(this.downloads);
    this.downloads = DownloadStore.downloads.slice();
    this.zips = DownloadStore.zips.slice();
    if (this.collectionFilter !== '*' && !this.collections.some((group: CollectionSummary): boolean =>
      group.id === this.collectionFilter)) { this.collectionFilter = '*'; }
    const nextCatalogSignature: string = this.downloads.filter((item: DownloadItem): boolean =>
      item.status === 'completed').map((item: DownloadItem): string =>
      item.id + ':' + item.path + ':' + item.stillPath + ':' + item.size.toString()).join('|');
    if (nextCatalogSignature !== this.catalogSignature) {
      this.catalogSignature = nextCatalogSignature;
      LIBRARY_CATALOG.reconcile(this.downloads).then((): void => this.catalogChanged())
        .catch((): void => this.ui.say('图库整理信息读取失败，请重试'));
    }
    this.catalogChanged();
    const valid: string[] = this.downloads.map((item: DownloadItem): string => item.id)
      .concat(this.zips.map((item: ZipItem): string => item.id));
    this.selectedIds = this.selectedIds.filter((id: string): boolean => valid.includes(id));
    if (before !== this.duplicateSignature(this.downloads)) {
      this.cancelAnalysis();
      this.cancelSimilar();
      this.similarChecked = false;
      this.similarGroups = [];
      this.contentScanId += 1;
      this.contentAnalyzing = false;
      this.contentChecked = false;
      this.contentReport = new ContentScanResult();
    }
  }

  /** 关键词变了：只重算搜索相关的结果，不动统计。 */
  setQuery(value: string): void {
    this.query = value;
  }

  setDensity(value: number): void {
    this.density = value;
  }

  setSegment(value: string): void {
    this.segment = value;
    this.selecting = false;
    this.selectedIds = [];
  }

  startSelection(): void {
    this.selecting = true;
  }

  endSelection(): void {
    this.selecting = false;
    this.selectedIds = [];
  }

  isSelected(id: string): boolean {
    return this.selectedIds.includes(id);
  }

  toggleSelection(id: string): void {
    this.selectedIds = this.isSelected(id)
      ? this.selectedIds.filter((selected: string): boolean => selected !== id)
      : this.selectedIds.concat(id);
  }

  selectVisible(): void {
    const ids: string[] = this.isZips()
      ? this.archives.map((item: ZipItem): string => item.id)
      : this.images.map((item: DownloadItem): string => item.id);
    this.selectedIds = Array.from(new Set(this.selectedIds.concat(ids)));
  }

  clearVisibleSelection(): void {
    const ids: string[] = this.isZips()
      ? this.archives.map((item: ZipItem): string => item.id)
      : this.images.map((item: DownloadItem): string => item.id);
    this.selectedIds = this.selectedIds.filter((id: string): boolean => !ids.includes(id));
  }

  private selectedEntries(): ExportEntry[] {
    if (this.isZips()) {
      return this.archives.filter((item: ZipItem): boolean => this.isSelected(item.id))
        .map((item: ZipItem): ExportEntry => ({ path: item.path, name: item.name }));
    }
    return this.images.filter((item: DownloadItem): boolean => this.isSelected(item.id))
      .map((item: DownloadItem): ExportEntry => ({ path: item.path, name: item.name }));
  }

  exportSelected(): void {
    const entries: ExportEntry[] = this.selectedEntries();
    if (entries.length === 0) { return; }
    exportFiles(this.ui.context(), entries).then((outcome: ActionOutcome): void => this.report(outcome));
  }

  shareSelected(): void {
    const entries: ExportEntry[] = this.selectedEntries();
    if (entries.length === 0) { return; }
    shareFiles(this.ui.context(), entries, this.isZips())
      .then((outcome: ActionOutcome): void => this.report(outcome));
  }

  deleteSelected(): void {
    const deletingZips: boolean = this.isZips();
    const ids: string[] = this.selectedIds.slice();
    const selectedImages: DownloadItem[] = this.images.filter((item: DownloadItem): boolean => ids.includes(item.id));
    const selectedZips: ZipItem[] = this.archives.filter((item: ZipItem): boolean => ids.includes(item.id));
    const count: number = deletingZips ? selectedZips.length : selectedImages.length;
    if (count === 0) { return; }
    this.ui.confirm('删除所选文件', '将删除 ' + count.toString()
      + ' 个应用内文件及对应记录，已导出的副本不受影响。', '删除', (): void => {
      if (deletingZips) {
        let failed: number = 0;
        selectedZips.forEach((item: ZipItem): void => {
          if (!DownloadStore.deleteZip(item)) { failed++; }
        });
        if (failed > 0) {
          this.endSelection();
          this.ui.say(failed.toString() + ' 个压缩包未能删除，记录已保留，可重试');
          return;
        }
      } else {
        let failed: number = 0;
        selectedImages.forEach((item: DownloadItem): void => {
          if (!DownloadStore.deleteDownload(item)) { failed++; }
        });
        if (failed > 0) {
          this.endSelection();
          this.ui.say(failed.toString() + ' 个文件未能删除，记录已保留，可重试');
          return;
        }
      }
      this.endSelection();
      this.ui.say('已删除 ' + count.toString() + ' 个文件');
    });
  }

  isZips(): boolean {
    return this.segment === LIBRARY_ZIPS;
  }

  /**
   * 从任务页「在图中定位」跳过来：切回图片段并把文件名（去扩展名）填进搜索框。
   */
  focus(name: string): void {
    this.segment = LIBRARY_IMAGES;
    this.setQuery(name);
  }

  // ------------------------------------------------------------------ 压缩包

  importZip(): void {
    ZipArchiveService.importZip(this.ui.context()).then((zip: ZipItem | undefined): void => {
      if (zip !== undefined) { this.ui.say('已导入 ' + zip.name); }
    }).catch((error: Error): void => { this.ui.say('导入失败：' + String(error)); });
  }

  startExtract(zip: ZipItem): void {
    try {
      this.extractEncrypted = ZipArchiveService.isEncrypted(zip);
      this.extractZipId = zip.id;
      this.extractTarget = '';
      this.extractPassword = '';
    } catch (error) { this.ui.say('无法解压：' + String(error)); }
  }

  chooseExtractTarget(target: string): void {
    if (this.extractBusy) { return; }
    this.extractTarget = target;
    if (!this.extractEncrypted) { this.submitExtract(); }
  }

  closeExtract(): void {
    if (this.extractBusy) { return; }
    this.extractZipId = '';
    this.extractTarget = '';
    this.extractPassword = '';
  }

  submitExtract(): void {
    if (this.extractBusy || this.extractTarget.length === 0) { return; }
    const zip: ZipItem | undefined = this.zips.find((item: ZipItem): boolean => item.id === this.extractZipId);
    if (zip === undefined) { this.closeExtract(); return; }
    this.extractBusy = true;
    const work: Promise<ZipExtractResult | undefined> = this.extractTarget === 'gallery'
      ? ZipArchiveService.extractToGallery(this.ui.context(), zip, this.extractPassword)
      : ZipArchiveService.extractToFolder(this.ui.context(), zip, this.extractPassword);
    work.then((result: ZipExtractResult | undefined): void => {
      this.extractBusy = false;
      if (result !== undefined) {
        this.ui.say(this.extractTarget === 'gallery'
          ? '已加入图库 ' + result.added.toString() + ' 张，跳过 ' + result.skipped.toString() + ' 个文件'
          : '已解压到 ' + result.location);
      }
      this.closeExtract();
    }).catch((error: Error): void => {
      this.extractBusy = false;
      this.ui.say('解压失败：' + String(error));
      if (this.extractEncrypted) { this.extractPassword = ''; }
      else { this.closeExtract(); }
    });
  }

  /** 改名入口只留给压缩包；图片改名跟着大图预览页走。 */
  startZipRename(zip: ZipItem): void {
    this.renameId = zip.id;
    this.renameName = zip.name;
  }

  applyZipRename(name: string): void {
    const id: string = this.renameId;
    this.renameId = '';
    if (id.length === 0) {
      return;
    }
    const zip: ZipItem | undefined = this.zips.find((item: ZipItem): boolean => item.id === id);
    if (zip !== undefined) {
      // 失败有两种原因（重名 / 原文件已不在），说清是哪一类，别一律赖「名称已存在」。
      this.ui.say(DownloadStore.renameZip(zip, name) ? '重命名完成' : '改名失败：名称已存在，或原文件已不在');
    }
  }

  cancelRename(): void {
    this.renameId = '';
  }

  confirmDeleteZip(item: ZipItem): void {
    this.ui.confirm('删除压缩包', '将同时删除压缩包文件和记录，已导出的副本不受影响。', '删除', (): void => {
      this.ui.say(DownloadStore.deleteZip(item) ? '已删除压缩包' : '文件未能删除，记录已保留，请重试');
    });
  }

  exportZip(item: ZipItem): void {
    exportFile(this.ui.context(), item.path, item.name).then((outcome: ActionOutcome): void => {
      this.report(outcome);
    });
  }

  retryArchiveDelivery(item: ZipItem): void {
    if (item.receipt.status === 'interrupted') {
      this.ui.confirm('再次另存', '上次保存结果未确认。请先检查目标位置，避免产生重复副本。', '仍要另存',
        (): void => { DownloadStore.retryArchiveDelivery(item); });
      return;
    }
    DownloadStore.retryArchiveDelivery(item);
  }

  shareZip(item: ZipItem): void {
    shareFile(this.ui.context(), item.path, item.name, true).then((outcome: ActionOutcome): void => {
      this.report(outcome);
    });
  }

  openImage(item: DownloadItem): void {
    // 图库进预览可以改名，并带上当前显示的整批图片：预览页左右滑动就是在这批图之间换
    // （搜索后只在结果里滑）。
    this.ui.openViewer(item, true, this.images.map((entry: DownloadItem): string => entry.id));
  }

  /** 文件操作的返回值本身就是给用户看的话；空串表示不用吭声（如分享面板被划掉）。 */
  private report(outcome: ActionOutcome): void {
    if (outcome.message.length > 0) {
      this.ui.say(outcome.message);
    }
  }
}
