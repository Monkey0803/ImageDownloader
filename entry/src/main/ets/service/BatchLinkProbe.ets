import { http } from '@kit.NetworkKit';
import { BatchCheckKind, BatchLinkCheck, BatchLinks, BatchProbeToken } from './BatchLinks';
import { WebIdentity } from './WebIdentity';

/**
 * 批量直链的按需 HEAD 探测。
 *
 * 只回答“这个地址返回的是不是图片”，不下载正文、不带浏览器 Cookie。所有失败都收敛成
 * `BatchCheckKind.UNKNOWN`，由界面显示“仍可导入”，绝不把一条暂时探测不到的链接判死。
 *
 * 资源边界和 `SizeArbiter` 同一套思路：并发 4、单请求 2.5 秒、整轮 8 秒、最多 60 条；
 * 确定结论按 URL 缓存在本次会话里，重复确认不会把同一批 HEAD 再发一遍。
 */
export class BatchLinkProbe {
  private static readonly TIMEOUT_MS: number = 2500;
  private static readonly CONCURRENCY: number = 4;
  private static readonly DEADLINE_MS: number = 8000;
  private static readonly MAX_URLS: number = 60;
  private static readonly CACHE_LIMIT: number = 512;

  private static readonly CACHE: Map<string, BatchLinkCheck> = new Map<string, BatchLinkCheck>();

  /** 已经确认是图片 / 网页的结果；未知结果不缓存，允许换网络后重试。 */
  static cached(url: string): BatchLinkCheck | undefined {
    return BatchLinkProbe.CACHE.get(url);
  }

  /**
   * 探测一批地址。取消或预算用完时返回**已经拿到的结果**，剩下的留给界面保持“待确认”。
   */
  static async check(urls: string[], token: BatchProbeToken,
    progress: (done: number, total: number) => void): Promise<BatchLinkCheck[]> {
    const unique: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (const url of urls) {
      if (!seen.has(url)) {
        seen.add(url);
        unique.push(url);
      }
    }
    const total: number = unique.length;
    let done: number = 0;
    const results: BatchLinkCheck[] = [];
    const pending: string[] = [];
    for (const url of unique) {
      const cached: BatchLinkCheck | undefined = BatchLinkProbe.cached(url);
      if (cached !== undefined) {
        results.push(cached);
        done++;
        progress(done, total);
      } else {
        pending.push(url);
      }
    }
    if (token.cancelled || pending.length === 0) {
      return results;
    }
    const limited: string[] = pending.slice(0, BatchLinkProbe.MAX_URLS);
    const lanes: string[][] = [];
    const laneCount: number = Math.min(BatchLinkProbe.CONCURRENCY, limited.length);
    for (let lane: number = 0; lane < laneCount; lane++) {
      lanes.push([]);
    }
    for (let index: number = 0; index < limited.length; index++) {
      lanes[index % laneCount].push(limited[index]);
    }
    const startedAt: number = Date.now();
    const workers: Promise<void>[] = [];
    for (const lane of lanes) {
      workers.push(BatchLinkProbe.runLane(lane, token, startedAt, results, (): void => {
        done++;
        progress(done, total);
      }));
    }
    for (const worker of workers) {
      await worker;
    }
    return results;
  }

  private static async runLane(lane: string[], token: BatchProbeToken, startedAt: number,
    results: BatchLinkCheck[], onDone: () => void): Promise<void> {
    for (const url of lane) {
      if (token.cancelled || Date.now() - startedAt >= BatchLinkProbe.DEADLINE_MS) {
        return;
      }
      const check: BatchLinkCheck = await BatchLinkProbe.probe(url);
      results.push(check);
      if (check.kind === BatchCheckKind.IMAGE || check.kind === BatchCheckKind.PAGE) {
        BatchLinkProbe.remember(check);
      }
      onDone();
    }
  }

  private static async probe(url: string): Promise<BatchLinkCheck> {
    // @SuppressWarnings syscap
    if (!canIUse('SystemCapability.Communication.NetStack')) {
      return BatchLinks.checkOf(url, 0, '', true);
    }
    let request: http.HttpRequest | undefined = undefined;
    try {
      // @SuppressWarnings syscap
      request = http.createHttp();
      const headers: Record<string, string> = {};
      headers['Accept'] = 'image/*,*/*;q=0.8';
      headers['User-Agent'] = WebIdentity.userAgent();
      headers['Referer'] = url;
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.HEAD,
        header: headers,
        connectTimeout: BatchLinkProbe.TIMEOUT_MS,
        readTimeout: BatchLinkProbe.TIMEOUT_MS
      };
      const response: http.HttpResponse = await request.request(url, options);
      const received: Record<string, string> = response.header as Record<string, string>;
      const contentType: string | undefined = received['content-type'] ?? received['Content-Type'];
      return BatchLinks.checkOf(url, response.responseCode, contentType ?? '', false);
    } catch (error) {
      return BatchLinks.checkOf(url, 0, '', true);
    } finally {
      if (request !== undefined) {
        try {
          request.destroy();
        } catch (error) {
        }
      }
    }
  }

  private static remember(check: BatchLinkCheck): void {
    if (BatchLinkProbe.CACHE.size >= BatchLinkProbe.CACHE_LIMIT) {
      BatchLinkProbe.CACHE.clear();
    }
    BatchLinkProbe.CACHE.set(check.url, check);
  }
}
