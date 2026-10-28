/** Shared detail data for discovery, library and comparison. */
export class PreviewAsset {
  id: string = '';
  /** Stable ID of a completed local library record; empty for temporary web previews. */
  libraryId: string = '';
  src: string = '';
  localPath: string = '';
  name: string = '';
  url: string = '';
  sourcePage: string = '';
  bytes: number = 0;
  downloaded: boolean = false;
  downloadedAt: number = 0;
  width: number = 0;
  height: number = 0;
  animated: boolean = false;
}
