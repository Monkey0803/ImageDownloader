import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LibraryMeta } from '../model/LibraryAsset';
import { LivePhoto } from './LivePhoto';

/** An entry is written before moving bytes, so an interrupted move remains discoverable. */
export class TrashEntry {
  id: string = '';
  kind: string = 'image';
  name: string = '';
  deletedAt: number = 0;
  bytes: number = 0;
  snapshot: string = '';
  meta: LibraryMeta = new LibraryMeta();
  previewOriginal: string = '';
  previewPath: string = '';
  originals: string[] = [];
  stored: string[] = [];
  restoreTargets: string[] = [];
}

class TrashWire {
  version: number = 1;
  entries: TrashEntry[] = [];
}

/** App-private recycle bin. The ordinary download state never includes these entries. */
export class TrashStore {
  private dir: string = '';
  private entries: TrashEntry[] = [];

  initialize(filesDir: string): void {
    this.dir = filesDir + '/recently-deleted';
    if (!fs.accessSync(this.dir)) { fs.mkdirSync(this.dir, true); }
    const path: string = this.dir + '/manifest.json';
    if (!fs.accessSync(path)) { this.entries = []; return; }
    const wire: TrashWire = JSON.parse(fs.readTextSync(path));
    if (wire.version !== 1 || !Array.isArray(wire.entries)) { throw new Error('最近删除记录无法读取'); }
    this.entries = wire.entries.filter((entry: TrashEntry): boolean =>
      typeof entry.id === 'string' && typeof entry.snapshot === 'string' &&
      Array.isArray(entry.originals) && Array.isArray(entry.stored));
    for (const entry of this.entries) {
      if (!Array.isArray(entry.restoreTargets)) { entry.restoreTargets = []; }
      if (typeof entry.previewPath !== 'string') { entry.previewPath = ''; }
      if (entry.id === '.' || entry.id === '..' || entry.id.length === 0) { throw new Error('无效最近删除记录'); }
    }
  }

  list(): TrashEntry[] { return this.entries.slice().sort((a: TrashEntry, b: TrashEntry): number => b.deletedAt - a.deletedAt); }
  get(id: string): TrashEntry | undefined { return this.entries.find((entry: TrashEntry): boolean => entry.id === id); }
  count(): number { return this.entries.length; }
  bytes(): number { return this.entries.reduce((total: number, entry: TrashEntry): number => total + entry.bytes, 0); }

