import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

export class BrowserEntry {
  url: string = '';
  title: string = '';
  visitedAt: number = 0;
}

export class BrowserData {
  history: BrowserEntry[] = [];
  bookmarks: BrowserEntry[] = [];
}

/** 浏览记录与收藏独立存储，不随下载记录的高频进度更新重复写盘。 */
export class BrowserCollection {
  static readonly HISTORY_LIMIT: number = 100;

  static validUrl(url: string): boolean {
    return /^https?:\/\/[^\s/]+/i.test(url);
  }

  static remember(entries: BrowserEntry[], url: string, title: string, at: number, limit: number): BrowserEntry[] {
    if (!BrowserCollection.validUrl(url)) { return entries; }
    const entry: BrowserEntry = new BrowserEntry();
    entry.url = url;
    entry.title = title.trim().length > 0 ? title.trim() : url;
    entry.visitedAt = at;
    return [entry, ...entries.filter((item: BrowserEntry): boolean => item.url !== url)].slice(0, limit);
  }

  static normalize(raw: BrowserData): BrowserData {
    const data: BrowserData = new BrowserData();
    if (raw === null || typeof raw !== 'object') { return data; }
    const history: BrowserEntry[] = Array.isArray(raw.history) ? raw.history : [];
    const bookmarks: BrowserEntry[] = Array.isArray(raw.bookmarks) ? raw.bookmarks : [];
    for (const item of history.slice().reverse()) {
      if (item !== null && typeof item.url === 'string' && typeof item.title === 'string') {
        data.history = BrowserCollection.remember(data.history, item.url, item.title,
          typeof item.visitedAt === 'number' ? item.visitedAt : 0, BrowserCollection.HISTORY_LIMIT);
      }
    }
    for (const item of bookmarks.slice().reverse()) {
      if (item !== null && typeof item.url === 'string' && typeof item.title === 'string') {
        data.bookmarks = BrowserCollection.remember(data.bookmarks, item.url, item.title,
          typeof item.visitedAt === 'number' ? item.visitedAt : 0, 1000);
      }
    }
    return data;
  }

  static load(context: common.UIAbilityContext): BrowserData {
    try {
      const path: string = context.filesDir + '/browser-collection.json';
      if (!fs.accessSync(path)) { return new BrowserData(); }
      return BrowserCollection.normalize(JSON.parse(fs.readTextSync(path)) as BrowserData);
    } catch (error) {
      console.error('load browser collection failed: ' + String(error));
      return new BrowserData();
    }
  }

  static save(context: common.UIAbilityContext, data: BrowserData): boolean {
    const path: string = context.filesDir + '/browser-collection.json';
    const temp: string = path + '.tmp';
    try {
      const file: fs.File = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, JSON.stringify(data)); } finally { fs.closeSync(file); }
      fs.renameSync(temp, path);
      return true;
    } catch (error) {
      console.error('save browser collection failed: ' + String(error));
      return false;
    }
  }
}
