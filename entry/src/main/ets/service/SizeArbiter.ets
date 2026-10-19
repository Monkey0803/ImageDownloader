import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';

/**
 * 用 HEAD 请求的 `Content-Length` 给候选地址排大小（**仲裁者**）。
 *
 * 「这几个地址里哪个最大」只有服务端知道，页面里量不出来 —— 要么发一次请求，要么信页面自己
 * 声明的宽度。这里的取舍是**能少发就少发**：
 *
 * 1. 候选里已经有站点声明的宽度（`srcset` 的 `w`/`x`）时，`ScanUpgrader` 根本不会叫到这里；
 * 2. 每张图最多问 `PER_IMAGE` 个候选，一次扫描总共最多 `BUDGET` 次，并且有 `DEADLINE_MS` 的
 *    墙钟上限 —— 超了就用页面侧的排序结果，**绝不把扫描本身拖住**；
 * 3. 结果按 url 记在静态表里，扫描的重试轮次（`PageScanner` 每 500ms 一轮）和同一页面的
 *    重复扫描都直接命中缓存；
 * 4. 任何异常（405 不支持 HEAD、超时、断网、跨域限制）都只当「这条量不出来」，
 *    既不会让图片失败，也不会把好候选顶掉。
 *
 * 为什么用 HEAD 而不是 GET 的 `Range`：实测微博 CDN 对 HEAD 直接返回 `Content-Length`
 * 且 `time_total` 约 55ms，一个字节的图片都不下载；`Range` 反而有些站点会忽略并开始回正文。
 */
export class SizeArbiter {
  /** 单次 HEAD 的超时（连接、读取各一份）。 */
  private static readonly TIMEOUT_MS: number = 2000;
  /** 每张图最多探测几个候选。 */
  static readonly PER_IMAGE: number = 4;
  /** 一次扫描最多发几个「没缓存」的 HEAD。 */
  private static readonly BUDGET: number = 90;
  /** 一次扫描花在仲裁上的墙钟上限。 */
  private static readonly DEADLINE_MS: number = 3000;
  /** 并发数：和下载队列的默认并发同量级，不把站点打疼。 */
  private static readonly CONCURRENCY: number = 5;
  /** 缓存上限：超过就整体清掉，避免长会话里无限涨。 */
  private static readonly CACHE_LIMIT: number = 4096;

  /** url → 字节数；0 表示「量不出来」（404 / 405 / 超时 / 非 200）。 */
  private static readonly SIZES: Map<string, number> = new Map<string, number>();
  /** 本轮已经发出去的 HEAD 数、本轮开始时刻、是否已停止。 */
  private static spent: number = 0;
  private static startedAt: number = 0;
  private static stopped: boolean = false;

  /**
   * 开始一轮仲裁：重置本轮预算与计时，但**保留缓存**。
   *
   * 扫描是每 500ms 重来一次的多轮过程，只有缓存跨轮存活，「重扫不重复发请求」才成立。
   */
  static beginRound(): void {
    SizeArbiter.spent = 0;
    SizeArbiter.startedAt = Date.now();
    SizeArbiter.stopped = false;
  }

  /** 这个地址量过没有（量过 0 字节也算量过，不会再问第二次）。 */
  static known(url: string): boolean {
    return SizeArbiter.SIZES.has(url);
  }

  /** 量到过的字节数；没量过或量不出来都是 0。 */
  static cached(url: string): number {
    return SizeArbiter.SIZES.get(url) ?? 0;
  }

  /** 本轮还能不能继续发请求。 */
  private static available(): boolean {
    return !SizeArbiter.stopped && SizeArbiter.spent < SizeArbiter.BUDGET
      && Date.now() - SizeArbiter.startedAt < SizeArbiter.DEADLINE_MS;
  }

