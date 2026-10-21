import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { DownloadItem } from '../model/Models';

export class DuplicateGroup {
  key: string = '';
  items: DownloadItem[] = [];
}

export class ContentScanResult {
  groups: DuplicateGroup[] = [];
  candidates: number = 0;
  bytes: number = 0;
  elapsedMs: number = 0;
  failures: number = 0;
}

/** 三种证据各自成组；URL、文件名都不能推断内容相同。 */
export class DuplicateFinder {
  static completed(items: DownloadItem[]): DownloadItem[] {
    return items.filter((item: DownloadItem): boolean => item.status === 'completed'
      && item.batchId.length === 0 && item.path.length > 0);
  }

  static sourceName(url: string): string {
    const clean: string = url.split('#')[0].split('?')[0];
    const name: string = clean.substring(clean.lastIndexOf('/') + 1);
    if (name.length === 0) { return ''; }
    try { return decodeURIComponent(name); } catch (error) { return name; }
  }

  static byKey(items: DownloadItem[], keyOf: (item: DownloadItem) => string): DuplicateGroup[] {
    const buckets: Map<string, DownloadItem[]> = new Map<string, DownloadItem[]>();
    for (const item of DuplicateFinder.completed(items)) {
      const key: string = keyOf(item);
      if (key.length === 0) { continue; }
      const bucket: DownloadItem[] = buckets.get(key) ?? [];
      bucket.push(item);
      buckets.set(key, bucket);
    }
    const result: DuplicateGroup[] = [];
    buckets.forEach((bucket: DownloadItem[], key: string): void => {
      if (bucket.length < 2) { return; }
      const group: DuplicateGroup = new DuplicateGroup();
      group.key = key;
      group.items = bucket;
      result.push(group);
    });
    return result.sort((a: DuplicateGroup, b: DuplicateGroup): number => b.items.length - a.items.length);
  }

  static sameUrl(items: DownloadItem[]): DuplicateGroup[] {
    return DuplicateFinder.byKey(items, (item: DownloadItem): string => item.url);
  }

  static sameSourceName(items: DownloadItem[]): DuplicateGroup[] {
    return DuplicateFinder.byKey(items, (item: DownloadItem): string => DuplicateFinder.sourceName(item.url));
  }

  /** 仅手动触发；先按实际文件大小分组，再逐个异步计算哈希，不落盘缓存。 */
  static async sameContent(items: DownloadItem[], progress: (done: number, total: number) => void): Promise<ContentScanResult> {
    const started: number = Date.now();
    const bySize: Map<number, DownloadItem[]> = new Map<number, DownloadItem[]>();
    const result: ContentScanResult = new ContentScanResult();
    for (const item of DuplicateFinder.completed(items)) {
      try {
        const size: number = fs.statSync(item.path).size;
        const bucket: DownloadItem[] = bySize.get(size) ?? [];
        bucket.push(item);
        bySize.set(size, bucket);
      } catch (error) { result.failures += 1; }
    }
    const candidates: DownloadItem[] = [];
    bySize.forEach((bucket: DownloadItem[], size: number): void => {
      if (bucket.length < 2) { return; }
      candidates.push(...bucket);
      result.bytes += size * bucket.length;
    });
    result.candidates = candidates.length;
    const digests: Map<string, DownloadItem[]> = new Map<string, DownloadItem[]>();
    let done: number = 0;
    for (const item of candidates) {
      try {
        const digest: string = await hash.hash(item.path, 'sha256');
        const bucket: DownloadItem[] = digests.get(digest) ?? [];
        bucket.push(item);
        digests.set(digest, bucket);
      } catch (error) { result.failures += 1; }
      done += 1;
      progress(done, candidates.length);
    }
    digests.forEach((bucket: DownloadItem[], digest: string): void => {
      if (bucket.length < 2) { return; }
      const group: DuplicateGroup = new DuplicateGroup();
      group.key = digest;
      group.items = bucket;
      result.groups.push(group);
    });
    result.groups.sort((a: DuplicateGroup, b: DuplicateGroup): number => b.items.length - a.items.length);
    result.elapsedMs = Date.now() - started;
    return result;
  }
}
