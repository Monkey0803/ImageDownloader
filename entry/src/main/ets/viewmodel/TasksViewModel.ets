import { BatchItem, DownloadItem } from '../model/Models';
import { batchViewOf, BatchView } from '../model/BatchView';
import { DownloadStore } from '../service/DownloadStore';
import { fileUri } from '@kit.CoreFileKit';
import { UiPort } from '../service/UiPort';
import { ScreenMetrics } from '../theme/Metrics';

/**
 * 「任务」页的 ViewModel：下载队列 + 打包批次。
 *
 * 原先把「进行中 / 已结束 / 打包任务 / 徽标数」这几个派生列表写在 Index 的方法里，
 * 而 build 会**反复调用**它们 —— 一次渲染里 `activeTasks()` 被调 2 次、`settledTasks()` 3 次、
 * `batchViews()` 2 次，每次都是对 `downloads` 的一次全量扫描。列表一长就是几百次无谓比较。
 *
 * 派生状态只在 `sync()` 时算一次并写入 @Trace 字段，build 只读结果。任务状态从
 * 「进行中」转到「已结束」时，ForEach 需要观察到新数组，才能插入对应卡片。
 */
@ObservedV2
export class TasksViewModel {
  private ui: UiPort = new UiPort();
  private scroller: Scroller = new Scroller();

  private coverPath(task: DownloadItem): string {
    if (task.status !== 'completed') { return ''; }
    const path: string = task.kind === 'livephoto' ? task.stillPath : task.path;
    return path.length > 0 && DownloadStore.exists(path) ? path : '';
  }

  thumbnailSource(task: DownloadItem): string {
    if (task.status !== 'completed') { return task.url; }
    const path: string = this.coverPath(task);
    return path.length > 0 ? fileUri.getUriFromPath(path) : '';
  }

  firstFramePath(task: DownloadItem): string {
    return task.animated && task.kind !== 'livephoto' ? this.coverPath(task) : '';
  }

  /** `DownloadStore` 的两张表在这里的镜像。 */
  @Trace downloads: DownloadItem[] = [];
  @Trace batches: BatchItem[] = [];
  @Trace concurrency: number = 3;
  @Trace scrolled: boolean = false;

  @Trace active: DownloadItem[] = [];
  @Trace settled: DownloadItem[] = [];
  @Trace batchViews: BatchView[] = [];
  /** 包含批次成员和批次本身，供页签徽标使用。 */
  @Trace running: number = 0;

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

  /** 数据变了：重新生成每个分组的数组，让 ForEach 正确观察到跨分组的任务。 */
  sync(): void {
    this.downloads = DownloadStore.downloads.filter((item: DownloadItem): boolean => item.origin === 'download');
    this.batches = DownloadStore.batches.slice();
    this.concurrency = DownloadStore.concurrency;
    this.active = this.downloads.filter((item: DownloadItem): boolean =>
      item.batchId.length === 0
        && (item.status === 'running' || item.status === 'starting'
          || item.status === 'queued' || item.status === 'waiting' || item.status === 'paused'));
    this.settled = this.downloads.filter((item: DownloadItem): boolean =>
      item.batchId.length === 0
        && (item.status === 'completed' || item.status === 'failed' || item.status === 'cancelled'));
    const views: BatchView[] = [];
    for (const batch of this.batches) {
      const members: DownloadItem[] =
        this.downloads.filter((item: DownloadItem): boolean => item.batchId === batch.id);
      const done: number = members.filter((item: DownloadItem): boolean => item.status === 'completed').length;
      const failed: number = members.filter((item: DownloadItem): boolean =>
        item.status === 'failed' || item.status === 'cancelled').length;
      views.push(batchViewOf(batch, members, done, failed));
    }
    this.batchViews = views;
    let running: number = 0;
    for (const item of this.downloads) {
      if (item.status === 'running' || item.status === 'starting'
        || item.status === 'queued' || item.status === 'waiting' || item.status === 'paused') {
        running++;
      }
    }
    for (const batch of this.batches) {
      if (batch.status === 'downloading' || batch.status === 'packing') {
        running++;
      }
    }
    this.running = running;
  }

  /** 只有单任务和打包批次都没有卡片时才显示空态。 */
  isEmpty(): boolean {
    return this.active.length === 0 && this.settled.length === 0 && this.batchViews.length === 0;
  }

  /** 标题副标题：进行中优先；没有进行中时如实说明已结束数量。 */
  caption(): string {
    if (this.running > 0) {
      return this.running.toString() + ' 个任务进行中 · 并发 ' + this.concurrency.toString();
    }
    if (this.settled.length > 0) {
      return '无进行中 · 已结束 ' + this.settled.length.toString();
    }
    if (this.batchViews.length > 0) {
      return '有打包任务待处理';
    }
    return '队列为空';
  }

  setConcurrency(value: number): void {
    DownloadStore.setConcurrency(Math.round(value));
  }

  /** 标题栏清理入口与设置页使用同一份下载数据和删除语义。 */
  confirmClearAll(): void {
    if (this.isEmpty()) { return; }
    this.ui.confirm('清空下载记录', '将删除原始下载图片、压缩包与下载记录。编辑副本及已导出的文件不受影响。', '删除',
      (): void => {
        this.ui.say(DownloadStore.clearAll() ? '已清空下载记录，编辑副本已保留' :
          '部分文件未能删除，记录已保留，可重试清理');
      });
  }

  cancel(task: DownloadItem): void {
    DownloadStore.cancel(task);
    this.ui.say('已取消 ' + task.name);
  }

  async pause(task: DownloadItem): Promise<void> {
    this.ui.say(await DownloadStore.pause(task) ? '已暂停 ' + task.name : '暂停失败，请重试');
  }

  async resume(task: DownloadItem): Promise<void> {
    this.ui.say(await DownloadStore.resume(task) ? '已请求继续，服务器可能从头发送文件' : '继续失败，请重试');
  }

  retryDelivery(task: DownloadItem): void {
    if (task.receipt.status === 'interrupted') {
      this.ui.confirm('再次另存', '上次保存结果未确认。请先检查目标位置，避免产生重复副本。', '仍要另存',
        (): void => { DownloadStore.retryDelivery(task); });
      return;
    }
    DownloadStore.retryDelivery(task);
  }

  retry(task: DownloadItem): void {
    this.ui.say(DownloadStore.retry(task) ? '重新加入队列' : '任务尚未准备好重试');
  }

  retryBatch(batch: BatchView): void {
    this.ui.say(DownloadStore.retryBatch(batch.id) ? '重新打包 ' + batch.name : '批次尚未准备好重试');
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
