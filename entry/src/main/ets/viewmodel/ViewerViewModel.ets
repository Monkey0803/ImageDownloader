import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { DownloadItem } from '../model/Models';
import { ViewerSlide } from '../model/PreviewAsset';
import { DownloadStore } from '../service/DownloadStore';
import { ActionOutcome, exportFile, shareFile, shareLivePhoto } from '../service/FileActions';
import { kindOf } from '../theme/Tokens';

export interface ViewerRequest {
  id?: string;
  rename?: boolean;
  ids?: string[];
}

/** Downloaded-image viewer state and actions. Router, dialogs and rendering remain in the page. */
@ObservedV2
export class ViewerViewModel {
  @Trace order: string[] = [];
  @Trace slides: ViewerSlide[] = [];
  @Trace index: number = 0;
  @Trace renameAllowed: boolean = true;
  @Trace missing: boolean = false;
  @Trace local: boolean = false;
  @Trace completed: boolean = false;

  private listener: () => void = (): void => { this.refresh(); };

  start(params: ViewerRequest | undefined): void {
    const startId: string = typeof params?.id === 'string' ? params.id : '';
    this.renameAllowed = params?.rename !== false;
    const passed: string[] = params?.ids ?? [];
    this.order = passed.length > 0 ? passed : (startId.length > 0 ? [startId] : []);
    const at: number = this.order.indexOf(startId);
    this.index = at >= 0 ? at : 0;
    DownloadStore.subscribe(this.listener);
    this.refresh();
  }

  stop(): void { DownloadStore.unsubscribe(this.listener); }

  takeNotice(): string { return DownloadStore.takeNotice(); }

  currentId(): string {
    return this.index >= 0 && this.index < this.slides.length ? this.slides[this.index].id : '';
  }

  item(): DownloadItem | undefined {
    const id: string = this.currentId();
    return id.length > 0 ? DownloadStore.downloads.find((entry: DownloadItem): boolean => entry.id === id) : undefined;
  }

  private slideOf(item: DownloadItem): ViewerSlide {
    const landed: boolean = item.status === 'completed' && DownloadStore.exists(item.path);
    const live: boolean = item.kind === 'livephoto';
    const still: string = live && item.stillPath.length > 0 && DownloadStore.exists(item.stillPath)
      ? item.stillPath : '';
    const motion: string = live && item.motionPath.length > 0 && DownloadStore.exists(item.motionPath)
      ? item.motionPath : '';
    const slide: ViewerSlide = new ViewerSlide();
    slide.id = item.id;
    slide.libraryId = landed ? item.id : '';
    slide.downloaded = landed;
    slide.url = item.url;
    slide.sourcePage = item.sourcePage;
    slide.bytes = item.size;
    slide.downloadedAt = item.finishedAt;
    slide.src = landed ? fileUri.getUriFromPath(still.length > 0 ? still : item.path) : item.url;
    slide.localPath = landed ? (live ? still : item.path) : '';
    slide.animated = landed && item.animated;
    slide.name = item.name;
    slide.label = live ? '实况' : kindOf(item.name);
    slide.stillPath = still;
    slide.motionPath = motion;
    return slide;
  }

  refresh(): void {
    const current: string = this.currentId();
    const slides: ViewerSlide[] = [];
    const order: string[] = [];
    for (const id of this.order) {
      const item: DownloadItem | undefined =
        DownloadStore.downloads.find((entry: DownloadItem): boolean => entry.id === id);
      if (item !== undefined) { order.push(id); slides.push(this.slideOf(item)); }
    }
    this.order = order;
    this.slides = slides;
    if (slides.length === 0) {
      this.missing = true;
      this.local = false;
      this.completed = false;
      return;
    }
    const at: number = order.indexOf(current);
    this.index = at >= 0 ? at : Math.min(Math.max(this.index, 0), slides.length - 1);
    this.missing = false;
    const item: DownloadItem | undefined = this.item();
    this.completed = item?.status === 'completed';
    this.local = item !== undefined && this.completed && DownloadStore.exists(item.path);
  }

  setIndex(next: number): void { this.index = next; this.refresh(); }

  localHint(): string {
    const item: DownloadItem | undefined = this.item();
    if (this.local && item !== undefined) {
      return [item.note, item.receipt.message].filter((text: string): boolean => text.length > 0).join('；');
    }
    if (this.local) { return ''; }
    if (this.completed) { return '应用内文件已不存在，远程预览需要原地址仍可访问'; }
    if (item !== undefined && (item.status === 'failed' || item.status === 'cancelled')) {
      return '这次下载没有成功，只能看远程原图；重新下载后才能分享、导出或存相册。';
    }
    return '图片还没下载完成，暂时只能看大图，落盘后才能分享、导出或存相册。';
  }

  renameCurrent(name: string): string {
    const item: DownloadItem | undefined = this.item();
    if (item === undefined) { return ''; }
    return DownloadStore.renameDownload(item, name) ? '重命名完成' : '改名失败：名称已存在，或原文件已不在';
  }

  /** Returns true when the page has no surviving neighbor and should close. */
  deleteCurrent(): boolean {
    const item: DownloadItem | undefined = this.item();
    if (item === undefined) { return false; }
    const nextIds: string[] = this.slides.slice(this.index + 1).map((slide: ViewerSlide): string => slide.id);
    const previousIds: string[] = this.slides.slice(0, this.index).reverse()
      .map((slide: ViewerSlide): string => slide.id);
    if (!DownloadStore.deleteDownload(item)) { throw new Error('文件未能删除，记录已保留，请重试'); }
    const neighbor: string | undefined = nextIds.find((id: string): boolean => this.order.includes(id))
      ?? previousIds.find((id: string): boolean => this.order.includes(id));
    if (neighbor === undefined) { return true; }
    this.index = this.order.indexOf(neighbor);
    this.refresh();
    return false;
  }

  savePrompt(): string {
    const item: DownloadItem | undefined = this.item();
    if (item?.receipt.target === 'gallery' && item.receipt.status === 'saved') { return 'again'; }
    return item?.receipt.status === 'interrupted' ? 'interrupted' : '';
  }

  saveToGallery(force: boolean = false): void {
    const item: DownloadItem | undefined = this.item();
    if (item !== undefined) { DownloadStore.saveToGallery(item, force); }
  }

  private livePair(item: DownloadItem): boolean {
    return item.kind === 'livephoto' && item.stillPath.length > 0 && item.motionPath.length > 0
      && DownloadStore.exists(item.stillPath) && DownloadStore.exists(item.motionPath);
  }

  async share(context: common.UIAbilityContext): Promise<ActionOutcome> {
    const item: DownloadItem | undefined = this.item();
    if (item === undefined) { return { ok: false, message: '' }; }
    if (this.livePair(item)) {
      return await shareLivePhoto(context, item.stillPath, item.motionPath, item.path, item.name);
    }
    return await shareFile(context, item.path, item.name, false);
  }

  async export(context: common.UIAbilityContext): Promise<ActionOutcome> {
    const item: DownloadItem | undefined = this.item();
    return item === undefined ? { ok: false, message: '' } : await exportFile(context, item.path, item.name);
  }
}
