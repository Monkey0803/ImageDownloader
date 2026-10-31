import { DownloadItem } from '../model/Models';
import { AnalysisToken, AssetStamp } from '../model/LibraryAsset';
import { EditDocument, EditResult, EditTicket, PreviewSize } from '../model/ImageEditDocument';
import { DownloadStore } from './DownloadStore';
import { EditExport } from './EditExport';
import { EditJournal } from './EditJournal';
import { LibraryImageReader } from './LibraryImageReader';

/** Source validation and transactional export for the image editor. */
export class ImageEditorWorkflow {
  static async source(id: string): Promise<AssetStamp> {
    const item: DownloadItem | undefined = DownloadStore.downloads.find((entry: DownloadItem): boolean =>
      entry.id === id && entry.status === 'completed');
    if (item === undefined) { throw new Error('图片尚未下载或已删除'); }
    return LibraryImageReader.stamp(item);
  }

  static async info(stamp: AssetStamp): Promise<PreviewSize> {
    return LibraryImageReader.info(stamp);
  }

  static async exportAndRegister(id: string, doc: EditDocument, token: AnalysisToken,
    loaded: AssetStamp | undefined): Promise<DownloadItem> {
    const stamp: AssetStamp = await ImageEditorWorkflow.source(id);
    if (loaded === undefined || stamp.path !== loaded.path || stamp.bytes !== loaded.bytes ||
      stamp.modified !== loaded.modified || stamp.changed !== loaded.changed || token.cancelled) {
      throw new Error('原图已变化，请重新打开编辑');
    }
    const setting: string = DownloadStore.editQuality;
    const extension: string = await EditExport.extensionFor(stamp, setting);
    const ticket: EditTicket = await EditJournal.prepare(DownloadStore.context.filesDir,
      DownloadStore.nextId(), id, extension);
    try {
      const result: EditResult = await EditExport.render(stamp, doc, ticket.pendingPath, token, setting);
      if (token.cancelled) { throw new Error('编辑已取消'); }
      await EditJournal.finalize(ticket, result);
      if (token.cancelled) { throw new Error('编辑已取消'); }
      return await DownloadStore.registerEdited(id, ticket, result);
    } catch (error) {
      await EditJournal.rollback(ticket);
      throw new Error(String(error));
    }
  }
}
