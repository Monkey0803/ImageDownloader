import { fileIo as fs } from '@kit.CoreFileKit';
import { DownloadItem } from '../model/Models';

export interface LocalPreviewFile {
  path: string;
  size: number;
  stillPath: string;
  animated: boolean;
}

/** Prefer the newest completed app-owned copy with the exact original URL. */
export class LocalPreview {
  static find(url: string, kind: string, downloads: DownloadItem[]): LocalPreviewFile | undefined {
    // DownloadStore.add() prepends new records, so the first valid match is the newest.
    for (let index: number = 0; index < downloads.length; index++) {
      const item: DownloadItem = downloads[index];
      if (item.url !== url || item.kind !== kind || item.status !== 'completed'
        || item.path.length === 0) { continue; }
      try {
        const stat: fs.Stat = fs.statSync(item.path);
        if (!stat.isFile() || stat.size <= 0) { continue; }
        let stillPath: string = '';
        if (kind === 'livephoto' && item.stillPath.length > 0) {
          try {
            const still: fs.Stat = fs.statSync(item.stillPath);
            if (still.isFile() && still.size > 0) { stillPath = item.stillPath; }
          } catch (error) {}
        }
        return { path: item.path, size: stat.size, stillPath: stillPath,
          animated: kind === 'image' && item.animated === true };
      } catch (error) {}
    }
    return undefined;
  }
}
