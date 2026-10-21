import { Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';

/** Ability 与已经挂载的发现页之间的一次性分享收件箱。 */
export class ShareInbox {
  private static pendingUrl: string = '';
  private static pendingError: string = '';
  private static listener: (() => void) | undefined = undefined;

  static subscribe(listener: () => void): void {
    ShareInbox.listener = listener;
  }

  static unsubscribe(listener: () => void): void {
    if (ShareInbox.listener === listener) { ShareInbox.listener = undefined; }
  }

  static take(): string {
    const url: string = ShareInbox.pendingUrl;
    ShareInbox.pendingUrl = '';
    return url;
  }

  static takeError(): string {
    const error: string = ShareInbox.pendingError;
    ShareInbox.pendingError = '';
    return error;
  }

  static validUrl(raw: string): string {
    const value: string = raw.trim();
    return /^https?:\/\/[^/?#\s]+(?:[/?#][^\s]*)?$/i.test(value) ? value : '';
  }

  static async receive(want: Want): Promise<void> {
    if (want.action !== 'ohos.want.action.sendData') { return; }
    let link: string = '';
    try {
      const data: systemShare.SharedData = await systemShare.getSharedData(want);
      const records: systemShare.SharedRecord[] = data.getRecords();
      if (records.length === 1 && typeof records[0].content === 'string') {
        link = ShareInbox.validUrl(records[0].content ?? '');
      }
    } catch (error) {
      // 只接收 Share Kit 的链接或纯文本记录；解析失败时不碰当前浏览状态。
    }
    if (link.length > 0) {
      ShareInbox.pendingUrl = link;
      ShareInbox.pendingError = '';
    } else {
      ShareInbox.pendingUrl = '';
      ShareInbox.pendingError = '分享内容不是单个网页或图片链接';
    }
    ShareInbox.listener?.();
  }
}
