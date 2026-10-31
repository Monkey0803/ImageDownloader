import { PictureItem } from '../model/Models';
import { MediaFormat } from './MediaFormat';

/** 扫描结果筛选；宽高为 0 的图片尺寸未知，保留在结果中供用户自行判断。 */
export class PictureFilters {
  static matches(item: PictureItem, format: string, minWidth: number, minHeight: number,
    urlQuery: string, quick: string = '', textQuery: string = ''): boolean {
    const extension: string = MediaFormat.extensionOf(item.url);
    if (format.length > 0) {
      if (format === 'other') {
        if (['jpg', 'jpeg', 'png', 'gif', 'webp'].includes(extension)) { return false; }
      } else if (format === 'jpg') {
        if (extension !== 'jpg' && extension !== 'jpeg') { return false; }
      } else if (extension !== format) {
        return false;
      }
    }
    if (item.width > 0 && item.height > 0
      && (item.width < minWidth || item.height < minHeight)) {
      return false;
    }
    if (item.width > 0 && item.height > 0) {
      if (quick === 'large' && (Math.max(item.width, item.height) < 1200
        || Math.min(item.width, item.height) < 800)) { return false; }
      if (quick === 'landscape' && item.width <= item.height) { return false; }
      if (quick === 'portrait' && item.height <= item.width) { return false; }
    }
    if (!item.url.toLowerCase().includes(urlQuery.trim().toLowerCase())) { return false; }
    const query: string = textQuery.trim().toLowerCase();
    return query.length === 0 || (item.name ?? '').toLowerCase().includes(query)
      || (item.description ?? '').toLowerCase().includes(query) || item.url.toLowerCase().includes(query);
  }

  /** 元数据优先；没有元数据时仅推荐实际量到的较大图片。 */
  static suggested(items: PictureItem[]): PictureItem | undefined {
    const marked: PictureItem | undefined = items.find((item: PictureItem): boolean => item.featured);
    if (marked !== undefined) { return marked; }
    let best: PictureItem | undefined = undefined;
    for (const item of items) {
      if (Math.max(item.width, item.height) < 320 || Math.min(item.width, item.height) < 180) { continue; }
      if (best === undefined || item.width * item.height > best.width * best.height) { best = item; }
    }
    return best;
  }

  static minimum(text: string): number {
    const parsed: number = Number(text);
    return text.trim().length > 0 && isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : 0;
  }
}
