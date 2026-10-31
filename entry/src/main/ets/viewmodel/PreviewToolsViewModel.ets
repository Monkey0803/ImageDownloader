import { PreviewAsset } from '../model/PreviewAsset';
import { AnalysisToken, LibraryIndex } from '../model/LibraryAsset';
import { DownloadItem } from '../model/Models';
import { DownloadStore } from '../service/DownloadStore';
import { ImageMetadata, ImageTools } from '../service/ImageTools';
import { ImageSuperResolution } from '../service/ImageSuperResolution';
import { LIBRARY_CATALOG } from '../service/LibraryCatalog';
import { LibraryAnalysis } from '../service/LibraryAnalysis';
import { MediaFormat } from '../service/MediaFormat';

/** State and business actions for the details/tools sheet. The view owns only tabs and dialogs. */
@ObservedV2
export class PreviewToolsViewModel {
  @Trace metadata: ImageMetadata = new ImageMetadata();
  @Trace busy: boolean = false;
  @Trace notice: string = '';
  @Trace noticeGroup: string = 'details';
  @Trace recognizedText: string = '';
  @Trace codes: string[] = [];
  @Trace favorite: boolean = false;
  @Trace tags: string[] = [];

  private asset: PreviewAsset = new PreviewAsset();
  private generation: number = 0;
  private alive: boolean = false;
  private recognitionToken: AnalysisToken | undefined = undefined;
  private superResolutionToken: AnalysisToken | undefined = undefined;
  private catalogListener: () => void = (): void => { this.refreshMeta(); };

  start(asset: PreviewAsset): void {
    this.alive = true;
    LIBRARY_CATALOG.subscribe(this.catalogListener);
    this.load(asset);
  }

  stop(): void {
    this.alive = false;
    this.generation++;
    this.recognitionToken?.cancel();
    this.recognitionToken = undefined;
    this.superResolutionToken?.cancel();
    this.superResolutionToken = undefined;
    LIBRARY_CATALOG.unsubscribe(this.catalogListener);
  }

  load(asset: PreviewAsset): void {
    this.recognitionToken?.cancel();
    this.recognitionToken = undefined;
    this.superResolutionToken?.cancel();
    this.superResolutionToken = undefined;
    this.asset = asset;
    const generation: number = ++this.generation;
    this.metadata = new ImageMetadata();
    this.noticeGroup = 'details';
    this.busy = false;
    this.notice = '';
    this.recognizedText = '';
    this.codes = [];
    this.refreshMeta();
    if (asset.localPath.length === 0) { return; }
    ImageTools.metadata(asset.localPath).then((value: ImageMetadata): void => {
      if (this.alive && generation === this.generation) { this.metadata = value; }
    }).catch((): void => {
      if (this.alive && generation === this.generation) {
        this.noticeGroup = 'details';
        this.notice = '文件信息暂不可读';
      }
    });
  }

  private refreshMeta(): void {
    const id: string = this.asset.libraryId;
    if (id.length === 0) { this.favorite = false; this.tags = []; return; }
    const meta = LIBRARY_CATALOG.getMeta(id);
    this.favorite = meta.favorite;
    this.tags = meta.tags;
  }

  async toggleFavorite(): Promise<void> {
    if (this.asset.libraryId.length === 0) { return; }
    try {
      await LIBRARY_CATALOG.setFavorite([this.asset.libraryId], !this.favorite);
      this.refreshMeta();
    } catch (error) { this.noticeGroup = 'manage'; this.notice = '收藏保存失败，请重试'; }
  }

  async saveTags(add: string[], remove: string[]): Promise<void> {
    if (this.asset.libraryId.length === 0) { return; }
    try {
      await LIBRARY_CATALOG.changeTags([this.asset.libraryId], add, remove);
      this.refreshMeta();
    } catch (error) { this.noticeGroup = 'manage'; this.notice = '标签保存失败，请重试'; }
  }

  async copy(value: string, group: string = 'details'): Promise<void> {
    const generation: number = this.generation;
    this.noticeGroup = group;
    try {
      await ImageTools.copy(value);
      if (this.alive && generation === this.generation) { this.notice = '已复制'; }
    } catch (error) {
      if (this.alive && generation === this.generation) { this.notice = '复制失败，请重试'; }
    }
  }

