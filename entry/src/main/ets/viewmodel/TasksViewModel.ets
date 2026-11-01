import { BatchItem, DownloadItem } from '../model/Models';
import { batchViewOf, BatchView } from '../model/BatchView';
import { DownloadStore } from '../service/DownloadStore';
import { fileUri } from '@kit.CoreFileKit';
import { UiPort } from '../service/UiPort';
import { ScreenMetrics } from '../theme/Metrics';
import { CollectionGroups, CollectionSummary } from '../service/CollectionGroups';
import { TaskRow, TaskRows } from './TaskRows';
import { formatBytes } from '../theme/Tokens';

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
  readonly rows: TaskRows = new TaskRows();

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
  @Trace collectionFilter: string = '*';
  @Trace collections: CollectionSummary[] = [];
  @Trace statusFilter: string = 'all';
  @Trace statusCounts: number[] = [0, 0, 0, 0, 0];
  /** 包含批次成员和批次本身，供页签徽标使用。 */
  @Trace running: number = 0;
  @Trace queueSummary: string = '';
  @Trace failureSummary: string = '';

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
    this.collections = CollectionGroups.summaries(this.downloads, DownloadStore.zips,
      this.batches, DownloadStore.collections);
    if (this.collectionFilter !== '*' && !this.collections.some((group: CollectionSummary): boolean =>
      group.id === this.collectionFilter)) { this.collectionFilter = '*'; }
    this.concurrency = DownloadStore.concurrency;
    const visible: DownloadItem[] = this.downloads.filter((item: DownloadItem): boolean =>
      !item.taskHidden && (this.collectionFilter === '*' || item.collectionId === this.collectionFilter)
        && item.batchId.length === 0);
    const relevantBatches: BatchItem[] = this.batches.filter((batch: BatchItem): boolean =>
      this.collectionFilter === '*' || batch.collectionId === this.collectionFilter);
    const activeBatches: number = relevantBatches.filter((batch: BatchItem): boolean =>
      batch.status === 'downloading' || batch.status === 'waiting' || batch.status === 'packing').length;
    const failedBatches: number = relevantBatches.filter((batch: BatchItem): boolean => batch.status === 'failed').length;
    this.statusCounts = [visible.length + relevantBatches.length,
      visible.filter((item: DownloadItem): boolean => !['completed', 'failed', 'cancelled'].includes(item.status)).length
        + activeBatches,
      visible.filter((item: DownloadItem): boolean => item.status === 'completed').length,
      visible.filter((item: DownloadItem): boolean => item.status === 'failed').length + failedBatches,
      visible.filter((item: DownloadItem): boolean => item.status === 'cancelled').length];
    this.active = visible.filter((item: DownloadItem): boolean =>
      (this.statusFilter === 'all' || this.statusFilter === 'active') &&
      (item.status === 'running' || item.status === 'starting'
          || item.status === 'queued' || item.status === 'waiting' || item.status === 'paused'));
    this.settled = visible.filter((item: DownloadItem): boolean =>
      (this.statusFilter === 'all' || this.statusFilter === item.status) &&
      (item.status === 'completed' || item.status === 'failed' || item.status === 'cancelled'));
    const membersByBatch: Map<string, DownloadItem[]> = new Map<string, DownloadItem[]>();
    for (const item of this.downloads) {
      if (item.batchId.length === 0) { continue; }
      const members: DownloadItem[] = membersByBatch.get(item.batchId) ?? [];
      members.push(item);
      membersByBatch.set(item.batchId, members);
    }
    const views: BatchView[] = [];
    for (const batch of this.batches) {
      if (this.collectionFilter !== '*' && batch.collectionId !== this.collectionFilter) { continue; }
      if (this.statusFilter !== 'all' && this.statusFilter !== 'active' && this.statusFilter !== 'failed') { continue; }
      if (this.statusFilter === 'active' && batch.status !== 'downloading' && batch.status !== 'waiting'
        && batch.status !== 'packing') { continue; }
      if (this.statusFilter === 'failed' && batch.status !== 'failed') { continue; }
      const members: DownloadItem[] = membersByBatch.get(batch.id) ?? [];
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
    this.updateSummary(visible, relevantBatches);
    this.updateRows();
  }

  private updateRows(): void {
    const rows: TaskRow[] = [];
    if (this.batchViews.length > 0) {
      const heading: TaskRow = new TaskRow();
      heading.key = 'heading|batch'; heading.kind = 'heading'; heading.title = '打包任务';
      heading.count = this.batchViews.length; rows.push(heading);
      for (const batch of this.batchViews) {
        const row: TaskRow = new TaskRow();
        row.key = 'batch|' + batch.id; row.kind = 'batch'; row.batch = batch; rows.push(row);
      }
    }
    if (this.active.length > 0) {
      const heading: TaskRow = new TaskRow();
      heading.key = 'heading|active'; heading.kind = 'heading'; heading.title = '进行中';
      heading.count = this.active.length; rows.push(heading);
      for (const task of this.active) {
        const row: TaskRow = new TaskRow();
        row.key = 'task|' + task.id; row.kind = 'task'; row.task = task;
        row.state = task.status + '|' + task.path + '|' + task.stillPath + '|' + task.animated;
        rows.push(row);
      }
    }
    if (this.settled.length > 0) {
      const heading: TaskRow = new TaskRow();
      heading.key = 'heading|settled'; heading.kind = 'heading'; heading.title = '已结束';
      heading.count = this.settled.length; rows.push(heading);
      for (const task of this.settled) {
        const row: TaskRow = new TaskRow();
        row.key = 'task|' + task.id; row.kind = 'task'; row.task = task;
        row.state = task.status + '|' + task.path + '|' + task.stillPath + '|' + task.animated;
        rows.push(row);
      }
    }
    this.rows.replace(rows);
  }

  private failureKind(error: string): string {
    const value: string = (error || '').toLowerCase();
    if (/\b(401|403)\b|登录|权限|cookie|unauthorized|forbidden/.test(value)) { return '登录或权限'; }
    if (/\b(404|410)\b|链接|失效|not found/.test(value)) { return '链接失效'; }
    if (/网络|超时|连接|dns|timeout|network|socket/.test(value)) { return '网络'; }
    return '其他';
  }

  private updateSummary(visible: DownloadItem[], batches: BatchItem[]): void {
    let queued: number = 0; let downloading: number = 0; let transferring: number = 0; let paused: number = 0;
    let completed: number = 0; let failed: number = 0; let processed: number = 0;
    let total: number = 0; let unknown: number = 0;
    const reasons: Map<string, number> = new Map<string, number>();
    for (const item of visible) {
      if (item.status === 'queued' || item.status === 'starting' || item.status === 'waiting') { queued++; }
      else if (item.status === 'running') {
        downloading++; transferring++; processed += item.processed;
        if (item.total > 0) { total += item.total; } else { unknown++; }
      } else if (item.status === 'paused') { paused++; }
      else if (item.status === 'completed') { completed++; }
      else if (item.status === 'failed') {
        failed++;
        const kind: string = this.failureKind(item.error);
        reasons.set(kind, (reasons.get(kind) ?? 0) + 1);
      }
    }
    for (const batch of batches) {
      if (batch.status === 'failed') {
        failed++;
        const kind: string = this.failureKind(batch.error);
        reasons.set(kind, (reasons.get(kind) ?? 0) + 1);
      } else if (batch.status === 'waiting') { queued++; }
      else if (batch.status === 'downloading' || batch.status === 'packing') { downloading++; }
    }
    this.queueSummary = '等待 ' + queued.toString() + ' · 处理中 ' + downloading.toString()
      + ' · 暂停 ' + paused.toString() + ' · 完成 ' + completed.toString()
      + ' · 失败 ' + failed.toString()
      + (transferring > 0 ? ' · 正在接收 ' + formatBytes(processed)
        + (unknown === 0 && total > 0 ? ' / ' + formatBytes(total) : '（含大小未知）') : '');
    const parts: string[] = [];
    for (const kind of ['登录或权限', '链接失效', '网络', '其他']) {
      const count: number = reasons.get(kind) ?? 0;
      if (count > 0) { parts.push(kind + ' ' + count.toString()); }
    }
    this.failureSummary = parts.join(' · ');
  }

  retryAllFailed(): void {
    const taskIds: string[] = this.downloads.filter((item: DownloadItem): boolean =>
      !item.taskHidden && item.batchId.length === 0 && item.status === 'failed'
      && (this.collectionFilter === '*' || item.collectionId === this.collectionFilter))
      .map((item: DownloadItem): string => item.id);
    const batchIds: string[] = this.batches.filter((batch: BatchItem): boolean =>
      batch.status === 'failed' && (this.collectionFilter === '*' || batch.collectionId === this.collectionFilter))
      .map((batch: BatchItem): string => batch.id);
    const count: number = taskIds.length + batchIds.length;
    if (count === 0) { this.ui.say('当前筛选范围没有失败任务'); return; }
    this.ui.confirm('重试失败任务', '将重试当前筛选范围内的 ' + taskIds.length.toString() + ' 个单图任务与 '
      + batchIds.length.toString() + ' 个打包批次。', '重试', (): void => {
        let retried: number = 0;
        for (const id of batchIds) {
          const batch: BatchItem | undefined = DownloadStore.batches.find((item: BatchItem): boolean => item.id === id);
          if (batch !== undefined && batch.status === 'failed' && DownloadStore.retryBatch(id)) { retried++; }
        }
        for (const id of taskIds) {
          const item: DownloadItem | undefined = DownloadStore.downloads.find((value: DownloadItem): boolean => value.id === id);
          if (item !== undefined && item.status === 'failed' && DownloadStore.retry(item)) { retried++; }
        }
        this.ui.say('已重试 ' + retried.toString() + ' 项，跳过 ' + (count - retried).toString() + ' 项');
      });
  }

  setCollectionFilter(id: string): void { this.collectionFilter = id; this.sync(); }
  setStatusFilter(value: string): void { this.statusFilter = value; this.sync(); }

  hideTask(item: DownloadItem): void {
    this.ui.say(DownloadStore.hideTask(item) ? '已移出任务页，素材仍在图库' : '当前任务无法移出');
  }

  clearFinished(): void {
    const count: number = this.downloads.filter((item: DownloadItem): boolean =>
      !item.taskHidden && item.batchId.length === 0 &&
      (this.collectionFilter === '*' || item.collectionId === this.collectionFilter) &&
      (item.status === 'completed' || item.status === 'cancelled')).length;
    if (count === 0) { this.ui.say('没有可清理的已完成或已取消任务'); return; }
    this.ui.confirm('清理已完成与已取消', '将从任务页移出 ' + count.toString() +
      ' 条记录，下载文件仍保留在图库。失败任务继续显示。', '清理', (): void => {
        this.ui.say('已移出 ' + DownloadStore.hideFinishedTasks(this.collectionFilter).toString() + ' 条任务');
      });
  }

  selectedCollection(): CollectionSummary | undefined {
    return this.collections.find((group: CollectionSummary): boolean => group.id === this.collectionFilter);
  }

  /** 只有单任务和打包批次都没有卡片时才显示空态。 */
  isEmpty(): boolean {
    return this.active.length === 0 && this.settled.length === 0 && this.batchViews.length === 0;
  }

  /** 标题副标题：进行中优先；没有进行中时如实说明已结束数量。 */
  caption(): string {
    if (this.statusFilter !== 'all') {
      return '筛选结果 ' + (this.active.length + this.settled.length + this.batchViews.length).toString() + ' 条';
    }
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
