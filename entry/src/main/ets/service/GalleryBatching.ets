/** 系统相册确认框一次最多接收 100 个实际文件。 */
export const GALLERY_BATCH_LIMIT: number = 100;

export interface GalleryBatchOutcome {
  savedIndices?: number[];
  savedCount: number;
  cancelled: boolean;
  message: string;
  downgraded: boolean;
}

export interface GallerySaveOutcome {
  ok: boolean;
  cancelled: boolean;
  message: string;
  savedCount: number;
  remainingCount: number;
}

export interface GalleryCopyOutcome {
  ok: boolean;
  message: string;
}

export interface GalleryCopyResult {
  savedIndices: number[];
  error: string;
}

/** 目标地址不足或复制失败的文件不能计入已保存数量。 */
export async function copyGalleryTargets(count: number, targets: string[],
  copy: (index: number, target: string) => Promise<GalleryCopyOutcome>): Promise<GalleryCopyResult> {
  const savedIndices: number[] = [];
  let error: string = targets.length < count ? '系统返回的相册位置不足' : '';
  for (let i: number = 0; i < count && i < targets.length; i++) {
    const outcome: GalleryCopyOutcome = await copy(i, targets[i]);
    if (outcome.ok) {
      savedIndices.push(i);
    } else {
      error = outcome.message;
    }
  }
  return { savedIndices: savedIndices, error: error };
}

/** 每批完成后才请求下一批；任何取消或失败都会保留已经成功保存的部分。 */
export async function saveGalleryBatches(paths: string[], names: string[],
  saveBatch: (batchPaths: string[], batchNames: string[]) => Promise<GalleryBatchOutcome>,
  shouldContinue: () => boolean = (): boolean => true): Promise<GallerySaveOutcome> {
  const total: number = Math.min(paths.length, names.length);
  let saved: number = 0;
  let downgraded: boolean = false;
  for (let start: number = 0; start < total; start += GALLERY_BATCH_LIMIT) {
    if (!shouldContinue()) {
      const remaining: number = total - saved;
      return { ok: false, cancelled: true,
        message: saved === 0 ? '已取消保存到系统相册'
          : '已保存 ' + saved.toString() + ' 张，另有 ' + remaining.toString() + ' 张未保存；后续保存已取消',
        savedCount: saved, remainingCount: remaining };
    }
    const end: number = Math.min(start + GALLERY_BATCH_LIMIT, total);
    const result: GalleryBatchOutcome = await saveBatch(paths.slice(start, end), names.slice(start, end));
    saved += result.savedCount;
    downgraded = downgraded || result.downgraded;
    if (result.cancelled || result.savedCount !== end - start) {
      const remaining: number = total - saved;
      if (result.cancelled && saved === 0) {
        return { ok: false, cancelled: true, message: '已取消保存到系统相册', savedCount: 0,
          remainingCount: remaining };
      }
      const detail: string = result.cancelled ? '后续保存已取消' : (result.message || '保存失败');
      return { ok: false, cancelled: result.cancelled,
        message: '已保存 ' + saved.toString() + ' 张，另有 ' + remaining.toString() + ' 张未保存；' + detail,
        savedCount: saved, remainingCount: remaining };
    }
  }
  if (total === 0) {
    return { ok: true, cancelled: false, message: '', savedCount: 0, remainingCount: 0 };
  }
  const summary: string = total > 1 ? '已保存 ' + total.toString() + ' 张到系统相册' : '已保存到系统相册';
  return { ok: true, cancelled: false,
    message: downgraded ? summary + '（部分动图按静态图保存，动画没有保留）' : summary,
    savedCount: total, remainingCount: 0 };
}
