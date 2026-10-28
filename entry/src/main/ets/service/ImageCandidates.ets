/**
 * 候选地址的收集与择优 —— **与站点无关**的那一半。
 *
 * 同一个 `<img>` 在页面里往往同时挂着好几个地址：`src` 是缩略图、`srcset` 里才是大图、
 * 外面包着的 `<a href>` 指向原图……「取哪一张」原先是一张写死的属性顺序表，只看第一个命中的。
 * 这里把这件事拆成三步：
 *
 * 1. **收集**（`PageScanner` 注入的脚本，见 `ScanProtocol`）：把一个 `<img>` 身上所有
 *    能指向图片的地址都收下来，附上站点声明的宽度；
 * 2. **择优**（本文件的 `Candidates`）：按声明宽度排序，大的在前；
 * 3. **仲裁**（`SizeArbiter`）：声明宽度说不清谁大时，用 HEAD 的 `Content-Length` 量一次。
 *
 * 本文件是**纯计算**：不碰 DOM、不发请求，因此可以在 ohosTest 里直接测。
 */

/**
 * 一个候选地址。
 *
 * `declared` 是**站点自己声明的宽度**换算成的可比分数（`srcset` 的 `w` 描述符就是像素数，
 * `x` 描述符是倍率），0 表示站点没声明。它只用来排序，不参与「这张图多大」的展示。
 */
export interface ImageCandidate {
  url: string;
  declared: number;
}

/** 排序用的内部包裹：`order` 记住原始出现位置，让同分候选保持收集顺序。 */
interface Ranked {
  candidate: ImageCandidate;
  order: number;
}

/** 候选列表的纯函数工具箱。 */
export class Candidates {
  /**
   * 去重 + 按声明宽度降序排序。
   *
   * `declared` 全是 0（懒加载站点常见）时顺序**完全不变** —— 那条顺序是属性白名单算出来的，
   * 仍然比乱序可信；一旦有站点声明，声明值大的排前面。
   */
  static rank(list: ImageCandidate[]): ImageCandidate[] {
    const seen: Set<string> = new Set<string>();
    const unique: ImageCandidate[] = [];
    for (const item of list) {
      if (item.url.length === 0 || seen.has(item.url)) {
        continue;
      }
      seen.add(item.url);
      unique.push(item);
    }
    const rows: Ranked[] = [];
    for (let i: number = 0; i < unique.length; i++) {
      const row: Ranked = { candidate: unique[i], order: i };
      rows.push(row);
    }
    // 显式带上 order 再比一次，不依赖 Array.sort 的稳定性（各家 ArkTS 运行时不一定保证）。
    rows.sort((a: Ranked, b: Ranked): number => {
      if (a.candidate.declared !== b.candidate.declared) {
        return b.candidate.declared - a.candidate.declared;
      }
      return a.order - b.order;
    });
    const sorted: ImageCandidate[] = [];
    for (const row of rows) {
      sorted.push(row.candidate);
    }
    return sorted;
  }

  /** 候选里最大的声明宽度；0 表示这一组候选谁都没说清自己多大。 */
  static declaredTop(list: ImageCandidate[]): number {
    let top: number = 0;
    for (const item of list) {
      if (item.declared > top) {
        top = item.declared;
      }
    }
    return top;
  }

  /** 取前 `limit` 个；`limit <= 0` 表示不限。 */
  static head(list: ImageCandidate[], limit: number): ImageCandidate[] {
    if (limit <= 0 || list.length <= limit) {
      return list.slice();
    }
    return list.slice(0, limit);
  }

  /** 只取地址，喂给 `SizeArbiter`。 */
  static urls(list: ImageCandidate[]): string[] {
    const out: string[] = [];
    for (const item of list) {
      out.push(item.url);
    }
    return out;
  }
}

/**
 * 一张「尺寸阶梯」：某类图床把尺寸写在 URL 路径里，同名的兄弟地址就是不同档位。
 *
 * `host` 是主机名后缀（不含前导点），`tokens` 是见过的尺寸词（命中才认这是同类图床），
 * `steps` 从大到小。
 */
interface SizeLadder {
  host: string;
  tokens: string[];
  steps: string[];
}

/**
 * 一张「后缀阶梯」：图床把缩略图后缀拼在真地址后面，去掉后缀就是原图。
 *
 * 与 `SizeLadder` 分开：这类规则不靠路径里的尺寸词，而且原图地址不一定是同目录的兄弟。
 */
interface SuffixLadder {
  host: string;
  suffix: string;
}

