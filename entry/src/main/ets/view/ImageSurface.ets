import { PreviewCheckerboard } from './PreviewCheckerboard';
import { PreviewMotion, PreviewMotionStep } from '../util/PreviewMotion';
import { PreviewReadingState } from '../model/PreviewReadingState';
import { PreviewReadingStore } from '../service/PreviewReadingStore';
import { PreviewRegionImage } from './PreviewRegionImage';
import { AnimationPlayback, AnimationFrameInfo } from '../service/AnimationPlayback';
import { FrameSaveDestination } from '../service/ImageTools';
import { FrameSaveViewModel } from '../viewmodel/FrameSaveViewModel';
import { DownloadStore } from '../service/DownloadStore';
import { image } from '@kit.ImageKit';
import { display, promptAction } from '@kit.ArkUI';
import { Font, Palette, Radius, Space } from '../theme/Tokens';
import { SCREEN_INSETS } from '../theme/Metrics';
import { PreviewGeometry, PreviewPosition, PreviewSize } from '../util/PreviewGeometry';
import { Thumb } from './Thumb';
import { PreviewChrome, PreviewButton } from './PreviewChrome';
import { Glyph } from './Icons';

const PREVIEW_FIRST_FRAME_TIMEOUT_MS: number = 15000;
const PREVIEW_SOURCE_UNAVAILABLE: string = '图片源不可用，请检查文件或网络后重试';

/** Retain the last decoded frame while upgrading detail; never decode multiple revisions concurrently. */
@ComponentV2
export struct LocalPreviewImage {
  @Require @Param path: string;
  @Require @Param fallbackUri: string;
  @Param label: string = 'IMG';
  @Param active: boolean = true;
  @Param renderZoom: number = 1;
  @Param renderX: number = 0;
  @Param renderY: number = 0;
  @Event onMetadata: (width: number, height: number, transparent: boolean, isHdr: boolean) => void = () => {};
  @Local private frame: image.PixelMap | undefined = undefined;
  @Local private problem: string = '';
  @Local private loading: boolean = false;
  @Local private hdr: boolean = false;
  private ownedFrame: image.PixelMap | undefined = undefined;
  private generation: number = 0;
  private disposed: boolean = false;
  private decoding: boolean = false;
  private pending: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    this.load(false);
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.generation++;
    this.pending = false;
    this.clearFrame();
  }

  @Monitor('path', 'active')
  private onSourceChanged(monitor: IMonitor): void { this.load(this.active && this.path.length > 0); }

  private clearFrame(): void {
    this.frame = undefined;
    this.hdr = false;
    const old: image.PixelMap | undefined = this.ownedFrame;
    this.ownedFrame = undefined;
    if (old !== undefined) { try { old.release(); } catch (error) {} }
  }

  private load(preserve: boolean): void {
    this.generation++;
    if (!preserve || !this.active) { this.clearFrame(); }
    this.problem = '';
    if (this.disposed || !this.active) { this.pending = false; this.loading = false; return; }
    if (this.path.length === 0) { this.loading = false; return; }
    this.loading = true;
    if (this.decoding) { this.pending = true; return; }
    this.pending = false;
    this.decoding = true;
    this.decode(this.path, this.generation);
  }

  private async decode(path: string, generation: number): Promise<void> {
    let source: image.ImageSource | undefined = undefined;
    let decoded: image.PixelMap | undefined = undefined;
    try {
      source = image.createImageSource(path);
      const info: image.ImageInfo = await source.getImageInfo();
      if (this.disposed || !this.active || generation !== this.generation) { return; }
      if (info.size.width <= 0 || info.size.height <= 0) { throw new Error('Invalid image size'); }
      const screen: display.Display = display.getDefaultDisplaySync();
      const base: number = Math.min(3072, Math.max(screen.width, screen.height));
      // Visible detail belongs to PreviewRegionImage; keep only a small overview underneath it.
      const size: PreviewSize = PreviewGeometry.decodeSize({ width: info.size.width, height: info.size.height }, base, 3000000);
      const options: image.DecodingOptions = { index: 0, desiredSize: { width: size.width, height: size.height } };
      // HDR is requested only when the source carries it; unsupported devices fall back to SDR below.
      if (info.isHdr === true && DownloadStore.hdrEnabled) { options.desiredDynamicRange = image.DecodingDynamicRange.HDR; }
      try {
        decoded = await source.createPixelMap(options);
      } catch (error) {
        if (options.desiredDynamicRange !== image.DecodingDynamicRange.HDR) { throw new Error(String(error)); }
        options.desiredDynamicRange = image.DecodingDynamicRange.SDR;
        decoded = await source.createPixelMap(options);
      }
      const pixelInfo: image.ImageInfo = await decoded.getImageInfo();
      if (this.disposed || !this.active || generation !== this.generation || path !== this.path) { return; }
      const old: image.PixelMap | undefined = this.ownedFrame;
      this.ownedFrame = decoded;
      this.frame = decoded;
      decoded = undefined;
      if (old !== undefined) { try { old.release(); } catch (error) {} }
      // JPEG / HEIF 照片和 HDR 解码结果没有透明通道；即便 PixelMap 报告 PREMUL / UNPREMUL，也不应画棋盘格。
      const mime: string = (info.mimeType ?? '').toLowerCase();
      const jpeg: boolean = mime === 'image/jpeg' || mime === 'image/jpg'
        || (mime.length === 0 && /\.jpe?g$/i.test(path));
      const photo: boolean = jpeg || mime === 'image/heic' || mime === 'image/heif';
      // UNKNOWN 不代表透明；等像素可显示后再通知父层绘制棋盘格，避免解码期间只剩背景。
      const hdr: boolean = pixelInfo.isHdr === true;
      this.hdr = hdr;
      this.onMetadata(info.size.width, info.size.height,
        !photo && !hdr && (pixelInfo.alphaType === image.AlphaType.PREMUL
          || pixelInfo.alphaType === image.AlphaType.UNPREMUL
          || info.alphaType === image.AlphaType.PREMUL || info.alphaType === image.AlphaType.UNPREMUL), hdr);
    } catch (error) {
      if (!this.disposed && this.active && generation === this.generation) {
        this.problem = this.frame !== undefined ? '高清加载失败，已保留当前画面' : '图片无法解码或文件已失效';
      }
    } finally {
      if (decoded !== undefined) { try { decoded.release(); } catch (error) {} }
      if (source !== undefined) { try { await source.release(); } catch (error) {} }
      this.decoding = false;
      if (!this.disposed && generation === this.generation) { this.loading = false; }
      if (this.pending && !this.disposed && this.active) { this.load(true); }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.frame !== undefined) {
        Image(this.frame).width('100%').height('100%').objectFit(ImageFit.Contain)
          .dynamicRangeMode(this.hdr ? DynamicRangeMode.HIGH : DynamicRangeMode.STANDARD)
          .scale({ x: this.renderZoom, y: this.renderZoom }).translate({ x: this.renderX, y: this.renderY })
      } else if (this.active && this.fallbackUri.length > 0) {
        Thumb({ src: this.fallbackUri, label: this.label, fit: ImageFit.Contain, fallbackText: '预览不可用' })
          .width('100%').height('100%')
          .scale({ x: this.renderZoom, y: this.renderZoom }).translate({ x: this.renderX, y: this.renderY })
      }
      if (this.loading && this.frame === undefined) {
        LoadingProgress().width(28).height(28).color(Palette.white).hitTestBehavior(HitTestMode.None)
      }
      if (this.loading && this.frame !== undefined) {
        Column() {
          Blank()
          Text('正在加载清晰细节…').fontSize(Font.aux).fontColor(Palette.white)
            .padding(Space.s8).borderRadius(Radius.r8).backgroundColor('#99000000')
        }.width('100%').height('100%')
          .padding({ bottom: SCREEN_INSETS.safeBottom + 160 }).hitTestBehavior(HitTestMode.None)
      }
      if (this.problem.length > 0) {
        Column({ space: Space.s8 }) {
          Text(this.problem).fontSize(Font.aux).fontColor(Palette.white)
          PreviewButton({ label: '重试', variant: 'tonal', small: true,
            onAction: (): void => { this.load(true); } })
        }.padding(Space.s12).borderRadius(Radius.r8).backgroundColor('#CC222222')
      }
    }.width('100%').height('100%')
  }
}

