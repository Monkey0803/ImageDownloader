import { imageSuperResolution, visionBase } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AnalysisToken, AssetStamp } from '../model/LibraryAsset';
import { EditRect, EditResult, EditTicket, PreviewSize } from '../model/ImageEditDocument';
import { DownloadItem } from '../model/Models';
import { DownloadStore } from './DownloadStore';
import { EditJournal } from './EditJournal';
import { LibraryImageReader } from './LibraryImageReader';

/** Creates a still PNG copy from one completed local library image. */
export class ImageSuperResolution {
  private static readonly MAX_INPUT_PIXELS: number = 4000000;

  private static check(token: AnalysisToken): void {
    if (token.cancelled) { throw new Error('图片超分已取消'); }
  }

  private static async source(id: string): Promise<AssetStamp> {
    const item: DownloadItem | undefined = DownloadStore.downloads.find((entry: DownloadItem): boolean =>
      entry.id === id && entry.status === 'completed');
    if (item === undefined || !DownloadStore.exists(item.path)) {
      throw new Error('本地图片不可读，请先下载');
    }
    return LibraryImageReader.stamp(item);
  }

  private static async checkSource(id: string, original: AssetStamp, token: AnalysisToken): Promise<void> {
    ImageSuperResolution.check(token);
    const current: AssetStamp = await ImageSuperResolution.source(id);
    if (current.path !== original.path || current.bytes !== original.bytes ||
      current.modified !== original.modified || current.changed !== original.changed ||
      current.orientation !== original.orientation) {
      throw new Error('原图已变化，请重新打开预览');
    }
    ImageSuperResolution.check(token);
  }

  private static label(stamp: AssetStamp, item: DownloadItem): string {
    if (stamp.sourceKind === 'livephoto') { return '超分封面静图'; }
    if (item.animated) { return '超分首帧静图'; }
    return '超分';
  }

  static async createCopy(id: string, token: AnalysisToken): Promise<DownloadItem> {
    ImageSuperResolution.check(token);
    if (!canIUse('SystemCapability.AI.Vision.VisionBase')) {
      throw new Error('此设备不支持图片超分');
    }
    const stamp: AssetStamp = await ImageSuperResolution.source(id);
    const sourceSize: PreviewSize = await LibraryImageReader.info(stamp);
    const pixels: number = sourceSize.width * sourceSize.height;
    if (pixels <= 0 || !Number.isSafeInteger(pixels)) { throw new Error('图片尺寸无效'); }
    if (pixels > ImageSuperResolution.MAX_INPUT_PIXELS) {
      throw new Error('原图超过 400 万像素，暂不能超分');
    }
    ImageSuperResolution.check(token);

    const region: EditRect = new EditRect();
    region.width = sourceSize.width; region.height = sourceSize.height;
    let input: image.PixelMap | undefined = undefined;
    let output: image.PixelMap | undefined = undefined;
    let analyzer: imageSuperResolution.ImageSRAnalyzer | undefined = undefined;
    let ticket: EditTicket | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    let file: fs.File | undefined = undefined;
    try {
      input = await LibraryImageReader.decode(stamp, region, sourceSize, false);
      ImageSuperResolution.check(token);
      analyzer = await imageSuperResolution.ImageSRAnalyzer.create();
      ImageSuperResolution.check(token);
      const data: visionBase.ImageData = { pixelMap: input };
      const request: visionBase.Request = { inputData: data };
      const response: imageSuperResolution.ISPResponse = await analyzer.process(request);
      output = response.pixelMap;
      ImageSuperResolution.check(token);
      if (output === undefined) { throw new Error('超分服务未返回图片'); }
      const resultInfo: image.ImageInfo = await output.getImageInfo();
      const expectedWidth: number = sourceSize.width * 2;
      const expectedHeight: number = sourceSize.height * 2;
      if (resultInfo.size.width !== expectedWidth || resultInfo.size.height !== expectedHeight) {
        throw new Error('超分结果尺寸不符合预期');
      }
      await ImageSuperResolution.checkSource(id, stamp, token);
      ticket = await EditJournal.prepare(DownloadStore.context.filesDir, DownloadStore.nextId(), id);
      packer = image.createImagePacker();
      file = fs.openSync(ticket.pendingPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { await packer.packToFile(output, file.fd, { format: 'image/png', quality: 100 }); }
      finally { fs.closeSync(file); file = undefined; }
      ImageSuperResolution.check(token);
      const bytes: number = fs.statSync(ticket.pendingPath).size;
      if (bytes <= 0) { throw new Error('超分图片写入不完整'); }
      const saved: image.ImageSource = image.createImageSource(ticket.pendingPath);
      try {
        const savedInfo: image.ImageInfo = await saved.getImageInfo();
        if (savedInfo.size.width !== expectedWidth || savedInfo.size.height !== expectedHeight) {
          throw new Error('超分图片尺寸验证失败');
        }
      } finally { await saved.release(); }
      await ImageSuperResolution.checkSource(id, stamp, token);
      const result: EditResult = new EditResult();
      result.path = ticket.pendingPath; result.width = expectedWidth;
      result.height = expectedHeight; result.bytes = bytes;
      await EditJournal.finalize(ticket, result);
      ImageSuperResolution.check(token);
      const sourceItem: DownloadItem | undefined = DownloadStore.downloads.find((entry: DownloadItem): boolean =>
        entry.id === id);
      if (sourceItem === undefined) { throw new Error('原图已删除'); }
      return await DownloadStore.registerEdited(id, ticket, result,
        ImageSuperResolution.label(stamp, sourceItem), token, stamp);
    } catch (error) {
      if (ticket !== undefined) { await EditJournal.rollback(ticket); }
      throw new Error(error instanceof Error ? error.message : String(error));
    } finally {
      if (file !== undefined) { try { fs.closeSync(file); } catch (closeError) {} }
      if (packer !== undefined) { try { await packer.release(); } catch (releaseError) {} }
      if (output !== undefined && output !== input) { try { await output.release(); } catch (releaseError) {} }
      if (input !== undefined) { try { await input.release(); } catch (releaseError) {} }
      if (analyzer !== undefined) { try { await analyzer.destroy(); } catch (releaseError) {} }
    }
  }
}
