import { PreviewGeometry, PreviewPosition, PreviewSize } from '../util/PreviewGeometry';

export class PreviewReadingState {
  key: string = '';
  width: number = 0;
  height: number = 0;
  mode: string = 'screen';
  scale: number = 1;
  centerX: number = 0.5;
  centerY: number = 0.5;

  static capture(key: string, image: PreviewSize, viewport: PreviewSize, zoom: number,
    position: PreviewPosition, mode: string): PreviewReadingState {
    const state: PreviewReadingState = new PreviewReadingState();
    const fitted: PreviewSize = PreviewGeometry.fit(image, viewport);
    const bounded: PreviewPosition = PreviewGeometry.clamp(image, viewport, zoom, position);
    state.key = key;
    state.width = image.width;
    state.height = image.height;
    state.mode = mode;
    state.scale = fitted.width * zoom / Math.max(1, image.width);
    state.centerX = 0.5 - bounded.x / Math.max(1, fitted.width * zoom);
    state.centerY = 0.5 - bounded.y / Math.max(1, fitted.height * zoom);
    return state;
  }

  static valid(value: PreviewReadingState): boolean {
    return value !== null && typeof value === 'object' && typeof value.key === 'string'
      && value.key.length > 0 && value.key.length <= 8192
      && Number.isFinite(value.width) && value.width > 0 && Number.isFinite(value.height) && value.height > 0
      && Number.isFinite(value.scale) && value.scale > 0
      && Number.isFinite(value.centerX) && value.centerX >= 0 && value.centerX <= 1
      && Number.isFinite(value.centerY) && value.centerY >= 0 && value.centerY <= 1
      && ['screen', 'width', 'native', 'free'].includes(value.mode);
  }

  zoom(image: PreviewSize, viewport: PreviewSize, density: number): number {
    if (this.mode === 'screen') { return 1; }
    if (this.mode === 'width') { return PreviewGeometry.widthScale(image, viewport); }
    if (this.mode === 'native') { return PreviewGeometry.nativeScale(image, viewport, density); }
    return this.scale * image.width / Math.max(0.001, PreviewGeometry.fit(image, viewport).width);
  }

  position(image: PreviewSize, viewport: PreviewSize, zoom: number): PreviewPosition {
    const fitted: PreviewSize = PreviewGeometry.fit(image, viewport);
    return PreviewGeometry.clamp(image, viewport, zoom,
      { x: (0.5 - this.centerX) * fitted.width * zoom, y: (0.5 - this.centerY) * fitted.height * zoom });
  }
}

/** Bounded value-only memory: no decoded frames, credentials or component references. */
export class PreviewReadingCache {
  private entries: PreviewReadingState[] = [];

  put(state: PreviewReadingState): void {
    if (!PreviewReadingState.valid(state)) { return; }
    this.entries = this.entries.filter((entry: PreviewReadingState): boolean => entry.key !== state.key);
    this.entries.push(state);
    if (this.entries.length > 100) { this.entries.shift(); }
  }

  get(key: string, width: number, height: number): PreviewReadingState | undefined {
    const at: number = this.entries.findIndex((entry: PreviewReadingState): boolean => entry.key === key);
    if (at < 0) { return undefined; }
    const entry: PreviewReadingState = this.entries.splice(at, 1)[0];
    if (entry.width !== width || entry.height !== height) { return undefined; }
    this.entries.push(entry);
    return entry;
  }

  serialize(): string {
    return JSON.stringify(this.entries.filter((entry: PreviewReadingState): boolean => entry.key.startsWith('local:')));
  }

  restore(text: string): void {
    try {
      const values: PreviewReadingState[] = JSON.parse(text);
      if (!Array.isArray(values)) { return; }
      for (const value of values.slice(-100)) {
        if (!PreviewReadingState.valid(value) || !value.key.startsWith('local:')) { continue; }
        const state: PreviewReadingState = new PreviewReadingState();
        state.key = value.key; state.width = value.width; state.height = value.height;
        state.scale = value.scale; state.mode = value.mode; state.centerX = value.centerX; state.centerY = value.centerY;
        this.put(state);
      }
    } catch (error) {}
  }
}
