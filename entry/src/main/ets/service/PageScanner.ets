import { webview } from '@kit.ArkWeb';
import { ScanImage } from './PictureFactory';

/** 一次扫描的结果：页面标题、页面真实地址、扫到的图片。 */
export interface ScanData {
  title: string;
  url: string;
  images: ScanImage[];
}

/**
 * **策略**：一次扫描里，每个 `<img>` 该按什么顺序取地址。
 *
 * 「下载图片质量」那一行的三档，本质是三套取址算法 —— 原先写成 Index 里的一个 if 链，
 * 返回的数组再被序列化进注入脚本。现在每档一个实现，加档位不用动扫描器。
 *
 * `order()` 的返回值**必须是白名单常量**：它会被 JSON 序列化后拼进 JS 脚本，
 * 用户输入没有进入这里的路径。
 */
export interface SourceOrderStrategy {
  /** 属性优先级；**空数组 = 「全部」档**：每个候选地址各收一张。 */
  order(): string[];
}

/** 原图优先：懒加载站点通常把原图放在 data-* 上，src 放占位图，所以 data-* 排在前面。 */
class OriginalFirstOrder implements SourceOrderStrategy {
  order(): string[] {
    return ['data-original', 'data-src', 'currentSrc', 'src'];
  }
}

/** 网页显示图：只取浏览器真正渲染出来的那张。 */
class DisplayOnlyOrder implements SourceOrderStrategy {
  order(): string[] {
    return ['currentSrc', 'src'];
  }
}

/** 全部：每个候选地址各收一张（旧行为），同一张图的缩略图与大图会同时出现。 */
class AllCandidatesOrder implements SourceOrderStrategy {
  order(): string[] {
    return [];
  }
}

/** 档位 → 策略的映射（**简单工厂**）。认不出的档位一律退回「全部」。 */
export class ScanStrategies {
  static of(quality: string): SourceOrderStrategy {
    if (quality === 'original') {
      return new OriginalFirstOrder();
    }
    if (quality === 'display') {
      return new DisplayOnlyOrder();
    }
    return new AllCandidatesOrder();
  }
}

/**
 * 注入脚本与结果解析（**适配器**：网页 DOM → `ScanData`）。
 *
 * 脚本本身是纯函数式的：不依赖页面里的任何变量名，只读 `document.images`，
 * 用 `document.baseURI` 解析相对地址，最后把结果 JSON 化回传。
 */
export class ScanProtocol {
  static script(order: string[]): string {
    // 优先级表来自上面的三份白名单常量，序列化后注入：没有用户输入进脚本的路径。
    const orderJson: string = JSON.stringify(order);
    return `(() => {
      const found = new Map();
      const order = ${orderJson};
      const read = (img, key) => key === 'currentSrc' ? img.currentSrc : (key === 'src' ? img.src : img.getAttribute(key));
      for (const img of document.images) {
        const description = img.alt || img.title || '';
        if (order.length === 0) {
          const sources = [img.currentSrc, img.getAttribute('data-src'), img.getAttribute('data-original'), img.src];
          for (const raw of sources) {
            if (!raw) continue;
            try {
              const url = new URL(raw, document.baseURI).href;
              if (url.startsWith('http://') || url.startsWith('https://'))
                found.set(url, { url: url, description: description });
            } catch (_) {}
          }
          continue;
        }
        for (const key of order) {
          const raw = read(img, key);
          if (!raw) continue;
          let url = '';
          try {
            const resolved = new URL(raw, document.baseURI).href;
            if (resolved.startsWith('http://') || resolved.startsWith('https://')) url = resolved;
          } catch (_) {}
          if (!url) continue;
          if (!found.has(url)) found.set(url, { url: url, description: description });
          break;
        }
      }
      return JSON.stringify({ title: document.title || '', url: location.href, images: Array.from(found.values()) });
    })()`;
  }

  /**
   * 解析回传的 JSON。
   *
   * `runJavaScriptExt` 在某些实现里会把结果再包一层字符串，所以这里允许解析两次；
   * 缺字段一律补成安全默认值，绝不把 undefined 传下去。
   */
  static parse(raw: string): ScanData {
    let parsed: Object = JSON.parse(raw) as Object;
    if (typeof parsed === 'string') {
      parsed = JSON.parse(parsed as string) as Object;
    }
    const data: ScanData = parsed as ScanData;
    if (typeof data.url !== 'string') {
      data.url = '';
    }
    if (typeof data.title !== 'string') {
      data.title = '';
    }
    if (!Array.isArray(data.images)) {
      data.images = [];
    }
    return data;
  }
}

