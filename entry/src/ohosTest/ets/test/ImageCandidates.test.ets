import { describe, it, expect } from '@ohos/hypium';
import { ImageCandidate, Candidates, SiteRules } from '../../../main/ets/service/ImageCandidates';

// ImageCandidates 是纯计算：不碰 DOM、不发请求，所以可以直接测。
// 这两件事值得单独测：
// 1. 择优排序 —— 它是「原图优先」能不能真的取到大图的第一道关；
// 2. 新浪图床的地址推导 —— 微博页面 HTML 里只有缩略图一个地址，通用信号一个都拿不到，
//    取大图全靠这条规则。规则里的 `tokens` 是白名单：写错一个词就会去猜别的站点的地址。

function cand(url: string, declared: number): ImageCandidate {
  const item: ImageCandidate = { url: url, declared: declared };
  return item;
}

export default function imageCandidatesTest() {
  describe('Candidates.rank', () => {
    it('dedupes_by_url_keeping_the_first', 0, () => {
      const list: ImageCandidate[] = [
        cand('https://a.com/1.jpg', 0),
        cand('https://a.com/2.jpg', 800),
        cand('https://a.com/1.jpg', 1600)
      ];
      // 后出现的重复地址不会顶掉先出现的那个，声明宽度也不参与合并。
      expect(Candidates.urls(Candidates.rank(list)).join(',')).assertEqual('https://a.com/2.jpg,https://a.com/1.jpg');
    });

    it('drops_empty_urls', 0, () => {
      const list: ImageCandidate[] = [cand('', 900), cand('https://a.com/1.jpg', 0)];
      expect(Candidates.rank(list).length).assertEqual(1);
      expect(Candidates.rank(list)[0].url).assertEqual('https://a.com/1.jpg');
    });

    it('sorts_by_declared_width_descending', 0, () => {
      const list: ImageCandidate[] = [
        cand('https://a.com/small.jpg', 250),
        cand('https://a.com/big.jpg', 1280),
        cand('https://a.com/mid.jpg', 640)
      ];
      expect(Candidates.urls(Candidates.rank(list)).join(','))
        .assertEqual('https://a.com/big.jpg,https://a.com/mid.jpg,https://a.com/small.jpg');
    });

    it('keeps_collection_order_when_nothing_is_declared', 0, () => {
      // 懒加载站点常见情形：所有候选的 declared 都是 0，这时顺序必须原样保留 ——
      // 那条顺序是属性白名单算出来的，比任意重排可信。
      const list: ImageCandidate[] = [
        cand('https://a.com/data-original.jpg', 0),
        cand('https://a.com/src.jpg', 0),
        cand('https://a.com/href.jpg', 0)
      ];
      expect(Candidates.urls(Candidates.rank(list)).join(','))
        .assertEqual('https://a.com/data-original.jpg,https://a.com/src.jpg,https://a.com/href.jpg');
    });

    it('keeps_ties_in_collection_order', 0, () => {
      const list: ImageCandidate[] = [
        cand('https://a.com/first.jpg', 800),
        cand('https://a.com/second.jpg', 800)
      ];
      expect(Candidates.urls(Candidates.rank(list)).join(','))
        .assertEqual('https://a.com/first.jpg,https://a.com/second.jpg');
    });
  });

  describe('Candidates.declaredTop / head / urls', () => {
    it('reports_the_largest_declaration', 0, () => {
      const list: ImageCandidate[] = [cand('https://a.com/1.jpg', 320), cand('https://a.com/2.jpg', 1600)];
      expect(Candidates.declaredTop(list)).assertEqual(1600);
      expect(Candidates.declaredTop([cand('https://a.com/3.jpg', 0)])).assertEqual(0);
      expect(Candidates.declaredTop([])).assertEqual(0);
    });

    it('head_limits_and_never_returns_the_input_array', 0, () => {
      const list: ImageCandidate[] = [
        cand('https://a.com/1.jpg', 0),
        cand('https://a.com/2.jpg', 0),
        cand('https://a.com/3.jpg', 0)
      ];
      expect(Candidates.head(list, 2).length).assertEqual(2);
      expect(Candidates.urls(Candidates.head(list, 2)).join(',')).assertEqual('https://a.com/1.jpg,https://a.com/2.jpg');
      // limit <= 0 表示不限；返回的是副本，调用方改它不该影响原列表。
      const all: ImageCandidate[] = Candidates.head(list, 0);
      expect(all.length).assertEqual(3);
      all.pop();
      expect(list.length).assertEqual(3);
    });
  });

  describe('SiteRules.expand', () => {
    const ORJ360: string = 'https://wx3.sinaimg.cn/orj360/6f551839gy1ii7hod53hbj247s6bk7wr.jpg';

    it('derives_larger_siblings_for_the_weibo_cdn', 0, () => {
      const out: ImageCandidate[] = SiteRules.expand(ORJ360);
      const urls: string[] = Candidates.urls(out);
      // 阶梯从大到小，且不含它自己（当前这档没必要再猜一遍）。
      expect(urls.join(',')).assertEqual([
        'https://wx3.sinaimg.cn/original/6f551839gy1ii7hod53hbj247s6bk7wr.jpg',
        'https://wx3.sinaimg.cn/large/6f551839gy1ii7hod53hbj247s6bk7wr.jpg',
        'https://wx3.sinaimg.cn/mw2000/6f551839gy1ii7hod53hbj247s6bk7wr.jpg',
        'https://wx3.sinaimg.cn/mw690/6f551839gy1ii7hod53hbj247s6bk7wr.jpg',
        'https://wx3.sinaimg.cn/bmiddle/6f551839gy1ii7hod53hbj247s6bk7wr.jpg',
        'https://wx3.sinaimg.cn/orj480/6f551839gy1ii7hod53hbj247s6bk7wr.jpg'
      ].join(','));
      // 猜出来的候选没有像素数可言，声明宽度一律是 0。
      expect(Candidates.declaredTop(out)).assertEqual(0);
    });

    it('keeps_the_query_string', 0, () => {
      const out: ImageCandidate[] = SiteRules.expand('https://wx1.sinaimg.cn/mw690/a.jpg?tags=1&x=2');
      expect(out.length).assertEqual(6);
      expect(out[0].url).assertEqual('https://wx1.sinaimg.cn/original/a.jpg?tags=1&x=2');
    });

    it('never_repeats_the_current_step', 0, () => {
      // `thumb150` 是一条没有兄弟档位关系的旧尺寸词，但它同样命中这台图床，
      // 于是照阶梯展开；只是当前这一档本身不再重复猜一遍。
      const out: ImageCandidate[] = SiteRules.expand('https://wx1.sinaimg.cn/thumb150/a.jpg');
      expect(out.length).assertEqual(7);
      expect(Candidates.urls(out).indexOf('https://wx1.sinaimg.cn/thumb150/a.jpg')).assertEqual(-1);
    });

    it('stays_silent_on_unknown_hosts_and_tokens', 0, () => {
      // 后缀匹配必须是完整的域名段：`notsinaimg.cn` 不能命中 `sinaimg.cn`。
      expect(SiteRules.expand('https://notsinaimg.cn/orj360/a.jpg').length).assertEqual(0);
      expect(SiteRules.expand('https://img.example.com/orj360/a.jpg').length).assertEqual(0);
      // 同一台图床上的普通地址（尺寸不写在路径里）不猜。
      expect(SiteRules.expand('https://wx1.sinaimg.cn/album/photo.jpg').length).assertEqual(0);
      // 尺寸词不在白名单里（多套了一层目录时中间那段不是尺寸词）同样不猜。
      expect(SiteRules.expand('https://wx1.sinaimg.cn/a.jpg').length).assertEqual(0);
      expect(SiteRules.expand('https://wx1.sinaimg.cn/orj360/1/2/a.jpg').length).assertEqual(0);
      expect(SiteRules.expand('').length).assertEqual(0);
    });

    it('strips_the_coolapk_thumbnail_suffix_and_keeps_the_query', 0, () => {
      const thumb: string = 'https://image.coolapk.com/feed/2026/1027/03/27167986_5e6db78f_2793_9069_796-uhdr@2494x3325.jpg.m.jpg';
      expect(Candidates.urls(SiteRules.expand(thumb)).join(',')).assertEqual(
        'https://image.coolapk.com/feed/2026/1027/03/27167986_5e6db78f_2793_9069_796-uhdr@2494x3325.jpg');
      expect(Candidates.urls(SiteRules.expand(thumb + '?sign=1')).join(',')).assertEqual(
        'https://image.coolapk.com/feed/2026/1027/03/27167986_5e6db78f_2793_9069_796-uhdr@2494x3325.jpg?sign=1');
      expect(SiteRules.expand('https://image.coolapk.com/feed/a.png').length).assertEqual(0);
      expect(SiteRules.expand('https://notcoolapk.com/feed/a.jpg.m.jpg').length).assertEqual(0);
    });
  });
}
