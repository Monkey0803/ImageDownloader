import { EditDocument, EditPoint, EditRect, EditStroke, PreviewSize } from '../model/ImageEditDocument';

/** All document coordinates refer to original, orientation-corrected source pixels. */
export class ImageEditGeometry {
  static create(width: number, height: number): EditDocument {
    if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
      throw new Error('无效原图尺寸');
    }
    const doc: EditDocument = new EditDocument();
    doc.sourceWidth = width; doc.sourceHeight = height;
    doc.crop.width = width; doc.crop.height = height;
    return doc;
  }

  static copy(source: EditDocument): EditDocument {
    const doc: EditDocument = new EditDocument();
    doc.sourceWidth = source.sourceWidth; doc.sourceHeight = source.sourceHeight;
    doc.crop = ImageEditGeometry.copyRect(source.crop);
    doc.turns = source.turns;
    doc.strokes = source.strokes.map((stroke: EditStroke): EditStroke => {
      const next: EditStroke = new EditStroke();
      next.kind = stroke.kind; next.color = stroke.color; next.width = stroke.width;
      next.points = stroke.points.map((point: EditPoint): EditPoint =>
        ImageEditGeometry.point(point.x, point.y));
      return next;
    });
    return doc;
  }

  /** Show the full source while moving crop handles; the export crop stays unchanged. */
  static forCropPreview(source: EditDocument): EditDocument {
    const display: EditDocument = new EditDocument();
    display.sourceWidth = source.sourceWidth;
    display.sourceHeight = source.sourceHeight;
    display.turns = source.turns;
    display.crop = ImageEditGeometry.create(source.sourceWidth, source.sourceHeight).crop;
    return display;
  }

  private static copyRect(source: EditRect): EditRect {
    const value: EditRect = new EditRect();
    value.x = source.x; value.y = source.y; value.width = source.width; value.height = source.height;
    return value;
  }

  private static point(x: number, y: number): EditPoint {
    const value: EditPoint = new EditPoint(); value.x = x; value.y = y;
    return value;
  }

  private static turns(doc: EditDocument): number {
    return Number.isFinite(doc.turns) ? ((Math.round(doc.turns) % 4) + 4) % 4 : 0;
  }

  static outputSize(doc: EditDocument): PreviewSize {
    const size: PreviewSize = new PreviewSize();
    const swapped: boolean = ImageEditGeometry.turns(doc) % 2 === 1;
    size.width = swapped ? doc.crop.height : doc.crop.width;
    size.height = swapped ? doc.crop.width : doc.crop.height;
    return size;
  }

  static toOutput(point: EditPoint, doc: EditDocument): EditPoint {
    const x: number = point.x - doc.crop.x;
    const y: number = point.y - doc.crop.y;
    switch (ImageEditGeometry.turns(doc)) {
      case 1: return ImageEditGeometry.point(doc.crop.height - 1 - y, x);
      case 2: return ImageEditGeometry.point(doc.crop.width - 1 - x, doc.crop.height - 1 - y);
      case 3: return ImageEditGeometry.point(y, doc.crop.width - 1 - x);
      default: return ImageEditGeometry.point(x, y);
    }
  }

  static toSource(point: EditPoint, doc: EditDocument): EditPoint {
    const x: number = point.x;
    const y: number = point.y;
    switch (ImageEditGeometry.turns(doc)) {
      case 1: return ImageEditGeometry.point(doc.crop.x + y,
        doc.crop.y + doc.crop.height - 1 - x);
      case 2: return ImageEditGeometry.point(doc.crop.x + doc.crop.width - 1 - x,
        doc.crop.y + doc.crop.height - 1 - y);
      case 3: return ImageEditGeometry.point(doc.crop.x + doc.crop.width - 1 - y,
        doc.crop.y + x);
      default: return ImageEditGeometry.point(doc.crop.x + x, doc.crop.y + y);
    }
  }

  static constrainCrop(input: EditRect, width: number, height: number): EditRect {
    if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
      throw new Error('无效原图尺寸');
    }
    const full: EditRect = new EditRect(); full.width = width; full.height = height;
    if (![input.x, input.y, input.width, input.height].every((value: number): boolean =>
      Number.isFinite(value))) { return full; }
    const x0: number = Math.max(0, Math.min(width - 1, Math.floor(Math.min(input.x, input.x + input.width))));
    const y0: number = Math.max(0, Math.min(height - 1, Math.floor(Math.min(input.y, input.y + input.height))));
    const x1: number = Math.max(x0 + 1, Math.min(width, Math.ceil(Math.max(input.x, input.x + input.width))));
    const y1: number = Math.max(y0 + 1, Math.min(height, Math.ceil(Math.max(input.y, input.y + input.height))));
    const crop: EditRect = new EditRect();
    crop.x = x0; crop.y = y0; crop.width = x1 - x0; crop.height = y1 - y0;
    return crop;
  }

  static aspectCrop(doc: EditDocument, ratio: number): EditRect {
    const current: EditRect = ImageEditGeometry.constrainCrop(doc.crop, doc.sourceWidth, doc.sourceHeight);
    const target: number = ratio === 0 ? doc.sourceWidth / doc.sourceHeight : ratio;
    if (!Number.isFinite(target) || target <= 0) { throw new Error('无效裁剪比例'); }
    let width: number = current.width;
    let height: number = Math.max(1, Math.round(width / target));
    if (height > current.height) {
      height = current.height;
      width = Math.max(1, Math.round(height * target));
    }
    const rect: EditRect = new EditRect();
    rect.x = current.x + Math.floor((current.width - width) / 2);
    rect.y = current.y + Math.floor((current.height - height) / 2);
    rect.width = width; rect.height = height;
    return ImageEditGeometry.constrainCrop(rect, doc.sourceWidth, doc.sourceHeight);
  }

  /** Image pixels fitted inside a viewport; bars around this rectangle are not editable. */
  static viewRect(doc: EditDocument, viewport: EditRect): EditRect {
    const output: PreviewSize = ImageEditGeometry.outputSize(doc);
    if (output.width <= 0 || output.height <= 0 || viewport.width <= 0 || viewport.height <= 0) {
      throw new Error('无效预览尺寸');
    }
    const scale: number = Math.min(viewport.width / output.width, viewport.height / output.height);
    const rect: EditRect = new EditRect();
    rect.width = output.width * scale; rect.height = output.height * scale;
    rect.x = viewport.x + (viewport.width - rect.width) / 2;
    rect.y = viewport.y + (viewport.height - rect.height) / 2;
    return rect;
  }

  static sourceToView(point: EditPoint, doc: EditDocument, viewport: EditRect): EditPoint {
    const rect: EditRect = ImageEditGeometry.viewRect(doc, viewport);
    const output: PreviewSize = ImageEditGeometry.outputSize(doc);
    const pixel: EditPoint = ImageEditGeometry.toOutput(point, doc);
    return ImageEditGeometry.point(rect.x + (pixel.x + 0.5) * rect.width / output.width,
      rect.y + (pixel.y + 0.5) * rect.height / output.height);
  }

  static viewToSource(point: EditPoint, doc: EditDocument, viewport: EditRect): EditPoint | undefined {
    const rect: EditRect = ImageEditGeometry.viewRect(doc, viewport);
    if (point.x < rect.x || point.y < rect.y || point.x >= rect.x + rect.width ||
      point.y >= rect.y + rect.height) { return undefined; }
    const output: PreviewSize = ImageEditGeometry.outputSize(doc);
    const pixel: EditPoint = ImageEditGeometry.point(
      (point.x - rect.x) * output.width / rect.width - 0.5,
      (point.y - rect.y) * output.height / rect.height - 0.5);
    return ImageEditGeometry.toSource(pixel, doc);
  }
}
