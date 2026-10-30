import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

/**
 * 预览页系统栏控制。
 *
 * 大图预览需要真正贴边：进入预览时隐藏状态栏、三键导航栏和手势条，退出时恢复。
 * 同时把系统栏内容切成白色，避免浅色主题下深色图标压在深色照片上不可见。
 *
 * 用 owner 集合而不是简单计数：发现页预览与 Viewer 可能叠加、也可能交错退出，只有最后
 * 一个 owner 离开时才恢复。窗口调用串行化，避免快速进出时旧请求晚到覆盖新状态。
 */
export class SystemBars {
  private static owners: Set<string> = new Set<string>();
  private static pending: Promise<void> = Promise.resolve();
  private static saved: window.SystemBarProperties | undefined = undefined;

  /** 进入沉浸式预览：第一个 owner 负责保存内容色、切白并隐藏系统栏。 */
  static enter(owner: string, context: common.UIAbilityContext): void {
    const first: boolean = SystemBars.owners.size === 0;
    SystemBars.owners.add(owner);
    if (!first) {
      return;
    }
    SystemBars.pending = SystemBars.pending.then(async (): Promise<void> => {
      try {
        const target: window.Window = await window.getLastWindow(context);
        SystemBars.saved = target.getWindowSystemBarProperties();
        await target.setWindowSystemBarProperties({
          statusBarContentColor: '#FFFFFFFF',
          navigationBarContentColor: '#FFFFFFFF'
        });
        await target.setWindowSystemBarEnable([]);
        await SystemBars.setBar(target, 'status', false);
        await SystemBars.setBar(target, 'navigation', false);
        await SystemBars.setBar(target, 'navigationIndicator', false);
      } catch (error) {
      }
    }).catch((): void => {});
  }

  /** 离开预览：最后一个 owner 离开时恢复系统栏与进入前的内容色。 */
  static leave(owner: string, context: common.UIAbilityContext): void {
    SystemBars.owners.delete(owner);
    if (SystemBars.owners.size > 0) {
      return;
    }
    SystemBars.pending = SystemBars.pending.then(async (): Promise<void> => {
      const saved: window.SystemBarProperties | undefined = SystemBars.saved;
      SystemBars.saved = undefined;
      try {
        const target: window.Window = await window.getLastWindow(context);
        await target.setWindowSystemBarEnable(['status', 'navigation']);
        await SystemBars.setBar(target, 'status', true);
        await SystemBars.setBar(target, 'navigation', true);
        await SystemBars.setBar(target, 'navigationIndicator', true);
        if (saved !== undefined) {
          await target.setWindowSystemBarProperties({
            statusBarContentColor: saved.statusBarContentColor,
            navigationBarContentColor: saved.navigationBarContentColor
          });
        }
      } catch (error) {
      }
    }).catch((): void => {});
  }

  /** 个别设备/导航模式不支持某一类系统栏，单独吞掉失败，不影响其它栏。 */
  private static async setBar(target: window.Window, name: window.SpecificSystemBar,
    visible: boolean): Promise<void> {
    try {
      await target.setSpecificSystemBarEnabled(name, visible, true);
    } catch (error) {
    }
  }
}
