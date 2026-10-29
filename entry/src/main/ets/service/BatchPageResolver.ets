import { webview } from '@kit.ArkWeb';
import { BatchPageGroup, BatchPageResult } from './BatchPageGroups';
import { BatchPageProtocol, BatchPageStep } from './BatchPageProtocol';
import { ScanUpgrader } from './ScanUpgrader';
import { ScanImage } from './PictureFactory';

/** Owns one mounted Web controller. Navigation and extraction each have a 20-second deadline. */
export class BatchPageResolver {
  private browser: webview.WebviewController = new webview.WebviewController();
  private attached: boolean = false;
  private launch: (() => void) | undefined = undefined;
  private abort: (() => void) | undefined = undefined;
  private ended: ((url: string) => void) | undefined = undefined;
  private failed: (() => void) | undefined = undefined;
  private generation: number = 0;
  private resetEnded: (() => void) | undefined = undefined;
  private issued: boolean = false;
  private began: boolean = false;

  controller(): webview.WebviewController { return this.browser; }
  ready(): void { this.attached = true; this.launch?.(); }
  pageBegan(url: string): void {
    if (this.issued && new RegExp('^https?://').test(url)) { this.began = true; }
  }
  pageEnded(url: string): void {
    try {
      if (url !== this.browser.getUrl()) { return; }
      if (url === 'about:blank') { this.resetEnded?.(); return; }
      if (this.issued && this.began && new RegExp('^https?://').test(url)) { this.ended?.(url); }
    } catch (error) {}
  }
  pageFailed(): void { if (this.issued) { this.failed?.(); } }

  cancel(): void {
    this.generation++;
    this.abort?.(); this.launch = undefined; this.ended = undefined; this.failed = undefined;
    this.resetEnded = undefined; this.issued = false; this.began = false;
    try { this.browser.stop(); } catch (error) {}
  }

  clear(): void {
    this.cancel();
    try { if (this.attached) { this.browser.loadUrl('about:blank'); } } catch (error) {}
  }

  openForHandling(url: string): void {
    this.cancel();
    this.launch = (): void => {
      this.launch = undefined;
      try { this.browser.loadUrl(url); } catch (error) {}
    };
    if (this.attached) { this.launch(); }
  }

  resolve(group: BatchPageGroup, quality: string): Promise<BatchPageResult> {
    this.cancel();
    const generation: number = this.generation;
    return new Promise<BatchPageResult>((resolve, reject): void => {
      let active: boolean = true;
      let scanning: boolean = false;
      let timer: number = -1;
      let waitTimer: number = -1;
      let wake: (() => void) | undefined = undefined;
      let last: BatchPageResult = new BatchPageResult();
      const valid = (): boolean => active && generation === this.generation;
      const finish = (result: BatchPageResult | undefined, message: string): void => {
        if (!active) { return; }
        active = false;
        clearTimeout(timer); clearTimeout(waitTimer); wake?.();
        this.abort = undefined; this.ended = undefined; this.failed = undefined; this.launch = undefined;
        this.resetEnded = undefined; this.issued = false;
        if (result !== undefined) { resolve(result); } else { reject(new Error(message)); }
      };
      const wait = (): Promise<void> => new Promise<void>((resume): void => {
        wake = resume;
        waitTimer = setTimeout((): void => { wake = undefined; resume(); }, 900);
      });
      this.abort = (): void => { finish(undefined, '已取消解析'); };
      this.failed = (): void => { finish(undefined, '网页加载失败，请打开网页查看或重试'); };
      timer = setTimeout((): void => { finish(undefined, '网页加载超时，可重试'); }, 20000);
      this.ended = (finalUrl: string): void => {
        if (!valid() || scanning) { return; }
        scanning = true;
        clearTimeout(timer);
        timer = setTimeout((): void => {
          if (last.images.length > 0) { last.limited = true; finish(last, ''); }
          else { finish(undefined, '网页采集超时，未发现图片，可打开网页查看后重试'); }
        }, 20000);
        const collect = async (): Promise<void> => {
          let stable: number = 0;
          // 换票/跳转后的地址才是真正要采的页面，所以在采集过程中跟着 location 走。
          let scanUrl: string = finalUrl;
          let pending: boolean = false;
          const images: Map<string, ScanImage> = new Map<string, ScanImage>();
          for (let round: number = 0; round < 12 && valid(); round++) {
            if (round > 0) { await wait(); }
            if (!valid()) { return; }
            let step: BatchPageStep;
            try {
              const raw: webview.JsMessageExt = await this.browser.runJavaScriptExt(
                BatchPageProtocol.script(group.inputUrl, quality));
              if (!valid()) { return; }
              step = BatchPageProtocol.parse(raw.getString());
            } catch (error) {
              if (!valid()) { return; }
              // 页面正在跳转时脚本会被打断，下一轮再看，不要把它当成终态。
              stable = 0;
              continue;
            }
            if (step.pending) {
              // 中间页还在跳，等它落到正文；期间已经采到的图片不属于目标页。
              pending = true; stable = 0;
              images.clear();
              last.url = step.url; last.title = step.title; last.images = [];
              continue;
            }
            pending = false;
            if (step.url !== scanUrl) {
              if (!new RegExp('^https?://').test(step.url)) {
                throw new Error('网页发生跳转，请打开网页处理后重试');
              }
              scanUrl = step.url;
              images.clear(); stable = 0;
            }
            if (step.error.length > 0) { throw new Error(step.error); }
            const before: number = images.size;
            for (const image of step.images) { images.set(image.url, image); }
            last.url = step.url; last.title = step.title; last.direct = step.direct;
            last.images = Array.from(images.values());
            stable = step.bottom && images.size === before && step.scopeFound ? stable + 1 : 0;
            if (step.direct || stable >= 3 || round === 11) {
              last.limited = !step.direct && stable < 3;
              if (!step.scopeFound) { throw new Error('无法定位目标微博正文，请打开网页处理后重试'); }
              if (quality === 'original') { await ScanUpgrader.apply(last.images, last.url, valid); }
              if (valid()) { finish(last, ''); }
              return;
            }
          }
          if (!valid()) { return; }
          if (pending) { throw new Error('需要登录或验证，请打开网页处理后重试'); }
          throw new Error('网页采集超时，未发现图片，可打开网页查看后重试');
        };
        collect().catch((error: Error): void => { if (valid()) { finish(undefined, error.message); } });
      };
      this.launch = (): void => {
        if (!valid()) { return; }
        this.launch = undefined;
        // A committed blank document separates successive owners of this Web. Only then
        // accept redirected/normalized target URLs; a late previous-page event cannot scan it.
        this.resetEnded = (): void => {
          if (!valid()) { return; }
          this.resetEnded = undefined; this.issued = true; this.began = false;
          try { this.browser.loadUrl(group.inputUrl); }
          catch (error) { finish(undefined, '无法打开网页，请重试'); }
        };
        try { this.browser.loadUrl('about:blank'); }
        catch (error) { finish(undefined, '无法打开网页，请重试'); }
      };
      if (this.attached) { this.launch(); }
    });
  }
}
