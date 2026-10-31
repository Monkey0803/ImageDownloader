import { DownloadItem, PictureItem } from '../model/Models';

export type DownloadPresence = 'new' | 'active' | 'completed';

export class AdmissionResult {
  added: number = 0;
  skippedActive: number = 0;
  skippedCompleted: number = 0;
  skippedRepeated: number = 0;

  skipped(): number { return this.skippedActive + this.skippedCompleted + this.skippedRepeated; }
}

export class AdmissionPlan {
  items: PictureItem[] = [];
  result: AdmissionResult = new AdmissionResult();
}

/** One URL and media kind identify a source. Query parameters remain part of the URL. */
export class DownloadAdmission {
  static presence(url: string, kind: string, downloads: DownloadItem[], exists: (path: string) => boolean): DownloadPresence {
    let completed: boolean = false;
    for (const item of downloads) {
      if (item.url !== url || item.kind !== kind || item.origin === 'edited') { continue; }
      if (['queued', 'waiting', 'running', 'paused', 'starting'].includes(item.status)) { return 'active'; }
      if (item.status === 'completed' && item.path.length > 0 && exists(item.path)) { completed = true; }
    }
    return completed ? 'completed' : 'new';
  }

  static plan(pictures: PictureItem[], downloads: DownloadItem[], exists: (path: string) => boolean,
    allowCompleted: boolean = false): AdmissionPlan {
    const plan: AdmissionPlan = new AdmissionPlan();
    const seen: Set<string> = new Set<string>();
    for (const picture of pictures) {
      if (!picture.selected || picture.url.length === 0) { continue; }
      const key: string = picture.kind + '\u0000' + picture.url;
      if (seen.has(key)) { plan.result.skippedRepeated++; continue; }
      seen.add(key);
      const state: DownloadPresence = DownloadAdmission.presence(picture.url, picture.kind, downloads, exists);
      if (state === 'active') { plan.result.skippedActive++; continue; }
      if (state === 'completed' && !allowCompleted) { plan.result.skippedCompleted++; continue; }
      plan.items.push(picture);
    }
    plan.result.added = plan.items.length;
    return plan;
  }
}
