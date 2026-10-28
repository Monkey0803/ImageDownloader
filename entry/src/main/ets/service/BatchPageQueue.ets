import { BatchPageGroup, BatchPageGroups, BatchPageResult } from './BatchPageGroups';

/** Serial browser ownership, with a generation boundary around every asynchronous result. */
export class BatchPageQueue {
  private generation: number = 0;

  cancel(): void { this.generation++; }

  async run(groups: BatchPageGroup[], resolve: (group: BatchPageGroup) => Promise<BatchPageResult>,
    changed: () => void): Promise<void> {
    const generation: number = ++this.generation;
    for (const group of groups) {
      if (generation !== this.generation) { return; }
      if (group.status === 'ready') { continue; }
      group.status = 'loading'; group.message = ''; changed();
      try {
        const result: BatchPageResult = await resolve(group);
        if (generation !== this.generation) { return; }
        BatchPageGroups.accept(group, result);
      } catch (error) {
        if (generation !== this.generation) { return; }
        group.status = 'failed';
        group.message = error instanceof Error ? error.message : '网页解析失败，请重试';
      }
      changed();
    }
  }
}