/** Reactive animation actions supplied to the host's shared toolbar. */
@ObservedV2
export class AnimationDockActions {
  @Trace available: boolean = false;
  @Trace canPause: boolean = false;
  @Trace paused: boolean = false;
  @Trace exporting: boolean = false;
  @Trace choosingDestination: boolean = false;
  @Trace notice: string = '';
  onToggle: () => void = (): void => {};
  onSave: () => void = (): void => {};
}

/** Read reactive state inside each button so labels and enabled state update in place. */
@ComponentV2
export struct AnimationToolbarAction {
  @Require @Param actions: AnimationDockActions;
  @Param frameAction: boolean = false;

  private actionLabel(): string {
    return this.frameAction ? (this.actions.exporting ? '正在保存…' : '保存当前帧')
      : (this.actions.paused ? '继续' : '暂停');
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: Space.s6 }) {
        Glyph({ glyph: this.frameAction ? 'image' : (this.actions.paused ? 'play' : 'pause'),
          glyphSize: 21, glyphTone: '#E6FFFFFF', glyphWeight: 1.7 })
        Text(this.actionLabel()).fontSize(11).minFontSize(9).maxFontSize(11).maxLines(1)
          .fontColor('#E6FFFFFF')
      }.padding({ top: Space.s6, bottom: Space.s6 })
    }.width('100%').height(52).padding({ left: 2, right: 2 }).backgroundColor(Color.Transparent)
      .borderRadius(Radius.r6).accessibilityText(this.actionLabel())
      .enabled(!this.frameAction || (!this.actions.exporting && !this.actions.choosingDestination))
      .onClick((): void => {
        if (this.frameAction) { this.actions.onSave(); } else { this.actions.onToggle(); }
      })
  }
}

