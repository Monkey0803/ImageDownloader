import { EditDocument, EditPoint, EditRect, EditStroke } from '../model/ImageEditDocument';
import { ImageEditGeometry } from './ImageEditGeometry';

/** Paints only covered BGRA bytes, preserving untouched semi-transparent source pixels. */
export class EditRasterizer {
  static bounds(stroke: EditStroke, doc: EditDocument): EditRect | undefined {
    if (stroke.points.length === 0 || !Number.isFinite(stroke.width) || stroke.width <= 0) {
      return undefined;
    }
    let left: number = Number.POSITIVE_INFINITY;
    let top: number = Number.POSITIVE_INFINITY;
    let right: number = Number.NEGATIVE_INFINITY;
    let bottom: number = Number.NEGATIVE_INFINITY;
    for (const source of stroke.points) {
      if (!Number.isFinite(source.x) || !Number.isFinite(source.y)) { return undefined; }
      const point: EditPoint = ImageEditGeometry.toOutput(source, doc);
      left = Math.min(left, point.x); top = Math.min(top, point.y);
      right = Math.max(right, point.x); bottom = Math.max(bottom, point.y);
    }
    const padding: number = stroke.width / 2 + 0.5;
    const rect: EditRect = new EditRect();
    rect.x = Math.floor(left - padding); rect.y = Math.floor(top - padding);
    rect.width = Math.ceil(right + padding) - rect.x + 1;
    rect.height = Math.ceil(bottom + padding) - rect.y + 1;
    return rect;
  }

  static intersects(a: EditRect, b: EditRect): boolean {
    return a.x < b.x + b.width && b.x < a.x + a.width &&
      a.y < b.y + b.height && b.y < a.y + a.height;
  }

  private static color(value: string): number[] | undefined {
    if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(value)) { return undefined; }
    const red: number = parseInt(value.slice(1, 3), 16);
    const green: number = parseInt(value.slice(3, 5), 16);
    const blue: number = parseInt(value.slice(5, 7), 16);
    const alpha: number = value.length === 9 ? parseInt(value.slice(7, 9), 16) : 255;
    return [blue, green, red, alpha];
  }

  private static distance(x: number, y: number, a: EditPoint, b: EditPoint): number {
    const dx: number = b.x - a.x;
    const dy: number = b.y - a.y;
    const length: number = dx * dx + dy * dy;
    const position: number = length <= 0 ? 0 :
      Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / length));
    const nearestX: number = a.x + position * dx;
    const nearestY: number = a.y + position * dy;
    return Math.hypot(x - nearestX, y - nearestY);
  }

  private static coverage(stroke: EditStroke, points: EditPoint[], x: number, y: number): number {
    if (points.length === 0) { return 0; }
    let distance: number = Number.POSITIVE_INFINITY;
    if (stroke.kind === 'rect' && points.length >= 2) {
      const first: EditPoint = points[0];
      const last: EditPoint = points[points.length - 1];
      const left: number = Math.min(first.x, last.x);
      const right: number = Math.max(first.x, last.x);
      const top: number = Math.min(first.y, last.y);
      const bottom: number = Math.max(first.y, last.y);
      const a: EditPoint = { x: left, y: top };
      const b: EditPoint = { x: right, y: top };
      const c: EditPoint = { x: right, y: bottom };
      const d: EditPoint = { x: left, y: bottom };
      distance = Math.min(EditRasterizer.distance(x, y, a, b),
        EditRasterizer.distance(x, y, b, c), EditRasterizer.distance(x, y, c, d),
        EditRasterizer.distance(x, y, d, a));
    } else if (stroke.kind === 'pen') {
      if (points.length === 1) { distance = EditRasterizer.distance(x, y, points[0], points[0]); }
      for (let i: number = 1; i < points.length; i++) {
        distance = Math.min(distance, EditRasterizer.distance(x, y, points[i - 1], points[i]));
      }
    }
    return Math.max(0, Math.min(1, stroke.width / 2 + 0.5 - distance));
  }

  static paintBgra(buffer: Uint8Array, tile: EditRect, doc: EditDocument,
    premultiplied: boolean): void {
    if (!Number.isInteger(tile.width) || !Number.isInteger(tile.height) || tile.width <= 0 ||
      tile.height <= 0 || buffer.length !== tile.width * tile.height * 4) {
      throw new Error('标注像素缓冲区无效');
    }
    for (const stroke of doc.strokes) {
      const bounds: EditRect | undefined = EditRasterizer.bounds(stroke, doc);
      const color: number[] | undefined = EditRasterizer.color(stroke.color);
      if (bounds === undefined || color === undefined || !EditRasterizer.intersects(bounds, tile)) { continue; }
      const points: EditPoint[] = stroke.points.map((point: EditPoint): EditPoint =>
        ImageEditGeometry.toOutput(point, doc));
      const x0: number = Math.max(tile.x, bounds.x);
      const y0: number = Math.max(tile.y, bounds.y);
      const x1: number = Math.min(tile.x + tile.width, bounds.x + bounds.width);
      const y1: number = Math.min(tile.y + tile.height, bounds.y + bounds.height);
      for (let y: number = y0; y < y1; y++) {
        for (let x: number = x0; x < x1; x++) {
          const coverage: number = EditRasterizer.coverage(stroke, points, x, y);
          if (coverage <= 0) { continue; }
          const offset: number = ((y - tile.y) * tile.width + x - tile.x) * 4;
          const sourceAlpha: number = coverage * color[3] / 255;
          const targetAlpha: number = buffer[offset + 3] / 255;
          const resultAlpha: number = sourceAlpha + targetAlpha * (1 - sourceAlpha);
          for (let channel: number = 0; channel < 3; channel++) {
            const base: number = premultiplied ? buffer[offset + channel] :
              buffer[offset + channel] * targetAlpha;
            const blended: number = color[channel] * sourceAlpha + base * (1 - sourceAlpha);
            buffer[offset + channel] = Math.round(premultiplied || resultAlpha === 0 ?
              blended : blended / resultAlpha);
          }
          buffer[offset + 3] = Math.round(resultAlpha * 255);
        }
      }
    }
  }
}
