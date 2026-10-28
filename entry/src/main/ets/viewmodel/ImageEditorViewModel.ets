import { AnalysisToken, AssetStamp } from '../model/LibraryAsset';
import { EditDocument, EditHistory, EditRect, EditStroke, ImageEditorPort, PreviewSize } from '../model/ImageEditDocument';
import { ImageEditGeometry } from '../util/ImageEditGeometry';
import { DownloadItem } from '../model/Models';

/** Draft state and export lifecycle. Native pixels stay behind ImageEditorPort. */
@ObservedV2
export class ImageEditorViewModel {
  private port: ImageEditorPort | undefined = undefined;
  private token: AnalysisToken = new AnalysisToken();
  private history: EditHistory = new EditHistory();
  private initial: string = '';
  private itemId: string = '';

  @Trace stamp: AssetStamp | undefined = undefined;
  @Trace document: EditDocument = new EditDocument();
  @Trace loading: boolean = false;
  @Trace saving: boolean = false;
  @Trace hasChanges: boolean = false;
  @Trace ready: boolean = false;

  attach(port: ImageEditorPort): void { this.port = port; }

  async load(itemId: string): Promise<void> {
    if (this.port === undefined) { throw new Error('图片编辑尚未就绪'); }
    this.token.cancel();
    this.token = new AnalysisToken();
    const token: AnalysisToken = this.token;
    this.ready = false; this.loading = true; this.itemId = itemId;
    try {
      const stamp: AssetStamp = await this.port.source(itemId);
      const size: PreviewSize = await this.port.info(stamp);
      if (token.cancelled) { return; }
      this.stamp = stamp;
      this.document = ImageEditGeometry.create(size.width, size.height);
      this.history.reset(this.document);
      this.initial = JSON.stringify(this.document);
      this.hasChanges = false;
      this.ready = true;
    } finally {
      if (this.token === token) { this.loading = false; }
    }
  }

  private commit(next: EditDocument): void {
    if (!this.ready || this.saving || this.token.cancelled) { return; }
    this.document = next;
    this.history.commit(next);
    this.hasChanges = JSON.stringify(next) !== this.initial;
  }

  setCrop(rect: EditRect): void {
    const next: EditDocument = ImageEditGeometry.copy(this.document);
    next.crop = ImageEditGeometry.constrainCrop(rect, next.sourceWidth, next.sourceHeight);
    this.commit(next);
  }

  setAspect(ratio: number): void {
    const next: EditDocument = ImageEditGeometry.copy(this.document);
    next.crop = ImageEditGeometry.aspectCrop(next, ratio);
    this.commit(next);
  }

  rotate(): void {
    const next: EditDocument = ImageEditGeometry.copy(this.document);
    next.turns = (next.turns + 1) % 4;
    this.commit(next);
  }

  addStroke(stroke: EditStroke): void {
    if (stroke.points.length === 0) { return; }
    const next: EditDocument = ImageEditGeometry.copy(this.document);
    next.strokes.push(stroke);
    this.commit(ImageEditGeometry.copy(next));
  }

  undo(): void {
    if (!this.ready || this.saving) { return; }
    const previous: EditDocument | undefined = this.history.undo();
    if (previous === undefined) { return; }
    this.document = previous;
    this.hasChanges = JSON.stringify(previous) !== this.initial;
  }

  clearStrokes(): void {
    if (this.document.strokes.length === 0) { return; }
    const next: EditDocument = ImageEditGeometry.copy(this.document);
    next.strokes = [];
    this.commit(next);
  }

  restoreCrop(): void {
    const next: EditDocument = ImageEditGeometry.copy(this.document);
    next.crop = ImageEditGeometry.create(next.sourceWidth, next.sourceHeight).crop;
    this.commit(next);
  }

  async save(): Promise<void> {
    if (!this.ready || !this.hasChanges || this.saving || this.token.cancelled) { return; }
    if (this.port === undefined) { throw new Error('图片编辑尚未就绪'); }
    this.saving = true;
    try {
      const copy: DownloadItem = await this.port.exportAndRegister(this.itemId,
        ImageEditGeometry.copy(this.document), this.token);
      if (!this.token.cancelled) { this.port.finish(copy.id); }
    } catch (error) {
      if (!this.token.cancelled) { this.port.showError('保存失败，编辑内容已保留，请重试'); }
    } finally {
      this.saving = false;
    }
  }

  cancel(): void { this.token.cancel(); }
}
