import { ScanData, ScanProtocol, ScanStrategies } from './PageScanner';

export interface BatchPageStep extends ScanData {
  bottom: boolean;
  direct: boolean;
  scopeFound: boolean;
  /** 中间跳转页（例如微博的 Sina Visitor System）：还在换票，等它落到正文再判断。 */
  pending: boolean;
  error: string;
}

/** Scripts run only in the mounted batch Web. Site data never crosses into another origin. */
export class BatchPageProtocol {
  static weiboId(url: string): string {
    const match: RegExpMatchArray | null = url.match(new RegExp(
      '^https?://(?:(?:www|m)\\.)?weibo\\.(?:com|cn)/(?:\\d+/|status/|detail/)([A-Za-z0-9]+)(?:[/?#]|$)', 'i'));
    return match === null ? '' : match[1];
  }

  static script(input: string, quality: string): string {
    const id: string = BatchPageProtocol.weiboId(input);
    const weibo: boolean = new RegExp('^https?://(?:(?:www|m)\\.)?weibo\\.(?:com|cn)/', 'i').test(input);
    const strategy = ScanStrategies.of(quality);
    const generic: string = ScanProtocol.script(strategy.order(), strategy.arbitrate());
    return `(() => {
      const out = { url: location.href, title: document.title || '', images: [], bottom: false,
        direct: false, scopeFound: true, pending: false, error: '' };
      const body = (document.body ? document.body.innerText : '').slice(0, 1800);
      // 微博未登录时的 Sina Visitor System 是换票中间页：它自己写 Cookie 后跳回正文，
      // 单页扫描靠反复重扫能穿过去，批量这里也必须等，不能把中间页当最终结果判死。
      if (/\\/visitor\\/visitor/i.test(location.href) || /Sina Visitor System/i.test(out.title)) {
        out.pending = true; return JSON.stringify(out);
      }
      if (/passport\\.weibo\\.|visitor\\.passport\\.|(?:^|\\/)(?:login|captcha|verify)(?:\\/|$)/i.test(location.href)
        || /系统安全验证|安全验证|请先登录|登录后查看/i.test(out.title)
        || (/系统安全验证|访问频次过高/.test(body) && document.images.length === 0)) {
        out.error = '需要登录或验证，请打开网页处理后重试'; return JSON.stringify(out);
      }
      if ((document.contentType || '').startsWith('image/')) {
        out.direct = true; out.bottom = true;
        out.images = [{ url: location.href, description: '' }]; return JSON.stringify(out);
      }
      const finalMatch = /^https?:\\/\\/(?:(?:www|m)\\.)?weibo\\.(?:com|cn)\\/(?:\\d+\\/|status\\/|detail\\/)([A-Za-z0-9]+)(?:[/?#]|$)/i.exec(location.href);
      const finalWeibo = /^https?:\\/\\/(?:(?:www|m)\\.)?weibo\\.(?:com|cn)\\//i.test(location.href);
      const target = ${JSON.stringify(id)} || (finalMatch ? finalMatch[1] : '');
      if (${JSON.stringify(weibo)} || finalWeibo) {
        out.scopeFound = false;
        if (!target) { out.error = '请使用微博详情页链接'; return JSON.stringify(out); }
        if (!/^(?:www\\.)?weibo\\.com$|^m\\.weibo\\.cn$/i.test(location.hostname)) {
          out.error = '未能打开目标微博，可能需要登录或验证'; return JSON.stringify(out);
        }
        // JSON is fetched in-page with that origin's existing cookies. No credentials are copied.
        let state = window.__imageDownloaderBatchPost;
        if (!state || state.target !== target) {
          state = { target, value: null, error: '' };
          window.__imageDownloaderBatchPost = state;
          const endpoint = location.hostname.endsWith('weibo.com') ? '/ajax/statuses/show?id=' : '/statuses/show?id=';
          fetch(endpoint + encodeURIComponent(target), { credentials: 'same-origin' })
            .then(r => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
            .then(raw => { state.value = raw.data || raw; })
            .catch(() => { state.error = '无法读取目标微博，请打开网页确认登录或验证后重试'; });
        }
        const post = state.value;
        if (!post) { out.error = state.error; return JSON.stringify(out); }
        const numericId = value => {
          if (/^\\d+$/.test(value)) return value;
          const alphabet = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
          let text = '';
          for (let end = value.length; end > 0; end -= 4) {
            let sum = 0;
            for (const ch of value.slice(Math.max(0, end - 4), end)) sum = sum * 62 + alphabet.indexOf(ch);
            text = (end <= 4 ? String(sum) : String(sum).padStart(7, '0')) + text;
          }
          return text;
        };
        const received = String(post.mblogid || post.bid || post.idstr || post.id || '');
        if (!received || numericId(received) !== numericId(target)) {
          out.error = '无法定位目标微博正文，帖子可能已删除或不可访问'; return JSON.stringify(out);
        }
        out.scopeFound = true; out.bottom = true;
        const text = String(post.text_raw || post.text || '').replace(/<[^>]*>/g, '').trim();
        if (text) out.title = text.slice(0, 80);
        const pics = Array.isArray(post.pics) ? post.pics
          : (post.pic_ids || []).map(key => (post.pic_infos || {})[key]).filter(Boolean);
        const seen = new Set();
        for (const pic of pics) {
          const candidates = [];
          const add = item => {
            const raw = typeof item === 'string' ? item : item && item.url;
            if (!raw) return;
            try {
              const url = new URL(raw, location.href).href;
              if (/^https?:\\/\\//i.test(url) && !candidates.some(x => x.url === url))
                candidates.push({ url, declared: Number(item.width) || 0 });
            } catch (_) {}
          };
          if (${JSON.stringify(quality)} === 'display') { add(pic.url); add(pic.bmiddle); }
          for (const key of ['original','largest','large','url','bmiddle','thumbnail']) add(pic[key]);
          if (!candidates.length || seen.has(candidates[0].url)) continue;
          seen.add(candidates[0].url);
          out.images.push({ url: candidates[0].url, description: '', candidates,
            width: 0, height: 0 });
        }
        return JSON.stringify(out);
      }
      const data = ${generic};
      const parsed = JSON.parse(data);
      out.images = parsed.images; out.title = parsed.title;
      const height = Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0);
      out.bottom = window.scrollY + window.innerHeight >= height - 4;
      window.scrollBy(0, Math.max(300, Math.floor(window.innerHeight * 0.8)));
      return JSON.stringify(out);
    })()`;
  }

  static parse(raw: string): BatchPageStep {
    let parsed: Object = JSON.parse(raw) as Object;
    if (typeof parsed === 'string') { parsed = JSON.parse(parsed as string) as Object; }
    const step = parsed as BatchPageStep;
    const scan: ScanData = ScanProtocol.parse(JSON.stringify(parsed));
    step.images = scan.images;
    step.title = scan.title; step.url = scan.url;
    step.error = typeof step.error === 'string' ? step.error : '';
    step.bottom = step.bottom === true; step.direct = step.direct === true;
    step.scopeFound = step.scopeFound === true; step.pending = step.pending === true;
    return step;
  }
}
