import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { ScanImage } from './PictureFactory';
import { MediaFormat } from './MediaFormat';
import { WebIdentity } from './WebIdentity';

/*
 * WeiboLivePhotos.ets — 微博实况照片的动态部分。
 *
 * 微博的「实况照片」不是 `.livp` 包：正文接口里静图在 `pics`，动态视频单独放在
 * `post.live_photo[]`（与 `pics` 同序）或单条的 `videoSrc` 上。批量页走页内脚本，
 * 地址栏扫描走这里：用同一份 Cookie 取正文，按静图文件名（pid）把动态地址配回去。
 *
 * 只在页面被判定为微博时调用；失败一律当作「没有动态部分」，不阻塞普通扫描。
 */

interface WeiboPictureSize {
  url?: string;
}

interface WeiboPicture {
  pid?: string;
  url?: string;
  large?: WeiboPictureSize;
  original?: WeiboPictureSize;
  videoSrc?: string;
  video_src?: string;
}

interface WeiboPost {
  data?: WeiboPost;
  pics?: WeiboPicture[] | Record<string, WeiboPicture>;
  pic_ids?: string[];
  pic_infos?: Record<string, WeiboPicture>;
  live_photo?: string[];
}

export class WeiboLivePhotos {
  private static readonly TIMEOUT_MS: number = 4000;
  private static readonly CACHE_LIMIT: number = 32;
  /** bid → (静图 pid → 动态视频地址)。一次扫描会重试多轮，失败结果也缓存，避免每轮都发请求。 */
  private static cache: Map<string, Map<string, string>> = new Map<string, Map<string, string>>();
  private static pending: Map<string, Promise<Map<string, string>>> =
    new Map<string, Promise<Map<string, string>>>();

  static isWeibo(pageUrl: string): boolean {
    return new RegExp('^https?://(?:(?:www|m)\\.)?weibo\\.(?:com|cn)/', 'i').test(pageUrl);
  }

  /** 从详情页地址里取微博 bid；取不到（例如个人主页）时返回空串。 */
  static bidOf(pageUrl: string): string {
    const match: RegExpExecArray | null = new RegExp(
      '^https?://(?:(?:www|m)\\.)?weibo\\.(?:com|cn)/(?:\\d+/|status/|detail/)([A-Za-z0-9]+)',
      'i').exec(pageUrl);
    return match === null ? '' : match[1];
  }

  /** 静图地址里的文件名主干（微博就是 pid）：`.../mw2000/<pid>.jpg` → `<pid>`。 */
  static stemOf(imageUrl: string): string {
    const leaf: string = MediaFormat.leafOf(imageUrl);
    const dot: number = leaf.lastIndexOf('.');
    return dot > 0 ? leaf.substring(0, dot) : leaf;
  }

  /** 把动态地址补到扫描结果的每张图上；没有对应关系时原样返回。 */
  static async apply(pageUrl: string, images: ScanImage[]): Promise<void> {
    if (images.length === 0 || !WeiboLivePhotos.isWeibo(pageUrl)) { return; }
    const bid: string = WeiboLivePhotos.bidOf(pageUrl);
    if (bid.length === 0) { return; }
    const motions: Map<string, string> = await WeiboLivePhotos.motionsOf(pageUrl, bid);
    if (motions.size === 0) { return; }
    for (const image of images) {
      if (image.motion !== undefined && image.motion.length > 0) { continue; }
      const motion: string | undefined = motions.get(WeiboLivePhotos.stemOf(image.url));
      if (motion !== undefined && motion.length > 0) { image.motion = motion; }
    }
  }

  private static async motionsOf(pageUrl: string, bid: string): Promise<Map<string, string>> {
    const cached: Map<string, string> | undefined = WeiboLivePhotos.cache.get(bid);
    if (cached !== undefined) { return cached; }
    const running: Promise<Map<string, string>> | undefined = WeiboLivePhotos.pending.get(bid);
    if (running !== undefined) { return running; }
    const task: Promise<Map<string, string>> = WeiboLivePhotos.request(pageUrl, bid);
    WeiboLivePhotos.pending.set(bid, task);
    try {
      const motions: Map<string, string> = await task;
      WeiboLivePhotos.remember(bid, motions);
      return motions;
    } finally {
      WeiboLivePhotos.pending.delete(bid);
    }
  }

