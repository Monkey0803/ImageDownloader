import { DownloadItem } from './Models';
import { AssetStamp, AnalysisToken } from './LibraryAsset';

export class EditPoint {
  x: number = 0;
  y: number = 0;
}

export class EditRect {
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
}

export class EditStroke {
  kind: string = 'pen';
  color: string = '#FF0000';
  width: number = 4;
  points: EditPoint[] = [];
}

export class EditDocument {
  sourceWidth: number = 0;
  sourceHeight: number = 0;
  crop: EditRect = new EditRect();
  turns: number = 0;
  strokes: EditStroke[] = [];
}

export class EditResult {
  path: string = '';
  width: number = 0;
  height: number = 0;
  bytes: number = 0;
}

export class EditTicket {
  id: string = '';
  originalId: string = '';
  /** 'png' | 'jpg' — 输出容器的真实扩展名；日志、恢复与显示名都以此为准。 */
  extension: string = 'png';
  pendingPath: string = '';
  finalPath: string = '';
  journalPath: string = '';
}

export class PreviewSize {
  width: number = 0;
  height: number = 0;
}

export interface ImageEditorPort {
  source(id: string): Promise<AssetStamp>;
  info(stamp: AssetStamp): Promise<PreviewSize>;
  exportAndRegister(id: string, doc: EditDocument, token: AnalysisToken): Promise<DownloadItem>;
  showError(message: string): void;
  finish(newId: string): void;
}

/** One snapshot per completed edit; pointer moves are never recorded individually. */
export class EditHistory {
  private snapshots: EditDocument[] = [];

  private clone(source: EditDocument): EditDocument {
    const doc: EditDocument = new EditDocument();
    doc.sourceWidth = source.sourceWidth; doc.sourceHeight = source.sourceHeight;
    doc.turns = source.turns;
    const crop: EditRect = new EditRect();
    crop.x = source.crop.x; crop.y = source.crop.y;
    crop.width = source.crop.width; crop.height = source.crop.height;
    doc.crop = crop;
    doc.strokes = source.strokes.map((stroke: EditStroke): EditStroke => {
      const value: EditStroke = new EditStroke();
      value.kind = stroke.kind; value.color = stroke.color; value.width = stroke.width;
      value.points = stroke.points.map((point: EditPoint): EditPoint => {
        const next: EditPoint = new EditPoint(); next.x = point.x; next.y = point.y;
        return next;
      });
      return value;
    });
    return doc;
  }

  reset(doc: EditDocument): void { this.snapshots = [this.clone(doc)]; }

  commit(doc: EditDocument): void {
    this.snapshots.push(this.clone(doc));
    if (this.snapshots.length > 101) { this.snapshots.shift(); }
  }

  canUndo(): boolean { return this.snapshots.length > 1; }

  undo(): EditDocument | undefined {
    if (!this.canUndo()) { return undefined; }
    this.snapshots.pop();
    return this.clone(this.snapshots[this.snapshots.length - 1]);
  }
}
