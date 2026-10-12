/** One image found by scanning a page, before it becomes a download. */
@Observed
export class PictureItem {
  id: string = '';
  url: string = '';
  name: string = '';
  description: string = '';
  selected: boolean = false;
  userNamed: boolean = false;
}

/** One image download, from the queue through to the finished file. */
@Observed
export class DownloadItem {
  id: string = '';
  url: string = '';
  name: string = '';
  userNamed: boolean = false;
  path: string = '';
  sourcePage: string = '';
  batchId: string = '';
  taskId: string = '';
  status: string = 'queued';
  processed: number = 0;
  total: number = 0;
  /** Final on-disk byte count, recorded when the download completes. */
  size: number = 0;
  error: string = '';
  createdAt: number = 0;
  /** When the download finished, used for the gallery's timestamp. */
  finishedAt: number = 0;
}

/** A ZIP archive produced by packing a batch. */
@Observed
export class ZipItem {
  id: string = '';
  name: string = '';
  path: string = '';
  batchId: string = '';
  imageCount: number = 0;
  failedCount: number = 0;
  size: number = 0;
  createdAt: number = 0;
  /** Source URLs of a few members, kept only to draw the stacked preview. */
  thumbs: string[] = [];
}

/** A ZIP-in-progress: the batch groups its member downloads. */
@Observed
export class BatchItem {
  id: string = '';
  name: string = '';
  sourcePage: string = '';
  status: string = 'downloading';
  error: string = '';
}

/** Everything that survives a restart. */
export class SavedState {
  downloads: DownloadItem[] = [];
  zips: ZipItem[] = [];
  batches: BatchItem[] = [];
  concurrency: number = 3;
  /** 'system' | 'light' | 'dark' */
  themeMode: string = 'system';
  /** 'adaptive' | 'immersive' */
  materialType: string = 'adaptive';
  /** Whether the immersive material lights up under touch. */
  lightEffect: boolean = true;
}

/** Fallback for a field that an older state file did not persist yet. */
export function orNumber(value: number, fallback: number): number {
  return value === undefined ? fallback : value;
}

/** Fallback for a boolean that an older state file did not persist yet. */
export function orBoolean(value: boolean, fallback: boolean): boolean {
  return value === undefined ? fallback : value;
}

/** Fallback for a string that an older state file did not persist yet. */
export function orString(value: string, fallback: string): string {
  return value === undefined ? fallback : value;
}

/** Fallback for an array an older state file did not persist yet. */
export function orArray(value: string[], fallback: string[]): string[] {
  return value === undefined ? fallback : value;
}
