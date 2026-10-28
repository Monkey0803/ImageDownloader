import { imageSuperResolution, visionBase } from '@kit.CoreVisionKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AnalysisToken, AssetStamp } from '../model/LibraryAsset';
import { EditRect, EditResult, EditTicket, PreviewSize } from '../model/ImageEditDocument';
import { DownloadItem } from '../model/Models';
import { DownloadStore } from './DownloadStore';
import { EditJournal } from './EditJournal';
import { LibraryImageReader } from './LibraryImageReader';
import { SuperResolutionGeometry } from './SuperResolutionGeometry';

/** Creates a still PNG copy from one completed local library image. */
export class ImageSuperResolution {
  /** 同一用户不能并发调用超分，这里把并发挡在服务入口。 */
  private static running: boolean = false;

  /** 模拟器能通过 canIUse 但 Core Vision Kit 的服务不可用，提前拦掉。 */
  static available(): boolean {
    return deviceInfo.productModel !== 'emulator' && canIUse('SystemCapability.AI.Vision.VisionBase');
  }

  static unavailableHint(): string {
    if (deviceInfo.productModel === 'emulator') { return '模拟器不支持图片超分，请在真机上使用'; }
    return '此设备不支持图片超分';
  }

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

  /** 把系统错误翻译成用户能理解的提示。 */
  private static describe(error: Object): string {
    const message: string = error instanceof Error ? error.message : String(error);
    const lower: string = message.toLowerCase();
    if (lower.includes('timed out') || lower.includes('timeout')) { return '超分服务超时，请重试'; }
    if (lower.includes('service is abnormal')) { return '超分服务暂不可用，请稍后重试'; }
    return message.length > 0 ? message : '超分服务暂不可用';
  }

  static async createCopy(id: string, token: AnalysisToken): Promise<DownloadItem> {
    if (!ImageSuperResolution.available()) { throw new Error(ImageSuperResolution.unavailableHint()); }
    if (ImageSuperResolution.running) { throw new Error('超分服务正在处理，请稍候'); }
    ImageSuperResolution.running = true;
    try {
      return await ImageSuperResolution.run(id, token);
    } finally {
      ImageSuperResolution.running = false;
    }
  }

  private static async run(id: string, token: AnalysisToken): Promise<DownloadItem> {
    ImageSuperResolution.check(token);
    const stamp: AssetStamp = await ImageSuperResolution.source(id);
    const sourceSize: PreviewSize = await LibraryImageReader.info(stamp);
    if (sourceSize.width <= 0 || sourceSize.height <= 0) { throw new Error('图片尺寸无效'); }
    const inputSize: PreviewSize = SuperResolutionGeometry.decodeSize(sourceSize.width, sourceSize.height);
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
      input = await LibraryImageReader.decode(stamp, region, inputSize, false);
      const inputInfo: image.ImageInfo = await input.getImageInfo();
      ImageSuperResolution.check(token);
      analyzer = await imageSuperResolution.ImageSRAnalyzer.create();
      ImageSuperResolution.check(token);
      const data: visionBase.ImageData = { pixelMap: input };
      const request: visionBase.Request = { inputData: data };
      let response: imageSuperResolution.ISPResponse | undefined = undefined;
      try {
        response = await analyzer.process(request);
      } catch (error) {
        throw new Error(ImageSuperResolution.describe(error));
      }
      if (response === undefined) { throw new Error('超分服务未返回结果'); }
      output = response.pixelMap;
      ImageSuperResolution.check(token);
      if (output === undefined) { throw new Error('超分服务未返回图片'); }
      const resultInfo: image.ImageInfo = await output.getImageInfo();
      if (!SuperResolutionGeometry.accepts(inputInfo.size.width, inputInfo.size.height,
        resultInfo.size.width, resultInfo.size.height)) {
        throw new Error('超分结果尺寸异常');
      }
      const resultWidth: number = resultInfo.size.width;
      const resultHeight: number = resultInfo.size.height;
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
        if (savedInfo.size.width !== resultWidth || savedInfo.size.height !== resultHeight) {
          throw new Error('超分图片尺寸验证失败');
        }
      } finally { await saved.release(); }
      await ImageSuperResolution.checkSource(id, stamp, token);
      const result: EditResult = new EditResult();
      result.path = ticket.pendingPath; result.width = resultWidth;
      result.height = resultHeight; result.bytes = bytes;
      await EditJournal.finalize(ticket, result);
      ImageSuperResolution.check(token);
      const sourceItem: DownloadItem | undefined = DownloadStore.downloads.find((entry: DownloadItem): boolean =>
        entry.id === id);
      if (sourceItem === undefined) { throw new Error('原图已删除'); }
      return await DownloadStore.registerEdited(id, ticket, result,
        ImageSuperResolution.label(stamp, sourceItem), token, stamp);
    } catch (error) {
      if (ticket !== undefined) { await EditJournal.rollback(ticket); }
      throw new Error(ImageSuperResolution.describe(error));
    } finally {
      if (file !== undefined) { try { fs.closeSync(file); } catch (closeError) {} }
      if (packer !== undefined) { try { await packer.release(); } catch (releaseError) {} }
      if (output !== undefined && output !== input) { try { await output.release(); } catch (releaseError) {} }
      if (input !== undefined) { try { await input.release(); } catch (releaseError) {} }
      if (analyzer !== undefined) { try { await analyzer.destroy(); } catch (releaseError) {} }
    }
  }
}
