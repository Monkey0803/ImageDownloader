import { webview } from '@kit.ArkWeb';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { PreviewGeometry, PreviewSize } from '../util/PreviewGeometry';
import { PreviewTransfer, PreviewTransferResult } from './PreviewTransfer';
import { PreviewLoadProgress } from '../model/PreviewLoadProgress';

export class PreviewResult {
  uri: string = '';
  path: string = '';
  width: number = 0;
  height: number = 0;
  animated: boolean = false;
  message: string = '';
  failure: string = '';
}

class PreviewEntry {
  key: string = '';
  thumbnail: string = '';
  result: PreviewResult = new PreviewResult();
  bytes: number = 0;
}

/** Session-only disk LRU: five visited pictures / 128 MiB. Credentials never persist. */
export class AuthenticatedPreview {
  private static sequence: number = 0;
  private transfer: PreviewTransfer | undefined = undefined;
  private generation: number = 0;
  private entries: PreviewEntry[] = [];

  static clearStale(cacheDir: string): void {
    try {
      for (const name of fs.listFileSync(cacheDir)) {
        if (/^inspection-preview-\d+-\d+\.(jpg|png|source)$/.test(name)) {
          try { fs.unlinkSync(cacheDir + '/' + name); } catch (error) {}
        }
      }
    } catch (error) {}
  }

  cancelRequest(): void {
    this.generation++;
    this.transfer?.cancel();
    this.transfer = undefined;
  }

  cancel(): void {
    this.cancelRequest();
    for (const entry of this.entries) { this.removeEntry(entry); }
    this.entries = [];
  }

  private remove(path: string): void {
    if (path.length === 0) { return; }
    try { fs.unlinkSync(path); } catch (error) {}
  }

  private removeEntry(entry: PreviewEntry): void {
    this.remove(entry.thumbnail);
    this.remove(entry.result.path);
  }

  private cached(key: string, force: boolean): PreviewResult | undefined {
    const at: number = this.entries.findIndex((entry: PreviewEntry): boolean => entry.key === key);
    if (at < 0) { return undefined; }
    const entry: PreviewEntry = this.entries.splice(at, 1)[0];
    try {
      if (!force && fs.statSync(entry.thumbnail).size > 0 && fs.statSync(entry.result.path).size > 0) {
        this.entries.push(entry);
        return entry.result;
      }
    } catch (error) {}
    this.removeEntry(entry);
    return undefined;
  }

  private remember(entry: PreviewEntry): void {
    this.entries.push(entry);
    let bytes: number = this.entries.reduce((total: number, item: PreviewEntry): number => total + item.bytes, 0);
    while (this.entries.length > 5 || bytes > 128 * 1024 * 1024) {
      const oldest: PreviewEntry | undefined = this.entries.shift();
      if (oldest === undefined) { break; }
      bytes -= oldest.bytes;
      this.removeEntry(oldest);
    }
  }

  private failure(kind: string, message: string): PreviewResult {
    const result: PreviewResult = new PreviewResult();
    result.failure = kind;
    result.message = message;
    return result;
  }

