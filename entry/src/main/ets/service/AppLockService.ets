/*
 * AppLockService.ets — 应用锁（生物识别 / 锁屏口令）。
 *
 * 行为：
 * - 冷启动：如果开启应用锁，进入即锁定，并自动拉起一次认证；
 * - 后台：立即锁定并把界面盖住（应用切换器看不到验证码）；
 * - 回前台：离开时长小于「自动锁定间隔」时自动解锁，否则要求认证。
 *
 * 认证失败/取消不能把用户永久锁死；界面提供重试，设置页可以关闭应用锁，
 * 关闭应用锁同样需要认证（设备无任何可用凭证时保留确认后关闭的兜底）。
 */

import { common } from '@kit.AbilityKit';
import { userAuth } from '@kit.UserAuthenticationKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DownloadStore } from './DownloadStore';

export enum AppLockError {
  NONE = '',
  BIOMETRIC_UNAVAILABLE = 'BIOMETRIC_UNAVAILABLE',
  AUTH_FAILED = 'AUTH_FAILED'
}

const DOMAIN: number = 0x0000;
const TAG: string = 'AppLockService';

const ERR_CANCELED: number = 12500003;
const ERR_TYPE_NOT_SUPPORT: number = 12500005;
const ERR_TRUST_LEVEL_NOT_SUPPORT: number = 12500006;
const ERR_NOT_ENROLLED: number = 12500010;
const ERR_CANCELED_FROM_WIDGET: number = 12500011;

@ObservedV2
export class AppLockService {
  /** 是否显示遮罩。默认 true，避免设置加载前的一帧泄露验证码。 */
  @Trace locked: boolean = true;
  /** 设置是否已经加载完成。 */
  @Trace ready: boolean = false;
  /** 认证进行中。 */
  @Trace authenticating: boolean = false;
  /** 失败原因，取值见 AppLockError；NONE 表示无错误。 */
  @Trace errorCode: AppLockError = AppLockError.NONE;

  private lastBackgroundAt: number = 0;
  private instance: userAuth.UserAuthInstance | undefined = undefined;
  /** 自动解锁所需的应用上下文。 */
  private appContext: common.Context | undefined = undefined;
  /** UIAbility 是否在前台；后台锁定时不允许自动拉起认证。 */
  private active: boolean = false;
  /** 每个锁定期只自动尝试一次，失败后由用户点「解锁」重试。 */
  private autoUnlockAttempted: boolean = false;
  /** 本次切后台前是否已解锁：未解锁就离开的用户返回时不能被自动锁定间隔放行。 */
  private wasUnlockedBeforeBackground: boolean = false;
  /** 认证代次：取消或新认证后丢弃旧实例的回调。 */
  private authSeq: number = 0;
  private pendingResolve: ((ok: boolean) => void) | undefined = undefined;

  /** 缓存应用上下文；设置加载前调用，供自动解锁发起认证。 */
  attach(context: common.Context): void {
    this.appContext = context;
  }

  /** 设置加载完成后调用。 */
  afterSettingsLoaded(): void {
    this.ready = true;
    this.locked = DownloadStore.appLockEnabled;
    this.autoUnlockAttempted = false;
    this.tryAutoUnlock();
  }

  refreshFromSettings(): void {
    if (!DownloadStore.appLockEnabled) {
      this.locked = false;
      this.errorCode = AppLockError.NONE;
    }
  }

  /** 立即锁定（关闭应用锁时不会生效）。 */
  lockNow(): void {
    if (DownloadStore.appLockEnabled) {
      this.locked = true;
      this.errorCode = AppLockError.NONE;
      this.autoUnlockAttempted = false;
      this.tryAutoUnlock();
    }
  }

  /** 设置页关闭应用锁后调用。 */
  markUnlocked(): void {
    this.locked = false;
    this.errorCode = AppLockError.NONE;
    this.autoUnlockAttempted = false;
  }

  /** 关闭应用锁：有凭证时必须认证；无凭证时由调用方先取得明确确认。 */
  async disable(context: common.Context, confirmedWithoutCredential: boolean = false): Promise<boolean> {
    if (!DownloadStore.appLockEnabled) { return true; }
    if (this.canAuthenticate()) {
      if (!await this.authenticate(context)) { return false; }
    } else if (!confirmedWithoutCredential) {
      return false;
    }
    DownloadStore.setAppLockEnabled(false);
    this.markUnlocked();
    return true;
  }

  onBackground(): void {
    this.active = false;
    this.autoUnlockAttempted = false;
    this.wasUnlockedBeforeBackground = !this.locked;
    // 后台不能继续停留在系统认证界面上；取消后回到前台由 onForeground 决定是否重试。
    this.cancelAuth();
    if (!this.ready || !DownloadStore.appLockEnabled) {
      return;
    }
    this.lastBackgroundAt = Date.now();
    this.locked = true;
  }

  onForeground(): void {
    this.active = true;
    if (!this.ready || !DownloadStore.appLockEnabled || !this.locked) {
      return;
    }
    const minutes: number = DownloadStore.autoLockMinutes;
    if (minutes > 0 && this.lastBackgroundAt > 0) {
      const awayMs: number = Date.now() - this.lastBackgroundAt;
      if (awayMs < minutes * 60000 && this.wasUnlockedBeforeBackground) {
        this.locked = false;
        this.errorCode = AppLockError.NONE;
        return;
      }
    }
    this.tryAutoUnlock();
  }

