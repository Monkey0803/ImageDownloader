import { describe, it, expect, afterEach } from '@ohos/hypium';
import { BatchItem, DownloadItem } from '../../../main/ets/model/Models';
import { BatchView } from '../../../main/ets/model/BatchView';
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

    it('captions_settled_records_instead_of_claiming_an_empty_queue', 0, () => {
      const model: TasksViewModel = new TasksViewModel();
      expect(model.caption()).assertEqual('队列为空');

      model.settled = [task('done', 'completed'), task('failed', 'failed')];
      expect(model.caption()).assertEqual('无进行中 · 已结束 2');

      model.settled = [];
      model.running = 1;
      expect(model.caption()).assertEqual('1 个任务进行中 · 并发 3');

      model.running = 0;
      model.batchViews = [new BatchView()];
      expect(model.caption()).assertEqual('有打包任务待处理');
    });

    it('hides_zero_counts_in_status_labels', 0, () => {
      DownloadStore.downloads = [task('a', 'completed'), task('b', 'completed')];

      const model: TasksViewModel = new TasksViewModel();
      model.sync();
      expect(model.statusLabels[0]).assertEqual('全部 2');
      expect(model.statusLabels[1]).assertEqual('进行中');
      expect(model.statusLabels[2]).assertEqual('已完成 2');
      expect(model.statusLabels[3]).assertEqual('失败');
      expect(model.statusLabels[4]).assertEqual('已取消');
    });

    it('hides_the_summary_when_nothing_is_active', 0, () => {
      DownloadStore.downloads = [task('done', 'completed')];
      const model: TasksViewModel = new TasksViewModel();
      model.sync();
      expect(model.summaryVisible).assertFalse();

      DownloadStore.downloads = [task('run', 'running')];
      model.sync();
      expect(model.summaryVisible).assertTrue();
    });

    it('settled_heading_follows_status_filter', 0, () => {
      DownloadStore.downloads = [task('a', 'completed'), task('b', 'failed')];
      const model: TasksViewModel = new TasksViewModel();
      model.sync();
      expect(model.rows.getData(0).title).assertEqual('已结束');
      expect(model.rows.getData(0).actionLabel).assertEqual('清理');

      model.setStatusFilter('completed');
      expect(model.rows.getData(0).title).assertEqual('已完成');

      model.setStatusFilter('failed');
      expect(model.rows.getData(0).title).assertEqual('失败');
      expect(model.rows.getData(0).actionLabel).assertEqual('');
    });

    it('search_filters_by_name_and_reports_no_match', 0, () => {
      const alpha: DownloadItem = task('a', 'completed');
      alpha.name = 'alpha.jpg';
      const beta: DownloadItem = task('b', 'completed');
      beta.name = 'beta.jpg';
      DownloadStore.downloads = [alpha, beta];

      const model: TasksViewModel = new TasksViewModel();
      model.sync();
      model.toggleSearch();
      expect(model.searching).assertTrue();
      expect(model.caption()).assertEqual('输入文件名搜索');

      model.setQuery('alpha');
      expect(model.settled.length).assertEqual(1);
      expect(model.caption()).assertEqual('搜索到 1 条');

      model.setQuery('zzz');
      expect(model.isEmpty()).assertTrue();
      expect(model.caption()).assertEqual('没有匹配的任务');

      model.endSearch();
      expect(model.searching).assertFalse();
      expect(model.settled.length).assertEqual(2);
    });

    it('marks_settled_rows_as_mixed_only_when_statuses_differ', 0, () => {
      DownloadStore.downloads = [task('a', 'completed'), task('b', 'completed')];
      const model: TasksViewModel = new TasksViewModel();
      model.sync();
      expect(model.settledMixed).assertFalse();

      DownloadStore.downloads = [task('a', 'completed'), task('b', 'failed')];
      model.sync();
      expect(model.settledMixed).assertTrue();
    });
  });
}
