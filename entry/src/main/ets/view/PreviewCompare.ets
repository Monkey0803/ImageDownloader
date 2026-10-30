import { PreviewAsset } from '../model/PreviewAsset';
import { AuthenticatedPreview, PreviewResult } from '../service/AuthenticatedPreview';
import { DownloadStore } from '../service/DownloadStore';
import { ImageTools } from '../service/ImageTools';
import { Font, Palette, Space } from '../theme/Tokens';
import { ZoomablePreviewImage } from './ImageSurface';
import { PreviewStrip, PreviewThumbnail } from './PreviewStrip';
import { IconButton, PillButton } from './Widgets';
import { PreviewChrome } from './PreviewChrome';

@ComponentV2
struct ComparisonPane {
  @Require @Param asset: PreviewAsset;
  @Param backgroundMode: string = 'auto';
  @Local private pathValue: string = '';
  @Local private uriValue: string = '';
  @Local private message: string = '';
  @Local private busy: boolean = false;
  private preview: AuthenticatedPreview = new AuthenticatedPreview();
  private generation: number = 0;
  private alive: boolean = false;

  aboutToAppear(): void { this.alive = true; this.load(); }
  aboutToDisappear(): void { this.alive = false; this.generation++; this.preview.cancel(); }
  private loadedId: string = '';
  private loadedPath: string = '';
  @Monitor('asset')
  private onAssetChanged(monitor: IMonitor): void {
    if (this.asset.id !== this.loadedId || this.asset.localPath !== this.loadedPath) { this.load(); }
  }

  private async load(force: boolean = false): Promise<void> {
    this.loadedId = this.asset.id;
    this.loadedPath = this.asset.localPath;
    const token: number = ++this.generation;
    this.preview.cancel();
    this.pathValue = this.asset.localPath;
    this.uriValue = this.asset.localPath.length > 0 ? this.asset.src : '';
    this.message = '';
    this.busy = false;
    if (this.asset.localPath.length > 0) { return; }
    if (ImageTools.link(this.asset.url).length === 0) { this.message = '此图片暂不可用于对比'; return; }
    this.busy = true;
    try {
      const result: PreviewResult = await this.preview.load(this.asset.url, this.asset.sourcePage,
        DownloadStore.context.cacheDir, force);
      if (!this.alive || token !== this.generation) { return; }
      this.pathValue = result.path;
      this.uriValue = result.uri;
      this.message = result.uri.length === 0 ? result.message : '';
    } catch (error) {
      if (this.alive && token === this.generation) { this.message = '加载失败，可重试或先下载原图'; }
    } finally {
      if (this.alive && token === this.generation) { this.busy = false; }
    }
  }

  build() {
    Column() {
      Text(this.asset.name).fontSize(Font.caption).fontColor(Palette.white).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).padding(Space.s8).width('100%')
      Stack() {
        if (this.uriValue.length > 0) {
          ZoomablePreviewImage({ imageId: this.asset.id, path: this.pathValue, fallbackUri: this.uriValue,
            backgroundMode: this.backgroundMode, controlsVisible: false })
        }
        if (this.busy) { LoadingProgress().width(28).height(28).color(Palette.white) }
        if (this.message.length > 0) {
          Column({ space: Space.s8 }) {
            Text(this.message).fontSize(Font.aux).fontColor(Palette.white).textAlign(TextAlign.Center)
            PillButton({ label: '重试', small: true, variant: 'tonal', onAction: (): void => { this.load(true); } })
          }.padding(Space.s12)
        }
      }.width('100%').layoutWeight(1).clip(true)
    }.width('100%').height('100%').backgroundColor('#111111')
  }
}

/** Each pane owns its transform and request lifecycle. References load only after selection. */
@ComponentV2
export struct PreviewCompare {
  @Require @Param assets: PreviewAsset[];
  @Require @Param currentId: string;
  @Param backgroundMode: string = 'auto';
  @Event onClose: () => void = (): void => {};
  @Local private referenceId: string = '';
  @Local private pickerShown: boolean = true;
  @Local private landscape: boolean = false;

