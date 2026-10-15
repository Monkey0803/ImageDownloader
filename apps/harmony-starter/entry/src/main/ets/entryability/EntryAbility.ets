import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'starter', 'onCreate bundleName: %{public}s', want.bundleName ?? '');
    try {
      /* Follow the system light/dark setting. The design system's "跟随系统" default
         depends on this: the HAR ships resources/dark, and the platform swaps it in
         only when the app does not pin a colour mode of its own. */
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'starter', 'setColorMode failed: %{public}s', JSON.stringify(err));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'starter', '%{public}s', 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'starter', 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'starter', 'loadContent ok');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'starter', '%{public}s', 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'starter', '%{public}s', 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'starter', '%{public}s', 'onBackground');
  }
}
