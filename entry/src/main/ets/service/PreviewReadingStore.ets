import { fileIo as fs } from '@kit.CoreFileKit';
import { PreviewReadingCache, PreviewReadingState } from '../model/PreviewReadingState';

/** Persist only local record IDs; remote reading positions are limited to this app process. */
export class PreviewReadingStore {
  private static cache: PreviewReadingCache = new PreviewReadingCache();
  private static filePath: string = '';
  private static timer: number = -1;
  private static dirty: boolean = false;

  static initialize(filesDir: string): void {
    const path: string = filesDir + '/preview-reading.json';
    if (PreviewReadingStore.filePath === path) { return; }
    PreviewReadingStore.filePath = path;
    try {
      if (fs.statSync(path).size <= 128 * 1024) { PreviewReadingStore.cache.restore(fs.readTextSync(path)); }
    } catch (error) {}
  }

  static get(key: string, width: number, height: number): PreviewReadingState | undefined {
    return PreviewReadingStore.cache.get(key, width, height);
  }

  static remember(state: PreviewReadingState): void {
    if (!PreviewReadingState.valid(state)) { return; }
    PreviewReadingStore.cache.put(state);
    if (!state.key.startsWith('local:')) { return; }
    PreviewReadingStore.dirty = true;
    if (PreviewReadingStore.timer >= 0) { clearTimeout(PreviewReadingStore.timer); }
    PreviewReadingStore.timer = setTimeout((): void => { PreviewReadingStore.flush(); }, 350);
  }

  static flush(): void {
    if (PreviewReadingStore.timer >= 0) { clearTimeout(PreviewReadingStore.timer); PreviewReadingStore.timer = -1; }
    if (!PreviewReadingStore.dirty || PreviewReadingStore.filePath.length === 0) { return; }
    const pending: string = PreviewReadingStore.filePath + '.pending';
    let file: fs.File | undefined = undefined;
    try {
      const content: string = PreviewReadingStore.cache.serialize();
      file = fs.openSync(pending, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file); file = undefined;
      if (fs.readTextSync(pending) !== content) { throw new Error('Incomplete reading position write'); }
      fs.renameSync(pending, PreviewReadingStore.filePath);
      PreviewReadingStore.dirty = false;
    } catch (error) {
      if (file !== undefined) { try { fs.closeSync(file); } catch (closeError) {} }
      try { fs.unlinkSync(pending); } catch (removeError) {}
    }
  }
}
