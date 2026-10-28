/** Value-only progress. Unknown totals remain unknown rather than showing a fabricated percentage. */
export class PreviewLoadProgress {
  phase: string = 'connecting';
  received: number = 0;
  total: number = 0;

  static value(phase: string, received: number = 0, total: number = 0): PreviewLoadProgress {
    const result: PreviewLoadProgress = new PreviewLoadProgress();
    result.phase = phase;
    result.received = Math.max(0, received);
    result.total = Number.isFinite(total) && total >= received ? total : 0;
    return result;
  }
}
