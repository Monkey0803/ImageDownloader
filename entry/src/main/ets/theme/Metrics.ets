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

/**
 * 安全区与键盘高度的全局单例（**V2 写法**）。
 *
 * V1 的做法是 `AppStorage` + `@StorageProp`，让七个组件各自订阅这份全局状态。
 * 但 `@StorageProp` 在 V2 里是**非法**的 —— 实测报 10905339：
 * `The '@StorageProp' decorator can only be used in a 'struct' decorated with '@Component'.`
 * V2 的等价做法就是这个 `@ObservedV2` 单例：`EntryAbility` 直接写 `@Trace` 字段，
 * 组件在 build 里读它就会自动订阅、自动刷新，**不需要层层透传**
 * （而这正是当初改用全局态的理由）。
 *
 * 过渡期 `EntryAbility` **两边都写**：`AppStorage` 留给还没迁到 V2 的组件，
 * 等最后一个 `@StorageProp` 消失后，把那一半连同 7 处声明一起删掉。
 */
@ObservedV2
export class ScreenInsets {
  /** 状态栏高度（vp）：浮动标题栏据此下移。 */
  @Trace safeTop: number = 0;
  /** 底部导航条高度（vp）：浮动页签栏据此上抬。 */
  @Trace safeBottom: number = 0;
  /** 软键盘高度（vp），0 表示没有键盘；Toast 据此决定压在键盘上沿还是贴底。 */
  @Trace keyboardHeight: number = 0;
}

/** 全局唯一实例：`EntryAbility` 写，组件在 build 里读。 */
export const SCREEN_INSETS: ScreenInsets = new ScreenInsets();