/** Native animation playback with a transparency backdrop and a recoverable loading state. */
@ComponentV2
export struct AnimatedPreviewImage {
  @Param backgroundMode: string = 'auto';
  @Require @Param src: string;
  @Event onTapImage: () => void = (): void => {};
  @Param localPath: string = '';
  @Param name: string = '图片';
  @Param controlsVisible: boolean = true;
  @Param controlsBottom: number = 80;
  @Param dockedControls: boolean = false;
  @BuilderParam bottomActions: (actions: AnimationDockActions) => void = this.emptyBottomActions;

  @Builder
  private emptyBottomActions(actions: AnimationDockActions) {}
  @Param allowDismiss: boolean = false;
  @Event onDismiss: () => void = (): void => {};
  @Local private dockState: AnimationDockActions = new AnimationDockActions();
  @Local private pullDistance: number = 0;
  private sourceIdentity: string = '';
  @Local private animationFrame: image.PixelMap | undefined = undefined;
  @Local private paused: boolean = false;
  @Local private frameIndex: number = 0;
  @Local private frameCount: number = 1;
  @Local private frameSave: FrameSaveViewModel = new FrameSaveViewModel();
  @Local private transparent: boolean = false;
  private playback: AnimationPlayback | undefined = undefined;
  private generation: number = 0;
  private alive: boolean = false;
  private firstFrameTimer: number = -1;
  @Local private loadAttempt: number = 0;
  @Local private failureMessage: string = PREVIEW_SOURCE_UNAVAILABLE;

  aboutToAppear(): void {
    this.dockState.onToggle = (): void => { this.togglePlayback(); };
    this.dockState.onSave = (): void => { this.saveFrame(); };
    this.alive = true;
    this.frameSave.start();
    this.sourceIdentity = this.localPath + this.src;
    this.start();
  }
  aboutToDisappear(): void { this.alive = false; this.frameSave.stop(); this.stop(); }

  private stop(): void {
    this.clearFirstFrameTimer();
    this.generation++;
    this.animationFrame = undefined;
    this.playback?.stop();
    this.playback = undefined;
  }

  private clearFirstFrameTimer(): void {
    if (this.firstFrameTimer >= 0) {
      clearTimeout(this.firstFrameTimer);
      this.firstFrameTimer = -1;
    }
  }

  private acceptsLoad(token: number): boolean {
    return this.alive && this.active && token === this.generation && !this.failed;
  }

  private failLoad(token: number, message: string): void {
    if (!this.acceptsLoad(token)) { return; }
    this.stop();
    this.loaded = false;
    this.failureMessage = message;
    this.failed = true;
  }

  private start(reset: boolean = true): void {
    this.stop();
    this.loaded = false;
    this.failed = false;
    this.failureMessage = PREVIEW_SOURCE_UNAVAILABLE;
    if (reset) {
      this.frameSave.reset();
      this.paused = false;
      this.frameIndex = 0;
    }
    if (!this.active || !this.alive) { return; }
    const token: number = this.generation;
    this.loadAttempt = token;
    if (this.localPath.length === 0 && this.src.trim().length === 0) {
      this.failLoad(token, PREVIEW_SOURCE_UNAVAILABLE);
      return;
    }
    this.firstFrameTimer = setTimeout((): void => {
      if (!this.acceptsLoad(token) || this.loaded) { return; }
      this.firstFrameTimer = -1;
      this.failLoad(token, '图片加载超时，请重试');
    }, PREVIEW_FIRST_FRAME_TIMEOUT_MS);
    if (this.localPath.length === 0) { return; }
    const session: AnimationPlayback = new AnimationPlayback();
    this.playback = session;
    if (this.paused) { session.pause(); }
    session.run(this.localPath, (frame: image.PixelMap, info: AnimationFrameInfo): void => {
      if (!this.acceptsLoad(token)) { return; }
      if (info.width <= 0 || info.height <= 0) {
        this.failLoad(token, PREVIEW_SOURCE_UNAVAILABLE);
        return;
      }
      this.clearFirstFrameTimer();
      this.animationFrame = frame;
      this.frameIndex = info.index;
      this.frameCount = info.count;
      this.imageWidth = info.width;
      this.imageHeight = info.height;
      this.transparent = info.transparent;
      this.loaded = true;
    }, (): void => {
      this.failLoad(token, PREVIEW_SOURCE_UNAVAILABLE);
    }, this.frameIndex);
  }

  private togglePlayback(): void {
    this.paused = !this.paused;
    if (this.paused) { this.playback?.pause(); } else { this.playback?.resume(); }
  }

  private saveFrame(): void {
    if (this.frameSave.exporting || this.frameSave.choosingDestination || !this.active || !this.alive
      || !this.loaded || this.localPath.length === 0) { return; }
    this.paused = true;
    this.playback?.pause();
    const path: string = this.localPath;
    const name: string = this.name;
    const index: number = this.frameIndex;
    this.frameSave.save(path, name, index, async (): Promise<FrameSaveDestination | undefined> => {
      const choice: promptAction.ActionMenuSuccessResponse = await this.getUIContext().getPromptAction().showActionMenu({
        title: '保存当前帧',
        buttons: [{ text: '保存到相册', color: Palette.fontPrimary }, { text: '保存到文件夹', color: Palette.fontPrimary }]
      });
      return choice.index === 0 ? 'album' : choice.index === 1 ? 'folder' : undefined;
    });
  }
  @Param active: boolean = true;
  @Local private imageWidth: number = 0;
  @Local private imageHeight: number = 0;
  @Local private viewportWidth: number = 0;
  @Local private viewportHeight: number = 0;
  @Local private loaded: boolean = false;
  @Local private failed: boolean = false;

