import { PreviewAsset } from '../model/PreviewAsset';
import { AuthenticatedPreview, PreviewResult } from '../service/AuthenticatedPreview';
import { DownloadStore } from '../service/DownloadStore';
import { ImageTools } from '../service/ImageTools';

/** Loads one comparison source and rejects results from an earlier selection. */
@ObservedV2
export class ComparisonPaneViewModel {
  @Trace pathValue: string = '';
  @Trace uriValue: string = '';
  @Trace message: string = '';
  @Trace busy: boolean = false;

  private preview: AuthenticatedPreview = new AuthenticatedPreview();
  private generation: number = 0;
  private alive: boolean = false;
  private asset: PreviewAsset = new PreviewAsset();

  start(asset: PreviewAsset): void { this.alive = true; this.load(asset); }
  stop(): void { this.alive = false; this.generation++; this.preview.cancel(); }

  async load(asset: PreviewAsset, force: boolean = false): Promise<void> {
    this.asset = asset;
    const generation: number = ++this.generation;
    this.preview.cancel();
    this.pathValue = asset.localPath;
    this.uriValue = asset.localPath.length > 0 ? asset.src : '';
    this.message = '';
    this.busy = false;
    if (asset.localPath.length > 0) { return; }
    if (ImageTools.link(asset.url).length === 0) { this.message = '此图片暂不可用于对比'; return; }
    this.busy = true;
    try {
      const result: PreviewResult = await this.preview.load(asset.url, asset.sourcePage,
        DownloadStore.context.cacheDir, force);
      if (!this.alive || generation !== this.generation) { return; }
      this.pathValue = result.path;
      this.uriValue = result.uri;
      this.message = result.uri.length === 0 ? result.message : '';
    } catch (error) {
      if (this.alive && generation === this.generation) { this.message = '加载失败，可重试或先下载原图'; }
    } finally {
      if (this.alive && generation === this.generation) { this.busy = false; }
    }
  }

  retry(): void { this.load(this.asset, true); }
}
