/** Stable image identity and file version used to reject obsolete analysis results. */
export class AssetStamp {
  id: string = '';
  path: string = '';
  sourceKind: string = 'image';
  bytes: number = 0;
  modified: number = 0;
  changed: number = 0;
  orientation: number = 1;
}

export class LibraryMeta {
  id: string = '';
  favorite: boolean = false;
  tags: string[] = [];
}

export class VisualFeature {
  version: number = 1;
  lowBits: string = '';
  edgeBits: string = '';
  red: number = 0;
  green: number = 0;
  blue: number = 0;
  alpha: number = 0;
  width: number = 0;
  height: number = 0;
}

export class LibraryIndex {
  version: number = 1;
  id: string = '';
  stamp: AssetStamp = new AssetStamp();
  ocrVersion: number = 1;
  ocrStatus: string = 'unindexed';
  text: string = '';
  ocrError: string = '';
  feature: VisualFeature | undefined = undefined;
}

export class LibrarySearchEntry {
  id: string = '';
  favorite: boolean = false;
  tags: string[] = [];
  text: string = '';
  ocrStatus: string = 'unindexed';
}

export class LibrarySearchOptions {
  scope: string = 'all';
  query: string = '';
  source: string = '';
  format: string = '';
  order: string = 'newest';
  favoritesOnly: boolean = false;
  tag: string = '';
}

export class AnalysisProgress {
  kind: string = 'ocr';
  done: number = 0;
  total: number = 0;
  success: number = 0;
  empty: number = 0;
  failed: number = 0;
  message: string = '';
}

export class SimilarGroup {
  representativeId: string = '';
  ids: string[] = [];
}

export class AnalysisToken {
  generation: number = 0;
  cancelled: boolean = false;

  cancel(): void {
    this.generation += 1;
    this.cancelled = true;
  }
}

/** OCR line bounds in the decoded frame's pixel coordinates. */
export class RecognizedLine {
  text: string = '';
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
}
