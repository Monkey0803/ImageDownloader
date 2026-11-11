import { display } from '@kit.ArkUI';
import { Layout, Space } from './Tokens';
import { safeArea, SafeAreaController } from '../service/SafeAreaController';

/**
 * 页面几何：安全区 + 标题栏 / 页签栏 / 滚动阈值。
 *
 * 原先这四五个加法散在 Index 里（topInset / tabBarSpace / bottomInset / topThreshold），
 * 每个页面自己拼一遍内边距，改一处要同时改四处 padding。现在统一成静态方法：
 * 输入只有「安全区高度 + 这个页面要预留多少额外空间」，输出是可直接填进 `padding` 的数字。
 *
 * 页面高度优先读取窗口当前值，旋转或分屏时随控制器更新；窗口尚未绑定时回退到屏幕高度。
 */
export class ScreenMetrics {
  /** 窗口尚未绑定时，默认屏幕高度（vp）只读取并缓存一次。 */
  private static cachedHeight: number = 0;

  static height(): number {
    if (safeArea.windowHeightVp > 0) { return safeArea.windowHeightVp; }
    if (ScreenMetrics.cachedHeight <= 0) {
      const info: display.Display = display.getDefaultDisplaySync();
      ScreenMetrics.cachedHeight = info.height / info.densityPixels;
    }
    return ScreenMetrics.cachedHeight;
  }

  /**
   * 滚动内容的上内边距。
   *
   * `tall` 指的是「标题栏是二层」的页面（发现 / 任务 / 图库），它们的标题占位更高，
   * 设置页是一层。数值都来自 design tokens，不在页面里写死。
   */
  static topInset(safeTop: number, tall: boolean): number {
    return safeTop + (tall ? Layout.tbLayerSecondary : Layout.tbLayerNormal) + Layout.tbGap;
  }

  /**
   * 发现页的上内边距：标题栏里挂的是地址胶囊（`Layout.tbAddressBar`），
   * 不是「标题 + 副标题」那一层，所以不能沿用 tbLayerSecondary 的 67。
   *
   * 标题栏是覆盖在内容之上的浮层，胶囊高度与标题栏自身留白一旦和页面占位对不上，
   * 紧贴胶囊下方的第一个内容（工具栏、扩张状态文字）就会被压进标题栏覆盖区。
   */
  static topInsetForDiscover(safeTop: number): number {
    return safeTop + Layout.tbAddressBar + Layout.tbTitlePad * 2 + Layout.tbGap;
  }

  /**
   * 标题栏里还挂了一层自定义控件（图库页的分段 + 搜索）时的上内边距。
   *
   * 标题栏是覆盖在内容之上的浮层，多出来的这段高度不会自动把滚动内容推下去，
   * 只能由页面的 `contentStartOffset` 让出来。
   */
  static topInsetWithHeader(safeTop: number, header: number): number {
    return ScreenMetrics.topInset(safeTop, true) + header + Layout.tbGap;
  }

  /** 浮动页签栏连安全区一共占掉多少高度。 */
  static tabBarSpace(safeBottom: number): number {
    return SafeAreaController.contentBottom(Layout.tabBarHeight + Layout.tabBarTopPad, safeBottom);
  }

  /**
   * 滚动内容的下内边距：页签栏 + 一个间距 + 这个页面自己的额外预留
   * （发现页要再让开选择条与握姿胶囊）。
   */
  static bottomInset(safeBottom: number, extra: number): number {
    return ScreenMetrics.tabBarSpace(safeBottom) + Space.s12 + extra;
  }

  static sideInset(safeSide: number): number {
    return Math.max(Layout.pagePad, safeSide + Space.s8);
  }

  /**
   * 「返回顶部」按钮浮出来的滚动阈值。
   *
   * 取半屏：再少一点的话，只是滑一下也会冒出来，反而挡视线；半屏时「上面还有东西没看完」
   * 已经是很确定的判断了。
   */
  static scrollThreshold(): number {
    return ScreenMetrics.height() * 0.5;
  }
}

/**
 * 安全区与键盘高度的全局单例（**V2 写法**）。
 *
 * V1 的做法是 `AppStorage` + `@StorageProp`，让七个组件各自订阅这份全局状态。
 * 但 `@StorageProp` 在 V2 里是**非法**的 —— 实测报 10905339：
 * `The '@StorageProp' decorator can only be used in a 'struct' decorated with '@Component'.`
 * V2 的等价做法是 `SafeAreaController` 的 `@ObservedV2` 单例：窗口监听由 service 持有，
 * 组件在 build 里读 `@Trace` 字段就会自动订阅、自动刷新，不需要层层透传。
 *
 * 保留 `SCREEN_INSETS` 别名给现有页面；它与 `safeArea` 是同一个实例。
 */
/** Compatibility alias for existing pages; the service owns the single live instance. */
export const SCREEN_INSETS: SafeAreaController = safeArea;
