import { MediaFormat } from './MediaFormat';

export interface BatchLinkReport {
  urls: string[];
  invalid: number;
  duplicates: number;
}

/** 只接收逐行填写的 HTTP(S) 图片直链，保留原顺序。 */
export class BatchLinks {
  static parse(text: string): BatchLinkReport {
    const urls: string[] = [];
    const seen: Set<string> = new Set<string>();
    let invalid: number = 0;
    let duplicates: number = 0;
    for (const row of text.split(/\r?\n/)) {
      const url: string = row.trim();
      if (url.length === 0) { continue; }
      if (!/^https?:\/\/[^/?#\s]+(?:[/?#][^\s]*)?$/i.test(url)
        || (MediaFormat.mediaKindOf(url) !== 'image' && MediaFormat.mediaKindOf(url) !== 'livephoto')) {
        invalid++;
        continue;
      }
      if (seen.has(url)) { duplicates++; continue; }
      seen.add(url);
      urls.push(url);
    }
    return { urls: urls, invalid: invalid, duplicates: duplicates };
  }
}
