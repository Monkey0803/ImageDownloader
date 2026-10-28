import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AnalysisToken, AssetStamp } from '../model/LibraryAsset';
import { EditDocument, EditRect, EditResult, EditStroke, PreviewSize } from '../model/ImageEditDocument';
import { ImageEditGeometry } from '../util/ImageEditGeometry';
import { EditRasterizer } from '../util/EditRasterizer';
import { LibraryImageReader } from './LibraryImageReader';

/** Exports an original-resolution PNG into a new pending file; registration is a separate transaction. */
export class EditExport {
  private static check(token: AnalysisToken): void {
    if (token.cancelled) { throw new Error('图片编辑已取消'); }
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
    token: AnalysisToken): Promise<EditResult> {
    EditExport.check(token);
    if (pendingPath.length === 0 || fs.accessSync(pendingPath)) {
      throw new Error('编辑输出文件已存在或路径无效');
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
      try { await packer.packToFile(frame, file.fd, { format: 'image/png', quality: 100 }); }
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
