import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

export interface PreviewResult {
  uri: string;
  message: string;
}

/** 详情专用的一次性预览；不改候选地址、不入下载队列、不持久化登录信息。 */
export class AuthenticatedPreview {
  private request: http.HttpRequest | undefined = undefined;
  private generation: number = 0;
  private path: string = '';

  static clearStale(cacheDir: string): void {
    try {
      for (const name of fs.listFileSync(cacheDir)) {
        if (/^inspection-preview-\d+-\d+\.jpg$/.test(name)) {
          try { fs.unlinkSync(cacheDir + '/' + name); } catch (error) {}
        }
      }
    } catch (error) {}
  }

  cancel(): void {
    this.generation++;
    try { this.request?.destroy(); } catch (error) {}
    this.request = undefined;
    this.remove(this.path);
    this.path = '';
  }

  private remove(path: string): void {
    if (path.length === 0) { return; }
    try { fs.unlinkSync(path); } catch (error) {}
  }

  async load(url: string, referer: string, cacheDir: string): Promise<PreviewResult> {
    this.cancel();
    const generation: number = this.generation;
    const request: http.HttpRequest = http.createHttp();
    this.request = request;
    let source: image.ImageSource | undefined = undefined;
    let frame: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    let file: fs.File | undefined = undefined;
    const path: string = cacheDir + '/inspection-preview-' + Date.now().toString()
      + '-' + generation.toString() + '.jpg';
    let keep: boolean = false;
    const deadline: number = setTimeout((): void => {
      try { request.destroy(); } catch (error) {}
    }, 15000);
    try {
      const cookie: string = webview.WebCookieManager.fetchCookieSync(url);
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: { Cookie: cookie, Referer: referer },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false,
        maxLimit: 8 * 1024 * 1024,
        // 不把当前地址的 Cookie 转发给重定向后的其他来源。
        maxRedirects: 0,
        connectTimeout: 5000,
        readTimeout: 8000
      };
      const response: http.HttpResponse = await request.request(url, options);
      if (generation !== this.generation) { return { uri: '', message: '' }; }
      if (response.responseCode === 401 || response.responseCode === 403) {
        return { uri: '', message: '预览不可用，请到来源页确认登录状态后重试' };
      }
      if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer)) {
        return { uri: '', message: '预览不可用，可查看来源页或下载原文件' };
      }
      source = image.createImageSource(response.result);
      const info: image.ImageInfo = await source.getImageInfo();
      const ratio: number = Math.min(1, 1200 / Math.max(info.size.width, info.size.height));
      frame = await source.createPixelMap({ index: 0, desiredSize: {
        width: Math.max(1, Math.round(info.size.width * ratio)),
        height: Math.max(1, Math.round(info.size.height * ratio))
      } });
      if (generation !== this.generation) { return { uri: '', message: '' }; }
      packer = image.createImagePacker();
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      await packer.packToFile(frame, file.fd, { format: 'image/jpeg', quality: 85 });
      if (generation !== this.generation) { return { uri: '', message: '' }; }
      this.path = path;
      keep = true;
      return { uri: fileUri.getUriFromPath(path), message: '预览已加载，下载仍保留原文件' };
    } catch (error) {
      return { uri: '', message: generation === this.generation
        ? '预览不可用或图片过大，可查看来源页或下载原文件' : '' };
    } finally {
      clearTimeout(deadline);
      if (file !== undefined) { try { fs.closeSync(file); } catch (error) {} }
      if (!keep) { this.remove(path); }
      if (frame !== undefined) { try { await frame.release(); } catch (error) {} }
      if (source !== undefined) { try { await source.release(); } catch (error) {} }
      if (packer !== undefined) { try { await packer.release(); } catch (error) {} }
      try { request.destroy(); } catch (error) {}
      if (this.request === request) { this.request = undefined; }
    }
  }
}
