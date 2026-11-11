import { BatchItem, DownloadItem } from '../model/Models';
import { batchViewOf, BatchView } from '../model/BatchView';
import { DownloadStore } from '../service/DownloadStore';
import { fileUri } from '@kit.CoreFileKit';
import { UiPort } from '../service/UiPort';
import { ScreenMetrics } from '../theme/Metrics';
import { CollectionGroups, CollectionSummary } from '../service/CollectionGroups';
import { TaskRow, TaskRows } from './TaskRows';
import { formatBytes } from '../theme/Tokens';
import { FloatDownload, FLOAT_DOWNLOAD_STATE } from '../service/FloatDownload';

/** 任务状态筛选的取值与显示顺序；与 `TasksViewModel.statusFilter` 一一对应。 */
export const TASK_STATUS_IDS: string[] = ['all', 'active', 'completed', 'failed', 'cancelled'];
export const TASK_STATUS_LABELS: string[] = ['全部', '进行中', '已完成', '失败', '已取消'];

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
  /**
   * 已完成任务的封面路径缓存：key 里带状态与路径，任务一变 key 就变。
   * 渲染路径上不再对同一张卡反复同步 `fs.accessSync`。
   */
  private thumbCache: Map<string, string> = new Map();

  private cachedCoverPath(task: DownloadItem): string {
    if (task.status !== 'completed') { return ''; }
    const key: string = task.id + '|' + task.status + '|' + task.path + '|' + task.stillPath
      + '|' + task.animated;
    const cached: string | undefined = this.thumbCache.get(key);
    if (cached !== undefined) { return cached; }
    const path: string = task.kind === 'livephoto' ? task.stillPath : task.path;
    const value: string = path.length > 0 && DownloadStore.exists(path) ? path : '';
    if (this.thumbCache.size > 256) { this.thumbCache.clear(); }
    this.thumbCache.set(key, value);
    return value;
  }

  thumbnailSource(task: DownloadItem): string {
    if (task.status !== 'completed') { return task.url; }
    const path: string = this.cachedCoverPath(task);
    return path.length > 0 ? fileUri.getUriFromPath(path) : '';
  }

  firstFramePath(task: DownloadItem): string {
    return task.animated && task.kind !== 'livephoto' ? this.cachedCoverPath(task) : '';
  }

  isActiveStatus(status: string): boolean {
    return status === 'running' || status === 'starting' || status === 'queued'
      || status === 'waiting' || status === 'paused';
  }

  isSettledStatus(status: string): boolean {
    return status === 'completed' || status === 'failed' || status === 'cancelled';
  }

  toggleSearch(): void {
    this.searching = !this.searching;
    if (!this.searching) { this.query = ''; }
    this.sync();
  }

  endSearch(): void {
    if (!this.searching && this.query.length === 0) { return; }
    this.searching = false;
    this.query = '';
    this.sync();
  }

  setQuery(value: string): void {
    this.query = value;
    this.sync();
  }

  private settledTitle(): string {
    if (this.statusFilter === 'completed') { return '已完成'; }
    if (this.statusFilter === 'failed') { return '失败'; }
    if (this.statusFilter === 'cancelled') { return '已取消'; }
    return '已结束';
  }

  private rebuildStatusLabels(): void {
    const labels: string[] = [];
    for (let index: number = 0; index < TASK_STATUS_LABELS.length; index += 1) {
      const count: number = this.statusCounts[index];
      labels.push(index === 0 || count > 0
        ? TASK_STATUS_LABELS[index] + ' ' + count.toString() : TASK_STATUS_LABELS[index]);
    }
    this.statusLabels = labels;
  }

  private rebuildCollectionOptions(): void {
    const options: SelectOption[] = [{ value: '全部来源' }];
    for (const group of this.collections) { options.push({ value: group.name }); }
    this.collectionOptions = options;
    this.selectedCollectionIndex = this.collectionFilter === '*' ? 0
      : this.collections.findIndex((group: CollectionSummary): boolean =>
        group.id === this.collectionFilter) + 1;
  }

  private computeSettledMixed(settled: DownloadItem[]): boolean {
    if (settled.length < 2) { return false; }
    const first: string = settled[0].status;
    for (let index: number = 1; index < settled.length; index += 1) {
      if (settled[index].status !== first) { return true; }
    }
    return false;
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
  /** 页签文案（含计数）；零计数只在「全部」上显示。 */
  @Trace statusLabels: string[] = ['全部 0', '进行中', '已完成', '失败', '已取消'];
  /** 来源下拉的选项与当前下标，避免 build 里反复分配数组 / findIndex。 */
  @Trace collectionOptions: SelectOption[] = [{ value: '全部来源' }];
  @Trace selectedCollectionIndex: number = 0;
  /** 已结束区块里是否混有多种状态；同质时不显示每行的状态胶囊。 */
  @Trace settledMixed: boolean = false;
  /** 队列摘要在空闲时是重复信息，只在确有活动 / 失败时显示。 */
  @Trace summaryVisible: boolean = false;
  @Trace searching: boolean = false;
  @Trace query: string = '';
  /** 包含批次成员和批次本身，供页签徽标使用。 */
  @Trace running: number = 0;
  @Trace queueSummary: string = '';
  @Trace failureSummary: string = '';

  floatActive(): boolean { return FLOAT_DOWNLOAD_STATE.active || FLOAT_DOWNLOAD_STATE.starting; }

  toggleFloat(): void {
    if (this.floatActive()) { FloatDownload.stop(); return; }
    FloatDownload.start(this.ui.context()).then((problem: string): void => {
      if (problem.length > 0) { this.ui.say(problem); }
    });
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
    // 用 scrollEdge 而不是 scrollTo(0)：列表用 `contentStartOffset` 给浮动标题栏让位，
    // scrollTo(0) 会把内容顶到容器上沿、绕过这段让位（标题栏压住筛选行）。
    this.scroller.scrollEdge(Edge.Top);
  }

  focusFromWidget(id: string, kind: string): void {
    this.collectionFilter = '*';
    this.statusFilter = 'all';
    this.searching = false;
    this.query = '';
    this.sync();
    const key: string = kind + '|' + id;
    let index: number = -1;
    for (let row: number = 0; row < this.rows.totalCount(); row++) {
      if (this.rows.getData(row).key === key) { index = row + 1; break; }
    }
    if (index < 0) { this.ui.say('该任务已不在任务列表'); return; }
    setTimeout((): void => { this.scroller.scrollToIndex(index, true, ScrollAlign.START); }, 0);
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

    const needle: string = this.query.toLowerCase();
    const visible: DownloadItem[] = [];
    for (const item of this.downloads) {
      if (item.taskHidden) { continue; }
      if (this.collectionFilter !== '*' && item.collectionId !== this.collectionFilter) { continue; }
      if (item.batchId.length !== 0) { continue; }
      if (needle.length > 0 && item.name.toLowerCase().indexOf(needle) < 0) { continue; }
      visible.push(item);
    }
    const relevantBatches: BatchItem[] = [];
    for (const batch of this.batches) {
      if (this.collectionFilter !== '*' && batch.collectionId !== this.collectionFilter) { continue; }
      if (needle.length > 0 && batch.name.toLowerCase().indexOf(needle) < 0) { continue; }
      relevantBatches.push(batch);
    }

    const membersByBatch: Map<string, DownloadItem[]> = new Map<string, DownloadItem[]>();
    let running: number = 0;
    for (const item of this.downloads) {
      if (this.isActiveStatus(item.status)) { running++; }
      if (item.batchId.length === 0) { continue; }
      const members: DownloadItem[] = membersByBatch.get(item.batchId) ?? [];
      members.push(item);
      membersByBatch.set(item.batchId, members);
    }
    for (const batch of this.batches) {
      if (batch.status === 'downloading' || batch.status === 'packing') { running++; }
    }
    this.running = running;

    const active: DownloadItem[] = [];
    const settled: DownloadItem[] = [];
    for (const item of visible) {
      if (this.isActiveStatus(item.status)) {
        if (this.statusFilter === 'all' || this.statusFilter === 'active') { active.push(item); }
      } else if (this.isSettledStatus(item.status)) {
        if (this.statusFilter === 'all' || this.statusFilter === item.status) { settled.push(item); }
      }
    }
    this.active = active;
    this.settled = settled;
    this.settledMixed = this.computeSettledMixed(settled);

    const views: BatchView[] = [];
    for (const batch of relevantBatches) {
      if (this.statusFilter !== 'all' && this.statusFilter !== 'active' && this.statusFilter !== 'failed') { continue; }
      if (this.statusFilter === 'active' && batch.status !== 'downloading' && batch.status !== 'waiting'
        && batch.status !== 'packing') { continue; }
      if (this.statusFilter === 'failed' && batch.status !== 'failed') { continue; }
      const members: DownloadItem[] = membersByBatch.get(batch.id) ?? [];
      let done: number = 0;
      let failed: number = 0;
      for (const item of members) {
        if (item.status === 'completed') { done++; }
        else if (item.status === 'failed' || item.status === 'cancelled') { failed++; }
      }
      views.push(batchViewOf(batch, members, done, failed));
    }
    this.batchViews = views;

    this.updateSummary(visible, relevantBatches);
    this.rebuildStatusLabels();
    this.rebuildCollectionOptions();
    this.updateRows();
  }

  private updateRows(): void {
    const rows: TaskRow[] = [];
    if (this.batchViews.length > 0) {
      const heading: TaskRow = new TaskRow();
      heading.key = 'heading|batch|' + this.batchViews.length.toString();
      heading.kind = 'heading'; heading.title = '打包任务';
      heading.count = this.batchViews.length; rows.push(heading);
      for (const batch of this.batchViews) {
        const row: TaskRow = new TaskRow();
        row.key = 'batch|' + batch.id; row.kind = 'batch'; row.batch = batch; rows.push(row);
      }
    }
    if (this.active.length > 0) {
      const heading: TaskRow = new TaskRow();
      heading.key = 'heading|active|' + this.active.length.toString();
      heading.kind = 'heading'; heading.title = '进行中';
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
      heading.title = this.settledTitle();
      heading.key = 'heading|settled|' + heading.title + '|' + this.settled.length.toString();
      heading.kind = 'heading';
      heading.count = this.settled.length;
      if (this.statusFilter !== 'failed' && this.statusCounts[2] + this.statusCounts[4] > 0) {
        heading.actionLabel = '清理';
      }
      rows.push(heading);
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
    let completed: number = 0; let failed: number = 0; let cancelled: number = 0;
    let activeItems: number = 0; let processed: number = 0;
    let total: number = 0; let unknown: number = 0;
    const reasons: Map<string, number> = new Map<string, number>();
    for (const item of visible) {
      if (!this.isSettledStatus(item.status)) { activeItems++; }
      if (item.status === 'queued' || item.status === 'starting' || item.status === 'waiting') { queued++; }
      else if (item.status === 'running') {
        downloading++; transferring++; processed += item.processed;
        if (item.total > 0) { total += item.total; } else { unknown++; }
      } else if (item.status === 'paused') { paused++; }
      else if (item.status === 'completed') { completed++; }
      else if (item.status === 'cancelled') { cancelled++; }
      else if (item.status === 'failed') {
        failed++;
        const kind: string = this.failureKind(item.error);
        reasons.set(kind, (reasons.get(kind) ?? 0) + 1);
      }
    }
    let activeBatches: number = 0;
    for (const batch of batches) {
      if (batch.status === 'failed') {
        failed++;
        const kind: string = this.failureKind(batch.error);
        reasons.set(kind, (reasons.get(kind) ?? 0) + 1);
      } else if (batch.status === 'waiting') { queued++; activeBatches++; }
      else if (batch.status === 'downloading' || batch.status === 'packing') { downloading++; activeBatches++; }
    }
    this.statusCounts = [visible.length + batches.length, activeItems + activeBatches,
      completed, failed, cancelled];
    this.summaryVisible = queued + downloading + paused + failed > 0;
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

  /** 标题副标题：搜索优先；其次进行中；没有进行中时如实说明已结束数量。 */
  caption(): string {
    if (this.searching) {
      if (this.query.length === 0) { return '输入文件名搜索'; }
      const matched: number = this.active.length + this.settled.length + this.batchViews.length;
      return matched > 0 ? '搜索到 ' + matched.toString() + ' 条' : '没有匹配的任务';
    }
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
    this.ui.confirm('清空下载记录', '将永久删除原始下载图片、压缩包与下载记录，不进入最近删除。编辑副本及已导出的文件不受影响。', '永久删除',
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
