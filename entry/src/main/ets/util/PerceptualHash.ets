import { SimilarGroup, VisualFeature } from '../model/LibraryAsset';

/** Small, deterministic feature for candidate grouping; it never deletes an image. */
export class PerceptualHash {
  static feature(rgba: Uint8Array, width: number, height: number): VisualFeature {
    if (width !== 32 || height !== 32 || rgba.length !== 4096) {
      throw new Error('相似图特征需要32×32 RGBA像素');
    }
    const gray: number[] = [];
    let red: number = 0;
    let green: number = 0;
    let blue: number = 0;
    let alpha: number = 0;
    for (let pixel: number = 0; pixel < 1024; pixel++) {
      const offset: number = pixel * 4;
      const opacity: number = rgba[offset + 3] / 255;
      const r: number = rgba[offset] * opacity + 255 * (1 - opacity);
      const g: number = rgba[offset + 1] * opacity + 255 * (1 - opacity);
      const b: number = rgba[offset + 2] * opacity + 255 * (1 - opacity);
      red += r; green += g; blue += b; alpha += rgba[offset + 3];
      gray.push(0.299 * r + 0.587 * g + 0.114 * b);
    }
    const cosine: number[][] = [];
    for (let frequency: number = 0; frequency < 8; frequency++) {
      const row: number[] = [];
      for (let position: number = 0; position < 32; position++) {
        row.push(Math.cos((2 * position + 1) * frequency * Math.PI / 64));
      }
      cosine.push(row);
    }
    const horizontal: number[][] = [];
    for (let y: number = 0; y < 32; y++) {
      const row: number[] = [];
      for (let u: number = 0; u < 8; u++) {
        let sum: number = 0;
        for (let x: number = 0; x < 32; x++) { sum += gray[y * 32 + x] * cosine[u][x]; }
        row.push(sum);
      }
      horizontal.push(row);
    }
    const coefficients: number[] = [];
    for (let v: number = 0; v < 8; v++) {
      for (let u: number = 0; u < 8; u++) {
        let sum: number = 0;
        for (let y: number = 0; y < 32; y++) { sum += horizontal[y][u] * cosine[v][y]; }
        coefficients.push(sum);
      }
    }
    let mean: number = 0;
    for (let i: number = 1; i < 64; i++) { mean += coefficients[i]; }
    mean /= 63;
    let lowBits: string = '0';
    for (let i: number = 1; i < 64; i++) { lowBits += coefficients[i] > mean ? '1' : '0'; }

    const samples: number[] = [];
    for (let y: number = 0; y < 8; y++) {
      for (let x: number = 0; x < 9; x++) {
        samples.push(PerceptualHash.sample(gray, (x + 0.5) * 32 / 9 - 0.5,
          (y + 0.5) * 32 / 8 - 0.5));
      }
    }
    let edgeBits: string = '';
    for (let y: number = 0; y < 8; y++) {
      for (let x: number = 0; x < 8; x++) {
        edgeBits += samples[y * 9 + x] > samples[y * 9 + x + 1] ? '1' : '0';
      }
    }
    const feature: VisualFeature = new VisualFeature();
    feature.lowBits = lowBits; feature.edgeBits = edgeBits;
    feature.red = Math.round(red / 1024); feature.green = Math.round(green / 1024);
    feature.blue = Math.round(blue / 1024); feature.alpha = Math.round(alpha / 1024);
    feature.width = width; feature.height = height;
    return feature;
  }

  private static sample(gray: number[], x: number, y: number): number {
    const left: number = Math.max(0, Math.min(31, Math.floor(x)));
    const top: number = Math.max(0, Math.min(31, Math.floor(y)));
    const right: number = Math.min(31, left + 1);
    const bottom: number = Math.min(31, top + 1);
    const fx: number = Math.max(0, Math.min(1, x - left));
    const fy: number = Math.max(0, Math.min(1, y - top));
    return gray[top * 32 + left] * (1 - fx) * (1 - fy) +
      gray[top * 32 + right] * fx * (1 - fy) +
      gray[bottom * 32 + left] * (1 - fx) * fy +
      gray[bottom * 32 + right] * fx * fy;
  }

  static distance(a: string, b: string): number {
    if (!/^[01]{64}$/.test(a) || !/^[01]{64}$/.test(b)) { return 65; }
    let count: number = 0;
    for (let i: number = 0; i < 64; i++) { if (a.charAt(i) !== b.charAt(i)) { count++; } }
    return count;
  }

  private static valid(value: VisualFeature): boolean {
    return value.version === 1 && /^[01]{64}$/.test(value.lowBits) &&
      /^[01]{64}$/.test(value.edgeBits) && Number.isFinite(value.width) && value.width > 0 &&
      Number.isFinite(value.height) && value.height > 0 &&
      [value.red, value.green, value.blue, value.alpha].every((channel: number): boolean =>
        Number.isFinite(channel) && channel >= 0 && channel <= 255);
  }

  static matches(a: VisualFeature, b: VisualFeature): boolean {
    if (!PerceptualHash.valid(a) || !PerceptualHash.valid(b)) { return false; }
    const ratioA: number = a.width / a.height;
    const ratioB: number = b.width / b.height;
    const low: number = PerceptualHash.distance(a.lowBits, b.lowBits);
    const edge: number = PerceptualHash.distance(a.edgeBits, b.edgeBits);
    return Math.abs(ratioA - ratioB) / Math.max(ratioA, ratioB) <= 0.05 &&
      low <= 8 && edge <= 10 && low + edge <= 11 &&
      Math.abs(a.red - b.red) <= 20 && Math.abs(a.green - b.green) <= 20 &&
      Math.abs(a.blue - b.blue) <= 20 && Math.abs(a.alpha - b.alpha) <= 16;
  }

  static groups(ids: string[], features: Map<string, VisualFeature>): SimilarGroup[] {
    const candidates: SimilarGroup[] = [];
    const seen: Set<string> = new Set();
    for (const id of ids) {
      if (seen.has(id)) { continue; }
      seen.add(id);
      const current: VisualFeature | undefined = features.get(id);
      if (current === undefined || !PerceptualHash.valid(current)) { continue; }
      let group: SimilarGroup | undefined = undefined;
      for (const candidate of candidates) {
        const representative: VisualFeature | undefined = features.get(candidate.representativeId);
        if (representative !== undefined && PerceptualHash.matches(representative, current)) {
          group = candidate; break;
        }
      }
      if (group === undefined) {
        group = new SimilarGroup(); group.representativeId = id; group.ids = [id];
        candidates.push(group);
      } else { group.ids.push(id); }
    }
    return candidates.filter((group: SimilarGroup): boolean => group.ids.length > 1);
  }
}