/**
 * 扫描过程的三个终态出口（**观察者**：扫描器不知道界面长什么样，只管把事件发出去）。
 *
 * `onProgress` 每轮都会来一次（用来增量合并图片）；三个终态里**恰好有一个**会被调用，
 * 调用方据此关掉「正在扫描」。
 */
export interface ScanEvents {
  /** 本轮拿到的（可能是中间态的）结果。 */
  onProgress: (data: ScanData) => void;
  /** 扫描结束，`total` 是本轮页面上图片的总张数。 */
  onSettled: (total: number) => void;
  /** 结果不可用（about:blank / 错误页），不算失败也不该提示。 */
  onAborted: () => void;
  /** 注入或解析失败。 */
  onError: (message: string) => void;
}

/**
 * 网页图片扫描器（**模板方法** + 代次保护）。
 *
 * 微博正文这类 SPA 在 `onPageEnd` 之后才把图片渲染进文档，所以「扫到 0 张」或「张数还在涨」
 * 都不算最终结果：保持「正在扫描」，隔一小段时间重扫，直到张数连续 `STABLE_ROUNDS` 轮不变，
 * 或者用完 `RETRY_LIMIT` 次。
 *
 * 重试的节奏在这里，界面只处理「拿到了什么」和「结束了没有」。**代次（generation）**是关键：
 * 每次换页或手动重扫都会 +1，所有异步回来的结果都要先比对代次，属于上一页的直接丢掉 ——
 * 否则上一页慢半拍的扫描结果会覆盖新页面的地址和列表。
 */
export class PageScanner {
  private static readonly RETRY_LIMIT: number = 8;
  private static readonly RETRY_DELAY: number = 500;
  private static readonly STABLE_ROUNDS: number = 2;

  /** 排队中的重扫；-1 表示没有等待中的重扫。 */
  private timer: number = -1;
  /** 每次换页 / 重扫自增，用来丢弃属于上一页的结果。 */
  private generation: number = 0;
  /** 上一轮扫到的张数，以及张数连续没变的轮数，用来判断页面是否渲染完。 */
  private seen: number = -1;
  private stable: number = 0;

  /** 只取消排队中的重扫，不动代次。 */
  cancel(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  /**
   * 换页：取消排队中的重扫并作废所有在飞结果。
   *
   * 打开新链接时要立刻调（那时 `onPageEnd` 还没来），否则上一页的结果会在这中间落地。
   */
  invalidate(): void {
    this.cancel();
    this.generation++;
  }

  /**
   * 开始一轮扫描（`attempt` 从 0 开始）。会作废上一轮的排队与在飞结果。
   *
   * 页面销毁时调 `cancel()` 就够了：重扫最多 8×500ms，页面没了还继续 `runJavaScriptExt` 是白跑。
   */
  async start(controller: webview.WebviewController, quality: string, events: ScanEvents): Promise<void> {
    this.invalidate();
    this.seen = -1;
    this.stable = 0;
    await this.probe(controller, quality, this.generation, 0, events);
  }

  private async probe(controller: webview.WebviewController, quality: string, generation: number,
    attempt: number, events: ScanEvents): Promise<void> {
    this.cancel();
    if (generation !== this.generation) {
      return;
    }
    let raw: string = '';
    try {
      const result: webview.JsMessageExt =
        await controller.runJavaScriptExt(ScanProtocol.script(ScanStrategies.of(quality).order()));
      if (generation !== this.generation) {
        // 结果属于上一个页面：交给当前这一轮扫描处理，这里直接丢掉。
        return;
      }
      raw = result.getString();
    } catch (error) {
      if (generation !== this.generation) {
        return;
      }
      events.onError('扫描失败，请等待页面加载后重试');
      return;
    }
    const data: ScanData = ScanProtocol.parse(raw);
    // about:blank and error pages report a non-http URL; scanning one would
    // both mislabel the page and overwrite the address the user typed.
    if (!data.url.startsWith('http://') && !data.url.startsWith('https://')) {
      events.onAborted();
      return;
    }
    events.onProgress(data);
    const total: number = data.images.length;
    this.stable = total > 0 && total === this.seen ? this.stable + 1 : 0;
    this.seen = total;
    const settled: boolean = total > 0 && this.stable >= PageScanner.STABLE_ROUNDS;
    if (!settled && attempt < PageScanner.RETRY_LIMIT) {
      // 页面还没渲染完：继续显示「正在扫描」，过一会儿再看一次。
      this.timer = setTimeout((): void => {
        this.timer = -1;
        this.probe(controller, quality, generation, attempt + 1, events);
      }, PageScanner.RETRY_DELAY);
      return;
    }
    events.onSettled(total);
  }
}