  private write(entries: TrashEntry[]): void {
    const wire: TrashWire = new TrashWire(); wire.entries = entries;
    const target: string = this.dir + '/manifest.json';
    const temp: string = target + '.tmp';
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(JSON.stringify(wire));
    const file: fs.File = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      if (fs.writeSync(file.fd, bytes.buffer) !== bytes.byteLength) { throw new Error('最近删除记录写入不完整'); }
    } finally { fs.closeSync(file); }
    fs.renameSync(temp, target);
    this.entries = entries;
  }

  /** Move a completed asset and any unpacked live-photo directory into the bin. */
  move(entry: TrashEntry): boolean {
    if (entry.id.length === 0 || entry.id === '.' || entry.id === '..' ||
      this.get(entry.id) !== undefined || entry.originals.length === 0) { return false; }
    const folder: string = this.dir + '/' + encodeURIComponent(entry.id);
    if (!fs.accessSync(folder)) { fs.mkdirSync(folder, true); }
    entry.stored = entry.originals.map((path: string, index: number): string =>
      folder + '/' + index.toString());
    entry.previewPath = entry.previewOriginal.length > 0 && entry.originals.length > 1
      && entry.previewOriginal.startsWith(entry.originals[1] + '/')
        ? entry.previewOriginal.replace(entry.originals[1], entry.stored[1]) : entry.stored[0];
    try { this.write(this.entries.concat(entry)); } catch (error) { return false; }
    const moved: number[] = [];
    try {
      for (let index: number = 0; index < entry.originals.length; index++) {
        if (!fs.accessSync(entry.originals[index])) { throw new Error('原文件已不存在'); }
        fs.renameSync(entry.originals[index], entry.stored[index]);
        moved.push(index);
      }
      return true;
    } catch (error) {
      let rolledBack: boolean = true;
      for (const index of moved.reverse()) {
        try { fs.renameSync(entry.stored[index], entry.originals[index]); }
        catch (rollbackError) { rolledBack = false; }
      }
      if (rolledBack) { this.write(this.entries.filter((item: TrashEntry): boolean => item.id !== entry.id)); }
      return false;
    }
  }

  /** Return the actual restored paths; collisions get a suffix without changing the stable ID. */
  restoreFiles(entry: TrashEntry): string[] | undefined {
    const targets: string[] = [];
    const moved: number[] = [];
    try {
      for (let index: number = 0; index < entry.originals.length; index++) {
        let target: string = entry.originals[index];
        if (!fs.accessSync(entry.stored[index])) { throw new Error('最近删除中的文件缺失'); }
        if (fs.accessSync(target)) {
          let suffix: number = 1;
          const dot: number = index === 0 ? target.lastIndexOf('.') : -1;
          const slash: number = target.lastIndexOf('/');
          const stem: string = dot > slash ? target.substring(0, dot) : target;
          const extension: string = dot > slash ? target.substring(dot) : '';
          while (fs.accessSync(stem + '-restored-' + suffix.toString() + extension)) { suffix++; }
          target = stem + '-restored-' + suffix.toString() + extension;
        }
        targets.push(target);
      }
      entry.restoreTargets = targets;
      this.write(this.entries.slice());
      for (let index: number = 0; index < entry.originals.length; index++) {
        const target: string = targets[index];
        const parent: string = target.substring(0, target.lastIndexOf('/'));
        if (!fs.accessSync(parent)) { fs.mkdirSync(parent, true); }
        fs.renameSync(entry.stored[index], target);
        moved.push(index);
      }
      return targets;
    } catch (error) {
      for (const index of moved.reverse()) {
        try { fs.renameSync(targets[index], entry.stored[index]); } catch (rollbackError) { }
      }
      if (moved.length === 0 || entry.stored.every((path: string): boolean => fs.accessSync(path))) {
        entry.restoreTargets = []; this.write(this.entries.slice());
      }
      return undefined;
    }
  }

  /** An interrupted restore without a committed normal record goes back to the bin. */
  rollbackRestore(entry: TrashEntry): boolean {
    for (let index: number = 0; index < entry.restoreTargets.length; index++) {
      if (fs.accessSync(entry.restoreTargets[index]) && !fs.accessSync(entry.stored[index])) {
        try { fs.renameSync(entry.restoreTargets[index], entry.stored[index]); } catch (error) { return false; }
      }
    }
    if (!entry.stored.every((path: string): boolean => fs.accessSync(path))) { return false; }
    entry.restoreTargets = []; this.write(this.entries.slice()); return true;
  }

  finish(id: string): void {
    const entry: TrashEntry | undefined = this.get(id);
    if (entry === undefined) { return; }
    this.write(this.entries.filter((item: TrashEntry): boolean => item.id !== id));
    LivePhoto.removeTree(this.dir + '/' + encodeURIComponent(id));
  }

  /** A download still in normal state means deletion never committed. */
  rollbackPending(entry: TrashEntry): boolean {
    for (let index: number = 0; index < entry.originals.length; index++) {
      if (fs.accessSync(entry.stored[index]) && !fs.accessSync(entry.originals[index])) {
        try {
          const parent: string = entry.originals[index].substring(0, entry.originals[index].lastIndexOf('/'));
          if (!fs.accessSync(parent)) { fs.mkdirSync(parent, true); }
          fs.renameSync(entry.stored[index], entry.originals[index]);
        } catch (error) { return false; }
      }
    }
    if (entry.originals.every((path: string): boolean => fs.accessSync(path))) { this.finish(entry.id); return true; }
    return false;
  }

  purge(id: string): boolean {
    const entry: TrashEntry | undefined = this.get(id);
    if (entry === undefined || entry.restoreTargets.length > 0) { return false; }
    for (const path of entry.stored) {
      if (!fs.accessSync(path)) { continue; }
      LivePhoto.removeTree(path);
      if (fs.accessSync(path)) { return false; }
    }
    this.finish(id);
    return true;
  }

  purgeExpired(now: number = Date.now()): number {
    let removed: number = 0;
    for (const entry of this.list()) {
      if (entry.deletedAt + 30 * 24 * 60 * 60 * 1000 <= now && this.purge(entry.id)) { removed++; }
    }
    return removed;
  }
}

export const TRASH_STORE: TrashStore = new TrashStore();
