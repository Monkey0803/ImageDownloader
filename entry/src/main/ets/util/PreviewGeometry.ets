export interface PreviewSize {
  width: number;
  height: number;
}

export interface PreviewPosition {
  x: number;
  y: number;
}

export interface PreviewRegion {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** All gesture coordinates and layout dimensions are vp; decoding dimensions are pixels. */
export class PreviewGeometry {
  static fit(image: PreviewSize, viewport: PreviewSize): PreviewSize {
    if (image.width <= 0 || image.height <= 0 || viewport.width <= 0 || viewport.height <= 0) {
      return { width: 0, height: 0 };
    }
    const ratio: number = Math.min(viewport.width / image.width, viewport.height / image.height);
    return { width: image.width * ratio, height: image.height * ratio };
  }

  static widthScale(image: PreviewSize, viewport: PreviewSize): number {
    const fitted: PreviewSize = PreviewGeometry.fit(image, viewport);
    return fitted.width > 0 ? Math.max(1, viewport.width / fitted.width) : 1;
  }

  static clamp(image: PreviewSize, viewport: PreviewSize, zoom: number,
    position: PreviewPosition): PreviewPosition {
    const fitted: PreviewSize = PreviewGeometry.fit(image, viewport);
    const x: number = Math.max(0, (fitted.width * zoom - viewport.width) / 2);
    const y: number = Math.max(0, (fitted.height * zoom - viewport.height) / 2);
    return { x: x === 0 ? 0 : Math.max(-x, Math.min(x, position.x)),
      y: y === 0 ? 0 : Math.max(-y, Math.min(y, position.y)) };
  }

  /** Keep the image point beneath oldAnchor underneath nextAnchor during a pinch. */
  static anchor(position: PreviewPosition, oldZoom: number, nextZoom: number,
    oldAnchor: PreviewPosition, nextAnchor: PreviewPosition): PreviewPosition {
    const ratio: number = nextZoom / Math.max(0.000001, oldZoom);
    return { x: nextAnchor.x - (oldAnchor.x - position.x) * ratio,
      y: nextAnchor.y - (oldAnchor.y - position.y) * ratio };
  }

  static top(image: PreviewSize, viewport: PreviewSize, zoom: number): PreviewPosition {
    const fitted: PreviewSize = PreviewGeometry.fit(image, viewport);
    return { x: 0, y: Math.max(0, (fitted.height * zoom - viewport.height) / 2) };
  }

  static nativeScale(image: PreviewSize, viewport: PreviewSize, density: number): number {
    const fitted: PreviewSize = PreviewGeometry.fit(image, viewport);
    return fitted.width > 0 && density > 0 ? image.width / (fitted.width * density) : 1;
  }

  /** Source-pixel rectangle covering the viewport with a small pre-render margin. */
  static visibleRegion(image: PreviewSize, viewport: PreviewSize, zoom: number,
    position: PreviewPosition): PreviewRegion {
    const fitted: PreviewSize = PreviewGeometry.fit(image, viewport);
    const unit: number = image.width > 0 ? fitted.width * zoom / image.width : 0;
    if (unit <= 0) { return { x: 0, y: 0, width: 0, height: 0 }; }
    const left: number = viewport.width / 2 + position.x - fitted.width * zoom / 2;
    const top: number = viewport.height / 2 + position.y - fitted.height * zoom / 2;
    const margin: number = 48;
    const x: number = Math.max(0, Math.min(image.width, Math.floor((-left - margin) / unit)));
    const y: number = Math.max(0, Math.min(image.height, Math.floor((-top - margin) / unit)));
    const right: number = Math.max(x, Math.min(image.width, Math.ceil((viewport.width - left + margin) / unit)));
    const bottom: number = Math.max(y, Math.min(image.height, Math.ceil((viewport.height - top + margin) / unit)));
    return { x: x, y: y, width: right - x, height: bottom - y };
  }

  /** Bound decoded pixel allocation, including very tall images and zoomed originals. */
  static decodeSize(image: PreviewSize, edge: number, pixels: number): PreviewSize {
    const ratio: number = Math.min(1, edge / Math.max(1, image.width, image.height),
      Math.sqrt(pixels / Math.max(1, image.width * image.height)));
    return { width: Math.max(1, Math.floor(image.width * ratio)),
      height: Math.max(1, Math.floor(image.height * ratio)) };
  }
}
