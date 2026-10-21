import { DownloadItem, ZipItem } from '../model/Models';
import { MediaFormat } from './MediaFormat';

/** 图库筛选和排序的纯计算，不修改商店持有的数组。 */
export class LibraryQuery {
  static images(items: DownloadItem[], name: string, source: string, format: string,
    order: string): DownloadItem[] {
    const nameNeedle: string = name.trim().toLowerCase();
    const sourceNeedle: string = source.trim().toLowerCase();
    const result: DownloadItem[] = items.filter((item: DownloadItem): boolean => {
      if (item.status !== 'completed' || item.batchId.length > 0) { return false; }
      if (!item.name.toLowerCase().includes(nameNeedle)
        || !item.sourcePage.toLowerCase().includes(sourceNeedle)) { return false; }
      if (format.length === 0) { return true; }
      const ext: string = MediaFormat.extensionOf(item.name);
      return format === 'jpg' ? ext === 'jpg' || ext === 'jpeg' : ext === format;
    });
    return LibraryQuery.sort(result, order, false);
  }

  static archives(items: ZipItem[], name: string, order: string): ZipItem[] {
    const needle: string = name.trim().toLowerCase();
    return LibraryQuery.sort(items.filter((item: ZipItem): boolean =>
      item.name.toLowerCase().includes(needle)), order, true);
  }

  private static sort<T extends DownloadItem | ZipItem>(items: T[], order: string, archive: boolean): T[] {
    const result: T[] = items.slice();
    result.sort((a: T, b: T): number => {
      if (order === 'name') { return a.name.localeCompare(b.name); }
      if (order === 'size') { return b.size - a.size || a.name.localeCompare(b.name); }
      const aTime: number = archive ? a.createdAt : (a as DownloadItem).finishedAt;
      const bTime: number = archive ? b.createdAt : (b as DownloadItem).finishedAt;
      return order === 'oldest' ? aTime - bTime : bTime - aTime;
    });
    return result;
  }
}
