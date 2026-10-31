import { BatchItem, CollectionRecord, DownloadItem, ZipItem } from '../model/Models';

export class CollectionSummary {
  id: string = '';
  name: string = '未分组';
  added: number = 0;
  skipped: number = 0;
  completed: number = 0;
  failed: number = 0;
  active: number = 0;
}

/** Derive current outcomes without mistaking a ZIP and its member tasks for two groups. */
export class CollectionGroups {
  static summaries(downloads: DownloadItem[], zips: ZipItem[], batches: BatchItem[],
    records: CollectionRecord[]): CollectionSummary[] {
    const groups: Map<string, CollectionSummary> = new Map<string, CollectionSummary>();
    const ensure = (id: string, name: string): CollectionSummary => {
      let group: CollectionSummary | undefined = groups.get(id);
      if (group === undefined) {
        group = new CollectionSummary(); group.id = id; group.name = name || '未分组';
        groups.set(id, group);
      }
      return group;
    };
    for (const item of downloads) {
      const group: CollectionSummary = ensure(item.collectionId, item.collectionName);
      if (item.origin !== 'download') { continue; }
      if (item.status === 'completed') { group.completed++; }
      else if (item.status === 'failed' || item.status === 'cancelled') { group.failed++; }
      else { group.active++; }
    }
    for (const zip of zips) {
      const group: CollectionSummary = ensure(zip.collectionId, zip.collectionName);
      group.completed += zip.imageCount;
      group.failed += zip.failedCount;
    }
    for (const batch of batches) { ensure(batch.collectionId, batch.collectionName); }
    for (const record of records) {
      const group: CollectionSummary | undefined = groups.get(record.id);
      if (group !== undefined) {
        group.added = record.added; group.skipped = record.skipped;
      }
    }
    for (const group of groups.values()) {
      if (group.added === 0) { group.added = group.completed + group.failed + group.active; }
    }
    return Array.from(groups.values());
  }
}
