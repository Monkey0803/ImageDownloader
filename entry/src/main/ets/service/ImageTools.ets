import { image } from '@kit.ImageKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { detectBarcode, scanBarcode } from '@kit.ScanKit';
import { Clipboard } from './Clipboard';
import { ActionOutcome, exportFile, saveImageToGallery } from './FileActions';
import { PreviewGeometry, PreviewSize } from '../util/PreviewGeometry';
import { RecognizedLine } from '../model/LibraryAsset';

export type FrameSaveDestination = 'album' | 'folder';

export class ImageMetadata {
  width: number = 0;
  height: number = 0;
  bytes: number = 0;
  format: string = '';
  isHdr: boolean = false;
}

/** Explicit, user-triggered operations; no recognition or navigation on image load. */
export class ImageTools {
  private static sequence: number = 0;
  private static recognition: Promise<void> = Promise.resolve();

  static async metadata(path: string): Promise<ImageMetadata> {
    const source: image.ImageSource = image.createImageSource(path);
    try {
      const info: image.ImageInfo = await source.getImageInfo();
      const result: ImageMetadata = new ImageMetadata();
      result.width = info.size.width;
      result.height = info.size.height;
      result.format = info.mimeType;
      result.bytes = fs.statSync(path).size;
      result.isHdr = info.isHdr === true;
      return result;
    } finally { await source.release(); }
  }

  static async copy(value: string): Promise<void> { await Clipboard.writeText(value); }

  static link(value: string): string {
    const text: string = value.trim();
    return /^https?:\/\/[^\s/?#]+(?:[/?#][^\s]*)?$/i.test(text) ? text : '';
  }

  static async open(context: common.UIAbilityContext, value: string): Promise<void> {
    const url: string = ImageTools.link(value);
    if (url.length === 0) { throw new Error('仅支持打开 HTTP 或 HTTPS 链接'); }
    await context.openLink(url);
  }

  /** Serialize the native OCR lifecycle so one panel cannot release another panel's engine. */
  static withTextEngine<T>(operation: () => Promise<T>): Promise<T> {
    const result: Promise<T> = ImageTools.recognition.then(async (): Promise<T> => {
      if (!canIUse('SystemCapability.AI.OCR.TextRecognition')) { throw new Error('此设备不支持文字识别'); }
      try {
        const initialized: boolean = await textRecognition.init();
        if (!initialized) { throw new Error('文字识别服务暂不可用'); }
        return await operation();
      } finally { try { await textRecognition.release(); } catch (error) { } }
    });
    ImageTools.recognition = result.then((): void => {}, (): void => {});
    return result;
  }

  /** Must run inside withTextEngine; this method never queues itself. */
  static async textLines(frame: image.PixelMap): Promise<RecognizedLine[]> {
    const result: textRecognition.TextRecognitionResult = await textRecognition.recognizeText({ pixelMap: frame });
    const lines: RecognizedLine[] = [];
    for (const block of result.blocks) {
      for (const line of block.lines) {
        if (line.value.length === 0 || line.cornerPoints.length === 0) { continue; }
        let left: number = line.cornerPoints[0].x;
        let top: number = line.cornerPoints[0].y;
        let right: number = left;
        let bottom: number = top;
        for (const point of line.cornerPoints) {
          left = Math.min(left, point.x); top = Math.min(top, point.y);
          right = Math.max(right, point.x); bottom = Math.max(bottom, point.y);
        }
        const value: RecognizedLine = new RecognizedLine();
        value.text = line.value; value.x = left; value.y = top;
        value.width = right - left; value.height = bottom - top;
        lines.push(value);
      }
    }
    return lines;
  }

  static text(path: string): Promise<string> {
    return ImageTools.withTextEngine((): Promise<string> => ImageTools.recognize(path));
  }

  private static async recognize(path: string): Promise<string> {
    const source: image.ImageSource = image.createImageSource(path);
    let frame: image.PixelMap | undefined = undefined;
    try {
      const info: image.ImageInfo = await source.getImageInfo();
      const size: PreviewSize = PreviewGeometry.decodeSize({ width: info.size.width, height: info.size.height }, 4096, 8000000);
      frame = await source.createPixelMap({ desiredSize: { width: size.width, height: size.height },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      const result: textRecognition.TextRecognitionResult = await textRecognition.recognizeText({ pixelMap: frame });
      return result.value;
    } finally {
      if (frame !== undefined) { try { await frame.release(); } catch (error) {} }
      try { await source.release(); } catch (error) {}
    }
  }

  private static async png(path: string, cacheDir: string, index: number, edge: number = 8192, pixels: number = 12000000): Promise<string> {
    const source: image.ImageSource = image.createImageSource(path);
    let packer: image.ImagePacker | undefined = undefined;
    let frame: image.PixelMap | undefined = undefined;
    let output: string = '';
    try {
      packer = image.createImagePacker();
      const info: image.ImageInfo = await source.getImageInfo();
      const size: PreviewSize = PreviewGeometry.decodeSize({ width: info.size.width, height: info.size.height }, edge, pixels);
      frame = await source.createPixelMap({ index: index, desiredSize: { width: size.width, height: size.height } });
      ImageTools.sequence++;
      output = cacheDir + '/image-tool-' + Date.now().toString() + '-' + ImageTools.sequence.toString() + '.png';
      const file: fs.File = fs.openSync(output, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        await packer.packToFile(frame, file.fd, { format: 'image/png', quality: 100 });
        if (fs.statSync(output).size <= 0) { throw new Error('图片写入不完整'); }
      } finally { fs.closeSync(file); }
      return output;
    } catch (error) {
      ImageTools.remove(output);
      throw new Error(String(error));
    } finally {
      if (frame !== undefined) { try { await frame.release(); } catch (error) {} }
      if (packer !== undefined) { try { await packer.release(); } catch (error) {} }
      try { await source.release(); } catch (error) {}
    }
  }

  private static remove(path: string): void {
    if (path.length > 0) { try { fs.unlinkSync(path); } catch (error) {} }
  }

  static async codes(path: string, cacheDir: string): Promise<string[]> {
    if (!canIUse('SystemCapability.Multimedia.Scan.ScanBarcode')) { throw new Error('此设备不支持二维码识别'); }
    const png: string = await ImageTools.png(path, cacheDir, 0, 4096, 8000000);
    try {
      const results: scanBarcode.ScanResult[] = await detectBarcode.decode({ uri: fileUri.getUriFromPath(png) },
        { enableMultiMode: true });
      const values: string[] = [];
      for (const result of results) {
        if (result.originalValue.length > 0 && !values.includes(result.originalValue)) { values.push(result.originalValue); }
      }
      return values;
    } finally { ImageTools.remove(png); }
  }

  static async saveFrame(context: common.UIAbilityContext, path: string, name: string, index: number,
    destination: FrameSaveDestination = 'folder'): Promise<ActionOutcome> {
    const png: string = await ImageTools.png(path, context.cacheDir, index);
    try {
      const base: string = name.replace(/\.[^.]+$/, '').replace(/[\\/:*?"<>|]/g, '_');
      const filename: string = base + '-第' + (index + 1).toString() + '帧.png';
      const outcome: ActionOutcome = destination === 'album'
        ? await saveImageToGallery(context, png, filename) : await exportFile(context, png, filename);
      if (outcome.cancelled === true) { return { ok: false, cancelled: true, message: '' }; }
      if (!outcome.ok) { return outcome; }
      return { ok: true, message: destination === 'album' ? '已保存当前帧到相册' : '已保存当前帧到文件夹' };
    } finally { ImageTools.remove(png); }
  }
}
