import { describe, it, expect } from '@ohos/hypium';
import { GalleryBatchOutcome, GalleryCopyOutcome, GalleryCopyResult, GallerySaveOutcome,
  copyGalleryTargets, saveGalleryBatches } from
  '../../../main/ets/service/GalleryBatching';

function files(count: number): string[] {
  const result: string[] = [];
  for (let i: number = 0; i < count; i++) {
    result.push(i.toString() + '.jpg');
  }
  return result;
}

function saved(count: number): GalleryBatchOutcome {
  return { savedCount: count, cancelled: false, message: '', downgraded: false };
}

export default function galleryBatchingTest() {
  describe('GalleryBatching', () => {
    it('saves_100_101_and_205_files_in_sequential_groups_without_repeats', 0, async () => {
      for (const total of [100, 101, 205]) {
        const input: string[] = files(total);
        const seen: string[] = [];
        const sizes: number[] = [];
        const result: GallerySaveOutcome = await saveGalleryBatches(input, input,
          async (paths: string[], names: string[]): Promise<GalleryBatchOutcome> => {
            sizes.push(paths.length);
            expect(paths.join(',')).assertEqual(names.join(','));
            for (const path of paths) {
              seen.push(path);
            }
            return saved(paths.length);
          });
        expect(result.ok).assertTrue();
        expect(result.savedCount).assertEqual(total);
        expect(result.remainingCount).assertEqual(0);
        expect(seen.join(',')).assertEqual(input.join(','));
        expect(sizes.join(',')).assertEqual(total === 100 ? '100' : total === 101 ? '100,1' : '100,100,5');
      }
    });

    it('stops_after_second_group_is_cancelled_and_reports_partial_save', 0, async () => {
      let calls: number = 0;
      const input: string[] = files(205);
      const result: GallerySaveOutcome = await saveGalleryBatches(input, input,
        async (paths: string[]): Promise<GalleryBatchOutcome> => {
          calls++;
          return calls === 1 ? saved(paths.length)
            : { savedCount: 0, cancelled: true, message: '', downgraded: false };
        });
      expect(calls).assertEqual(2);
      expect(result.ok).assertFalse();
      expect(result.cancelled).assertTrue();
      expect(result.savedCount).assertEqual(100);
      expect(result.remainingCount).assertEqual(105);
      expect(result.message.indexOf('已保存 100 张') >= 0).assertTrue();
    });

    it('counts_only_copied_files_when_second_group_fails', 0, async () => {
      let calls: number = 0;
      const input: string[] = files(205);
      const result: GallerySaveOutcome = await saveGalleryBatches(input, input,
        async (paths: string[]): Promise<GalleryBatchOutcome> => {
          calls++;
          return calls === 1 ? saved(paths.length)
            : { savedCount: 97, cancelled: false, message: '系统返回的相册位置不足或复制失败',
              downgraded: false };
        });
      expect(calls).assertEqual(2);
      expect(result.ok).assertFalse();
      expect(result.savedCount).assertEqual(197);
      expect(result.remainingCount).assertEqual(8);
      expect(result.message.indexOf('另有 8 张未保存') >= 0).assertTrue();
    });

    it('does_not_count_missing_targets_or_failed_copies', 0, async () => {
      const seen: number[] = [];
      const result: GalleryCopyResult = await copyGalleryTargets(5, ['a', 'b', 'c', 'd'],
        async (index: number): Promise<GalleryCopyOutcome> => {
          seen.push(index);
          return { ok: index !== 2, message: index === 2 ? '复制失败' : '' };
        });
      expect(seen.join(',')).assertEqual('0,1,2,3');
      expect(result.savedIndices.join(',')).assertEqual('0,1,3');
      expect(result.error.length > 0).assertTrue();
    });

    it('treats_first_cancellation_as_cancel_without_failure', 0, async () => {
      const input: string[] = files(101);
      const result: GallerySaveOutcome = await saveGalleryBatches(input, input,
        async (): Promise<GalleryBatchOutcome> =>
          ({ savedCount: 0, cancelled: true, message: '', downgraded: false }));
      expect(result.cancelled).assertTrue();
      expect(result.savedCount).assertEqual(0);
      expect(result.remainingCount).assertEqual(101);
      expect(result.message).assertEqual('已取消保存到系统相册');
    });

    it('does_not_open_another_dialog_after_delivery_stops', 0, async () => {
      const input: string[] = files(101);
      let active: boolean = true;
      let calls: number = 0;
      const result: GallerySaveOutcome = await saveGalleryBatches(input, input,
        async (paths: string[]): Promise<GalleryBatchOutcome> => {
          calls++;
          active = false;
          return saved(paths.length);
        }, (): boolean => active);
      expect(calls).assertEqual(1);
      expect(result.cancelled).assertTrue();
      expect(result.savedCount).assertEqual(100);
      expect(result.remainingCount).assertEqual(1);
    });

    it('reports_static_frame_fallback_after_every_group_succeeds', 0, async () => {
      const input: string[] = files(101);
      let calls: number = 0;
      const result: GallerySaveOutcome = await saveGalleryBatches(input, input,
        async (paths: string[]): Promise<GalleryBatchOutcome> => {
          calls++;
          return { savedCount: paths.length, cancelled: false, message: '', downgraded: calls === 2 };
        });
      expect(result.ok).assertTrue();
      expect(result.message.indexOf('按静态图保存') >= 0).assertTrue();
    });
  });
}
