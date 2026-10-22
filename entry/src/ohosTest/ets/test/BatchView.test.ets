import { describe, it, expect } from '@ohos/hypium';
import { BatchItem, DownloadItem } from '../../../main/ets/model/Models';
import { batchViewOf } from '../../../main/ets/model/BatchView';

function member(status: string): DownloadItem {
  const item: DownloadItem = new DownloadItem();
  item.status = status;
  return item;
}

export default function batchViewTest() {
  describe('BatchView', () => {
    it('reports_waiting_until_a_member_starts_transferring', 0, () => {
      const batch: BatchItem = new BatchItem();
      const waiting: DownloadItem = member('waiting');
      const done: DownloadItem = member('completed');
      expect(batchViewOf(batch, [done, waiting], 1, 0).status).assertEqual('waiting');
      waiting.status = 'running';
      expect(batchViewOf(batch, [done, waiting], 1, 0).status).assertEqual('downloading');
      waiting.status = 'completed';
      expect(batchViewOf(batch, [done, waiting], 2, 0).status).assertEqual('packing');
    });

    it('keeps_active_transfers_visible_in_mixed_batches', 0, () => {
      const batch: BatchItem = new BatchItem();
      expect(batchViewOf(batch, [member('waiting'), member('running')], 0, 0).status)
        .assertEqual('downloading');
      expect(batchViewOf(batch, [member('waiting'), member('starting')], 0, 0).status)
        .assertEqual('downloading');
      expect(batchViewOf(batch, [member('waiting'), member('queued')], 0, 0).status)
        .assertEqual('waiting');
    });

    it('preserves_terminal_batch_states_without_members', 0, () => {
      const batch: BatchItem = new BatchItem();
      batch.status = 'failed';
      expect(batchViewOf(batch, [], 0, 0).status).assertEqual('failed');
      batch.status = 'completed';
      expect(batchViewOf(batch, [], 0, 0).status).assertEqual('completed');
    });
  });
}
