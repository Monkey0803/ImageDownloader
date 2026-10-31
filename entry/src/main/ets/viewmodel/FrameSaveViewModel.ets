import { DownloadStore } from '../service/DownloadStore';
import { ActionOutcome } from '../service/FileActions';
import { FrameSaveDestination, ImageTools } from '../service/ImageTools';

/** Saving an animation frame is a cancellable business action, independent of frame rendering. */
@ObservedV2
export class FrameSaveViewModel {
  @Trace exporting: boolean = false;
  @Trace choosingDestination: boolean = false;
  @Trace notice: string = '';
  private generation: number = 0;
  private alive: boolean = false;

  start(): void { this.alive = true; }
  stop(): void { this.alive = false; this.generation++; }
  reset(): void {
    this.generation++;
    this.exporting = false;
    this.choosingDestination = false;
    this.notice = '';
  }

  async save(path: string, name: string, index: number,
    chooseDestination: () => Promise<FrameSaveDestination | undefined>): Promise<void> {
    if (!this.alive || this.exporting || this.choosingDestination || path.length === 0) { return; }
    const generation: number = this.generation;
    this.notice = '';
    this.choosingDestination = true;
    let destination: FrameSaveDestination | undefined = undefined;
    try {
      destination = await chooseDestination();
    } catch (error) {
      const message: string = String(error).toLowerCase();
      if (this.alive && generation === this.generation && !message.includes('cancel') && !message.includes('取消')) {
        this.notice = '无法打开保存选项，可重试';
      }
      return;
    } finally {
      if (this.alive && generation === this.generation) { this.choosingDestination = false; }
    }
    if (!this.alive || generation !== this.generation || destination === undefined) { return; }
    this.exporting = true;
    try {
      const outcome: ActionOutcome = await ImageTools.saveFrame(DownloadStore.context, path, name, index, destination);
      if (this.alive && generation === this.generation) { this.notice = outcome.message; }
    } catch (error) {
      if (this.alive && generation === this.generation) { this.notice = '当前帧保存失败，可重试'; }
    } finally {
      if (this.alive && generation === this.generation) { this.exporting = false; }
    }
  }
}
