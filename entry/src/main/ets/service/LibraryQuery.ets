import { DownloadItem, ZipItem } from '../model/Models';
import { MediaFormat } from './MediaFormat';
import { LibrarySearchEntry, LibrarySearchOptions } from '../model/LibraryAsset';
import { LibraryText } from '../util/LibraryText';

/** 图库筛选和排序的纯计算，不修改商店持有的数组。 */
export class LibraryQuery {
  static search(items: DownloadItem[], entries: LibrarySearchEntry[],
    options: LibrarySearchOptions): DownloadItem[] {
    const byId: Map<string, LibrarySearchEntry> = new Map();
    for (const entry of entries) { byId.set(entry.id, entry); }
    const terms: string[] = LibraryText.normalize(options.query).split(' ')
      .filter((term: string): boolean => term.length > 0);
    const source: string = LibraryText.normalize(options.source);
    const tag: string = LibraryText.normalize(options.tag);
    const result: DownloadItem[] = items.filter((item: DownloadItem): boolean => {
      if (item.status !== 'completed' || item.batchId.length > 0) { return false; }
      if (source.length > 0 && !LibraryText.normalize(item.sourcePage).includes(source)) { return false; }
      if (options.format.length > 0) {
        const ext: string = MediaFormat.extensionOf(item.name);
        if (options.format === 'jpg' ? ext !== 'jpg' && ext !== 'jpeg' : ext !== options.format) {
          return false;
        }
      }
      const entry: LibrarySearchEntry | undefined = byId.get(item.id);
      if (options.favoritesOnly && (entry === undefined || !entry.favorite)) { return false; }
      if (tag.length > 0 && (entry === undefined || !entry.tags.some((label: string): boolean =>
        LibraryText.normalize(label) === tag))) { return false; }
      if (terms.length === 0) { return true; }
      const name: string = LibraryText.normalize(item.name);
      const labels: string = entry === undefined ? '' : LibraryText.normalize(entry.tags.join(' '));
      const ocr: string = entry === undefined ? '' : LibraryText.textKey(entry.text);
      return terms.every((term: string): boolean => {
        const ocrMatch: boolean = ocr.includes(LibraryText.textKey(term));
        if (options.scope === 'name') { return name.includes(term); }
        if (options.scope === 'text') { return ocrMatch; }
        if (options.scope === 'tags') { return labels.includes(term); }
        return name.includes(term) || ocrMatch || labels.includes(term);
      });
    });
    return LibraryQuery.sort(result, options.order, false);
  }

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
      if (order === 'name' || order === 'nameDesc') {
        return order === 'nameDesc' ? b.name.localeCompare(a.name) : a.name.localeCompare(b.name);
      }
      if (order === 'size') { return b.size - a.size || a.name.localeCompare(b.name); }
      if (order === 'sizeAsc') { return a.size - b.size || a.name.localeCompare(b.name); }
      const aTime: number = archive ? a.createdAt : (a as DownloadItem).finishedAt;
      const bTime: number = archive ? b.createdAt : (b as DownloadItem).finishedAt;
      return order === 'oldest' ? aTime - bTime : bTime - aTime;
    });
    return result;
  }
}
