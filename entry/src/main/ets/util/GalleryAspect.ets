/** Gallery cover height divided by column width. Unknown images start square. */
export class GalleryAspect {
  static heightRatio(width: number, height: number): number {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { return 1; }
    return Math.max(0.7, Math.min(1.8, height / width));
  }
}
