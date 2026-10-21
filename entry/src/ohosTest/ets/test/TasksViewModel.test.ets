import { describe, it, expect, afterEach } from '@ohos/hypium';
import { BatchItem, DownloadItem } from '../../../main/ets/model/Models';
import { DownloadStore } from '../../../main/ets/service/DownloadStore';
import { TasksViewModel } from '../../../main/ets/viewmodel/TasksViewModel';

function task(id: string, status: string, batchId: string = ''): DownloadItem {
  const item: DownloadItem = new DownloadItem();
  item.id = id;
  item.status = status;
  item.batchId = batchId;
  return item;
}

export default function tasksViewModelTest() {
  describe('TasksViewModel.sync', () => {
    afterEach(() => {
      DownloadStore.downloads = [];
      DownloadStore.batches = [];
    });

    it('shows_failed_zip_batch_instead_of_empty_state', 0, () => {
      const batch: BatchItem = new BatchItem();
      batch.id = 'zip';
      batch.status = 'failed';
      DownloadStore.batches = [batch];
      DownloadStore.downloads = [task('a', 'failed', 'zip'), task('b', 'failed', 'zip')];

      const model: TasksViewModel = new TasksViewModel();
      model.sync();
      expect(model.batchViews.length).assertEqual(1);
      expect(model.batchViews[0].status).assertEqual('failed');
      expect(model.isEmpty()).assertFalse();
      expect(model.running).assertEqual(0);
    });

    it('keeps_waiting_and_paused_tasks_visible_while_batch_counts_once', 0, () => {
      const batch: BatchItem = new BatchItem();
      batch.id = 'zip';
      DownloadStore.batches = [batch];
      DownloadStore.downloads = [
        task('waiting', 'waiting'), task('paused', 'paused'),
        task('queued-in-zip', 'queued', 'zip'), task('done-in-zip', 'completed', 'zip')
      ];

      const model: TasksViewModel = new TasksViewModel();
      model.sync();
      expect(model.active.length).assertEqual(2);
      expect(model.settled.length).assertEqual(0);
      expect(model.batchViews[0].total).assertEqual(2);
      expect(model.batchViews[0].done).assertEqual(1);
      expect(model.running).assertEqual(4);
      expect(model.isEmpty()).assertFalse();
    });
  });
}