  @Monitor('src', 'localPath', 'active')
  private onSourceChanged(monitor: IMonitor): void {
    const identity: string = this.localPath + this.src;
    const reset: boolean = identity !== this.sourceIdentity;
    this.sourceIdentity = identity;
    this.pullDistance = 0;
    this.start(reset);
  }

  private fitted(): PreviewSize {
    return PreviewGeometry.fit({ width: this.imageWidth, height: this.imageHeight },
      { width: this.viewportWidth, height: this.viewportHeight });
  }

  @Builder
  private remoteImage(attempt: number, source: string) {
    // API 26 reloadKey retries the unchanged source URL.
    Image(source, undefined, attempt.toString()).width('100%').height('100%').objectFit(ImageFit.Contain)
      .translate({ y: this.pullDistance * 0.65 })
      .onComplete((event): void => {
        if (!this.acceptsLoad(attempt) || source !== this.src) { return; }
        if (event !== undefined && event.loadingStatus === 1 && event.width > 0 && event.height > 0) {
          this.clearFirstFrameTimer();
          this.imageWidth = event.width;
          this.imageHeight = event.height;
          this.loaded = true;
        }
      })
      .onError((): void => {
        if (source === this.src) { this.failLoad(attempt, PREVIEW_SOURCE_UNAVAILABLE); }
      })
  }

  @Builder
  private animationCanvas() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.loaded && ((this.backgroundMode === 'auto' && this.transparent) || this.backgroundMode === 'checker')) {
        PreviewCheckerboard().width(this.fitted().width).height(this.fitted().height)
      }
      if (this.active && this.animationFrame !== undefined) {
        Image(this.animationFrame).width('100%').height('100%').objectFit(ImageFit.Contain)
          .translate({ y: this.pullDistance * 0.65 })
      } else if (this.active && !this.failed && this.localPath.length === 0) {
        ForEach([this.loadAttempt], (attempt: number) => {
          this.remoteImage(attempt, this.src)
        }, (attempt: number): string => attempt.toString())
      }
      if (this.active && !this.loaded && !this.failed) {
        LoadingProgress().width(28).height(28).color(Palette.white).hitTestBehavior(HitTestMode.None)
      }
      if (this.failed) {
        Column({ space: Space.s8 }) {
          Text(this.failureMessage).fontSize(Font.aux).fontColor(Palette.white)
          PreviewButton({ label: '重试', variant: 'tonal', small: true,
            onAction: (): void => { this.start(); } })
        }.padding(Space.s12).borderRadius(Radius.r8).backgroundColor('#CC222222')
      }
    }.width('100%').height('100%')
    .backgroundColor(this.backgroundMode === 'white' ? '#FFFFFF' : '#000000')
    .onGestureJudgeBegin((info: GestureInfo, event: BaseGestureEvent): GestureJudgeResult => {
      if (!this.active || (info.type === GestureControl.GestureType.PAN_GESTURE && !this.allowDismiss)) {
        return GestureJudgeResult.REJECT;
      }
      return GestureJudgeResult.CONTINUE;
    })
    .gesture(GestureGroup(GestureMode.Exclusive,
      PanGesture({ fingers: 1, direction: PanDirection.Vertical })
      .onActionUpdate((event: GestureEvent): void => { this.pullDistance = Math.max(0, event.offsetY); })
      .onActionEnd((event: GestureEvent): void => {
        const close: boolean = this.active && this.allowDismiss
          && PreviewMotion.dismiss(this.pullDistance, event.velocityY, this.viewportHeight);
        this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => { this.pullDistance = 0; });
        if (close) { this.onDismiss(); }
      }).onActionCancel((): void => { this.pullDistance = 0; }),
      TapGesture({ count: 1 }).onAction((): void => { if (this.active) { this.onTapImage(); } })
    ))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.animationCanvas()
      // Keep the dock outside the image's tap and dismiss gestures.
      if (this.dockedControls) {
        if (this.controlsVisible && this.active) {
          Column() {
            this.bottomActions(this.dockState)
          }.width('100%').padding({ top: Space.s24 })
            .linearGradient(PreviewChrome.bottomGradient())
            .hitTestBehavior(HitTestMode.None)
        }
      } else {
        this.animationControls()
      }
    }.width('100%').height('100%')
    .onSizeChange((oldValue: SizeOptions, next: SizeOptions): void => {
      this.viewportWidth = Number(next.width);
      this.viewportHeight = Number(next.height);
    })
  }
  @Monitor('loaded', 'frameCount', 'paused', 'exporting', 'choosingDestination', 'notice', 'localPath')
  private updateDockActions(monitor: IMonitor): void {
    this.dockState.available = this.loaded && this.localPath.length > 0;
    this.dockState.canPause = this.frameCount > 1;
    this.dockState.paused = this.paused;
    this.dockState.exporting = this.frameSave.exporting;
    this.dockState.choosingDestination = this.frameSave.choosingDestination;
    this.dockState.notice = this.frameSave.notice;
  }

  @Builder
  private animationControls() {
    if (this.controlsVisible && this.active && this.loaded && this.localPath.length > 0) {
      Column({ space: Space.s8 }) {
        if (this.frameSave.notice.length > 0) {
          Text(this.frameSave.notice).fontSize(Font.aux).fontColor(Palette.white).backgroundColor('#DD333333').padding(Space.s8)
            .hitTestBehavior(HitTestMode.None)
        }
        Row({ space: Space.s8 }) {
          if (this.frameCount > 1) {
            PreviewButton({ label: this.paused ? '继续' : '暂停', small: true, variant: 'tonal',
              icon: this.paused ? 'play' : 'pause', onAction: (): void => { this.togglePlayback(); } })
          }
          PreviewButton({ label: this.frameSave.exporting ? '正在保存…' : '保存当前帧', small: true, variant: 'tonal',
            active: !this.frameSave.exporting && !this.frameSave.choosingDestination, onAction: (): void => { this.saveFrame(); } })
        }.hitTestBehavior(HitTestMode.None)
      }.margin({ bottom: this.controlsBottom + 8 })
        .hitTestBehavior(HitTestMode.None)
    }
  }

}

