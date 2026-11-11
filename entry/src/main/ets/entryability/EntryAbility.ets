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
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { safeArea } from '../service/SafeAreaController';
import { DownloadStore } from '../service/DownloadStore';
import { ShareInbox } from '../service/ShareInbox';
import { WidgetLaunch } from '../service/WidgetLaunch';
import { PreviewReadingStore } from '../service/PreviewReadingStore';
import { PREVIEW_LIFECYCLE } from '../model/PreviewLifecycle';
import { LIBRARY_CATALOG } from '../service/LibraryCatalog';
import { FloatDownload } from '../service/FloatDownload';
import { appLock } from '../service/AppLockService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  /** 主窗口引用；避让区与键盘监听由 SafeAreaController 统一持有。 */
  private mainWindow: window.Window | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PreviewReadingStore.initialize(this.context.filesDir);
    LIBRARY_CATALOG.initialize(this.context.filesDir).catch((): void => {
      // Index listens to the catalog and presents its recoverable read error.
    });
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
    ShareInbox.receive(want);
    WidgetLaunch.receive(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    ShareInbox.receive(want);
    WidgetLaunch.receive(want);
  }

  onDestroy(): void {
    FloatDownload.stop();
    PREVIEW_LIFECYCLE.setForeground(false);
    PreviewReadingStore.flush();
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
   * the layout adapts to any device. HDS handles the title bar's top safe area;
   * SafeAreaController supplies live content and floating tab clearances.
   */
  private publishInsets(windowStage: window.WindowStage): void {
    try {
      const main: window.Window = windowStage.getMainWindowSync();
      EntryAbility.applyFullScreen(main);
      this.mainWindow = main;
      safeArea.attach(main);
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
    safeArea.refresh();
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    if (this.mainWindow !== undefined) {
      try {
        safeArea.detach();
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'Failed to unwatch the window. Cause: %{public}s', JSON.stringify(err));
      }
      this.mainWindow = undefined;
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    appLock.onForeground();
    PREVIEW_LIFECYCLE.setForeground(true);
    DownloadStore.setForeground(true);
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    appLock.onBackground();
    PREVIEW_LIFECYCLE.setForeground(false);
    PreviewReadingStore.flush();
    DownloadStore.setForeground(false);
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
