import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { DownloadItem } from '../model/Models';
import { AssetStamp } from '../model/LibraryAsset';
import { EditPoint, EditRect, PreviewSize } from '../model/ImageEditDocument';

/** Decodes the same first/still frame for OCR, visual features and editing. */
export class LibraryImageReader {
  private static orientation(value: string): number {
    const names: string[] = ['Top-left', 'Top-right', 'Bottom-right', 'Bottom-left',
      'Left-top', 'Right-top', 'Right-bottom', 'Left-bottom'];
    const named: number = names.indexOf(value);
    if (named >= 0) { return named + 1; }
    const parsed: number = Number(value);
    return Number.isInteger(parsed) && parsed >= 1 && parsed <= 8 ? parsed : 1;
  }

  static async stamp(item: DownloadItem): Promise<AssetStamp> {
    const path: string = item.kind === 'livephoto' ? item.stillPath : item.path;
    if (item.id.length === 0 || path.length === 0 || !fs.accessSync(path)) {
      throw new Error('图片文件不可读取');
    }
    const stat: fs.Stat = fs.statSync(path);
    if (stat.size <= 0) { throw new Error('图片文件为空'); }
    const stamp: AssetStamp = new AssetStamp();
    stamp.id = item.id; stamp.path = path; stamp.sourceKind = item.kind;
    stamp.bytes = stat.size; stamp.modified = stat.mtime; stamp.changed = stat.ctime;
    const source: image.ImageSource = image.createImageSource(path);
    try {
      await source.getImageInfo();
      try { stamp.orientation = LibraryImageReader.orientation(
        await source.getImageProperty(image.PropertyKey.ORIENTATION)); }
      catch (error) { stamp.orientation = 1; }
    } finally { await source.release(); }
    return stamp;
  }

  static async info(stamp: AssetStamp): Promise<PreviewSize> {
    const source: image.ImageSource = image.createImageSource(stamp.path);
    try {
      const info: image.ImageInfo = await source.getImageInfo();
      const size: PreviewSize = new PreviewSize();
      size.width = stamp.orientation >= 5 ? info.size.height : info.size.width;
      size.height = stamp.orientation >= 5 ? info.size.width : info.size.height;
      return size;
    } finally { await source.release(); }
  }

  /** Region is in displayed, orientation-corrected coordinates; size is output size. */
  static async decode(stamp: AssetStamp, region: EditRect, size: PreviewSize,
    editable: boolean): Promise<image.PixelMap> {
    const source: image.ImageSource = image.createImageSource(stamp.path);
    let frame: image.PixelMap | undefined = undefined;
    try {
      const info: image.ImageInfo = await source.getImageInfo();
      const rawWidth: number = info.size.width;
      const rawHeight: number = info.size.height;
      const swapped: boolean = stamp.orientation >= 5;
      const displayWidth: number = swapped ? rawHeight : rawWidth;
      const displayHeight: number = swapped ? rawWidth : rawHeight;
      if (region.width <= 0 || region.height <= 0 || region.x < 0 || region.y < 0 ||
        region.x + region.width > displayWidth || region.y + region.height > displayHeight ||
        size.width <= 0 || size.height <= 0 || size.width * size.height > 16000000) {
        throw new Error('图片裁剪区域或输出尺寸无效');
      }
      const first: EditPoint = LibraryImageReader.toEncoded(region.x, region.y,
        rawWidth, rawHeight, stamp.orientation);
      const last: EditPoint = LibraryImageReader.toEncoded(region.x + region.width,
        region.y + region.height, rawWidth, rawHeight, stamp.orientation);
      const nativeRegion: image.Region = { x: Math.min(first.x, last.x),
        y: Math.min(first.y, last.y), size: { width: Math.abs(first.x - last.x),
          height: Math.abs(first.y - last.y) } };
      frame = await source.createPixelMap({ index: 0, editable: editable || stamp.orientation !== 1,
        desiredRegion: nativeRegion,
        desiredSize: { width: swapped ? size.height : size.width,
          height: swapped ? size.width : size.height },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST });
      await LibraryImageReader.orient(frame, stamp.orientation);
      return frame;
    } catch (error) {
      if (frame !== undefined) { try { await frame.release(); } catch (releaseError) { } }
      throw new Error(String(error));
    } finally { await source.release(); }
  }

  private static toEncoded(x: number, y: number, width: number, height: number,
    orientation: number): EditPoint {
    const point: EditPoint = new EditPoint();
    switch (orientation) {
      case 2: point.x = width - x; point.y = y; break;
      case 3: point.x = width - x; point.y = height - y; break;
      case 4: point.x = x; point.y = height - y; break;
      case 5: point.x = y; point.y = x; break;
      case 6: point.x = y; point.y = height - x; break;
      case 7: point.x = width - y; point.y = height - x; break;
      case 8: point.x = width - y; point.y = x; break;
      default: point.x = x; point.y = y;
    }
    return point;
  }

  private static async orient(frame: image.PixelMap, orientation: number): Promise<void> {
    switch (orientation) {
      case 2: await frame.flip(true, false); break;
      case 3: await frame.rotate(180); break;
      case 4: await frame.flip(false, true); break;
      case 5: await frame.flip(true, false); await frame.rotate(270); break;
      case 6: await frame.rotate(90); break;
      case 7: await frame.flip(true, false); await frame.rotate(90); break;
      case 8: await frame.rotate(270); break;
    }
  }

  /** Returns straight-alpha RGBA regardless of the PixelMap's byte order or alpha storage. */
  static async rgba(frame: image.PixelMap): Promise<Uint8Array> {
    const info: image.ImageInfo = await frame.getImageInfo();
    if (info.pixelFormat !== image.PixelMapFormat.RGBA_8888 &&
      info.pixelFormat !== image.PixelMapFormat.BGRA_8888) {
      throw new Error('图片像素格式不受支持');
    }
    const count: number = info.size.width * info.size.height * 4;
    if (count <= 0 || count > 64000000) { throw new Error('图片像素数量超限'); }
    const stride: number = frame.getBytesNumberPerRow();
    if (stride < info.size.width * 4) { throw new Error('图片像素行宽无效'); }
    const buffer: ArrayBuffer = new ArrayBuffer(frame.getPixelBytesNumber());
    await frame.readPixelsToBuffer(buffer);
    const raw: Uint8Array = new Uint8Array(buffer);
    if (raw.length < stride * info.size.height) { throw new Error('图片像素数据不完整'); }
    const output: Uint8Array = new Uint8Array(count);
    const bgra: boolean = info.pixelFormat === image.PixelMapFormat.BGRA_8888;
    for (let y: number = 0; y < info.size.height; y++) {
      for (let x: number = 0; x < info.size.width; x++) {
        const input: number = y * stride + x * 4;
        const outputIndex: number = (y * info.size.width + x) * 4;
        const alpha: number = raw[input + 3];
        const red: number = raw[input + (bgra ? 2 : 0)];
        const green: number = raw[input + 1];
        const blue: number = raw[input + (bgra ? 0 : 2)];
        output[outputIndex] = LibraryImageReader.straight(red, alpha, info.alphaType);
        output[outputIndex + 1] = LibraryImageReader.straight(green, alpha, info.alphaType);
        output[outputIndex + 2] = LibraryImageReader.straight(blue, alpha, info.alphaType);
        output[outputIndex + 3] = alpha;
      }
    }
    return output;
  }

  private static straight(channel: number, alpha: number, type: image.AlphaType): number {
    if (alpha === 0) { return 0; }
    if (type !== image.AlphaType.PREMUL) { return channel; }
    return Math.min(255, Math.round(channel * 255 / alpha));
  }
}
