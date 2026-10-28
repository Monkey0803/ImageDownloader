import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AnalysisToken, AssetStamp } from '../model/LibraryAsset';
import { EditDocument, EditRect, EditResult, EditStroke, PreviewSize } from '../model/ImageEditDocument';
import { ImageEditGeometry } from '../util/ImageEditGeometry';
import { EditRasterizer } from '../util/EditRasterizer';
import { LibraryImageReader } from './LibraryImageReader';

/** Exports an original-resolution copy into a new pending file; registration is a separate transaction. */
export class EditExport {
  /** 无损档：与旧版行为一致，始终 PNG。 */
  static readonly LOSSLESS: string = 'lossless';
  /** 体积优先档：JPEG 质量 80。 */
  static readonly COMPACT: string = 'compact';
  static readonly JPEG_QUALITY_HIGH: number = 90;
  static readonly JPEG_QUALITY_COMPACT: number = 80;

  private static check(token: AnalysisToken): void {
    if (token.cancelled) { throw new Error('图片编辑已取消'); }
  }

  /**
   * 按档位、源图 alpha 类型与实际透明度决定容器：无损档、带 alpha 一律 PNG。
   *
   * JPEG 不支持 alpha，强行编码会把透明区域变成黑色；解码后的 PixelMap 对 JPEG 也可能
   * 报 PREMUL（见 ImageSurface 的说明），所以透明判据取源文件本身，而不是最终帧的 alphaType。
   */
  static extensionOf(setting: string, alphaType: number, transparent: boolean): string {
    if (setting === EditExport.LOSSLESS || transparent ||
      alphaType === image.AlphaType.PREMUL || alphaType === image.AlphaType.UNPREMUL) {
      return 'png';
    }
    return 'jpg';
  }

  static qualityOf(setting: string): number {
    return setting === EditExport.COMPACT
      ? EditExport.JPEG_QUALITY_COMPACT : EditExport.JPEG_QUALITY_HIGH;
  }

  /** 缩到长边 512 扫 alpha；只用于 alphaType 不明、又不是 JPEG/HEIF 的源。 */
  private static async hasTransparency(source: image.ImageSource, info: image.ImageInfo): Promise<boolean> {
    let frame: image.PixelMap | undefined = undefined;
    try {
      const edge: number = Math.max(info.size.width, info.size.height);
      const scale: number = edge > 512 ? 512 / edge : 1;
      const width: number = Math.max(1, Math.floor(info.size.width * scale));
      const height: number = Math.max(1, Math.floor(info.size.height * scale));
      frame = await source.createPixelMap({ index: 0, desiredSize: { width: width, height: height },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST });
      const buffer: ArrayBuffer = new ArrayBuffer(frame.getPixelBytesNumber());
      await frame.readPixelsToBuffer(buffer);
      const bytes: Uint8Array = new Uint8Array(buffer);
      const stride: number = frame.getBytesNumberPerRow();
      for (let y: number = 0; y < height; y++) {
        for (let x: number = 0; x < width; x++) {
          if (bytes[y * stride + x * 4 + 3] !== 255) { return true; }
        }
      }
      return false;
    } catch (error) {
      // 探测失败时保守按“可能有透明”处理，宁可存大一点也不能把透明区域压黑。
      return true;
    } finally {
      if (frame !== undefined) { try { await frame.release(); } catch (releaseError) { } }
    }
  }

  /**
   * 保存前先读一次源文件透明度，供 EditJournal 决定 pending/final 路径的后缀。
   *
   * JPEG / HEIF 格式本身没有 alpha，直接按 JPEG 处理；PNG / WebP 等格式若 alphaType
   * 已明确带 alpha，不再解码探测；只有 alphaType 未知时才做一次有界像素扫描。
   */
  static async extensionFor(stamp: AssetStamp, setting: string): Promise<string> {
    if (setting === EditExport.LOSSLESS) {
      return 'png';
    }
    const source: image.ImageSource = image.createImageSource(stamp.path);
    try {
      const info: image.ImageInfo = await source.getImageInfo();
      const mime: string = (info.mimeType ?? '').toLowerCase();
      if (mime === 'image/jpeg' || mime === 'image/jpg' ||
        mime === 'image/heic' || mime === 'image/heif') {
        return 'jpg';
      }
      if (info.alphaType === image.AlphaType.PREMUL ||
        info.alphaType === image.AlphaType.UNPREMUL) {
        return 'png';
      }
      const transparent: boolean = await EditExport.hasTransparency(source, info);
      return EditExport.extensionOf(setting, info.alphaType, transparent);
    } finally { await source.release(); }
  }

