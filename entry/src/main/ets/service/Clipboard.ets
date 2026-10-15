import {
  abilityAccessCtrl, bundleManager, common, PermissionRequestResult, Permissions
} from '@kit.AbilityKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';

/**
 * 系统剪贴板读取（**门面**：把权限申请 + 授权检查 + 取数这三步盖成一个 `readText`）。
 *
 * `ohos.permission.READ_PASTEBOARD` 是 user_grant，所以在用户第一次点「粘贴」时才申请，
 * 不在启动时打扰。顺序是平台要求的，不能换：check → request → **hasData** → getData。
 * 先 `getData` 不查 `hasData` 会被 CodeLinter 的
 * `@correctness/paste-board-for-user-grant-check` 报出来；而且剪贴板里没东西时，
 * 授权弹窗本身就会失败。
 *
 * 取不到授权时抛 Error，由调用方决定怎么提示（提示文案属于界面，不属于这一层）。
 */
export class Clipboard {
  static async readText(context: common.UIAbilityContext): Promise<string> {
    const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let tokenId: number = 0;
    try {
      const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      tokenId = info.appInfo.accessTokenId;
    } catch (error) {
      console.error('bundle info failed: ' + String((error as BusinessError).code));
    }
    let granted: boolean = false;
    if (tokenId !== 0) {
      try {
        const status: abilityAccessCtrl.GrantStatus =
          await manager.checkAccessToken(tokenId, 'ohos.permission.READ_PASTEBOARD' as Permissions);
        granted = status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      } catch (error) {
        console.error('checkAccessToken failed: ' + String((error as BusinessError).code));
      }
    }
    if (!granted) {
      const result: PermissionRequestResult =
        await manager.requestPermissionsFromUser(context, ['ohos.permission.READ_PASTEBOARD' as Permissions]);
      granted = result.authResults.length > 0
        && result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    }
    if (!granted) {
      throw new Error('未获得剪贴板读取权限');
    }
    const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    if (!await board.hasData()) {
      return '';
    }
    const data: pasteboard.PasteData = await board.getData();
    return data.getPrimaryText();
  }
}
