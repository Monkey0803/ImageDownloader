import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PreviewLoadProgress } from '../model/PreviewLoadProgress';
import { WebIdentity } from './WebIdentity';

export class PreviewTransferResult {
  code: number = 0;
  bytes: number = 0;
  failure: string = '';
}

/** One cancellable streaming request. No array of chunks or whole-response ArrayBuffer is retained. */
export class PreviewTransfer {
  static readonly MAX_BYTES: number = 64 * 1024 * 1024;
  private request: http.HttpRequest | undefined = undefined;
  private file: fs.File | undefined = undefined;
  private complete: ((result: PreviewTransferResult) => void) | undefined = undefined;
  private notify: (value: PreviewLoadProgress) => void = (value: PreviewLoadProgress): void => {};
  private finished: boolean = false;
  private ended: boolean = false;
  private statusReady: boolean = false;
  private code: number = 0;
  private received: number = 0;
  private total: number = 0;
  private lastProgress: number = 0;
  private idleTimer: number = -1;
  private deadline: number = -1;

  static contentLength(headers: Object): number {
    // HTTP's generic header object is a protocol boundary; avoid runtime property access in app models.
    const match: RegExpMatchArray | null = JSON.stringify(headers).match(/"content-length"\s*:\s*"?(\d+)/i);
    const value: number = match === null ? 0 : Number(match[1]);
    return Number.isFinite(value) && value > 0 ? value : 0;
  }

  cancel(): void { this.finish('cancelled'); }

  run(url: string, referer: string, cookie: string, path: string,
    notify: (value: PreviewLoadProgress) => void, redirectLimit: number = 0): Promise<PreviewTransferResult> {
    this.notify = notify;
    return new Promise<PreviewTransferResult>((resolve): void => {
      this.complete = resolve;
      try {
        this.file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      } catch (error) { this.finish('storage'); return; }
      this.notify(PreviewLoadProgress.value('connecting'));
      this.resetIdle();
      this.deadline = setTimeout((): void => { this.finish('timeout'); }, 120000);
      try {
        const request: http.HttpRequest = http.createHttp();
        this.request = request;
        request.on('headersReceive', (headers: Object): void => {
          if (this.finished) { return; }
          this.total = PreviewTransfer.contentLength(headers);
          if (this.total > PreviewTransfer.MAX_BYTES) { this.finish('size'); return; }
          this.resetIdle();
          this.progress(true);
        });
        request.on('dataReceive', (chunk: ArrayBuffer): void => { this.accept(chunk); });
        request.on('dataReceiveProgress', (progress: http.DataReceiveProgressInfo): void => {
          if (this.finished) { return; }
          if (progress.totalSize > 0) { this.total = progress.totalSize; }
          if (this.total > PreviewTransfer.MAX_BYTES) { this.finish('size'); return; }
          this.progress(false);
        });
        request.on('dataEnd', (): void => { this.ended = true; this.finishIfReady(); });
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          header: { 'User-Agent': WebIdentity.userAgent(), Cookie: cookie, Referer: referer },
          usingCache: false, maxLimit: PreviewTransfer.MAX_BYTES, maxRedirects: redirectLimit,
          connectTimeout: 8000, readTimeout: 120000
        };
        request.requestInStream(url, options).then((code: number): void => {
          if (this.finished) { return; }
          this.code = code;
          this.statusReady = true;
          this.finishIfReady();
        }).catch((error: BusinessError): void => {
          this.finish(error.code === 2300028 ? 'timeout' : error.code === 2300063 ? 'size' : 'network');
        });
      } catch (error) { this.finish('network'); }
    });
  }

  private resetIdle(): void {
    if (this.idleTimer >= 0) { clearTimeout(this.idleTimer); }
    this.idleTimer = setTimeout((): void => { this.finish('timeout'); }, 15000);
  }

  private accept(chunk: ArrayBuffer): void {
    if (this.finished || this.file === undefined) { return; }
    if (this.received + chunk.byteLength > PreviewTransfer.MAX_BYTES) { this.finish('size'); return; }
    try {
      if (fs.writeSync(this.file.fd, chunk) !== chunk.byteLength) { this.finish('storage'); return; }
      this.received += chunk.byteLength;
    } catch (error) { this.finish('storage'); return; }
    this.resetIdle();
    this.progress(false);
  }

  private progress(force: boolean): void {
    const now: number = Date.now();
    if (!force && now - this.lastProgress < 100) { return; }
    this.lastProgress = now;
    this.notify(PreviewLoadProgress.value('receiving', this.received, this.total));
  }

  private finishIfReady(): void {
    if (!this.finished && this.statusReady && (this.ended || this.code !== 200)) {
      this.progress(true);
      this.finish('');
    }
  }

  private finish(failure: string): void {
    if (this.finished) { return; }
    this.finished = true;
    if (this.idleTimer >= 0) { clearTimeout(this.idleTimer); this.idleTimer = -1; }
    if (this.deadline >= 0) { clearTimeout(this.deadline); this.deadline = -1; }
    let outcome: string = failure;
    if (this.file !== undefined) {
      try { fs.closeSync(this.file); } catch (error) { if (outcome.length === 0) { outcome = 'storage'; } }
      this.file = undefined;
    }
    try { this.request?.destroy(); } catch (error) {}
    this.request = undefined;
    const result: PreviewTransferResult = new PreviewTransferResult();
    result.code = this.code; result.bytes = this.received; result.failure = outcome;
    this.complete?.(result);
    this.complete = undefined;
  }
}
