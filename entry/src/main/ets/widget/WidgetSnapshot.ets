import { BatchItem, DownloadItem, SavedState } from '../model/Models';
import { StoreState } from '../service/StoreState';

/** Small, non-sensitive payload sent to the desktop card. */
export class WidgetSnapshot {
  count: string = '0';
  status: string = '暂无待处理任务';
  name: string = '';
  progress: string = '';
  percent: string = '0';
  layout: string = 'wide';

  static fromSavedText(raw: string): WidgetSnapshot {
    const parsed: SavedState | undefined = StoreState.parse(raw);
    if (parsed === undefined) {
      return new WidgetSnapshot();
    }
    const safe: SavedState = StoreState.normalized(parsed);
    return WidgetSnapshot.from(safe.downloads, safe.batches, safe.antiPeepEnabled);
  }

  static from(downloads: DownloadItem[], batches: BatchItem[], hideName: boolean): WidgetSnapshot {
    const snapshot: WidgetSnapshot = new WidgetSnapshot();
    let count: number = 0;
    let chosen: DownloadItem | undefined = undefined;
    let chosenBatch: BatchItem | undefined = undefined;
    let chosenPriority: number = 99;
    for (const item of downloads) {
      const priority: number = WidgetSnapshot.priority(item.status);
      if (priority < 99) {
        count++;
        if (priority < chosenPriority || (priority === chosenPriority &&
          (chosen === undefined || item.createdAt > chosen.createdAt))) {
          chosen = item;
          chosenPriority = priority;
        }
      }
    }
    for (const batch of batches) {
      if (batch.status === 'downloading' || batch.status === 'packing') {
        count++;
        if (chosenBatch === undefined || (batch.status === 'downloading' && chosenBatch.status === 'packing')) {
          chosenBatch = batch;
        }
      }
    }
    snapshot.count = count.toString();
    if (chosen !== undefined) {
      snapshot.status = WidgetSnapshot.statusText(chosen.status);
      snapshot.name = hideName ? '任务名称已隐藏' : (chosen.name.length > 0 ? chosen.name.slice(0, 80) : '未命名任务');
      if (chosen.total > 0 && Number.isFinite(chosen.total) && Number.isFinite(chosen.processed)) {
        const percent: number = Math.max(0, Math.min(100, Math.floor(chosen.processed * 100 / chosen.total)));
        snapshot.percent = percent.toString();
        snapshot.progress = percent.toString() + '%';
      } else {
        snapshot.progress = snapshot.status;
      }
    } else if (chosenBatch !== undefined) {
      snapshot.status = chosenBatch.status === 'packing' ? '正在打包' : '批次准备中';
      snapshot.name = hideName ? '任务名称已隐藏' :
        (chosenBatch.name.length > 0 ? chosenBatch.name.slice(0, 80) : '未命名批次');
      snapshot.progress = snapshot.status;
    }
    return snapshot;
  }

  private static priority(status: string): number {
    if (status === 'running') { return 0; }
    if (status === 'starting') { return 1; }
    if (status === 'waiting') { return 2; }
    if (status === 'queued') { return 3; }
    if (status === 'paused') { return 4; }
    return 99;
  }

  private static statusText(status: string): string {
    if (status === 'running') { return '下载中'; }
    if (status === 'starting') { return '连接中'; }
    if (status === 'waiting') { return '等待网络'; }
    if (status === 'queued') { return '排队中'; }
    return '已暂停';
  }
}