  async load(url: string, referer: string, cacheDir: string, force: boolean = false,
    onProgress: (progress: PreviewLoadProgress) => void = (progress: PreviewLoadProgress): void => {}): Promise<PreviewResult> {
    this.cancelRequest();
    const generation: number = this.generation;
    let source: image.ImageSource | undefined = undefined;
    let frame: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    let file: fs.File | undefined = undefined;
    let transfer: PreviewTransfer | undefined = undefined;
    const base: string = cacheDir + '/inspection-preview-' + Date.now().toString() + '-' + (++AuthenticatedPreview.sequence).toString();
    const raw: string = base + '.source';
    const thumbnail: string = base + '.png';
    let keep: boolean = false;
    let stage: string = 'network';
    try {
      const cookie: string = webview.WebCookieManager.fetchCookieSync(url);
      // Length-prefix fields so signed URLs and page strings cannot collide. Credentials stay in memory only.
      const key: string = url.length.toString() + ':' + url + referer.length.toString() + ':' + referer + cookie;
      const cached: PreviewResult | undefined = this.cached(key, force);
      if (cached !== undefined) { return cached; }
      transfer = new PreviewTransfer();
      this.transfer = transfer;
      const response: PreviewTransferResult = await transfer.run(url, referer, cookie, raw,
        (progress: PreviewLoadProgress): void => { if (generation === this.generation) { onProgress(progress); } });
      if (generation !== this.generation) { return new PreviewResult(); }
      if (response.failure === 'cancelled') { return this.failure('cancelled', '已取消加载，点重试继续查看'); }
      if (response.failure === 'size') { return this.failure('size', '文件较大，请下载原文件后查看（在线预览最多 64 MiB）'); }
      if (response.failure === 'timeout') { return this.failure('timeout', '加载等待过久，请重试或下载后查看'); }
      if (response.failure === 'storage') { return this.failure('storage', '预览缓存写入失败，请检查存储空间后重试'); }
      if (response.failure.length > 0) { return this.failure('network', '图片传输中断，请重试或下载原文件'); }
      if (response.code === 401 || response.code === 403) {
        return this.failure('login', '来源网站拒绝预览，请到来源页确认登录状态后重试');
      }
      if (response.code >= 300 && response.code < 400) {
        return this.failure('redirect', '图片地址发生跳转，请从来源页重新获取图片');
      }
      if (response.code !== 200) {
        return this.failure('network', '图片请求失败，可重试、查看来源页或下载原文件');
      }
      stage = 'decode';
      onProgress(PreviewLoadProgress.value('decoding', response.bytes, response.bytes));
      source = image.createImageSource(raw);
      const info: image.ImageInfo = await source.getImageInfo();
      if (info.size.width <= 0 || info.size.height <= 0) { throw new Error('Invalid image dimensions'); }
      const size: PreviewSize = PreviewGeometry.decodeSize({ width: info.size.width, height: info.size.height }, 1200, 1440000);
      frame = await source.createPixelMap({ index: 0, desiredSize: { width: size.width, height: size.height } });
      const result: PreviewResult = new PreviewResult();
      try { result.animated = await source.getFrameCount() > 1; } catch (error) {}
      if (generation !== this.generation) { return new PreviewResult(); }
      stage = 'storage';
      if (fs.statSync(raw).size !== response.bytes) { throw new Error('Incomplete preview cache write'); }
      packer = image.createImagePacker();
      file = fs.openSync(thumbnail, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      await packer.packToFile(frame, file.fd, { format: 'image/png', quality: 100 });
      fs.closeSync(file);
      file = undefined;
      if (generation !== this.generation) { return new PreviewResult(); }
      result.uri = fileUri.getUriFromPath(thumbnail);
      result.path = raw;
      result.width = info.size.width;
      result.height = info.size.height;
      result.message = result.animated ? '静态预览 · 动图首帧，下载后可播放' : '预览图 · 放大可查看更清晰细节';
      const entry: PreviewEntry = new PreviewEntry();
      entry.key = key;
      entry.thumbnail = thumbnail;
      entry.result = result;
      entry.bytes = fs.statSync(raw).size + fs.statSync(thumbnail).size;
      this.remember(entry);
      keep = true;
      onProgress(PreviewLoadProgress.value('ready', response.bytes, response.bytes));
      return result;
    } catch (error) {
      if (generation !== this.generation) { return new PreviewResult(); }
      if (stage === 'decode') { return this.failure('decode', '图片格式不支持或文件已损坏，可查看来源页或下载原文件'); }
      if (stage === 'storage') { return this.failure('storage', '预览缓存写入失败，请检查存储空间后重试'); }
      return this.failure('network', '网络连接失败，请重试、查看来源页或下载原文件');
    } finally {
      if (file !== undefined) { try { fs.closeSync(file); } catch (error) {} }
      if (!keep) { this.remove(raw); this.remove(thumbnail); }
      if (frame !== undefined) { try { await frame.release(); } catch (error) {} }
      if (source !== undefined) { try { await source.release(); } catch (error) {} }
      if (packer !== undefined) { try { await packer.release(); } catch (error) {} }
      transfer?.cancel();
      if (this.transfer === transfer) { this.transfer = undefined; }
    }
  }
}