  async recognize(text: boolean): Promise<void> {
    if (this.busy || this.asset.localPath.length === 0) { return; }
    const generation: number = this.generation;
    const path: string = this.asset.localPath;
    const token: AnalysisToken = new AnalysisToken();
    this.recognitionToken = token;
    this.busy = true;
    this.noticeGroup = 'recognize';
    this.notice = text ? '正在识别文字…' : '正在识别二维码…';
    try {
      if (text) {
        let value: string = '';
        const item: DownloadItem | undefined = DownloadStore.downloads.find((entry: DownloadItem): boolean =>
          entry.id === this.asset.libraryId && entry.status === 'completed');
        if (this.asset.libraryId.length > 0 && item !== undefined) {
          await LibraryAnalysis.ocr([item], true, token, (): void => {});
          const index: LibraryIndex | undefined = LIBRARY_CATALOG.getIndex(item.id);
          if (index?.ocrStatus === 'failed') { throw new Error(index.ocrError); }
          value = index?.text ?? '';
        } else {
          value = await ImageTools.text(path);
        }
        if (!this.alive || generation !== this.generation) { return; }
        this.recognizedText = value;
        this.notice = value.trim().length > 0 ? '文字识别完成，可选择或复制' : '未识别到文字，可下载原图后重试';
      } else {
        const values: string[] = await ImageTools.codes(path, DownloadStore.context.cacheDir);
        if (!this.alive || generation !== this.generation) { return; }
        this.codes = values;
        this.notice = values.length > 0 ? '识别完成，请选择复制或打开' : '未识别到二维码，可下载原图后重试';
      }
    } catch (error) {
      if (this.alive && generation === this.generation) { this.notice = '识别失败：' + String(error); }
    } finally {
      if (this.recognitionToken === token) { this.recognitionToken = undefined; }
      if (this.alive && generation === this.generation) { this.busy = false; }
    }
  }

  async superResolve(): Promise<void> {
    if (!ImageSuperResolution.available()) {
      this.noticeGroup = 'edit';
      this.notice = ImageSuperResolution.unavailableHint();
      return;
    }
    if (this.busy || this.asset.libraryId.length === 0) { return; }
    const id: string = this.asset.libraryId;
    const item: DownloadItem | undefined = DownloadStore.downloads.find((entry: DownloadItem): boolean =>
      entry.id === id && entry.status === 'completed');
    if (item === undefined || !DownloadStore.exists(item.path) || this.asset.localPath.length === 0) {
      this.notice = '请先下载图片，再使用超分';
      return;
    }
    const generation: number = this.generation;
    const token: AnalysisToken = new AnalysisToken();
    this.superResolutionToken = token;
    this.busy = true;
    this.noticeGroup = 'edit';
    this.notice = '正在处理图片超分…';
    try {
      await ImageSuperResolution.createCopy(id, token);
      if (this.alive && generation === this.generation && !token.cancelled) {
        this.notice = '已生成超分副本，可在图库查看';
      }
    } catch (error) {
      if (this.alive && generation === this.generation && !token.cancelled) {
        this.notice = '图片超分失败：' + (error instanceof Error ? error.message : String(error));
      }
    } finally {
      if (this.superResolutionToken === token) { this.superResolutionToken = undefined; }
      if (this.alive && generation === this.generation) { this.busy = false; }
    }
  }

  async open(value: string, group: string = 'details'): Promise<void> {
    const generation: number = this.generation;
    this.noticeGroup = group;
    try { await ImageTools.open(DownloadStore.context, value); }
    catch (error) {
      if (this.alive && generation === this.generation) { this.notice = '无法打开链接，可复制后使用浏览器打开'; }
    }
  }

  dimensions(): string {
    const width: number = this.metadata.width || this.asset.width;
    const height: number = this.metadata.height || this.asset.height;
    return width > 0 && height > 0 ? width.toString() + ' × ' + height.toString() : '未知';
  }

  localReady(): boolean { return this.asset.localPath.length > 0 && DownloadStore.exists(this.asset.localPath); }
  mediaKind(): string {
    return DownloadStore.downloads.find((entry: DownloadItem): boolean =>
      entry.id === this.asset.libraryId)?.kind ?? '';
  }
  canSuperResolve(): boolean { return ImageSuperResolution.available(); }
  superResolutionHint(): string { return ImageSuperResolution.unavailableHint(); }
  isLink(value: string): boolean { return ImageTools.link(value).length > 0; }
  isLivepicStill(): boolean { return MediaFormat.isLivepicStill(this.asset.url); }
}
