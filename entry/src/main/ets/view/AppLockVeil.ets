import { common } from '@kit.AbilityKit';
import { appLock, AppLockError } from '../service/AppLockService';
import { Palette, Radius, Space, Font } from '../theme/Tokens';

/** 覆盖当前页面，直到系统凭证认证通过。 */
@ComponentV2
export struct AppLockVeil {
  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private errorText(): string {
    if (appLock.errorCode === AppLockError.BIOMETRIC_UNAVAILABLE) {
      return '设备未设置可用的人脸、指纹或锁屏口令';
    }
    return appLock.errorCode === AppLockError.AUTH_FAILED ? '认证失败，请重试' : '';
  }

  private confirmRecovery(): void {
    const available: boolean = appLock.canAuthenticate();
    this.getUIContext().showAlertDialog({
      title: '关闭应用锁',
      message: available
        ? '关闭应用锁仍需通过设备认证。'
        : '设备没有可用的认证凭证。确认关闭应用锁后，打开应用将不再验证身份。',
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: { value: '继续', action: (): void => {
        appLock.disable(this.context(), !available).catch((): void => {});
      } }
    });
  }

  build() {
    Column({ space: Space.s16 }) {
      Text('🔒').fontSize(48)
      Text('应用已锁定').fontSize(Font.title).fontWeight(FontWeight.Bold)
        .fontColor(Palette.fontPrimary)
      Text('使用人脸、指纹或锁屏口令解锁')
        .fontSize(Font.aux).fontColor(Palette.fontSecondary)
        .textAlign(TextAlign.Center)
      if (!appLock.ready) {
        LoadingProgress().width(36).height(36)
      } else {
        if (appLock.errorCode !== AppLockError.NONE) {
          Text(this.errorText()).fontSize(Font.aux).fontColor(Palette.warning)
            .textAlign(TextAlign.Center)
        }
        Button('解锁', { type: ButtonType.Capsule })
          .width(220).height(48).backgroundColor(Palette.brand).fontColor(Palette.white)
          .enabled(!appLock.authenticating)
          .onClick((): void => { appLock.unlock(this.context()).catch((): void => {}); })
        Button('关闭应用锁', { type: ButtonType.Capsule })
          .width(220).height(44).backgroundColor(Palette.bg)
          .fontColor(Palette.fontSecondary)
          .borderRadius(Radius.full)
          .onClick((): void => { this.confirmRecovery(); })
      }
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .padding({ left: Space.s24, right: Space.s24 })
    .backgroundColor(Palette.bg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
