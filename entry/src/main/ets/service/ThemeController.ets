import { common, ConfigurationConstant } from '@kit.AbilityKit';

/**
 * 深浅色模式的应用。
 *
 * 「设置里的三个档位」到「系统 ColorMode」是一个纯映射，原先写在 Index 里。
 * 抽出来的意义是：这个映射只有一处，任何页面改主题都走同一条路。
 */
export class ThemeController {
  /** 'system' | 'light' | 'dark' → 系统 ColorMode；认不出的值一律当「跟随系统」。 */
  static colorModeOf(mode: string): ConfigurationConstant.ColorMode {
    if (mode === 'dark') {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    if (mode === 'light') {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }

  /**
   * 立刻把主题刷到应用级。
   *
   * 平台在极少数情况下会拒绝（例如 ability 还没起来），失败只意味着这次没生效，
   * 下一次进设置页再选一次即可，所以吞掉异常不往上抛 —— 弹一个「切换主题失败」对用户没用。
   */
  static apply(context: common.UIAbilityContext, mode: string): void {
    try {
      context.getApplicationContext().setColorMode(ThemeController.colorModeOf(mode));
    } catch (error) {
      console.error('setColorMode failed: ' + String(error));
    }
  }
}
