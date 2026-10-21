import { DownloadItem, ZipItem } from '../model/Models';
import { LIBRARY_IMAGES, LIBRARY_ZIPS } from '../model/Navigation';
import { DownloadStore } from '../service/DownloadStore';
import { ActionOutcome, ExportEntry, exportFile, exportFiles, shareFile, shareFiles } from '../service/FileActions';
import { UiPort } from '../service/UiPort';
import { LibraryQuery } from '../service/LibraryQuery';
import { ContentScanResult, DuplicateFinder, DuplicateGroup } from '../service/DuplicateFinder';
import { ScreenMetrics } from '../theme/Metrics';

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
  @Trace sourceQuery: string = '';
  @Trace formatFilter: string = '';
  @Trace sortOrder: string = 'newest';
  @Trace density: number = 2;
  /** 'images' | 'zips' */
  @Trace segment: string = LIBRARY_IMAGES;
  @Trace scrolled: boolean = false;
  @Trace selecting: boolean = false;
  @Trace selectedIds: string[] = [];
  @Trace duplicateOpen: boolean = false;
  @Trace contentAnalyzing: boolean = false;
  @Trace contentChecked: boolean = false;
  @Trace contentProgress: string = '';
  @Trace contentReport: ContentScanResult = new ContentScanResult();
  private contentScanId: number = 0;

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
    return LibraryQuery.images(this.downloads, this.query, this.sourceQuery, this.formatFilter, this.sortOrder);
  }

  @Computed
  get archives(): ZipItem[] {
    return LibraryQuery.archives(this.zips, this.query, this.sortOrder);
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
    const valid: string[] = this.downloads.map((item: DownloadItem): string => item.id)
      .concat(this.zips.map((item: ZipItem): string => item.id));
    this.selectedIds = this.selectedIds.filter((id: string): boolean => valid.includes(id));
    if (before !== this.duplicateSignature(this.downloads)) {
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
        selectedZips.forEach((item: ZipItem): void => DownloadStore.deleteZip(item));
      } else {
        selectedImages.forEach((item: DownloadItem): void => DownloadStore.deleteDownload(item));
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
      DownloadStore.deleteZip(item);
      this.ui.say('已删除压缩包');
    });
  }

  exportZip(item: ZipItem): void {
    exportFile(this.ui.context(), item.path, item.name).then((outcome: ActionOutcome): void => {
      this.report(outcome);
    });
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
