import { BatchItem, DownloadItem } from '../model/Models';
import { batchViewOf, BatchView } from '../model/BatchView';
import { DownloadStore } from '../service/DownloadStore';
import { UiPort } from '../service/UiPort';
import { ScreenMetrics } from '../theme/Metrics';

/**
 * 「任务」页的 ViewModel：下载队列 + 打包批次。
 *
 * 原先把「进行中 / 已结束 / 打包任务 / 徽标数」这几个派生列表写在 Index 的方法里，
 * 而 build 会**反复调用**它们 —— 一次渲染里 `activeTasks()` 被调 2 次、`settledTasks()` 3 次、
 * `batchViews()` 2 次，每次都是对 `downloads` 的一次全量扫描。列表一长就是几百次无谓比较。
 *
 * 这里改成**派生状态只在 `sync()` 时算一次**存成字段，build 只读数组。`sync()` 由界面在
 * 商店通知（`DownloadStore` 的监听回调）里调，也就是「数据真的变了」的那一刻，而不是每一帧。
 */
@ObservedV2
export class TasksViewModel {
  private ui: UiPort = new UiPort();
  private scroller: Scroller = new Scroller();

  /** `DownloadStore` 的两张表在这里的镜像。 */
  @Trace downloads: DownloadItem[] = [];
  @Trace batches: BatchItem[] = [];
  @Trace concurrency: number = 3;
  @Trace scrolled: boolean = false;

  /**
   * 以下四个是**派生**状态，改成 `@Computed`：
   * 原来靠 `recompute()` 手写重算，字段和依赖要人肉对齐（漏一处就静默不刷新）。
   * `@Computed` 按依赖缓存，读到的 @Trace 变了才重算，sync() 只需要拉原始镜像。
   */
  @Computed
  get active(): DownloadItem[] {
    return this.downloads.filter((item: DownloadItem): boolean =>
      item.batchId.length === 0
        && (item.status === 'running' || item.status === 'starting' || item.status === 'queued'));
  }

  @Computed
  get settled(): DownloadItem[] {
    return this.downloads.filter((item: DownloadItem): boolean =>
      item.batchId.length === 0
        && (item.status === 'completed' || item.status === 'failed' || item.status === 'cancelled'));
  }

  @Computed
  get batchViews(): BatchView[] {
    const views: BatchView[] = [];
    for (const batch of this.batches) {
      const members: DownloadItem[] =
        this.downloads.filter((item: DownloadItem): boolean => item.batchId === batch.id);
      const done: number = members.filter((item: DownloadItem): boolean => item.status === 'completed').length;
      const failed: number = members.filter((item: DownloadItem): boolean =>
        item.status === 'failed' || item.status === 'cancelled').length;
      views.push(batchViewOf(batch, members, done, failed));
    }
    return views;
  }

  /**
   * 「进行中」= 队列里跑着的单张任务 + 还在下载 / 打包的批次，这就是页签徽标。
   * 判据与改动前一致：**不过滤 batchId**（批次成员也算在跑），批次则看批次记录自己的状态。
   */
  @Computed
  get running(): number {
    let total: number = 0;
    for (const item of this.downloads) {
      if (item.status === 'running' || item.status === 'starting' || item.status === 'queued') {
        total++;
      }
    }
    for (const batch of this.batches) {
      if (batch.status === 'downloading' || batch.status === 'packing') {
        total++;
      }
    }
    return total;
  }

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

  /** 数据变了：只拉原始镜像；派生列表由 @Computed 自己按依赖重算。 */
  sync(): void {
    this.downloads = DownloadStore.downloads.slice();
    this.batches = DownloadStore.batches.slice();
    this.concurrency = DownloadStore.concurrency;
  }

  /** 任务页没有任何卡片时显示空态（与改动前同一判据）。 */
  isEmpty(): boolean {
    return this.running === 0 && this.settled.length === 0;
  }

  setConcurrency(value: number): void {
    DownloadStore.setConcurrency(Math.round(value));
  }

  cancel(task: DownloadItem): void {
    DownloadStore.cancel(task);
    this.ui.say('已取消 ' + task.name);
  }

  retry(task: DownloadItem): void {
    DownloadStore.retry(task);
    this.ui.say('重新加入队列');
  }

  retryBatch(batch: BatchView): void {
    DownloadStore.retryBatch(batch.id);
    this.ui.say('重新打包 ' + batch.name);
  }

  dismissBatch(batch: BatchView): void {
    DownloadStore.dismissBatch(batch.id);
    this.ui.say('已解散 ' + batch.name + '，图片回到任务列表');
  }

  /** 任务卡：点缩略图看大图；任务页不给改名，也只给这一张（预览页里滑不动）。 */
  openTask(task: DownloadItem): void {
    this.ui.openViewer(task, false, [task.id]);
  }

  /**
   * 打包卡：取这个批次里的一张成员图进预览。成员图已经被打包掉的批次不会出现在任务页
   * （打成功的批次已经变成压缩包）。
   */
  openBatch(batch: BatchView): void {
    const member: DownloadItem | undefined =
      this.downloads.find((item: DownloadItem): boolean => item.batchId === batch.id);
    if (member === undefined) {
      this.ui.say('这个批次里还没有可以预览的图片');
      return;
    }
    this.ui.openViewer(member, false, [member.id]);
  }

  /** 跳到图库并在搜索框里定位这条任务对应的文件名（去掉扩展名）。 */
  locate(task: DownloadItem): void {
    this.ui.focusLibrary(task.name.replace(new RegExp('\\.[^.]+$'), ''));
    this.ui.say('已在图库中定位');
  }
}
