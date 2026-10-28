import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { PreviewTransfer } from './PreviewTransfer';
import { PreviewLoadProgress } from '../model/PreviewLoadProgress';
import { PreviewGeometry, PreviewSize } from '../util/PreviewGeometry';

export class ThumbnailRequest {
  cancelled: boolean = false;
  onCancel: () => void = (): void => {};
  cancel(): void { this.cancelled = true; this.onCancel(); this.onCancel = (): void => {}; }
}

class ThumbnailJob {
  waiters: Set<ThumbnailRequest> = new Set<ThumbnailRequest>();
  transfer: PreviewTransfer | undefined = undefined;
  promise: Promise<string> = Promise.resolve('');
}

interface ThumbnailEntry { path: string; bytes: number; }

/** Grid-only, unauthenticated thumbnails. Crop before scaling so long-image details stay legible. */
export class ThumbnailImages {
  private static cache: Map<string, ThumbnailEntry> = new Map<string, ThumbnailEntry>();
  private static pending: Map<string, ThumbnailJob> = new Map<string, ThumbnailJob>();
  private static queue: (() => void)[] = [];
  private static running: number = 0;
  private static sequence: number = 0;
  private static directory: string = '';

  static async load(uri: string, cacheDir: string, aspect: number, contain: boolean, request: ThumbnailRequest): Promise<string> {
    if (request.cancelled || uri.length === 0 || cacheDir.length === 0) { return ''; }
    let path: string = uri;
    let revision: string = '';
    const remote: boolean = /^https?:\/\//i.test(uri);
    try {
      if (!remote) {
        path = uri.startsWith('file://') ? new fileUri.FileUri(uri).path : uri;
        const stat: fs.Stat = fs.statSync(path);
        revision = ':' + stat.size.toString() + ':' + stat.mtime.toString();
      }
      const ratio: number = Number.isFinite(aspect) && aspect > 0 ? Math.round(aspect * 100) / 100 : 1;
      const key: string = uri + revision + ':' + ratio.toString() + ':' + contain.toString();
      const cached: ThumbnailEntry | undefined = ThumbnailImages.cache.get(key);
      if (cached !== undefined) {
        ThumbnailImages.cache.delete(key); ThumbnailImages.cache.set(key, cached);
        return fileUri.getUriFromPath(cached.path);
      }
      let job: ThumbnailJob | undefined = ThumbnailImages.pending.get(key);
      if (job === undefined) {
        job = new ThumbnailJob();
        job.waiters.add(request);
        ThumbnailImages.pending.set(key, job);
        job.promise = ThumbnailImages.make(path, remote, cacheDir, ratio, contain, key, job);
      } else { job.waiters.add(request); }
      const current: ThumbnailJob = job;
      request.onCancel = (): void => {
        current.waiters.delete(request);
        if (current.waiters.size === 0) {
          current.transfer?.cancel();
          if (ThumbnailImages.pending.get(key) === current) { ThumbnailImages.pending.delete(key); }
        }
      };
      try {
        const result: string = await current.promise;
        return request.cancelled ? '' : result;
      } finally {
        request.onCancel = (): void => {};
        current.waiters.delete(request);
        if (ThumbnailImages.pending.get(key) === current) { ThumbnailImages.pending.delete(key); }
      }
    } catch (error) { return ''; }
  }

  private static async slot(): Promise<void> {
    if (ThumbnailImages.running >= 2) {
      await new Promise<void>((resolve): void => { ThumbnailImages.queue.push(resolve); });
    } else { ThumbnailImages.running++; }
  }

  private static done(): void {
    const next: (() => void) | undefined = ThumbnailImages.queue.shift();
    if (next !== undefined) { next(); } else { ThumbnailImages.running--; }
  }