  private current(): PreviewAsset | undefined { return this.assets.find((asset: PreviewAsset): boolean => asset.id === this.currentId); }
  private reference(): PreviewAsset | undefined { return this.assets.find((asset: PreviewAsset): boolean => asset.id === this.referenceId); }
  private candidates(): PreviewAsset[] { return this.assets.filter((asset: PreviewAsset): boolean => asset.id !== this.currentId); }
  private thumbnails(): PreviewThumbnail[] {
    return this.candidates().map((asset: PreviewAsset): PreviewThumbnail => {
      return { id: asset.id, src: asset.src, name: asset.name, localPath: asset.localPath };
    });
  }

  @Builder
  private referencePane() {
    if (this.reference() !== undefined) {
      ComparisonPane({ asset: this.reference()!, backgroundMode: this.backgroundMode })
    } else {
      Column({ space: Space.s12 }) {
        Text(this.candidates().length > 0 ? '从缩略图中选择一张参考图片' : '当前范围只有一张图片，无法对比')
          .fontSize(Font.body).fontColor(Palette.white).textAlign(TextAlign.Center)
      }.width('100%').height('100%').justifyContent(FlexAlign.Center).padding(Space.s16)
    }
  }

  build() {
    Column() {
      Column() {
        Row({ space: Space.s8 }) {
          Text('双图对比').fontSize(Font.body).fontColor(Palette.white).layoutWeight(1)
          PillButton({ label: '更换参考图', small: true, variant: 'tonal', active: this.candidates().length > 0,
            onAction: (): void => { this.pickerShown = !this.pickerShown; } })
          IconButton({ glyph: 'close', tone: Palette.white, plain: true, diameter: 36,
            accessibilityLabel: '退出双图对比', onAction: this.onClose })
        }.width('100%').padding(Space.s12)
      }
      .width('100%')
      .padding({ top: Space.s16, bottom: Space.s24 })
      .linearGradient(PreviewChrome.topGradient())
      .hitTestBehavior(HitTestMode.None)
      if (this.pickerShown && this.candidates().length > 0) {
        PreviewStrip({ items: this.thumbnails(), currentIndex: Math.max(0,
          this.candidates().findIndex((asset: PreviewAsset): boolean => asset.id === this.referenceId)),
          onJump: (index: number): void => {
            this.referenceId = this.candidates()[index]?.id ?? '';
            this.pickerShown = false;
          }, onClose: (): void => { this.pickerShown = false; } })
      }
      if (this.landscape) {
        Row({ space: 2 }) {
          if (this.current() !== undefined) {
            ComparisonPane({ asset: this.current()!, backgroundMode: this.backgroundMode }).layoutWeight(1)
          }
          Column() { this.referencePane() }.layoutWeight(1).height('100%')
        }.width('100%').layoutWeight(1)
      } else {
        Column({ space: 2 }) {
          if (this.current() !== undefined) {
            ComparisonPane({ asset: this.current()!, backgroundMode: this.backgroundMode }).layoutWeight(1)
          }
          Column() { this.referencePane() }.layoutWeight(1).width('100%')
        }.width('100%').layoutWeight(1)
      }
      Column() {
        Text('两张图片可独立双击、捏合和拖动；动图对比显示首帧')
          .fontSize(Font.aux).fontColor('#BBFFFFFF').padding(Space.s8).textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ top: Space.s24, bottom: Space.s24 })
      .linearGradient(PreviewChrome.bottomGradient())
      .hitTestBehavior(HitTestMode.None)
    }.width('100%').height('100%').backgroundColor('#000000')
      .onSizeChange((oldSize: SizeOptions, next: SizeOptions): void => { this.landscape = Number(next.width) > Number(next.height); })
      .hitTestBehavior(HitTestMode.Default)
      .onClick((): void => {})
  }
}