/**
 * 站点专属的地址推导（**策略**：把「不知道的站点」和「有约定的站点」分开）。
 *
 * 为什么必须有这一层：新浪图床的地址里写着尺寸（`/orj360/`），而页面 HTML 里**只有缩略图
 * 那一个地址**，`srcset` 也没有 —— 通用信号一个都拿不到。这种「尺寸写在路径里」的约定
 * 只能按站点补。
 *
 * 规矩有两条，避免这张表无限膨胀：
 *
 * 1. **只镜像实测过的阶梯**。微博那组数字是真的（见 `README` 的实测记录）；
 *    没量过的站点一律不进表 —— 猜错的代价不是「小一点」，而是 404。
 * 2. **只负责吐候选，不负责拍板**。猜出来的地址要被 `SizeArbiter` 量过字节数才作数，
 *    所以即使某个站点的阶梯记住了一半，最坏也只是白花几次 HEAD，不会下到坏地址。
 */
export class SiteRules {
  /**
   * 新浪图床（微博）实测阶梯（同一张图，字节数实测）：
   * `original` = `large`（11.7 MB）> `mw2000`（1.85 MB）> `mw690`（317 KB）>
   * `bmiddle`（109 KB）> `orj480`（65 KB）> `orj360`（40 KB）。
   */
  private static readonly LADDERS: SizeLadder[] = [
    {
      host: 'sinaimg.cn',
      tokens: ['thumbnail', 'small', 'thumb150', 'thumb180', 'thumb300', 'square', 'wap180',
        'wap360', 'orj360', 'orj480', 'bmiddle', 'mw690', 'mw2000', 'large', 'original', 'woriginal'],
      steps: ['original', 'large', 'mw2000', 'mw690', 'bmiddle', 'orj480', 'orj360']
    }
  ];

  /**
   * Coolapk 图床实测（2026-10-28，同一张 HDR 照片）：
   * `...@2494x3325.jpg` = 2494×3325 / 189,207 B；页面里的
   * `...@2494x3325.jpg.m.jpg` = 1080×1440 / 33,039 B，且缩略图不含 gain map。
   * 去掉末尾 `.m.jpg` 即可得到原图；仍需 `SizeArbiter` 的 HEAD 确认后才采用。
   */
  private static readonly SUFFIX_LADDERS: SuffixLadder[] = [
    { host: 'coolapk.com', suffix: '.m.jpg' }
  ];

  /** 拆 `主机/尺寸词/文件名` 三段；查询串会先切掉，拼兄弟地址时再补回去。 */
  private static readonly SIBLING_PATH: RegExp = new RegExp('^([^?#]+)/([^/?#]+)/([^/?#]+)$');

  /**
   * 给一个地址推导「可能更大的兄弟地址」，大的在前；没命中规则就返回空数组。
   *
   * 猜出来的候选 `declared` 一律是 0（我们不知道像素数，只知道档位的先后），
   * 排序时靠「放在列表最前面」拿到优先探测的位置。
   */
  static expand(url: string): ImageCandidate[] {
    const out: ImageCandidate[] = [];
    const queryAt: number = url.indexOf('?');
    const head: string = queryAt < 0 ? url : url.substring(0, queryAt);
    const query: string = queryAt < 0 ? '' : url.substring(queryAt);
    const parts: RegExpExecArray | null = SiteRules.SIBLING_PATH.exec(head);
    if (parts !== null && parts.length >= 4) {
      const host: string = parts[1];
      const token: string = parts[2];
      const file: string = parts[3];
      for (const ladder of SiteRules.LADDERS) {
        if (!SiteRules.matchesHost(host, ladder.host) || ladder.tokens.indexOf(token) < 0) {
          continue;
        }
        for (const step of ladder.steps) {
          if (step === token) {
            continue;
          }
          const candidate: ImageCandidate = { url: host + '/' + step + '/' + file + query, declared: 0 };
          out.push(candidate);
        }
      }
    }
    for (const ladder of SiteRules.SUFFIX_LADDERS) {
      const origin: string = SiteRules.hostOf(head);
      if (!SiteRules.matchesHost(origin, ladder.host) || !head.endsWith(ladder.suffix)) {
        continue;
      }
      const candidate: ImageCandidate = {
        url: head.substring(0, head.length - ladder.suffix.length) + query, declared: 0
      };
      out.push(candidate);
    }
    return out;
  }

  /** 取 `https://host/path` 里的 `https://host`；没有 scheme 时返回空串。 */
  private static hostOf(url: string): string {
    const scheme: number = url.indexOf('://');
    if (scheme < 0) {
      return '';
    }
    const start: number = scheme + 3;
    const slash: number = url.indexOf('/', start);
    return slash < 0 ? url.substring(start) : url.substring(start, slash);
  }

  /** `https://wx3.sinaimg.cn` 命中后缀 `sinaimg.cn`，`https://notsinaimg.cn` 不命中。 */
  private static matchesHost(host: string, suffix: string): boolean {
    return host.toLowerCase().endsWith('.' + suffix);
  }
}
