import { ScanData } from './PageScanner';

export interface ExpansionStep {
  data: ScanData;
  bottom: boolean;
}

/** 有界的当前页滚动采集；注入单步操作便于测试取消、迟到回调与自动停止。 */
export class PageExpansion {
  private generation: number = 0;
  private timer: number = -1;
  private wake: (() => void) | undefined = undefined;

  stop(): void {
    this.generation++;
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    this.wake?.();
    this.wake = undefined;
  }

  private wait(delay: number): Promise<void> {
    return new Promise<void>((resolve): void => {
      this.wake = resolve;
      this.timer = setTimeout((): void => {
        this.timer = -1;
        this.wake = undefined;
        resolve();
      }, delay);
    });
  }

  async run(url: string, existing: string[], step: () => Promise<ExpansionStep>,
    progress: (data: ScanData, added: number) => void,
    settled: (added: number, limited: boolean) => void,
    failed: () => void, delay: number = 900): Promise<void> {
    this.stop();
    const generation: number = this.generation;
    const seen: Set<string> = new Set<string>(existing);
    let added: number = 0;
    let stableBottom: number = 0;
    const started: number = Date.now();
    try {
      for (let round: number = 0; round < 12; round++) {
        await this.wait(delay);
        if (generation !== this.generation) { return; }
        const result: ExpansionStep = await step();
        if (generation !== this.generation) { return; }
        if (result.data.url !== url) { failed(); return; }
        let fresh: number = 0;
        for (const item of result.data.images) {
          if (!seen.has(item.url)) { seen.add(item.url); fresh++; }
        }
        added += fresh;
        stableBottom = result.bottom && fresh === 0 ? stableBottom + 1 : 0;
        progress(result.data, added);
        if (generation !== this.generation) { return; }
        if (stableBottom >= 3) { settled(added, false); return; }
        if (Date.now() - started >= 20000) { settled(added, true); return; }
      }
      settled(added, true);
    } catch (error) {
      if (generation === this.generation) { failed(); }
    }
  }
}