/** Both browsers share the geometry, gestures, long-image mode and progressive local decode. */
@ComponentV2
export struct ZoomablePreviewImage {
  @Param backgroundMode: string = 'auto';
  @Param imageId: string = '';
  @Require @Param path: string;
  @Require @Param fallbackUri: string;
  @Param label: string = 'IMG';
  @Param active: boolean = true;
  @Param controlsVisible: boolean = true;
  @Param controlsBottom: number = 80;
  @Param showFitControls: boolean = true;
  @Param fitCommand: string = '';
  @Param readingKey: string = '';
  @Param allowDismiss: boolean = false;
  @Event onDismiss: () => void = (): void => {};
  @Event onTapImage: () => void = (): void => {};
  @Event onZoomChange: (zoomed: boolean) => void = (zoomed: boolean): void => {};
  @Local private zoomFactor: number = 1;
  @Local private fitMode: string = 'screen';
  @Local private dragX: number = 0;
  @Local private dragY: number = 0;
  @Local private imageWidth: number = 0;
  @Local private imageHeight: number = 0;
  @Local private transparent: boolean = false;
  @Local private hdr: boolean = false;
  @Local private viewportWidth: number = 0;
  @Local private viewportHeight: number = 0;
  private pinchBase: number = 1;
  private pinchX: number = 0;
  private pinchY: number = 0;
  private pinchAnchorX: number = 0;
  private pinchAnchorY: number = 0;
  private panBaseX: number = 0;
  private panBaseY: number = 0;
  @Local private dismissDistance: number = 0;
  private closingGesture: boolean = false;
  private pinching: boolean = false;
  private tapSuppressed: boolean = false;
  private panning: boolean = false;
  private motionTimer: number = -1;
  private motionStarted: number = 0;
  private motionLast: number = 0;
  private motionState: PreviewMotionStep = new PreviewMotionStep();
  private boundKey: string = '';
  private restored: boolean = false;
  private alive: boolean = false;

  aboutToAppear(): void { this.alive = true; this.boundKey = this.readingKey; }
  aboutToDisappear(): void {
    this.stopMotion(true);
    this.remember();
    PreviewReadingStore.flush();
    this.alive = false;
  }

  private imageSize(): PreviewSize { return { width: this.imageWidth, height: this.imageHeight }; }
  private viewport(): PreviewSize { return { width: this.viewportWidth, height: this.viewportHeight }; }
  private fitted(): PreviewSize { return PreviewGeometry.fit(this.imageSize(), this.viewport()); }
  private widthScale(): number { return PreviewGeometry.widthScale(this.imageSize(), this.viewport()); }
  private nativeScale(): number {
    return PreviewGeometry.nativeScale(this.imageSize(), this.viewport(), this.getUIContext().vp2px(1));
  }
  private maximumScale(): number { return Math.max(3, this.widthScale(), this.nativeScale()); }
  private minimumScale(): number { return Math.min(1, this.nativeScale()); }
  private longImage(): boolean { return this.imageWidth > 0 && this.imageHeight / this.imageWidth >= 2; }

  @Monitor('fitCommand')
  private onFitCommandChanged(monitor: IMonitor): void {
    if (!this.active || this.imageWidth <= 0) { return; }
    if (this.fitCommand.startsWith('screen:')) {
      this.animateTo(1, { x: 0, y: 0 }, 'screen');
    } else if (this.fitCommand.startsWith('native:')) {
      this.animateTo(this.nativeScale(), { x: 0, y: 0 }, 'native');
    }
  }

