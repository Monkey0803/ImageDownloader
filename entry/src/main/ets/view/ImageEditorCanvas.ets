import { image } from '@kit.ImageKit';
import { AssetStamp } from '../model/LibraryAsset';
import { EditDocument, EditPoint, EditRect, EditStroke, PreviewSize } from '../model/ImageEditDocument';
import { LibraryImageReader } from '../service/LibraryImageReader';
import { ImageEditGeometry } from '../util/ImageEditGeometry';

/** A bounded preview; edits remain in original source coordinates. */
@ComponentV2
export struct ImageEditorCanvas {
  @Require @Param stamp: AssetStamp;
  @Require @Param document: EditDocument;
  @Param tool: string = 'crop';
  @Param color: string = '#FF0000';
  @Param strokeWidth: number = 4;
  @Event onCrop: (value: EditRect) => void = (value: EditRect): void => {};
  @Event onStroke: (value: EditStroke) => void = (value: EditStroke): void => {};

  @Local private frame: image.PixelMap | undefined = undefined;
  @Local private canvasWidth: number = 0;
  @Local private canvasHeight: number = 0;
  @Local private problem: string = '';
  private owned: image.PixelMap | undefined = undefined;
  private generation: number = 0;
  private decodeKey: string = '';
  private loading: boolean = false;
  private disposed: boolean = false;
  private drawing: EditStroke | undefined = undefined;
  private cropDraft: EditRect | undefined = undefined;
  private cropStart: EditRect | undefined = undefined;
  private dragStart: EditPoint | undefined = undefined;
  private dragHandle: string = '';
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(false));

  aboutToAppear(): void { this.disposed = false; this.decode(); }
  aboutToDisappear(): void {
    this.disposed = true; this.generation++;
    this.loading = false; this.decodeKey = '';
    this.frame = undefined;
    this.drawing = undefined; this.cropDraft = undefined;
    this.cropStart = undefined; this.dragStart = undefined;
    if (this.owned !== undefined) { this.owned.release(); this.owned = undefined; }
  }

  @Monitor('stamp', 'document')
  private onDocumentChanged(monitor: IMonitor): void { this.decode(); }

  @Monitor('tool')
  private onToolChanged(monitor: IMonitor): void { this.decode(); }

  private displayDocument(): EditDocument {
    if (this.tool !== 'crop') { return this.document; }
    return ImageEditGeometry.forCropPreview(this.document);
  }

  private viewport(): EditRect {
    const rect: EditRect = new EditRect(); rect.width = this.canvasWidth; rect.height = this.canvasHeight;
    return rect;
  }

  private async decode(): Promise<void> {
    if (this.canvasWidth <= 0 || this.canvasHeight <= 0 || this.stamp.path.length === 0) { return; }
    const display: EditDocument = this.displayDocument();
    const crop: EditRect = display.crop;
    const key: string = [this.stamp.path, this.stamp.bytes, this.stamp.modified, this.stamp.changed,
      this.stamp.orientation, crop.x, crop.y, crop.width, crop.height, display.turns,
      this.canvasWidth, this.canvasHeight].join(':');
    if (key === this.decodeKey && (this.loading || this.frame !== undefined)) {
      this.paint(); return;
    }
    const generation: number = ++this.generation;
    this.decodeKey = key;
    this.loading = true;
    this.frame = undefined;
    this.problem = '';
    this.drawing = undefined; this.cropDraft = undefined;
    this.cropStart = undefined; this.dragStart = undefined;
    if (this.owned !== undefined) { this.owned.release(); this.owned = undefined; }
    this.paint();
    let decoded: image.PixelMap | undefined = undefined;
    try {
      const output: PreviewSize = ImageEditGeometry.outputSize(display);
      const density: number = this.getUIContext().vp2px(1);
      const scale: number = Math.min(1, this.canvasWidth * density / output.width,
        this.canvasHeight * density / output.height,
        Math.sqrt(3000000 / (crop.width * crop.height)));
      const size: PreviewSize = new PreviewSize();
      size.width = Math.max(1, Math.round(crop.width * scale));
      size.height = Math.max(1, Math.round(crop.height * scale));
      decoded = await LibraryImageReader.decode(this.stamp, crop, size, false);
      const turns: number = ((display.turns % 4) + 4) % 4;
      if (turns > 0) { await decoded.rotate(turns * 90); }
      if (this.disposed || generation !== this.generation) { return; }
      this.owned = decoded; this.frame = decoded; decoded = undefined;
      this.problem = '';
      this.paint();
    } catch (error) {
      if (!this.disposed && generation === this.generation) { this.problem = '图片预览加载失败'; }
    } finally {
      if (decoded !== undefined) { decoded.release(); }
      if (generation === this.generation) { this.loading = false; }
    }
  }

  private drawStroke(stroke: EditStroke, display: EditDocument, viewport: EditRect,
    bounds: EditRect): void {
    if (stroke.points.length === 0) { return; }
    const ctx: CanvasRenderingContext2D = this.context;
    ctx.save(); ctx.beginPath(); ctx.rect(bounds.x, bounds.y, bounds.width, bounds.height); ctx.clip();
    ctx.strokeStyle = stroke.color;
    ctx.lineWidth = Math.max(2, stroke.width * bounds.width / ImageEditGeometry.outputSize(display).width);
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    const first: EditPoint = ImageEditGeometry.sourceToView(stroke.points[0], display, viewport);
    ctx.beginPath(); ctx.moveTo(first.x, first.y);
    if (stroke.kind === 'rect' && stroke.points.length > 1) {
      const last: EditPoint = ImageEditGeometry.sourceToView(stroke.points[stroke.points.length - 1],
        display, viewport);
      ctx.rect(Math.min(first.x, last.x), Math.min(first.y, last.y),
        Math.abs(last.x - first.x), Math.abs(last.y - first.y));
    } else {
      for (let i: number = 1; i < stroke.points.length; i++) {
        const point: EditPoint = ImageEditGeometry.sourceToView(stroke.points[i], display, viewport);
        ctx.lineTo(point.x, point.y);
      }
      if (stroke.points.length === 1) { ctx.lineTo(first.x + 0.1, first.y + 0.1); }
    }
    ctx.stroke(); ctx.restore();
  }

  private paint(): void {
    if (this.canvasWidth <= 0 || this.canvasHeight <= 0) { return; }
    const ctx: CanvasRenderingContext2D = this.context;
    ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    if (this.frame === undefined) { return; }
    const display: EditDocument = this.displayDocument();
    const viewport: EditRect = this.viewport();
    const bounds: EditRect = ImageEditGeometry.viewRect(display, viewport);
    for (const stroke of this.document.strokes) { this.drawStroke(stroke, display, viewport, bounds); }
    if (this.drawing !== undefined) { this.drawStroke(this.drawing, display, viewport, bounds); }
    if (this.tool !== 'crop') { return; }
    const crop: EditRect = this.cropDraft ?? this.document.crop;
    const top: EditPoint = new EditPoint(); top.x = crop.x; top.y = crop.y;
    const bottom: EditPoint = new EditPoint();
    bottom.x = crop.x + crop.width - 1; bottom.y = crop.y + crop.height - 1;
    const a: EditPoint = ImageEditGeometry.sourceToView(top, display, viewport);
    const b: EditPoint = ImageEditGeometry.sourceToView(bottom, display, viewport);
    ctx.strokeStyle = '#FFFFFFFF'; ctx.lineWidth = 2;
    ctx.strokeRect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y));
    ctx.fillStyle = '#FFFFFFFF';
    const corners: EditPoint[] = [a, b];
    const otherA: EditPoint = new EditPoint(); otherA.x = a.x; otherA.y = b.y;
    const otherB: EditPoint = new EditPoint(); otherB.x = b.x; otherB.y = a.y;
    corners.push(otherA, otherB);
    for (const point of corners) { ctx.fillRect(point.x - 5, point.y - 5, 10, 10); }
  }

  private sourcePoint(x: number, y: number, clamp: boolean = false): EditPoint | undefined {
    const display: EditDocument = this.displayDocument();
    if (clamp) {
      const view: EditRect = ImageEditGeometry.viewRect(display, this.viewport());
      x = Math.max(view.x, Math.min(view.x + view.width - 0.01, x));
      y = Math.max(view.y, Math.min(view.y + view.height - 0.01, y));
    }
    return ImageEditGeometry.viewToSource({ x: x, y: y }, display, this.viewport());
  }

  private startCrop(x: number, y: number, point: EditPoint): void {
    const crop: EditRect = this.document.crop;
    const corners: EditPoint[] = [
      { x: crop.x, y: crop.y }, { x: crop.x + crop.width - 1, y: crop.y },
      { x: crop.x, y: crop.y + crop.height - 1 },
      { x: crop.x + crop.width - 1, y: crop.y + crop.height - 1 }
    ];
    const names: string[] = ['topLeft', 'topRight', 'bottomLeft', 'bottomRight'];
    this.dragHandle = 'move';
    for (let i: number = 0; i < corners.length; i++) {
      const view: EditPoint = ImageEditGeometry.sourceToView(corners[i], this.displayDocument(), this.viewport());
      if (Math.abs(view.x - x) <= 24 && Math.abs(view.y - y) <= 24) {
        this.dragHandle = names[i]; break;
      }
    }
    this.dragStart = point;
    this.cropStart = { x: crop.x, y: crop.y, width: crop.width, height: crop.height };
    this.cropDraft = { x: crop.x, y: crop.y, width: crop.width, height: crop.height };
  }

  private moveCrop(point: EditPoint): void {
    const start: EditRect | undefined = this.cropStart;
    const down: EditPoint | undefined = this.dragStart;
    if (start === undefined || down === undefined) { return; }
    const next: EditRect = new EditRect();
    next.x = start.x; next.y = start.y; next.width = start.width; next.height = start.height;
    const dx: number = Math.round(point.x - down.x);
    const dy: number = Math.round(point.y - down.y);
    if (this.dragHandle === 'move') {
      next.x = Math.max(0, Math.min(this.document.sourceWidth - next.width, start.x + dx));
      next.y = Math.max(0, Math.min(this.document.sourceHeight - next.height, start.y + dy));
    } else {
      if (this.dragHandle.endsWith('Left')) { next.x += dx; next.width -= dx; }
      if (this.dragHandle.endsWith('Right')) { next.width += dx; }
      if (this.dragHandle.startsWith('top')) { next.y += dy; next.height -= dy; }
      if (this.dragHandle.startsWith('bottom')) { next.height += dy; }
      this.cropDraft = ImageEditGeometry.constrainCrop(next, this.document.sourceWidth, this.document.sourceHeight);
      this.paint(); return;
    }
    this.cropDraft = next;
    this.paint();
  }

  private touch(event: TouchEvent): void {
    if (this.frame === undefined) { return; }
    const contact: TouchObject | undefined = event.touches.length > 0 ? event.touches[0] : event.changedTouches[0];
    if (contact === undefined) { return; }
    const point: EditPoint | undefined = this.sourcePoint(contact.x, contact.y,
      this.tool === 'crop' && this.dragStart !== undefined && event.type !== TouchType.Down);
    if (event.type === TouchType.Down) {
      if (point === undefined) { return; }
      if (this.tool === 'crop') { this.startCrop(contact.x, contact.y, point); }
      else {
        const stroke: EditStroke = new EditStroke();
        stroke.kind = this.tool === 'rectangle' ? 'rect' : this.tool;
        stroke.color = this.color; stroke.width = this.strokeWidth;
        stroke.points = [point]; this.drawing = stroke;
      }
    } else if (event.type === TouchType.Move) {
      if (point === undefined) { return; }
      if (this.tool === 'crop') { this.moveCrop(point); }
      else if (this.drawing !== undefined) {
        if (this.tool === 'rectangle') { this.drawing.points = [this.drawing.points[0], point]; }
        else { this.drawing.points.push(point); }
        this.paint();
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (event.type === TouchType.Up && point !== undefined && this.tool === 'crop' && this.cropDraft !== undefined) {
        this.moveCrop(point); this.onCrop(this.cropDraft);
      } else if (event.type === TouchType.Up && this.drawing !== undefined) {
        if (point !== undefined && this.tool === 'rectangle') {
          this.drawing.points = [this.drawing.points[0], point];
        }
        this.onStroke(this.drawing);
      }
      this.drawing = undefined; this.cropDraft = undefined;
      this.cropStart = undefined; this.dragStart = undefined;
      this.paint();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.frame !== undefined) {
        Image(this.frame).width('100%').height('100%').objectFit(ImageFit.Contain)
      } else if (this.problem.length > 0) {
        Text(this.problem).fontColor('#FFFFFFFF')
      } else { LoadingProgress().width(28).height(28).color('#FFFFFFFF') }
      Canvas(this.context).width('100%').height('100%')
        .onReady((): void => { this.paint(); })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%').height('100%').backgroundColor('#FF151515')
    .onSizeChange((oldSize: SizeOptions, newSize: SizeOptions): void => {
      this.canvasWidth = Number(newSize.width); this.canvasHeight = Number(newSize.height);
      this.decode(); this.paint();
    })
    .onTouch((event: TouchEvent): void => { this.touch(event); })
  }
}
