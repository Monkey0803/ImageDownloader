import { PictureItem } from '../model/Models';
import { MediaFormat } from './MediaFormat';

/** 扫描结果筛选；宽高为 0 的图片尺寸未知，保留在结果中供用户自行判断。 */
export class PictureFilters {
  static matches(item: PictureItem, format: string, minWidth: number, minHeight: number,
    urlQuery: string): boolean {
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
    return item.url.toLowerCase().includes(urlQuery.trim().toLowerCase());
  }

  static minimum(text: string): number {
    const parsed: number = Number(text);
    return text.trim().length > 0 && isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : 0;
  }
}
