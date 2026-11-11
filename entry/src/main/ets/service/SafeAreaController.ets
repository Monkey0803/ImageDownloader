import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Layout } from '../theme/Tokens';
import { windowInsets, WindowInsets } from '../util/WindowAvoidPolicy';

/** Live full-screen insets owned by the main window. Pages only read traced values. */
@ObservedV2
export class SafeAreaController {
  @Trace safeTop: number = 0;
  @Trace safeBottom: number = 0;
  @Trace safeLeft: number = 0;
  @Trace safeRight: number = 0;
  @Trace keyboardHeight: number = 0;
  @Trace contentTopInsetVp: number = 0;
  @Trace contentBottomInsetVp: number = 0;
  @Trace windowHeightVp: number = 0;

  private mainWindow: window.Window | undefined = undefined;
  private avoidAreaWatch: ((data: window.AvoidAreaOptions) => void) | undefined = undefined;

  /** For content that intentionally extends beneath the HDS mini title bar. */
  static contentTop(top: number): number {
    return top + Layout.tbLayerNormal;
  }

  static contentBottom(tabClearance: number, bottom: number): number {
    return tabClearance + bottom;
  }

  static navBottom(indicator: number, systemBottom: number): number {
    return Math.max(indicator, systemBottom);
  }

  attach(main: window.Window): void {
    this.detach();
    this.mainWindow = main;
    this.refresh();
    this.avoidAreaWatch = (data: window.AvoidAreaOptions): void => {
      if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
        this.keyboardHeight = main.getUIContext().px2vp(Math.max(0, data.area.bottomRect.height));
      } else {
        this.refresh();
      }
    };
    try { main.on('avoidAreaChange', this.avoidAreaWatch); }
    catch (error) { hilog.error(0x0000, 'SafeAreaController', 'avoidAreaChange listen failed'); }
  }

  detach(): void {
    if (this.mainWindow !== undefined && this.avoidAreaWatch !== undefined) {
      try { this.mainWindow.off('avoidAreaChange', this.avoidAreaWatch); }
      catch (error) { hilog.error(0x0000, 'SafeAreaController', 'avoidAreaChange off failed'); }
    }
    this.mainWindow = undefined;
    this.avoidAreaWatch = undefined;
    this.keyboardHeight = 0;
  }

  private readArea(main: window.Window, type: window.AvoidAreaType): window.AvoidArea | undefined {
    try { return main.getWindowAvoidArea(type); }
    catch (error) { return undefined; }
  }

  refresh(): void {
    const main: window.Window | undefined = this.mainWindow;
    if (main === undefined) { return; }
    try {
      const system: window.AvoidArea | undefined = this.readArea(main, window.AvoidAreaType.TYPE_SYSTEM);
      const indicator: window.AvoidArea | undefined =
        this.readArea(main, window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const gesture: window.AvoidArea | undefined =
        this.readArea(main, window.AvoidAreaType.TYPE_SYSTEM_GESTURE);
      const cutout: window.AvoidArea | undefined = this.readArea(main, window.AvoidAreaType.TYPE_CUTOUT);
      const rect: window.Rect = main.getWindowProperties().windowRect;
      const px2vp: (value: number) => number = (value: number): number => main.getUIContext().px2vp(value);
      const systemTop: number = system?.visible ? system.topRect.height : 0;
      const systemBottom: number = system?.visible ? system.bottomRect.height : 0;
      const indicatorBottom: number = indicator?.visible ? indicator.bottomRect.height : 0;
      const gestureBottom: number = gesture?.visible ? gesture.bottomRect.height : 0;
      const cutoutTop: number = cutout?.visible && cutout.topRect.height > 0
        ? cutout.topRect.top + cutout.topRect.height : 0;
      const cutoutBottom: number = cutout?.visible && cutout.bottomRect.height > 0
        ? rect.height - cutout.bottomRect.top : 0;
      const cutoutLeft: number = cutout?.visible && cutout.leftRect.width > 0
        ? cutout.leftRect.left + cutout.leftRect.width : 0;
      const cutoutRight: number = cutout?.visible && cutout.rightRect.width > 0
        ? rect.width - cutout.rightRect.left : 0;
      const insets: WindowInsets = windowInsets(systemTop,
        SafeAreaController.navBottom(indicatorBottom, systemBottom), gestureBottom,
        cutoutTop, cutoutBottom, cutoutLeft, cutoutRight, 1);
      this.safeTop = px2vp(insets.top);
      this.safeBottom = px2vp(insets.bottom);
      this.safeLeft = px2vp(insets.left);
      this.safeRight = px2vp(insets.right);
      this.contentTopInsetVp = SafeAreaController.contentTop(this.safeTop);
      this.contentBottomInsetVp = SafeAreaController.contentBottom(
        Layout.tabBarHeight + Layout.tabBarTopPad, this.safeBottom);
      this.windowHeightVp = px2vp(rect.height);
    } catch (error) {
      // Keep the last valid geometry while the window is being rotated or resized.
      hilog.error(0x0000, 'SafeAreaController', 'refresh window insets failed');
    }
  }
}

export const safeArea: SafeAreaController = new SafeAreaController();
