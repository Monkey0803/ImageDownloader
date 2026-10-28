import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { DownloadItem } from '../model/Models';
import { EditResult, EditTicket } from '../model/ImageEditDocument';

/** Only paths recorded in a valid edit journal may be removed during recovery. */
export class EditJournal {
  private static readonly ID: RegExp = new RegExp('^[A-Za-z0-9_-]{1,80}$');

  private static ticket(filesDir: string, id: string, originalId: string): EditTicket {
    if (!EditJournal.ID.test(id) || originalId.length === 0 || filesDir.length === 0) {
      throw new Error('编辑记录编号无效');
    }
    const ticket: EditTicket = new EditTicket();
    ticket.id = id; ticket.originalId = originalId;
    const base: string = filesDir + '/edits/edit-' + id;
    ticket.pendingPath = base + '.pending.png';
    ticket.finalPath = base + '.png';
    ticket.journalPath = base + '.json';
    return ticket;
  }

  private static checked(ticket: EditTicket): EditTicket {
    const suffix: string = '/edits/edit-' + ticket.id + '.json';
    if (!ticket.journalPath.endsWith(suffix)) { throw new Error('编辑日志路径无效'); }
    const root: string = ticket.journalPath.substring(0, ticket.journalPath.length - suffix.length);
    const expected: EditTicket = EditJournal.ticket(root, ticket.id, ticket.originalId);
    if (ticket.pendingPath !== expected.pendingPath || ticket.finalPath !== expected.finalPath) {
      throw new Error('编辑输出路径无效');
    }
    return expected;
  }

  private static write(ticket: EditTicket): void {
    const target: string = ticket.journalPath;
    const temp: string = target + '.tmp';
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(JSON.stringify(ticket));
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      if (fs.writeSync(file.fd, bytes.buffer) !== bytes.byteLength) {
        throw new Error('编辑日志写入不完整');
      }
      fs.closeSync(file); file = undefined;
      fs.renameSync(temp, target);
    } catch (error) {
      if (file !== undefined) { try { fs.closeSync(file); } catch (closeError) {} }
      EditJournal.remove(temp);
      throw new Error('编辑日志写入失败：' + String(error));
    }
  }

  private static remove(path: string): void {
    try { if (fs.accessSync(path)) { fs.unlinkSync(path); } } catch (error) {}
  }

  static async prepare(filesDir: string, id: string, originalId: string): Promise<EditTicket> {
    const ticket: EditTicket = EditJournal.ticket(filesDir, id, originalId);
    const dir: string = filesDir + '/edits';
    if (!fs.accessSync(dir)) { fs.mkdirSync(dir, true); }
    if (fs.accessSync(ticket.pendingPath) || fs.accessSync(ticket.finalPath) ||
      fs.accessSync(ticket.journalPath)) { throw new Error('编辑副本编号已占用'); }
    EditJournal.write(ticket);
    return ticket;
  }

  static async finalize(ticket: EditTicket, result: EditResult): Promise<void> {
    EditJournal.checked(ticket);
    if (!fs.accessSync(ticket.journalPath) || result.path !== ticket.pendingPath ||
      result.bytes <= 0 || result.width <= 0 || result.height <= 0 ||
      !fs.accessSync(ticket.pendingPath) || fs.accessSync(ticket.finalPath) ||
      fs.statSync(ticket.pendingPath).size !== result.bytes) {
      throw new Error('编辑输出文件校验失败');
    }
    fs.renameSync(ticket.pendingPath, ticket.finalPath);
  }

  static async finish(ticket: EditTicket): Promise<void> {
    EditJournal.checked(ticket);
    EditJournal.remove(ticket.journalPath);
  }

  static async rollback(ticket: EditTicket): Promise<void> {
    EditJournal.checked(ticket);
    if (!fs.accessSync(ticket.journalPath)) { return; }
    EditJournal.remove(ticket.pendingPath);
    EditJournal.remove(ticket.finalPath);
    EditJournal.remove(ticket.journalPath);
  }

  static async recover(filesDir: string, items: DownloadItem[]): Promise<void> {
    const dir: string = filesDir + '/edits';
    if (!fs.accessSync(dir)) { return; }
    for (const name of fs.listFileSync(dir)) {
      if (!name.startsWith('edit-') || !name.endsWith('.json')) { continue; }
      const id: string = name.substring(5, name.length - 5);
      if (!EditJournal.ID.test(id)) { continue; }
      const path: string = dir + '/' + name;
      let raw: EditTicket;
      try { raw = JSON.parse(fs.readTextSync(path)) as EditTicket; } catch (error) { continue; }
      if (raw.id !== id || raw.journalPath !== path) { continue; }
      try { EditJournal.checked(raw); } catch (error) { continue; }
      const registered: boolean = items.some((item: DownloadItem): boolean =>
        item.id === id && item.origin === 'edited' && item.path === raw.finalPath);
      if (registered) {
        if (fs.accessSync(raw.finalPath)) { EditJournal.remove(path); }
      } else {
        await EditJournal.rollback(raw);
      }
    }
  }
}
