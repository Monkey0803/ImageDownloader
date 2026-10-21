import { describe, it, expect } from '@ohos/hypium';
import { BatchItem, DownloadItem } from '../../../main/ets/model/Models';
import { WidgetSnapshot } from '../../../main/ets/widget/WidgetSnapshot';

function task(name: string, status: string, createdAt: number, processed: number = 0, total: number = 0): DownloadItem {
  const item: DownloadItem = new DownloadItem();
  item.name = name;
  item.status = status;
  item.createdAt = createdAt;
  item.processed = processed;
  item.total = total;
  return item;
}

export default function widgetSnapshotTest(): void {
  describe('WidgetSnapshot', () => {
    it('matches_task_badge_count_and_prefers_running', 0, () => {
      const batch: BatchItem = new BatchItem();
      batch.status = 'packing';
      const snapshot: WidgetSnapshot = WidgetSnapshot.from([
        task('paused.png', 'paused', 20),
        task('running.png', 'running', 10, 50, 200),
        task('done.png', 'completed', 30)
      ], [batch], false);
      expect(snapshot.count).assertEqual('3');
      expect(snapshot.status).assertEqual('下载中');
      expect(snapshot.name).assertEqual('running.png');
      expect(snapshot.progress).assertEqual('25%');
    });

    it('hides_name_when_privacy_is_enabled_and_handles_unknown_total', 0, () => {
      const snapshot: WidgetSnapshot = WidgetSnapshot.from([
        task('private.png', 'waiting', 1, 20, 0)
      ], [], true);
      expect(snapshot.name).assertEqual('任务名称已隐藏');
      expect(snapshot.progress).assertEqual('等待网络');
      expect(snapshot.percent).assertEqual('0');
    });

    it('shows_empty_or_batch_only_state', 0, () => {
      expect(WidgetSnapshot.from([], [], false).status).assertEqual('暂无待处理任务');
      const batch: BatchItem = new BatchItem();
      batch.status = 'packing';
      batch.name = '图片批次';
      const snapshot: WidgetSnapshot = WidgetSnapshot.from([], [batch], false);
      expect(snapshot.count).assertEqual('1');
      expect(snapshot.status).assertEqual('正在打包');
      expect(snapshot.name).assertEqual('图片批次');
      expect(snapshot.progress).assertEqual('正在打包');
    });
  });
}
