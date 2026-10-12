/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', 'Ability onCreate, bundleName: %{public}s, launchReason: %{public}d',
      want.bundleName ?? '', launchParam.launchReason);
    try {
      // 预加载 ArkWeb 内核并关闭 web 调试，缩短首个页面加载耗时
      webview.WebviewController.initializeWebEngine();
      webview.WebviewController.setWebDebuggingAccess(false);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to initialize web engine. Cause: %{public}s', JSON.stringify(err));
    }
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
    EntryAbility.publishInsets(windowStage);
  }

  /**
   * Let the page draw under the system bars, then publish the inset heights.
   *
   * The insets are read from the live window instead of being hard-coded, so
   * the layout adapts to any device. Full-screen layout is what the design
   * assumes: the floating title bar owns the top edge and pads itself by
   * `safeTop`, and the tab bar pads itself by `safeBottom`.
   */
  private static publishInsets(windowStage: window.WindowStage): void {
    try {
      const main: window.Window = windowStage.getMainWindowSync();
      EntryAbility.applyFullScreen(main);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to read the main window. Cause: %{public}s', JSON.stringify(err));
    }
  }

  private static async applyFullScreen(main: window.Window): Promise<void> {
    try {
      await main.setWindowLayoutFullScreen(true);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to enable full-screen layout. Cause: %{public}s', JSON.stringify(err));
    }
    EntryAbility.storeInsets(main);
  }

  private static storeInsets(main: window.Window): void {
    try {
      const density: number = display.getDefaultDisplaySync().densityPixels;
      const top: number = main.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height / density;
      const bottom: number =
        main.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height / density;
      AppStorage.setOrCreate('safeTop', top);
      AppStorage.setOrCreate('safeBottom', bottom);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to read the window insets. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}