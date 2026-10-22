import { describe, it, expect } from '@ohos/hypium';
import { DownloadItem, SavedState, ZipItem } from '../../../main/ets/model/Models';
import { ReceiptWire } from '../../../main/ets/model/SaveReceipt';
import { StoreState } from '../../../main/ets/service/StoreState';

export default function saveReceiptTest() {
  describe('SaveReceipt', () => {
    it('old_records_do_not_claim_an_unverified_external_copy', 0, () => {
      const receipt = ReceiptWire.restore(undefined);
      expect(receipt.status).assertEqual('');
      expect(receipt.message).assertEqual('');
    });

    it('round_trips_download_and_archive_receipts_without_proxy_names', 0, () => {
      const state: SavedState = new SavedState();
      const item: DownloadItem = new DownloadItem();
      item.id = 'image';
      item.status = 'completed';
      item.receipt.target = 'gallery';
      item.receipt.status = 'saved';
      item.receipt.parts = ['image'];
      item.receipt.message = '已另存到系统相册';
      item.recoveryMessage = '本次从头重新下载';
      state.downloads = [item];
      const zip: ZipItem = new ZipItem();
      zip.receipt.target = 'custom';
      zip.receipt.folderUri = 'file://docs/folder';
      zip.receipt.status = 'failed';
      state.zips = [zip];
      const raw: string = StoreState.serialize(state);
      expect(raw.includes('__ob_')).assertFalse();
      const safe: SavedState = StoreState.normalized(StoreState.parse(raw) ?? new SavedState());
      expect(safe.downloads[0].receipt.status).assertEqual('saved');
      expect(safe.downloads[0].receipt.parts.join(',')).assertEqual('image');
      expect(safe.downloads[0].recoveryMessage).assertEqual('本次从头重新下载');
      expect(safe.zips[0].receipt.folderUri).assertEqual('file://docs/folder');
    });

    it('marks_interrupted_confirmation_without_forgetting_successful_parts', 0, () => {
      const pending: ReceiptWire = new ReceiptWire();
      pending.target = 'gallery';
      pending.status = 'pending';
      pending.parts = ['still'];
      const restored = ReceiptWire.restore(pending);
      expect(restored.status).assertEqual('interrupted');
      expect(restored.parts.join(',')).assertEqual('still');
      expect(restored.message.includes('未确认')).assertTrue();
    });
  });
}