  @Monitor('active')
  private onActiveChanged(monitor: IMonitor): void {
    if (!this.active) {
      this.pinching = false; this.panning = false;
      this.stopMotion(true);
      this.dismissDistance = 0;
      this.remember();
      PreviewReadingStore.flush();
    } else {
      this.restoreReading();
      this.onZoomChange(this.zoomFactor > 1.001);
    }
  }

  @Monitor('imageId', 'readingKey')
  private onIdentityChanged(monitor: IMonitor): void {
    this.stopMotion(true);
    this.remember();
    this.boundKey = this.readingKey;
    this.clearGeometry();
  }

  @Monitor('path', 'fallbackUri')
  private onPathChanged(monitor: IMonitor): void {
    if (this.imageId.length === 0) { this.clearGeometry(); }
  }

  private clearGeometry(): void {
    this.restored = false;
    this.imageWidth = 0;
    this.imageHeight = 0;
    this.transparent = false;
    this.hdr = false;
    this.reset();
  }

  private reset(): void {
    this.fitMode = 'screen';
    this.zoomFactor = 1;
    this.dragX = 0;
    this.dragY = 0;
    if (this.active) { this.onZoomChange(false); }
  }

  private remember(): void {
    if (!this.restored || this.boundKey.length === 0 || this.imageWidth <= 0 || this.viewportWidth <= 0) { return; }
    PreviewReadingStore.remember(PreviewReadingState.capture(this.boundKey, this.imageSize(), this.viewport(),
      this.zoomFactor, { x: this.dragX, y: this.dragY }, this.fitMode));
  }

  private restoreReading(): void {
    if (this.restored || this.imageWidth <= 0 || this.viewportWidth <= 0 || this.viewportHeight <= 0) { return; }
    const saved: PreviewReadingState | undefined = PreviewReadingStore.get(this.boundKey, this.imageWidth, this.imageHeight);
    this.restored = true;
    if (saved === undefined) { return; }
    this.fitMode = saved.mode;
    const zoom: number = Math.max(this.minimumScale(), Math.min(this.maximumScale(),
      saved.zoom(this.imageSize(), this.viewport(), this.getUIContext().vp2px(1))));
    this.apply(zoom, saved.position(this.imageSize(), this.viewport(), zoom));
  }

  private apply(zoom: number, position: PreviewPosition): void {
    this.zoomFactor = Math.max(this.minimumScale(), Math.min(this.maximumScale(), zoom));
    const bounded: PreviewPosition = PreviewGeometry.clamp(this.imageSize(), this.viewport(), this.zoomFactor, position);
    this.dragX = bounded.x;
    this.dragY = bounded.y;
    if (this.active) { this.onZoomChange(this.zoomFactor > 1.001); }
  }