  private static tiles(doc: EditDocument): EditRect[] {
    const size: PreviewSize = ImageEditGeometry.outputSize(doc);
    const keys: Set<string> = new Set();
    const result: EditRect[] = [];
    for (const stroke of doc.strokes) {
      const bounds: EditRect | undefined = EditRasterizer.bounds(stroke, doc);
      if (bounds === undefined) { continue; }
      const left: number = Math.max(0, bounds.x);
      const top: number = Math.max(0, bounds.y);
      const right: number = Math.min(size.width, bounds.x + bounds.width);
      const bottom: number = Math.min(size.height, bounds.y + bounds.height);
      if (right <= left || bottom <= top) { continue; }
      for (let row: number = Math.floor(top / 256); row <= Math.floor((bottom - 1) / 256); row++) {
        for (let col: number = Math.floor(left / 256); col <= Math.floor((right - 1) / 256); col++) {
          const key: string = col.toString() + ':' + row.toString();
          if (keys.has(key)) { continue; }
          keys.add(key);
          const tile: EditRect = new EditRect();
          tile.x = col * 256; tile.y = row * 256;
          tile.width = Math.min(256, size.width - tile.x);
          tile.height = Math.min(256, size.height - tile.y);
          result.push(tile);
        }
      }
    }
    return result;
  }

  static async render(stamp: AssetStamp, doc: EditDocument, pendingPath: string,
    token: AnalysisToken, setting: string = EditExport.LOSSLESS): Promise<EditResult> {
    EditExport.check(token);
    if (pendingPath.length === 0 || fs.accessSync(pendingPath)) {
      throw new Error('编辑输出文件已存在或路径无效');
    }
    const extension: string = await EditExport.extensionFor(stamp, setting);
    if (!pendingPath.toLowerCase().endsWith('.' + extension)) {
      throw new Error('编辑输出文件扩展名与格式不符');
    }
    const sourceSize: PreviewSize = await LibraryImageReader.info(stamp);
    if (doc.sourceWidth !== sourceSize.width || doc.sourceHeight !== sourceSize.height ||
      !Number.isInteger(doc.crop.x) || !Number.isInteger(doc.crop.y) ||
      !Number.isInteger(doc.crop.width) || !Number.isInteger(doc.crop.height) ||
      doc.crop.x < 0 || doc.crop.y < 0 || doc.crop.width <= 0 || doc.crop.height <= 0 ||
      doc.crop.x + doc.crop.width > sourceSize.width ||
      doc.crop.y + doc.crop.height > sourceSize.height) {
      throw new Error('原图已变化或裁剪区域无效');
    }
    const expected: PreviewSize = ImageEditGeometry.outputSize(doc);
    let frame: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    let file: fs.File | undefined = undefined;
    let owned: boolean = false;
    try {
      const decoded: PreviewSize = new PreviewSize();
      decoded.width = doc.crop.width; decoded.height = doc.crop.height;
      frame = await LibraryImageReader.decode(stamp, doc.crop, decoded, true);
      const turns: number = ((Math.round(doc.turns) % 4) + 4) % 4;
      if (turns > 0) { await frame.rotate(turns * 90); }
      const info: image.ImageInfo = await frame.getImageInfo();
      if (info.size.width !== expected.width || info.size.height !== expected.height ||
        info.pixelFormat !== image.PixelMapFormat.RGBA_8888) {
        throw new Error('编辑像素尺寸或格式不符合预期');
      }
      for (const tile of EditExport.tiles(doc)) {
        EditExport.check(token);
        const buffer: ArrayBuffer = new ArrayBuffer(tile.width * tile.height * 4);
        const area: image.PositionArea = { pixels: buffer, offset: 0, stride: tile.width * 4,
          region: { x: tile.x, y: tile.y,
            size: { width: tile.width, height: tile.height } } };
        await frame.readPixels(area);
        EditExport.check(token);
        // PositionArea uses straight BGRA, even when the PixelMap itself is PREMUL RGBA.
        EditRasterizer.paintBgra(new Uint8Array(buffer), tile, doc, false);
        await frame.writePixels(area);
      }
      EditExport.check(token);
      packer = image.createImagePacker();
      file = fs.openSync(pendingPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      owned = true;
      const format: string = extension === 'jpg' ? 'image/jpeg' : 'image/png';
      const quality: number = extension === 'jpg' ? EditExport.qualityOf(setting) : 100;
      try { await packer.packToFile(frame, file.fd, { format: format, quality: quality }); }
      finally { fs.closeSync(file); file = undefined; }
      EditExport.check(token);
      const bytes: number = fs.statSync(pendingPath).size;
      if (bytes <= 0) { throw new Error('编辑图片写入不完整'); }
      const output: image.ImageSource = image.createImageSource(pendingPath);
      try {
        const resultInfo: image.ImageInfo = await output.getImageInfo();
        if (resultInfo.size.width !== expected.width || resultInfo.size.height !== expected.height) {
          throw new Error('编辑图片尺寸验证失败');
        }
      } finally { await output.release(); }
      EditExport.check(token);
      const result: EditResult = new EditResult();
      result.path = pendingPath; result.width = expected.width;
      result.height = expected.height; result.bytes = bytes;
      return result;
    } catch (error) {
      if (owned) { try { fs.unlinkSync(pendingPath); } catch (cleanupError) { } }
      throw new Error(String(error));
    } finally {
      if (file !== undefined) { try { fs.closeSync(file); } catch (closeError) { } }
      if (packer !== undefined) { try { await packer.release(); } catch (releaseError) { } }
      if (frame !== undefined) { try { await frame.release(); } catch (releaseError) { } }
    }
  }
}
