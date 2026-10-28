import { PictureItem } from '../model/Models';
import { BatchLinkReport, BatchLinkStatus } from './BatchLinks';
import { PictureFactory, ScanImage } from './PictureFactory';

@ObservedV2
export class BatchPageGroup {
  @Trace id: string = '';
  @Trace line: number = 0;
  @Trace inputUrl: string = '';
  @Trace pageUrl: string = '';
  @Trace title: string = '';
  /** direct | page | pending */
  @Trace kind: string = 'page';
  /** waiting | loading | ready | failed */
  @Trace status: string = 'waiting';
  @Trace message: string = '';
  @Trace pictures: PictureItem[] = [];
}

export class BatchPageResult {
  url: string = '';
  title: string = '';
  images: ScanImage[] = [];
  direct: boolean = false;
  limited: boolean = false;
}

export interface BatchPageDownload {
  pictures: PictureItem[];
  pageUrl: string;
  title: string;
}

/** Session-only review state. No files or download tasks are created here. */
export class BatchPageGroups {
  static create(report: BatchLinkReport): BatchPageGroup[] {
    const groups: BatchPageGroup[] = [];
    const direct: BatchPageGroup = new BatchPageGroup();
    direct.id = 'direct'; direct.kind = 'direct'; direct.title = '批量链接'; direct.status = 'ready';
    for (const row of report.rows) {
      if (row.status === BatchLinkStatus.VALID) {
        direct.pictures.push(PictureFactory.fromUrl(row.url));
        if (!groups.includes(direct)) { groups.push(direct); }
      } else if (row.status === BatchLinkStatus.PAGE || row.status === BatchLinkStatus.PENDING) {
        const group: BatchPageGroup = new BatchPageGroup();
        group.id = 'line-' + row.line.toString(); group.line = row.line;
        group.inputUrl = row.url; group.pageUrl = row.url; group.title = row.url;
        group.kind = row.status === BatchLinkStatus.PENDING ? 'pending' : 'page';
        groups.push(group);
      }
    }
    return groups;
  }

  static accept(group: BatchPageGroup, result: BatchPageResult): void {
    const seen: Set<string> = new Set<string>();
    const pictures: PictureItem[] = [];
    for (const source of result.images) {
      if (!new RegExp('^https?://', 'i').test(source.url) || seen.has(source.url)) { continue; }
      seen.add(source.url);
      const picture: PictureItem = result.direct
        ? PictureFactory.fromUrl(source.url) : PictureFactory.fromScan(source, pictures.length + 1);
      picture.selected = true;
      pictures.push(picture);
    }
    group.pageUrl = result.url || group.inputUrl;
    group.title = result.title || group.inputUrl;
    if (result.direct) { group.kind = 'direct'; }
    group.pictures = pictures;
    group.status = pictures.length > 0 ? 'ready' : 'failed';
    group.message = pictures.length === 0 ? '未发现可下载图片，可打开网页查看后重试'
      : result.limited ? '已达到采集边界，图片可能尚未采集完整' : '';
  }

  static downloads(groups: BatchPageGroup[]): BatchPageDownload[] {
    const jobs: BatchPageDownload[] = [];
    const direct: PictureItem[] = [];
    for (const group of groups) {
      if (group.status !== 'ready') { continue; }
      const selected: PictureItem[] = group.pictures.filter((picture: PictureItem): boolean => picture.selected);
      if (selected.length === 0) { continue; }
      if (group.kind === 'direct') { direct.push(...selected); }
      else { jobs.push({ pictures: selected, pageUrl: group.pageUrl, title: group.title }); }
    }
    if (direct.length > 0) { jobs.unshift({ pictures: direct, pageUrl: '', title: '批量链接' }); }
    return jobs;
  }

  static count(groups: BatchPageGroup[]): number {
    return BatchPageGroups.downloads(groups).reduce((total: number, job: BatchPageDownload): number =>
      total + job.pictures.length, 0);
  }
}
