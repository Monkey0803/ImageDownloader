import { display } from '@kit.ArkUI';
import { Layout, Space } from './Tokens';

/**
 * 页面几何：安全区 + 标题栏 / 页签栏 / 滚动阈值。
 *
 * 原先这四五个加法散在 Index 里（topInset / tabBarSpace / bottomInset / topThreshold），
 * 每个页面自己拼一遍内边距，改一处要同时改四处 padding。现在统一成静态方法：
 * 输入只有「安全区高度 + 这个页面要预留多少额外空间」，输出是可直接填进 `padding` 的数字。
 *
 * 全是纯函数（屏幕高度只读一次缓存起来），所以 screen 组件在 build 里直接调也安全。
 */
export class ScreenMetrics {
  /** 屏幕高度（vp）只算一次：`getDefaultDisplaySync` 每次调用都要过一遍系统接口。 */
  private static cachedHeight: number = 0;

  static height(): number {
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

  /** 浮动页签栏连安全区一共占掉多少高度。 */
  static tabBarSpace(safeBottom: number): number {
    return Layout.tabBarHeight + Layout.tabBarTopPad + safeBottom;
  }

  /**
   * 滚动内容的下内边距：页签栏 + 一个间距 + 这个页面自己的额外预留
   * （发现页要再让开选择条与握姿胶囊）。
   */
  static bottomInset(safeBottom: number, extra: number): number {
    return ScreenMetrics.tabBarSpace(safeBottom) + Space.s12 + extra;
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
