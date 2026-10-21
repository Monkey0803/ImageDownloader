import { common } from '@kit.AbilityKit';
import { DownloadItem } from '../model/Models';

/**
 * ViewModel 反向依赖界面的唯一出口（**端口 / 中介者**）。
 *
 * 五个 ViewModel 都需要「弹一句提示」「拿 UIAbilityContext」「推预览页」「切页签」
 * 「弹确认框」这几件只有组件才做得了的事。让它们各自持有一堆回调会重复五遍，也会让
 * 「谁提供 UI 能力」这件事散落各处；这里把出口收成一个对象，由页面在 `attach` 时注入。
 *
 * 默认实现全是**安全的空操作**（`context` 除外，它在没注入时明确抛错）：这样 ViewModel
 * 在单元测试或没界面的场景里也能构造，不会因为少注一个回调就崩在运行时。
 */
export class UiPort {
  /** 弹一句 2.6 秒的提示；空串表示不吭声。 */
  say: (text: string) => void = (text: string): void => {
  };

  /** 拿 UIAbilityContext（文件操作、目录选择、主题切换要用）。 */
  context: () => common.UIAbilityContext = (): common.UIAbilityContext => {
    throw new Error('UiPort.context 尚未注入');
  };

  /** 推大图预览页；`rename` 决定那边给不给改名，`siblings` 是左右滑动的那一批。 */
  openViewer: (item: DownloadItem, rename: boolean, siblings: string[]) => void =
    (item: DownloadItem, rename: boolean, siblings: string[]): void => {
    };

  /** 切底部页签。 */
  switchTab: (index: number) => void = (index: number): void => {
  };

  /** 发现页的结果与全屏浏览视图共用一个 Web 控制器。 */
  showBrowser: () => void = (): void => {
  };
  showResults: () => void = (): void => {
  };

  /** 跳到图库并按关键词定位一条记录（任务页「在图中定位」用）。 */
  focusLibrary: (name: string) => void = (name: string): void => {
  };

  /** 危险操作前的二次确认；`onConfirm` 只在用户点了确认按钮后调用。 */
  confirm: (title: string, message: string, confirmText: string, onConfirm: () => void) => void =
    (title: string, message: string, confirmText: string, onConfirm: () => void): void => {
    };
}
