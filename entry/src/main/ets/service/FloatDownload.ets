import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { floatView } from '@kit.ArkUI';
import { DownloadStore } from './DownloadStore';
import { WidgetSnapshot } from '../widget/WidgetSnapshot';

@ObservedV2
export class FloatDownloadState {
  @Trace active: boolean = false;
  @Trace starting: boolean = false;
  @Trace count: string = '0';
  @Trace status: string = '暂无待处理任务';
  @Trace name: string = '';
  @Trace progress: string = '';
  @Trace percent: number = 0;
}

export const FLOAT_DOWNLOAD_STATE: FloatDownloadState = new FloatDownloadState();

/** One system-managed float view for the current Ability lifetime. */
export class FloatDownload {
  private static controller: floatView.FloatViewController | undefined = undefined;
  private static revision: number = 0;
  private static listener: () => void = (): void => { FloatDownload.sync(); };
  private static stateListener: (info: floatView.FloatViewStateChangeInfo) => void =
    (info: floatView.FloatViewStateChangeInfo): void => {
      if (info.state === floatView.FloatViewState.STARTED) {
        FLOAT_DOWNLOAD_STATE.active = true;
        FLOAT_DOWNLOAD_STATE.starting = false;
      } else if (info.state === floatView.FloatViewState.STOPPED) {
        FloatDownload.release();
      }
    };

  static supported(): boolean {
    try {
      return canIUse('SystemCapability.Window.SessionManager') && floatView.isFloatViewEnabled();
    } catch (error) { return false; }
  }

  static async start(context: common.UIAbilityContext): Promise<string> {
    if (FLOAT_DOWNLOAD_STATE.active || FLOAT_DOWNLOAD_STATE.starting) { return ''; }
    if (!FloatDownload.supported()) { return '本机暂不支持闪控窗'; }
    if (DownloadStore.downloads.length === 0 && DownloadStore.batches.length === 0) {
      return '暂无下载任务';
    }
    const revision: number = ++FloatDownload.revision;
    FLOAT_DOWNLOAD_STATE.starting = true;
    FloatDownload.sync();
    DownloadStore.subscribe(FloatDownload.listener);
    try {
      const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const permission: PermissionRequestResult = await manager.requestPermissionsFromUser(context,
        ['ohos.permission.FLOAT_VIEW' as Permissions]);
      if (revision !== FloatDownload.revision) { return ''; }
      if (permission.authResults.length === 0 ||
        permission.authResults[0] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        FloatDownload.release();
        return '未获得闪控窗权限';
      }
      if (revision !== FloatDownload.revision) { return ''; }
      const controller: floatView.FloatViewController = await floatView.create({
        context: context, templateType: floatView.FloatViewTemplateType.ROUNDED_RECTANGLE
      });
      if (revision !== FloatDownload.revision) {
        controller.stop().catch((): void => {});
        return '';
      }
      FloatDownload.controller = controller;
      controller.onStateChange(FloatDownload.stateListener);
      await controller.setUIContext('pages/DownloadFloatView');
      if (revision !== FloatDownload.revision) { return ''; }
      try { await controller.setWindowSize({ width: 800, height: 300 }); } catch (error) {}
      if (revision !== FloatDownload.revision) { return ''; }
      await controller.start();
      return '';
    } catch (error) {
      FloatDownload.release();
      return '闪控窗未能开启，请检查悬浮窗授权';
    }
  }

  static stop(): void {
    ++FloatDownload.revision;
    const controller: floatView.FloatViewController | undefined = FloatDownload.controller;
    FloatDownload.release();
    if (controller !== undefined) { controller.stop().catch((): void => {}); }
  }

  private static release(): void {
    DownloadStore.unsubscribe(FloatDownload.listener);
    if (FloatDownload.controller !== undefined) {
      try { FloatDownload.controller.offStateChange(FloatDownload.stateListener); } catch (error) {}
    }
    FloatDownload.controller = undefined;
    FLOAT_DOWNLOAD_STATE.active = false;
    FLOAT_DOWNLOAD_STATE.starting = false;
  }

  private static sync(): void {
    const snapshot: WidgetSnapshot = WidgetSnapshot.from(DownloadStore.downloads, DownloadStore.batches,
      DownloadStore.antiPeepEnabled);
    FLOAT_DOWNLOAD_STATE.count = snapshot.count;
    FLOAT_DOWNLOAD_STATE.name = snapshot.name;
    FLOAT_DOWNLOAD_STATE.status = snapshot.status;
    FLOAT_DOWNLOAD_STATE.progress = snapshot.progress;
    FLOAT_DOWNLOAD_STATE.percent = Number(snapshot.percent);
    if (snapshot.targetId.length > 0) { return; }
    let completed: number = 0;
    let failed: number = 0;
    for (const task of DownloadStore.downloads) {
      if (task.origin !== 'download' || task.taskHidden || task.batchId.length > 0) { continue; }
      if (task.status === 'completed') { completed++; }
      else if (task.status === 'failed') { failed++; }
    }
    for (const batch of DownloadStore.batches) {
      if (batch.status === 'completed') { completed++; }
      else if (batch.status === 'failed') { failed++; }
    }
    FLOAT_DOWNLOAD_STATE.status = failed > 0 ? '有 ' + failed.toString() + ' 项失败' : '任务已结束';
    FLOAT_DOWNLOAD_STATE.name = DownloadStore.antiPeepEnabled ? '任务名称已隐藏' :
      '完成 ' + completed.toString() + ' 项';
    FLOAT_DOWNLOAD_STATE.progress = '';
    FLOAT_DOWNLOAD_STATE.percent = 0;
  }
}
