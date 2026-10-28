import { PreviewCheckerboard } from './PreviewCheckerboard';
import { image } from '@kit.ImageKit';
import { PreviewGeometry, PreviewRegion, PreviewSize } from '../util/PreviewGeometry';
import { Font, Palette, Space } from '../theme/Tokens';
import { PillButton } from './Widgets';

/** Keep a low-resolution full image beneath this bounded, on-demand viewport decode. */
@ComponentV2
export struct PreviewRegionImage {
  @Require @Param sourcePath: string;
  @Require @Param originalWidth: number;
  @Require @Param originalHeight: number;
  @Require @Param viewportWidth: number;
  @Require @Param viewportHeight: number;
  @Require @Param zoomFactor: number;
  @Require @Param offsetX: number;
  @Require @Param offsetY: number;
  @Param backgroundMode: string = 'auto';
  @Param transparent: boolean = false;
  @Param hdr: boolean = false;
  @Param active: boolean = true;
  @Local private frame: image.PixelMap | undefined = undefined;
  @Local private region: PreviewRegion = { x: 0, y: 0, width: 0, height: 0 };
  @Local private failed: boolean = false;
  private timer: number = -1;
  private generation: number = 0;
  private alive: boolean = false;
  private decoding: boolean = false;
  private pending: boolean = false;
  private previousPath: string = '';

  aboutToAppear(): void { this.alive = true; this.schedule(); }
  aboutToDisappear(): void {
    this.alive = false;
    this.generation++;
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    this.clearFrame();
  }

  @Monitor('sourcePath', 'originalWidth', 'originalHeight', 'viewportWidth', 'viewportHeight', 'zoomFactor', 'offsetX', 'offsetY', 'active', 'hdr')
  private onViewportChanged(monitor: IMonitor): void { this.schedule(); }

  private clearFrame(): void {
    const old: image.PixelMap | undefined = this.frame;
    this.frame = undefined;
    if (old !== undefined) { try { old.release(); } catch (error) {} }
  }

  private imageSize(): PreviewSize { return { width: this.originalWidth, height: this.originalHeight }; }
  private viewport(): PreviewSize { return { width: this.viewportWidth, height: this.viewportHeight }; }
  private unit(): number {
    return this.originalWidth > 0 ? PreviewGeometry.fit(this.imageSize(), this.viewport()).width * this.zoomFactor / this.originalWidth : 0;
  }
  private left(): number { return this.viewportWidth / 2 + this.offsetX - this.originalWidth * this.unit() / 2 + this.region.x * this.unit(); }
  private top(): number { return this.viewportHeight / 2 + this.offsetY - this.originalHeight * this.unit() / 2 + this.region.y * this.unit(); }

  private schedule(): void {
    this.generation++;
    this.failed = false;
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    if (this.previousPath !== this.sourcePath || !this.active || this.zoomFactor <= 1.001) { this.clearFrame(); }
    this.previousPath = this.sourcePath;
    this.pending = false;
    if (!this.alive || !this.active || this.zoomFactor <= 1.001 || this.sourcePath.length === 0) { return; }
    this.timer = setTimeout((): void => {
      this.timer = -1;
      if (this.decoding) { this.pending = true; } else { this.decode(); }
    }, 120);
  }

  private async decode(): Promise<void> {
    const token: number = this.generation;
    const path: string = this.sourcePath;
    const region: PreviewRegion = PreviewGeometry.visibleRegion(this.imageSize(), this.viewport(), this.zoomFactor,
      { x: this.offsetX, y: this.offsetY });
    if (region.width < 1 || region.height < 1) { return; }
    this.decoding = true;
    this.pending = false;
    let source: image.ImageSource | undefined = undefined;
    let decoded: image.PixelMap | undefined = undefined;
    try {
      source = image.createImageSource(path);
      const displayScale: number = Math.min(1, this.unit() * this.getUIContext().vp2px(1));
      const size: PreviewSize = PreviewGeometry.decodeSize({ width: region.width * displayScale,
        height: region.height * displayScale }, 8192, 8000000);
      const options: image.DecodingOptions = { index: 0,
        desiredRegion: { x: region.x, y: region.y, size: { width: region.width, height: region.height } },
        desiredSize: { width: size.width, height: size.height }, cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
        desiredDynamicRange: this.hdr ? image.DecodingDynamicRange.HDR : image.DecodingDynamicRange.SDR };
      try {
        decoded = await source.createPixelMap(options);
      } catch (error) {
        if (options.desiredDynamicRange !== image.DecodingDynamicRange.HDR) { throw new Error(String(error)); }
        options.desiredDynamicRange = image.DecodingDynamicRange.SDR;
        decoded = await source.createPixelMap(options);
      }
      if (!this.alive || token !== this.generation) { return; }
      const old: image.PixelMap | undefined = this.frame;
      this.frame = decoded;
      this.region = region;
      decoded = undefined;
      if (old !== undefined) { try { old.release(); } catch (error) {} }
    } catch (error) {
      if (this.alive && token === this.generation) { this.failed = true; }
    } finally {
      if (decoded !== undefined) { try { await decoded.release(); } catch (error) {} }
      if (source !== undefined) { try { await source.release(); } catch (error) {} }
      this.decoding = false;
      if (this.pending && this.alive && this.active) { this.decode(); }
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.frame !== undefined) {
        Stack() {
          if (this.backgroundMode === 'checker' || (this.backgroundMode === 'auto' && this.transparent)) {
            PreviewCheckerboard({ cellSize: 12 * this.zoomFactor,
              phaseX: this.region.x * this.unit(), phaseY: this.region.y * this.unit() }).width('100%').height('100%')
          }
          Image(this.frame).width('100%').height('100%').objectFit(ImageFit.Fill)
            .dynamicRangeMode(this.hdr ? DynamicRangeMode.HIGH : DynamicRangeMode.STANDARD)
        }.width(this.region.width * this.unit()).height(this.region.height * this.unit())
          .backgroundColor(this.backgroundMode === 'white' ? '#FFFFFF' : '#000000')
          .position({ x: this.left(), y: this.top() }).hitTestBehavior(HitTestMode.None)
      }
      if (this.failed) {
        Row({ space: Space.s8 }) {
          Text('局部细节加载失败').fontSize(Font.aux).fontColor(Palette.white)
          PillButton({ label: '重试', small: true, variant: 'tonal', onAction: (): void => { this.schedule(); } })
        }.padding(Space.s8).backgroundColor('#CC333333').position({ x: 12, y: '50%' })
      }
    }.width('100%').height('100%').clip(true).hitTestBehavior(HitTestMode.Transparent)
  }
}