  private static async request(pageUrl: string, bid: string): Promise<Map<string, string>> {
    const motions: Map<string, string> = new Map<string, string>();
    if (!canIUse('SystemCapability.Communication.NetStack')) { return motions; }
    const weiboCom: boolean = new RegExp('weibo\\.com$', 'i').test(WeiboLivePhotos.hostOf(pageUrl));
    const url: string = (weiboCom ? 'https://weibo.com/ajax/statuses/show?id=' : 'https://m.weibo.cn/statuses/show?id=')
      + encodeURIComponent(bid);
    let client: http.HttpRequest | undefined = undefined;
    try {
      // @SuppressWarnings syscap
      client = http.createHttp();
      const headers: Record<string, string> = {};
      headers['Accept'] = 'application/json, text/plain, */*';
      headers['User-Agent'] = WebIdentity.userAgent();
      headers['Referer'] = pageUrl;
      try {
        const cookie: string = webview.WebCookieManager.fetchCookieSync(url);
        if (cookie.length > 0) { headers['Cookie'] = cookie; }
      } catch (error) {
      }
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: WeiboLivePhotos.TIMEOUT_MS,
        readTimeout: WeiboLivePhotos.TIMEOUT_MS
      };
      const response: http.HttpResponse = await client.request(url, options);
      if (response.responseCode < 200 || response.responseCode >= 300) { return motions; }
      const text: string = typeof response.result === 'string' ? response.result : '';
      if (text.length === 0) { return motions; }
      const parsed: WeiboPost = JSON.parse(text) as WeiboPost;
      WeiboLivePhotos.collect(parsed.data ?? parsed, motions);
    } catch (error) {
    } finally {
      if (client !== undefined) {
        try { client.destroy(); } catch (error) {}
      }
    }
    return motions;
  }

  private static collect(post: WeiboPost, motions: Map<string, string>): void {
    const pictures: WeiboPicture[] = WeiboLivePhotos.picturesOf(post);
    const lives: string[] = Array.isArray(post.live_photo) ? post.live_photo : [];
    for (let index: number = 0; index < pictures.length; index++) {
      const picture: WeiboPicture = pictures[index];
      const motion: string = WeiboLivePhotos.motionOf(picture, lives, index);
      if (motion.length === 0) { continue; }
      const pid: string = WeiboLivePhotos.pidOf(picture);
      if (pid.length > 0) { motions.set(pid, motion); }
    }
  }

  private static picturesOf(post: WeiboPost): WeiboPicture[] {
    const source: WeiboPicture[] | Record<string, WeiboPicture> | undefined = post.pics;
    if (source !== undefined) {
      if (Array.isArray(source)) { return source as WeiboPicture[]; }
      const map: Record<string, WeiboPicture> = source as Record<string, WeiboPicture>;
      const pictures: WeiboPicture[] = [];
      for (const key of Object.keys(map)) { pictures.push(map[key]); }
      return pictures;
    }
    const pictures: WeiboPicture[] = [];
    if (post.pic_ids !== undefined && post.pic_infos !== undefined) {
      for (const key of post.pic_ids) {
        const picture: WeiboPicture | undefined = post.pic_infos[key];
        if (picture !== undefined) { pictures.push(picture); }
      }
    }
    return pictures;
  }

  private static motionOf(picture: WeiboPicture, lives: string[], index: number): string {
    if (typeof picture.videoSrc === 'string' && picture.videoSrc.length > 0) { return picture.videoSrc; }
    if (typeof picture.video_src === 'string' && picture.video_src.length > 0) { return picture.video_src; }
    return index < lives.length && typeof lives[index] === 'string' ? lives[index] : '';
  }

  private static pidOf(picture: WeiboPicture): string {
    if (typeof picture.pid === 'string' && picture.pid.length > 0) { return picture.pid; }
    const candidates: string[] = [picture.large?.url ?? '', picture.original?.url ?? '', picture.url ?? ''];
    for (const candidate of candidates) {
      if (candidate.length === 0) { continue; }
      const stem: string = WeiboLivePhotos.stemOf(candidate);
      if (stem.length > 0) { return stem; }
    }
    return '';
  }

  private static hostOf(url: string): string {
    const match: RegExpExecArray | null = new RegExp('^https?://([^/?#]+)', 'i').exec(url);
    return match === null ? '' : match[1].toLowerCase();
  }

  private static remember(bid: string, motions: Map<string, string>): void {
    if (WeiboLivePhotos.cache.size >= WeiboLivePhotos.CACHE_LIMIT) { WeiboLivePhotos.cache.clear(); }
    WeiboLivePhotos.cache.set(bid, motions);
  }
}
