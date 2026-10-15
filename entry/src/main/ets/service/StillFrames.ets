import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { MediaFormat } from './MediaFormat';

/*
 * StillFrames.ets — 动图的「静止首帧」与「是否动图」。
 *
 * 为什么需要它：ArkUI 的 Image 组件会自己播放 GIF / WebP 动图，**没有「只画第一帧」的开关**。
 * 图库里几十个格子同时播动画既费电又晃眼，所以网格里的动图要换成「解码第 0 帧成 PixelMap」再画。
 *
 * 两条缓存都按**文件路径**做键（路径在一次下载里是稳定的）：
 *   - `animated`：头部判定结果，避免每次重建组件都读一次文件头；
 *   - `frames`：首帧 PixelMap，FIFO 上限 64，淘汰时 release() 掉，防止大动图把内存吃穿。
 *
 * 首帧解码按长边封顶 512，因为网格格子最多也就一两百 vp：全尺寸解码 1080p 一帧就是 8 MB。
 */

/** 读文件头时最多读多少字节：GIF/WebP 的动图标记都在最前面，64 KB 足够。 */
const HEADER_BYTES: number = 64 * 1024;

/** 首帧解码的长边上限（像素）。 */
const FRAME_MAX_EDGE: number = 512;

/** 首帧缓存条数上限。 */
const FRAME_CACHE_LIMIT: number = 64;

export class StillFrames {
  private static animated: Map<string, boolean> = new Map<string, boolean>();
  private static frames: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  /** 与 frames 同步的先进先出顺序，用来挑淘汰对象。 */
  private static order: string[] = [];

  /** 读文件开头若干字节；读不到（文件不存在 / 无权限）返回 undefined。 */
  static readHeader(path: string, length: number): Uint8Array | undefined {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(path).size;
      const wanted: number = Math.min(length, size);
      if (wanted <= 0) {
        return undefined;
      }
      const buffer: ArrayBuffer = new ArrayBuffer(wanted);
      const read: number = fs.readSync(file.fd, buffer);
      return new Uint8Array(buffer.slice(0, read));
    } catch (error) {
      return undefined;
    } finally {
      StillFrames.close(file);
    }
  }

  /**
   * 这个本地文件是不是动图。
   *
   * 先按扩展名筛（只有 gif/webp 才值得读文件头），再交给 MediaFormat 做字节判定；
   * 读不到文件头时按静态处理：宁可网格里不播，也不要因为一次读失败就乱播。
   */
  static isAnimatedFile(path: string): boolean {
    const cached: boolean | undefined = StillFrames.animated.get(path);
    if (cached !== undefined) {
      return cached;
    }
    const extension: string = MediaFormat.extensionOf(path);
    let result: boolean = false;
    if (MediaFormat.isAnimatedExt(extension)) {
      const header: Uint8Array | undefined = StillFrames.readHeader(path, HEADER_BYTES);
      if (header !== undefined) {
        result = extension === 'gif'
          ? MediaFormat.gifLooksAnimated(header)
          : MediaFormat.webpLooksAnimated(header);
      }
    }
    StillFrames.animated.set(path, result);
    return result;
  }

  /** 同步取已缓存的首帧；没缓存就返回 undefined（调用方再去 await stillFrame）。 */
  static cachedFrame(path: string): image.PixelMap | undefined {
    return StillFrames.frames.get(path);
  }

  /**
   * 解码第 0 帧并缓存。
   *
   * 失败返回 undefined：调用方回落成直接画原文件（动图就是会动，静态图没有区别），
   * 不影响任何一条主流程。
   */
  static async stillFrame(path: string): Promise<image.PixelMap | undefined> {
    const cached: image.PixelMap | undefined = StillFrames.frames.get(path);
    if (cached !== undefined) {
      return cached;
    }
    let source: image.ImageSource | undefined = undefined;
    try {
      source = image.createImageSource(path);
      const info: image.ImageInfo = await source.getImageInfo();
      const options: image.DecodingOptions = {
        index: 0,
        desiredSize: StillFrames.frameSize(info.size)
      };
      const frame: image.PixelMap = await source.createPixelMap(options);
      StillFrames.store(path, frame);
      return frame;
    } catch (error) {
      return undefined;
    } finally {
      if (source !== undefined) {
        try {
          await source.release();
        } catch (error) {
        }
      }
    }
  }

  /** 清空两份缓存：删除、清空图库后调用，免得缓存里留着已删文件的 PixelMap。 */
  static clear(): void {
    for (const frame of StillFrames.frames.values()) {
      StillFrames.releaseQuietly(frame);
    }
    StillFrames.frames.clear();
    StillFrames.animated.clear();
    StillFrames.order = [];
  }

  /** 忘掉一个文件的判定与首帧（删除单条记录时调用；比 clear() 精确，不牵连别家）。 */
  static forget(path: string): void {
    if (path.length === 0) {
      return;
    }
    StillFrames.animated.delete(path);
    const frame: image.PixelMap | undefined = StillFrames.frames.get(path);
    if (frame === undefined) {
      return;
    }
    StillFrames.frames.delete(path);
    StillFrames.order = StillFrames.order.filter((entry: string): boolean => entry !== path);
    StillFrames.releaseQuietly(frame);
  }

  /** 首帧的目标尺寸：长边不超过 FRAME_MAX_EDGE，短边按比例缩。 */
  private static frameSize(size: image.Size): image.Size {
    const width: number = size.width;
    const height: number = size.height;
    const longest: number = Math.max(width, height);
    if (longest <= FRAME_MAX_EDGE || longest <= 0) {
      return { width: width, height: height };
    }
    const scale: number = FRAME_MAX_EDGE / longest;
    return {
      width: Math.max(1, Math.round(width * scale)),
      height: Math.max(1, Math.round(height * scale))
    };
  }

  private static store(path: string, frame: image.PixelMap): void {
    if (StillFrames.frames.has(path)) {
      StillFrames.frames.set(path, frame);
      return;
    }
    if (StillFrames.order.length >= FRAME_CACHE_LIMIT) {
      const oldest: string = StillFrames.order.shift() ?? '';
      if (oldest.length > 0) {
        const evicted: image.PixelMap | undefined = StillFrames.frames.get(oldest);
        StillFrames.frames.delete(oldest);
        if (evicted !== undefined) {
          StillFrames.releaseQuietly(evicted);
        }
      }
    }
    StillFrames.frames.set(path, frame);
    StillFrames.order.push(path);
  }

  private static releaseQuietly(frame: image.PixelMap): void {
    try {
      frame.release();
    } catch (error) {
    }
  }

  private static close(file: fs.File | undefined): void {
    if (file === undefined) {
      return;
    }
    try {
      fs.closeSync(file);
    } catch (error) {
    }
  }
}