  private static folder(cacheDir: string): string {
    if (ThumbnailImages.directory.length > 0) { return ThumbnailImages.directory; }
    const path: string = cacheDir + '/grid-thumbnails';
    try { fs.mkdirSync(path); } catch (error) {}
    // Session keys are never persisted; discard leftovers after a previous process exit.
    for (const name of fs.listFileSync(path)) {
      if (/^thumb-\d+\.(source|png)$/.test(name)) { ThumbnailImages.remove(path + '/' + name); }
    }
    ThumbnailImages.directory = path;
    return path;
  }

  private static async make(input: string, remote: boolean, cacheDir: string, aspect: number,
    contain: boolean, key: string, job: ThumbnailJob): Promise<string> {
    await ThumbnailImages.slot();
    let raw: string = '';
    let output: string = '';
    let kept: boolean = false;
    let source: image.ImageSource | undefined = undefined;
    let frame: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    let file: fs.File | undefined = undefined;
    try {
      if (job.waiters.size === 0) { return ''; }
      const base: string = ThumbnailImages.folder(cacheDir) + '/thumb-' + (++ThumbnailImages.sequence).toString();
      output = base + '.png';
      let path: string = input;
      if (remote) {
        raw = base + '.source';
        const transfer: PreviewTransfer = new PreviewTransfer();
        job.transfer = transfer;
        const result = await transfer.run(input, '', '', raw, (value: PreviewLoadProgress): void => {}, 5);
        if (result.failure.length > 0 || result.code !== 200 || result.bytes === 0) { return ''; }
        path = raw;
      }
      if (job.waiters.size === 0) { return ''; }
      source = image.createImageSource(path);
      const info: image.ImageInfo = await source.getImageInfo();
      const width: number = info.size.width;
      const height: number = info.size.height;
      if (width <= 0 || height <= 0) { return ''; }
      const cropWidth: number = contain ? width : Math.max(1, Math.min(width, Math.floor(height * aspect)));
      const cropHeight: number = contain ? height : Math.max(1, Math.min(height, Math.floor(width / aspect)));
      const size: PreviewSize = PreviewGeometry.decodeSize({ width: cropWidth, height: cropHeight },
        contain ? 2048 : 512, contain ? 3000000 : 262144);
      frame = await source.createPixelMap({ index: 0,
        desiredRegion: { x: Math.floor((width - cropWidth) / 2), y: Math.floor((height - cropHeight) / 2),
          size: { width: cropWidth, height: cropHeight } },
        desiredSize: { width: size.width, height: size.height }, cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST });
      if (job.waiters.size === 0) { return ''; }
      packer = image.createImagePacker();
      file = fs.openSync(output, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      await packer.packToFile(frame, file.fd, { format: 'image/png', quality: 100 });
      fs.closeSync(file); file = undefined;
      if (job.waiters.size === 0) { return ''; }
      const bytes: number = fs.statSync(output).size;
      ThumbnailImages.cache.set(key, { path: output, bytes: bytes });
      kept = true;
      ThumbnailImages.trim();
      return fileUri.getUriFromPath(output);
    } catch (error) { return ''; }
    finally {
      if (file !== undefined) { try { fs.closeSync(file); } catch (error) {} }
      if (packer !== undefined) { try { await packer.release(); } catch (error) {} }
      if (frame !== undefined) { try { await frame.release(); } catch (error) {} }
      if (source !== undefined) { try { await source.release(); } catch (error) {} }
      job.transfer = undefined;
      ThumbnailImages.remove(raw);
      if (!kept) { ThumbnailImages.remove(output); }
      ThumbnailImages.done();
    }
  }

  private static trim(): void {
    let bytes: number = 0;
    for (const entry of ThumbnailImages.cache.values()) { bytes += entry.bytes; }
    for (const entry of ThumbnailImages.cache.entries()) {
      if (ThumbnailImages.cache.size <= 64 && bytes <= 32 * 1024 * 1024) { break; }
      ThumbnailImages.cache.delete(entry[0]); bytes -= entry[1].bytes;
      ThumbnailImages.remove(entry[1].path);
    }
  }

  private static remove(path: string): void {
    if (path.length === 0) { return; }
    try { fs.unlinkSync(path); } catch (error) {}
  }
}
