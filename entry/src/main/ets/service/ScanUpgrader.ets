import { ImageCandidate, Candidates, SiteRules } from './ImageCandidates';
import { SizeArbiter } from './SizeArbiter';
import { ScanImage } from './PictureFactory';

/**
 * 扫描结果落地前的最后一道加工：把每个 `<img>` 的候选地址**择优 + 仲裁**成一个下载地址。
 *
 * 流程（顺序不能变）：
 *
 * 1. `SiteRules.expand`：站点专属的地址推导（微博的 `/orj360/` → `/large/` 这类）；
 * 2. `Candidates.rank`：站点声明过宽度的候选排前面，推导出来的候选在最前兜底；
 * 3. `Candidates.head`：只取前 `SizeArbiter.PER_IMAGE` 个去量，避免一张图问十条；
 * 4. `SizeArbiter.largest`：量出最大的那个。
 *
 * **只在失败姿态下才保留原地址**：`largest` 返回空串（全都量不出来，或全都超过 `SIZE_CAP`）
 * 时不动 `image.url`，用户至少还能拿到页面上那张图。这条规则让「猜错」的代价仅限于白花几次
 * HEAD，绝不会把一张 404 的地址交给下载器。
 */
export class ScanUpgrader {
  /**
   * 单张图的字节上限：微博的 `large` 实测 11.7 MB、`mw2000` 1.85 MB，32 MB 足够容纳
   * 常见原图，又能拦住「九张图加起来 100 MB」这类失控情况。
   */
  private static readonly SIZE_CAP: number = 32 * 1024 * 1024;

  /**
   * 就地把 `images` 的 `url` 换成量出来最大的候选；没有候选的图原样保留。
   *
   * 用 `void` 而不是返回新数组：`url` 是 `PictureItem` 的身份键（`PictureFactory.merge`
   * 按 url 去重），原地替换才能让「重扫」合并到同一项上，而不是每轮多出一批新图。
   */
  static async apply(images: ScanImage[], referer: string): Promise<void> {
    if (images.length === 0) {
      return;
    }
    SizeArbiter.beginRound();
    for (const image of images) {
      const raw: ImageCandidate[] | undefined = image.candidates;
      if (raw === undefined || raw.length === 0) {
        continue;
      }
      const expanded: ImageCandidate[] = SiteRules.expand(image.url);
      const ranked: ImageCandidate[] = Candidates.rank(expanded.concat(raw));
      const urls: string[] = Candidates.urls(Candidates.head(ranked, SizeArbiter.PER_IMAGE));
      const best: string = await SizeArbiter.largest(urls, referer, ScanUpgrader.SIZE_CAP);
      if (best.length > 0) {
        image.url = best;
      }
    }
  }
}