  /**
   * 在候选里挑字节数最大的那个，返回它的地址。
   *
   * - `capBytes` 是安全阀：所有候选都超过它就返回 `''`（宁可保留页面上那张，也不悄悄下 100 MB）；
   * - 量不出来（全是 0）时返回 `''` —— 调用方据此保留原来的地址，这是**最重要的失败姿态**：
   *   探测失败绝不改变用户拿到的结果。
   */
  static async largest(candidates: string[], referer: string, capBytes: number): Promise<string> {
    if (candidates.length === 0) {
      return '';
    }
    const sizes: number[] = [];
    for (let i: number = 0; i < candidates.length; i++) {
      sizes.push(-1);
    }
    // 按 worker 轮转分道：等价于「谁空谁取下一个」，但不需要在闭包里改游标。
    const lanes: number[][] = [];
    const laneCount: number = Math.min(SizeArbiter.CONCURRENCY, candidates.length);
    for (let w: number = 0; w < laneCount; w++) {
      lanes.push([]);
    }
    for (let i: number = 0; i < candidates.length; i++) {
      lanes[i % laneCount].push(i);
    }
    const workers: Promise<void>[] = [];
    for (const lane of lanes) {
      workers.push(SizeArbiter.runLane(lane, candidates, sizes, referer));
    }
    for (const worker of workers) {
      await worker;
    }
    let best: number = -1;
    for (let i: number = 0; i < sizes.length; i++) {
      if (sizes[i] <= 0 || sizes[i] > capBytes) {
        continue;
      }
      if (best < 0 || sizes[i] > sizes[best]) {
        best = i;
      }
    }
    return best < 0 ? '' : candidates[best];
  }

  /** 一条道上的候选按顺序探测；预算或时间用完就停下，剩下的保持 -1（未知）。 */
  private static async runLane(lane: number[], candidates: string[], sizes: number[],
    referer: string): Promise<void> {
    for (const index of lane) {
      const url: string = candidates[index];
      if (SizeArbiter.known(url)) {
        sizes[index] = SizeArbiter.cached(url);
        continue;
      }
      if (!SizeArbiter.available()) {
        continue;
      }
      sizes[index] = await SizeArbiter.lengthOf(url, referer);
    }
  }

  /**
   * 量一个地址的字节数；量不出来返回 0。
   *
   * 读的是响应头里的 `content-length`：不同实现给的大小写不一样（HTTP 头本身大小写不敏感），
   * 所以两种写法都试。非 200 一律当 0 —— 404 页面也有 `content-length`，不能当真。
   */
  private static async lengthOf(url: string, referer: string): Promise<number> {
    let bytes: number = 0;
    // @SuppressWarnings syscap
    if (!canIUse('SystemCapability.Communication.NetStack')) {
      SizeArbiter.remember(url, 0);
      return 0;
    }
    const headers: Record<string, string> = {};
    if (referer.startsWith('http')) {
      headers['Referer'] = referer;
    }
    try {
      const cookie: string = webview.WebCookieManager.fetchCookieSync(url);
      if (cookie.length > 0) {
        headers['Cookie'] = cookie;
      }
    } catch (error) {}
    let request: http.HttpRequest | undefined = undefined;
    try {
      SizeArbiter.spent++;
      // @SuppressWarnings syscap
      request = http.createHttp();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.HEAD,
        header: headers,
        connectTimeout: SizeArbiter.TIMEOUT_MS,
        readTimeout: SizeArbiter.TIMEOUT_MS
      };
      const response: http.HttpResponse = await request.request(url, options);
      if (response.responseCode === http.ResponseCode.OK) {
        const received: Record<string, string> = response.header as Record<string, string>;
        const raw: string | undefined = received['content-length'] ?? received['Content-Length'];
        if (raw !== undefined) {
          const value: number = parseInt(raw, 10);
          if (!isNaN(value) && value > 0) {
            bytes = value;
          }
        }
      }
    } catch (error) {
      bytes = 0;
    } finally {
      if (request !== undefined) {
        try {
          request.destroy();
        } catch (error) {}
      }
    }
    SizeArbiter.remember(url, bytes);
    return bytes;
  }

  /** 记进缓存；满了就整体清掉（比 LRU 简单，且这些数据重建代价很低）。 */
  private static remember(url: string, bytes: number): void {
    if (SizeArbiter.SIZES.size >= SizeArbiter.CACHE_LIMIT) {
      SizeArbiter.SIZES.clear();
    }
    SizeArbiter.SIZES.set(url, bytes);
  }
}
