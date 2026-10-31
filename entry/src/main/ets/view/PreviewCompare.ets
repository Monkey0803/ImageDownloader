import { PreviewAsset } from '../model/PreviewAsset';
import { ComparisonPaneViewModel } from '../viewmodel/ComparisonPaneViewModel';
import { Font, Palette, Space } from '../theme/Tokens';
import { ZoomablePreviewImage } from './ImageSurface';
import { PreviewStrip, PreviewThumbnail } from './PreviewStrip';
import { IconButton, PillButton } from './Widgets';
import { PreviewChrome } from './PreviewChrome';

@ComponentV2
struct ComparisonPane {
  @Require @Param asset: PreviewAsset;
  @Param backgroundMode: string = 'auto';
  @Local private vm: ComparisonPaneViewModel = new ComparisonPaneViewModel();
  private loadedId: string = '';
  private loadedPath: string = '';

  aboutToAppear(): void {
    this.loadedId = this.asset.id;
    this.loadedPath = this.asset.localPath;
    this.vm.start(this.asset);
  }
  aboutToDisappear(): void { this.vm.stop(); }

  @Monitor('asset')
  private onAssetChanged(monitor: IMonitor): void {
    if (this.asset.id === this.loadedId && this.asset.localPath === this.loadedPath) { return; }
    this.loadedId = this.asset.id;
    this.loadedPath = this.asset.localPath;
    this.vm.load(this.asset);
  }

  build() {
    Column() {
      Text(this.asset.name).fontSize(Font.caption).fontColor(Palette.white).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).padding(Space.s8).width('100%')
      Stack() {
        if (this.vm.uriValue.length > 0) {
          ZoomablePreviewImage({ imageId: this.asset.id, path: this.vm.pathValue, fallbackUri: this.vm.uriValue,
            backgroundMode: this.backgroundMode, controlsVisible: false })
        }
        if (this.vm.busy) { LoadingProgress().width(28).height(28).color(Palette.white) }
        if (this.vm.message.length > 0) {
          Column({ space: Space.s8 }) {
            Text(this.vm.message).fontSize(Font.aux).fontColor(Palette.white).textAlign(TextAlign.Center)
            PillButton({ label: '重试', small: true, variant: 'tonal', onAction: (): void => { this.vm.retry(); } })
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
