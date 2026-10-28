import { image } from '@kit.ImageKit';
import { PreviewGeometry, PreviewSize } from '../util/PreviewGeometry';

export interface AnimationFrameInfo {
  index: number;
  count: number;
  width: number;
  height: number;
  transparent: boolean;
}

/** Decode frames on demand. Only the displayed frame and one pending frame are resident. */
export class AnimationPlayback {
  private alive: boolean = true;
  private playing: boolean = true;
  private wake: (() => void) | undefined = undefined;
  private timer: number = -1;

  pause(): void { this.playing = false; this.interrupt(); }
  resume(): void { this.playing = true; this.interrupt(); }
  stop(): void { this.alive = false; this.interrupt(); }

  private interrupt(): void {
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    const wake: (() => void) | undefined = this.wake;
    this.wake = undefined;
    if (wake !== undefined) { wake(); }
  }

  private wait(delay: number): Promise<void> {
    return new Promise<void>((resolve): void => {
      this.wake = resolve;
      if (delay >= 0) {
        this.timer = setTimeout((): void => { this.timer = -1; this.wake = undefined; resolve(); }, delay);
      }
    });
  }

  async run(path: string, onFrame: (frame: image.PixelMap, info: AnimationFrameInfo) => void,
    onError: () => void, startIndex: number = 0): Promise<void> {
    let source: image.ImageSource | undefined = undefined;
    let displayed: image.PixelMap | undefined = undefined;
    let pending: image.PixelMap | undefined = undefined;
    try {
      source = image.createImageSource(path);
      const info: image.ImageInfo = await source.getImageInfo();
      const count: number = Math.max(1, await source.getFrameCount());
      let delays: number[] = [];
      if (count > 1) { delays = await source.getDelayTimeList(); }
      const size: PreviewSize = PreviewGeometry.decodeSize({ width: info.size.width, height: info.size.height }, 3072, 4000000);
      let index: number = Math.max(0, Math.min(count - 1, Math.floor(startIndex)));
      let first: boolean = true;
      while (this.alive) {
        if (!first && !this.playing) { await this.wait(-1); continue; }
        const started: number = Date.now();
        pending = await source.createPixelMap({ index: index, desiredSize: { width: size.width, height: size.height } });
        if (!this.alive) { break; }
        if (!first && !this.playing) { await pending.release(); pending = undefined; continue; }
        const previous: image.PixelMap | undefined = displayed;
        displayed = pending;
        pending = undefined;
        onFrame(displayed, { index: index, count: count, width: info.size.width, height: info.size.height,
          transparent: info.alphaType !== image.AlphaType.OPAQUE });
        if (previous !== undefined) { await previous.release(); }
        first = false;
        if (count === 1) { await this.wait(-1); continue; }
        const delay: number = Math.max(20, Math.min(60000, delays[index] || 100));
        index = (index + 1) % count;
        if (this.alive && this.playing) { await this.wait(Math.max(0, delay - (Date.now() - started))); }
      }
    } catch (error) { if (this.alive) { onError(); } }
    finally {
      this.interrupt();
      if (pending !== undefined) { try { await pending.release(); } catch (error) {} }
      if (displayed !== undefined) { try { await displayed.release(); } catch (error) {} }
      if (source !== undefined) { try { await source.release(); } catch (error) {} }
    }
  }
}
