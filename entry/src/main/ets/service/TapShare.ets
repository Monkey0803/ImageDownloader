import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { ExportEntry } from './FileActions';

/** User-armed, foreground-only near-field file sharing. */
export class TapShare {
  private static entries: ExportEntry[] = [];
  private static zip: boolean = false;
  private static active: boolean = false;
  private static report: (message: string) => void = (message: string): void => {};
  private static callback: (target: harmonyShare.SharableTarget) => void =
    (target: harmonyShare.SharableTarget): void => { TapShare.send(target); };

  static start(entries: ExportEntry[], zip: boolean, report: (message: string) => void): boolean {
    TapShare.stop();
    if (!canIUse('SystemCapability.Collaboration.HarmonyShare') || entries.length === 0) { return false; }
    TapShare.entries = entries.slice();
    TapShare.zip = zip;
    TapShare.report = report;
    try {
      harmonyShare.on('knockShare', TapShare.callback);
      TapShare.active = true;
      return true;
    } catch (error) {
      TapShare.entries = [];
      return false;
    }
  }

  static stop(): void {
    if (TapShare.active) {
      try { harmonyShare.off('knockShare', TapShare.callback); } catch (error) {}
    }
    TapShare.active = false;
    TapShare.entries = [];
  }

  private static async send(target: harmonyShare.SharableTarget): Promise<void> {
    if (!TapShare.active) { return; }
    const entries: ExportEntry[] = TapShare.entries.slice();
    const isZip: boolean = TapShare.zip;
    const report: (message: string) => void = TapShare.report;
    TapShare.stop();
    if (entries.some((entry: ExportEntry): boolean => {
      try { return !fs.accessSync(entry.path) || fs.statSync(entry.path).size <= 0; }
      catch (error) { return true; }
    })) {
      try { await target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR); } catch (error) {}
      report('所选文件已不可用，请重新选择');
      return;
    }
    try {
      const typeId: string = isZip ? utd.UniformDataType.ZIP_ARCHIVE : utd.UniformDataType.IMAGE;
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: typeId, uri: fileUri.getUriFromPath(entries[0].path), title: entries[0].name
      });
      for (let index: number = 1; index < entries.length; index++) {
        data.addRecord({ utd: typeId, uri: fileUri.getUriFromPath(entries[index].path), title: entries[index].name });
      }
      await target.share(data);
      report('已发起碰一碰分享，请在接收设备确认结果');
    } catch (error) {
      report('碰一碰分享未发起，请重试或使用系统分享');
    }
  }
}
