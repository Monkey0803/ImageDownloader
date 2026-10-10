export class PictureItem {
  id: string = '';
  url: string = '';
  name: string = '';
  description: string = '';
  selected: boolean = false;
  userNamed: boolean = false;
}

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
  error: string = '';
  createdAt: number = 0;
}

export class ZipItem {
  id: string = '';
  name: string = '';
  path: string = '';
  batchId: string = '';
  imageCount: number = 0;
  failedCount: number = 0;
  createdAt: number = 0;
}

export class BatchItem {
  id: string = '';
  name: string = '';
  sourcePage: string = '';
  status: string = 'downloading';
  error: string = '';
}

export class SavedState {
  downloads: DownloadItem[] = [];
  zips: ZipItem[] = [];
  batches: BatchItem[] = [];
  concurrency: number = 3;
}