  private animateTo(zoom: number, position: PreviewPosition, mode: string = 'free'): void {
    this.stopMotion(false);
    this.fitMode = mode;
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => { this.apply(zoom, position); });
    this.remember();
  }

  private stopMotion(settle: boolean): void {
    if (this.motionTimer >= 0) { clearTimeout(this.motionTimer); this.motionTimer = -1; }
    if (settle) { this.apply(this.zoomFactor, { x: this.dragX, y: this.dragY }); }
  }

  private fling(vx: number, vy: number): void {
    this.stopMotion(false);
    this.motionState = new PreviewMotionStep();
    this.motionState.x = this.dragX; this.motionState.y = this.dragY;
    this.motionState.vx = vx; this.motionState.vy = vy;
    this.motionStarted = Date.now(); this.motionLast = this.motionStarted;
    this.motionTick();
  }

  private motionTick(): void {
    this.motionTimer = -1;
    if (!this.alive || !this.active) { return; }
    const now: number = Date.now();
    this.motionState = PreviewMotion.advance(this.imageSize(), this.viewport(), this.zoomFactor,
      this.motionState, Math.max(0.016, (now - this.motionLast) / 1000));
    this.motionLast = now;
    this.dragX = this.motionState.x; this.dragY = this.motionState.y;
    if (this.motionState.done || now - this.motionStarted > 1800) {
      this.stopMotion(true);
      this.remember();
      return;
    }
    this.motionTimer = setTimeout((): void => { this.motionTick(); }, 16);
  }

  private endPan(event?: GestureEvent): void {
    this.panning = false;
    if (this.pinching) { return; }
    if (this.closingGesture) {
      const close: boolean = this.active && this.allowDismiss && event !== undefined
        && PreviewMotion.dismiss(this.dismissDistance, event.velocityY, this.viewportHeight);
      this.closingGesture = false;
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => { this.dismissDistance = 0; });
      if (close) { this.onDismiss(); }
      return;
    }
    if (this.zoomFactor > 1.001 && this.active) { this.fling(event?.velocityX ?? 0, event?.velocityY ?? 0); }
  }

  private readingProgress(): number {
    return Math.round(PreviewMotion.progress(this.imageSize(), this.viewport(), this.zoomFactor, this.dragY) * 100);
  }

  private seekReading(value: number, finished: boolean = true): void {
    this.stopMotion(false);
    this.fitMode = 'width';
    const zoom: number = this.widthScale();
    this.apply(zoom, PreviewMotion.seek(this.imageSize(), this.viewport(), zoom, value / 100));
    if (finished) { this.remember(); }
  }

  private toggleWidth(): void {
    if (this.zoomFactor > 1.001) { this.animateTo(1, { x: 0, y: 0 }, 'screen'); return; }
    const zoom: number = this.widthScale();
    this.animateTo(zoom, PreviewGeometry.top(this.imageSize(), this.viewport(), zoom), 'width');
  }

  private doubleTap(event: GestureEvent): void {
    if (!this.tapsAllowed()) { return; }
    if (this.zoomFactor > 1.001) { this.animateTo(1, { x: 0, y: 0 }, 'screen'); return; }
    const finger: FingerInfo | undefined = event.fingerList[0];
    const anchor: PreviewPosition = { x: finger !== undefined ? finger.localX - this.viewportWidth / 2 : 0,
      y: finger !== undefined ? finger.localY - this.viewportHeight / 2 : 0 };
    const position: PreviewPosition = PreviewGeometry.anchor({ x: this.dragX, y: this.dragY }, this.zoomFactor, 2, anchor, anchor);
    this.animateTo(2, position);
  }

  private tapsAllowed(): boolean {
    return !this.pinching && !this.tapSuppressed;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.imageWidth > 0 && (this.backgroundMode === 'checker' || (this.backgroundMode === 'auto' && this.transparent))) {
          PreviewCheckerboard().width(this.fitted().width).height(this.fitted().height)
            .scale({ x: this.zoomFactor, y: this.zoomFactor }).translate({ x: this.dragX, y: this.dragY })
        }
        LocalPreviewImage({ path: this.path, fallbackUri: this.fallbackUri,
          label: this.label, active: this.active,
          renderZoom: this.zoomFactor, renderX: this.dragX, renderY: this.dragY,
          onMetadata: (width: number, height: number, transparent: boolean, isHdr: boolean): void => {
            this.imageWidth = width;
            this.imageHeight = height;
            this.transparent = transparent;
            this.hdr = isHdr;
            this.restoreReading();
            this.apply(this.fitMode === 'native' ? this.nativeScale()
              : this.fitMode === 'width' ? this.widthScale() : this.zoomFactor, { x: this.dragX, y: this.dragY });
          } })
          .width('100%').height('100%')
        PreviewRegionImage({ sourcePath: this.path, originalWidth: this.imageWidth, originalHeight: this.imageHeight,
          viewportWidth: this.viewportWidth, viewportHeight: this.viewportHeight, zoomFactor: this.zoomFactor,
          offsetX: this.dragX, offsetY: this.dragY, active: this.active, hdr: this.hdr,
          backgroundMode: this.backgroundMode, transparent: this.transparent })
      }
      .width('100%').height('100%')
      .translate({ y: this.dismissDistance * 0.65 })
      .scale({ x: 1 - Math.min(0.08, this.dismissDistance / 3000), y: 1 - Math.min(0.08, this.dismissDistance / 3000) })

    }
    .width('100%').height('100%').clip(true)
    .backgroundColor(this.backgroundMode === 'white' ? '#FFFFFF' : '#000000')
    .onSizeChange((oldValue: SizeOptions, newValue: SizeOptions): void => {
      const saved: PreviewReadingState = PreviewReadingState.capture('', this.imageSize(), this.viewport(),
        this.zoomFactor, { x: this.dragX, y: this.dragY }, this.fitMode);
      const hadViewport: boolean = this.viewportWidth > 0 && this.viewportHeight > 0 && this.restored;
      this.stopMotion(false);
      this.viewportWidth = Number(newValue.width);
      this.viewportHeight = Number(newValue.height);
      if (hadViewport) {
        const zoom: number = Math.max(this.minimumScale(), Math.min(this.maximumScale(),
          saved.zoom(this.imageSize(), this.viewport(), this.getUIContext().vp2px(1))));
        this.apply(zoom, saved.position(this.imageSize(), this.viewport(), zoom));
      } else { this.restoreReading(); }
    })
    .onTouch((event: TouchEvent): void => {
      // A recognizer may deliver a delayed tap after pinch end. Only a new
      // single-finger contact may re-enable taps; a short time window is insufficient.
      if (event.type === TouchType.Down && event.touches.length === 1 && !this.pinching) { this.tapSuppressed = false; }
      if (event.touches.length > 1) { this.tapSuppressed = true; }
      if (event.type === TouchType.Down) { this.stopMotion(false); }
      if ((event.type === TouchType.Up || event.type === TouchType.Cancel) && !this.panning && !this.pinching
        && this.motionTimer < 0 && this.zoomFactor > 1.001 && this.active) { this.fling(0, 0); }
    })
    .onGestureJudgeBegin((gestureInfo: GestureInfo, event: BaseGestureEvent): GestureJudgeResult => {
      if (!this.active || (gestureInfo.type === GestureControl.GestureType.PAN_GESTURE
        && this.zoomFactor <= 1.001 && !this.allowDismiss)) {
        return GestureJudgeResult.REJECT;
      }
      return GestureJudgeResult.CONTINUE;
    })
    .gesture(GestureGroup(GestureMode.Parallel,
      GestureGroup(GestureMode.Exclusive,
        PanGesture({ fingers: 1, direction: this.zoomFactor > 1.001 ? PanDirection.All : PanDirection.Vertical })
        .onActionStart((): void => {
          if (this.pinching || !this.active) { return; }
          this.panning = true;
          this.stopMotion(false);
          this.closingGesture = this.zoomFactor <= 1.001 && this.allowDismiss;
          this.panBaseX = this.dragX;
          this.panBaseY = this.dragY;
        }).onActionUpdate((event: GestureEvent): void => {
          if (this.pinching || !this.active) { return; }
          if (this.closingGesture) { this.dismissDistance = Math.max(0, event.offsetY); return; }
          if (this.zoomFactor <= 1.001) { return; }
          const position: PreviewPosition = PreviewMotion.rubber(this.imageSize(), this.viewport(), this.zoomFactor,
            { x: this.panBaseX + event.offsetX, y: this.panBaseY + event.offsetY });
          this.dragX = position.x; this.dragY = position.y;
        }).onActionEnd((event: GestureEvent): void => { this.endPan(event); })
          .onActionCancel((): void => { this.endPan(); }),
        GestureGroup(GestureMode.Exclusive,
          TapGesture({ count: 2 }).onAction((event: GestureEvent): void => { this.doubleTap(event); }),
          TapGesture({ count: 1 }).onAction((): void => { if (this.tapsAllowed()) { this.onTapImage(); } })
        )
      ),
      PinchGesture().onActionStart((event: GestureEvent): void => {
        this.pinching = true;
        this.tapSuppressed = true;
        this.stopMotion(true);
        this.dismissDistance = 0; this.closingGesture = false;
        this.fitMode = 'free';
        this.pinchBase = this.zoomFactor;
        this.pinchX = this.dragX;
        this.pinchY = this.dragY;
        this.pinchAnchorX = event.pinchCenterX - this.viewportWidth / 2;
        this.pinchAnchorY = event.pinchCenterY - this.viewportHeight / 2;
      }).onActionUpdate((event: GestureEvent): void => {
        const zoom: number = Math.max(this.minimumScale(), Math.min(this.maximumScale(), this.pinchBase * event.scale));
        const position: PreviewPosition = PreviewGeometry.anchor({ x: this.pinchX, y: this.pinchY },
          this.pinchBase, zoom, { x: this.pinchAnchorX, y: this.pinchAnchorY },
          { x: event.pinchCenterX - this.viewportWidth / 2, y: event.pinchCenterY - this.viewportHeight / 2 });
        this.apply(zoom, position);
      }).onActionEnd((): void => {
        this.pinching = false; this.stopMotion(true); this.remember();
      }).onActionCancel((): void => {
        this.pinching = false; this.stopMotion(true); this.remember();
      })
    ))
    .overlay(this.readingControl(), { align: Alignment.Bottom })
  }

  @Builder
  private readingControl() {
    if (this.controlsVisible && this.imageWidth > 0 &&
      (this.showFitControls || (this.longImage() && this.widthScale() > 1.05))) {
      Column({ space: Space.s4 }) {
        Row({ space: Space.s8 }) {
        if (this.showFitControls) {
          PreviewButton({ label: '适合屏幕', small: true, variant: 'tonal',
            onAction: (): void => { this.animateTo(1, { x: 0, y: 0 }, 'screen'); } })
          PreviewButton({ label: '原始像素', small: true, variant: 'tonal',
            onAction: (): void => { this.animateTo(this.nativeScale(), { x: 0, y: 0 }, 'native'); } })
        }
        if (this.longImage() && this.widthScale() > 1.05) {
          PreviewButton({ label: this.zoomFactor > 1.001 ? '查看全图' : '适合宽度', small: true, variant: 'tonal',
            onAction: (): void => { this.toggleWidth(); } })
        }
        }.width('100%').justifyContent(FlexAlign.Center)
        if (this.longImage() && this.widthScale() > 1.05) {
          Row({ space: Space.s8 }) {
            PreviewButton({ label: '顶部', small: true, variant: 'tonal', onAction: (): void => { this.seekReading(0); } })
            Slider({ value: this.readingProgress(), min: 0, max: 100, step: 1 })
              .layoutWeight(1).height(40).selectedColor('#409CFF').trackColor('#99FFFFFF')
              .accessibilityText('长图阅读进度 ' + this.readingProgress().toString() + '%')
              .onChange((value: number, mode: SliderChangeMode): void => {
                this.seekReading(value, mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
              })
            Text(this.readingProgress().toString() + '%').fontSize(Font.aux).fontColor(Palette.white)
              .width(36).textAlign(TextAlign.Center)
            PreviewButton({ label: '底部', small: true, variant: 'tonal', onAction: (): void => { this.seekReading(100); } })
          }.width('100%')
        }
      }.width('100%').constraintSize({ maxWidth: 560 }).padding(Space.s8).borderRadius(Radius.r8).backgroundColor('#E61C1C1E')
        .margin({ bottom: this.controlsBottom + 8 })
    }
  }
}