  /** 设备是否存在可用于本应用认证等级的凭证（人脸 / 指纹 / 锁屏口令）。 */
  canAuthenticate(): boolean {
    const types: userAuth.UserAuthType[] = [
      userAuth.UserAuthType.FACE,
      userAuth.UserAuthType.FINGERPRINT,
      userAuth.UserAuthType.PIN
    ];
    for (let i: number = 0; i < types.length; i += 1) {
      try {
        userAuth.getAvailableStatus(types[i], userAuth.AuthTrustLevel.ATL3);
        return true;
      } catch (err) {
        // 该类型未注册或不支持：继续检查下一种凭证。
      }
    }
    return false;
  }

  /** 只做认证，不改 locked；供解锁与「关闭应用锁」共用。 */
  authenticate(context: common.Context): Promise<boolean> {
    if (this.authenticating) {
      return Promise.resolve(false);
    }
    this.authenticating = true;
    this.errorCode = AppLockError.NONE;
    const seq: number = ++this.authSeq;
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      this.pendingResolve = resolve;
      try {
        const challenge: Uint8Array = cryptoFramework.createRandom().generateRandomSync(16).data;
        const authParam: userAuth.AuthParam = {
          challenge: challenge,
          authType: [userAuth.UserAuthType.PIN, userAuth.UserAuthType.FACE, userAuth.UserAuthType.FINGERPRINT],
          authTrustLevel: userAuth.AuthTrustLevel.ATL3
        };
        const widgetParam: userAuth.WidgetParam = {
          title: '解锁图片下载管理'
        };
        const instance: userAuth.UserAuthInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
        this.instance = instance;
        const callback: userAuth.IAuthCallback = {
          onResult: (result: userAuth.UserAuthResult) => {
            this.handleAuthResult(seq, instance, result.result);
          }
        };
        instance.on('result', callback);
        instance.start();
      } catch (err) {
        const error: BusinessError = err as BusinessError;
        hilog.warn(DOMAIN, TAG, 'authenticate failed: %{public}d', error.code);
        this.finishAuth(seq, false, error.code);
      }
    });
  }

  /** 发起认证；成功后解锁。 */
  async unlock(context: common.Context): Promise<void> {
    if (!DownloadStore.appLockEnabled) {
      this.markUnlocked();
      return;
    }
    if (this.authenticating) {
      return;
    }
    const ok: boolean = await this.authenticate(context);
    // 认证回调与切后台可能交错：后台成功也不能把遮罩撤掉，避免应用切换器泄露内容。
    if (ok && this.active) {
      this.markUnlocked();
    }
  }

  private handleAuthResult(seq: number, instance: userAuth.UserAuthInstance, code: number): void {
    if (seq !== this.authSeq) {
      return;
    }
    try {
      instance.off('result');
    } catch (err) {
      // 已经解除订阅：继续按结果收尾。
    }
    this.finishAuth(seq, code === userAuth.UserAuthResultCode.SUCCESS, code);
  }

  private finishAuth(seq: number, ok: boolean, code: number): void {
    if (seq !== this.authSeq) {
      return;
    }
    this.authenticating = false;
    this.instance = undefined;
    if (ok) {
      this.errorCode = AppLockError.NONE;
    } else if (code === ERR_NOT_ENROLLED || code === ERR_TYPE_NOT_SUPPORT || code === ERR_TRUST_LEVEL_NOT_SUPPORT) {
      this.errorCode = AppLockError.BIOMETRIC_UNAVAILABLE;
    } else if (code === ERR_CANCELED || code === ERR_CANCELED_FROM_WIDGET) {
      // 用户主动取消：不再显示红色错误，遮罩保留并允许手动重试。
      this.errorCode = AppLockError.NONE;
    } else {
      this.errorCode = AppLockError.AUTH_FAILED;
    }
    const resolve: ((ok: boolean) => void) | undefined = this.pendingResolve;
    this.pendingResolve = undefined;
    if (resolve !== undefined) {
      resolve(ok);
    }
  }

  /** 取消在途认证并让等待方立即收到失败，避免 authenticating 卡死。 */
  private cancelAuth(): void {
    this.authSeq += 1;
    const instance: userAuth.UserAuthInstance | undefined = this.instance;
    this.instance = undefined;
    this.authenticating = false;
    this.errorCode = AppLockError.NONE;
    if (instance !== undefined) {
      try {
        instance.off('result');
      } catch (err) {
        // 即使解除订阅失败，也仍要取消系统认证界面。
      }
      try {
        instance.cancel();
      } catch (err) {
        // 已结束的实例无法取消：忽略即可。
      }
    }
    const resolve: ((ok: boolean) => void) | undefined = this.pendingResolve;
    this.pendingResolve = undefined;
    if (resolve !== undefined) {
      resolve(false);
    }
  }

  /** 遮罩出现时自动拉起一次认证；只在前后台、设置加载完成后触发。 */
  private tryAutoUnlock(): void {
    const context: common.Context | undefined = this.appContext;
    if (!this.active || !this.ready || !this.locked || !DownloadStore.appLockEnabled) {
      return;
    }
    if (this.authenticating || this.autoUnlockAttempted || context === undefined) {
      return;
    }
    this.autoUnlockAttempted = true;
    this.unlock(context).catch(() => {
    });
  }

}

export const appLock: AppLockService = new AppLockService();
