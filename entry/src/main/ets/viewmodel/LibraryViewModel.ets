import { DownloadItem, ZipItem } from '../model/Models';
import { LIBRARY_IMAGES, LIBRARY_ZIPS } from '../model/Navigation';
import { DownloadStore } from '../service/DownloadStore';
import { ActionOutcome, exportFile, shareFile } from '../service/FileActions';
import { UiPort } from '../service/UiPort';
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
  @Trace density: number = 2;
  /** 'images' | 'zips' */
  @Trace segment: string = LIBRARY_IMAGES;
  @Trace scrolled: boolean = false;

  /** 以下都是派生字段，只在 sync() / setQuery() 里重算。 */
  @Trace images: DownloadItem[] = [];
  @Trace archives: ZipItem[] = [];
  @Trace imageCount: number = 0;
  @Trace imageBytes: number = 0;

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
    this.downloads = DownloadStore.downloads.slice();
    this.zips = DownloadStore.zips.slice();
    this.recompute();
  }

  /** 关键词变了：只重算搜索相关的结果，不动统计。 */
  setQuery(value: string): void {
    this.query = value;
    this.recompute();
  }

  setDensity(value: number): void {
    this.density = value;
  }

  setSegment(value: string): void {
    this.segment = value;
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

  private recompute(): void {
    const needle: string = this.query.trim().toLowerCase();
    // 网格只显示「下载完成、且不属于任何批次」的图片 —— 批次成员归打包卡。
    this.images = this.downloads.filter((item: DownloadItem): boolean => item.status === 'completed'
      && item.batchId.length === 0
      && item.name.toLowerCase().includes(needle));
    this.archives = this.zips.filter((item: ZipItem): boolean => item.name.toLowerCase().includes(needle));

    // 标题上的张数与占用**不受搜索影响**，所以单独统计一遍。
    // 实况照片占两份空间：原始包（size）+ 解出来的静图与视频（auxSize），
    // 与设置页那行的 `DownloadStore.usedBytes()` 口径保持一致。
    let count: number = 0;
    let bytes: number = 0;
    for (const item of this.downloads) {
      if (item.status === 'completed' && item.batchId.length === 0) {
        count++;
        bytes += item.size + item.auxSize;
      }
    }
    this.imageCount = count;
    this.imageBytes = bytes;
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
