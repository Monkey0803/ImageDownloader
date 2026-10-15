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
import { SCREEN_INSETS } from '../theme/Metrics';
import { DownloadStore } from '../service/DownloadStore';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  /**
   * 主窗口引用与键盘监听的注销函数。
   *
   * `main.on('avoidAreaChange', ...)` 在 `onWindowStageDestroy` 时没有 `off` 的话，
   * 回调会留在已销毁的窗口上：它往 AppStorage 写的是全局状态，一次不会立刻出事，
   * 但窗口重建（多窗口 / 分屏）时会叠加多份监听，键盘高度被写多次。
   */
  private mainWindow: window.Window | undefined = undefined;
  private keyboardWatch: ((data: window.AvoidAreaOptions) => void) | undefined = undefined;

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
    // 页面已经不在了，但商店里可能还挂着「待存相册」的防抖定时器与合并写盘的定时器：
    // 前者会在别的应用上弹系统确认框，后者会让最后一次进度没落盘。
    DownloadStore.shutdown();
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
    this.publishInsets(windowStage);
  }

  /**
   * Let the page draw under the system bars, then publish the inset heights.
   *
   * The insets are read from the live window instead of being hard-coded, so
   * the layout adapts to any device. Full-screen layout is what the design
   * assumes: the floating title bar owns the top edge and pads itself by
   * `safeTop`, and the tab bar pads itself by `safeBottom`.
   */
  private publishInsets(windowStage: window.WindowStage): void {
    try {
      const main: window.Window = windowStage.getMainWindowSync();
      EntryAbility.applyFullScreen(main);
      this.watchKeyboard(main);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to read the main window. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 把软键盘的高度也发到 AppStorage。
   *
   * 键盘弹起时窗口会被压矮（默认 avoid 模式是 resize），页面里所有「贴底」的东西
   * 都会跟着往上跳 —— toast 就是这么跑到屏幕中部的。页面拿到这个高度才能判断
   * 「现在有没有键盘」，从而把 toast 压在键盘上沿而不是浮在内容中间。
   */
  private watchKeyboard(main: window.Window): void {
    this.mainWindow = main;
    this.keyboardWatch = (data: window.AvoidAreaOptions): void => {
      if (data.type !== window.AvoidAreaType.TYPE_KEYBOARD) {
        return;
      }
      const density: number = display.getDefaultDisplaySync().densityPixels;
      const height: number = data.area.bottomRect.height / density;
      AppStorage.setOrCreate('keyboardHeight', height);
      SCREEN_INSETS.keyboardHeight = height;
    };
    main.on('avoidAreaChange', this.keyboardWatch);
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
      SCREEN_INSETS.safeTop = top;
      SCREEN_INSETS.safeBottom = bottom;
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to read the window insets. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    if (this.mainWindow !== undefined && this.keyboardWatch !== undefined) {
      try {
        this.mainWindow.off('avoidAreaChange', this.keyboardWatch);
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'Failed to unwatch the keyboard. Cause: %{public}s', JSON.stringify(err));
      }
      this.keyboardWatch = undefined;
      this.mainWindow = undefined;
    }
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