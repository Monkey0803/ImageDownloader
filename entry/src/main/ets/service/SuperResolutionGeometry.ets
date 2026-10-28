import { PreviewSize } from '../model/ImageEditDocument';

/** Sizing and result checks for image super resolution; pure so they can be tested. */
export class SuperResolutionGeometry {
  /** System input limit is 2048×2048; 1600 keeps the 16× output pixel cost in check. */
  static readonly MAX_INPUT_EDGE: number = 1600;

  static decodeSize(width: number, height: number): PreviewSize {
    const size: PreviewSize = new PreviewSize();
    if (width <= 0 || height <= 0) {
      size.width = 0; size.height = 0;
      return size;
    }
    const edge: number = Math.max(width, height);
    if (edge <= SuperResolutionGeometry.MAX_INPUT_EDGE) {
      size.width = width; size.height = height;
      return size;
    }
    const scale: number = SuperResolutionGeometry.MAX_INPUT_EDGE / edge;
    size.width = Math.max(1, Math.floor(width * scale));
    size.height = Math.max(1, Math.floor(height * scale));
    return size;
  }

  /** Output multiples vary by device/service; require growth plus a stable aspect ratio. */
  static accepts(inputWidth: number, inputHeight: number,
    outputWidth: number, outputHeight: number): boolean {
    if (inputWidth <= 0 || inputHeight <= 0 ||
      outputWidth <= inputWidth || outputHeight <= inputHeight) {
      return false;
    }
    const inputRatio: number = inputWidth / inputHeight;
    const outputRatio: number = outputWidth / outputHeight;
    return Math.abs(inputRatio - outputRatio) / inputRatio <= 0.01;
  }
}
