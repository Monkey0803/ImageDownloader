import { fileIo as fs } from '@kit.CoreFileKit';
import { DownloadItem } from '../model/Models';

export interface LocalPreviewFile {
  path: string;
  size: number;
  stillPath: string;
  motionPath: string;
  animated: boolean;
}

/** Prefer the newest completed app-owned copy with the exact original URL. */
export class LocalPreview {
  static find(url: string, kind: string, downloads: DownloadItem[]): LocalPreviewFile | undefined {
    // DownloadStore.add() prepends new records, so the first valid match is the newest.
    let packageOnly: LocalPreviewFile | undefined = undefined;
    for (let index: number = 0; index < downloads.length; index++) {
      const item: DownloadItem = downloads[index];
      if (item.url !== url || item.kind !== kind || item.status !== 'completed'
        || item.path.length === 0) { continue; }
      try {
        const stat: fs.Stat = fs.statSync(item.path);
        if (!stat.isFile() || stat.size <= 0) { continue; }
        let stillPath: string = '';
        let motionPath: string = '';
        if (kind === 'livephoto' && item.stillPath.length > 0) {
          try {
            const still: fs.Stat = fs.statSync(item.stillPath);
            if (still.isFile() && still.size > 0) { stillPath = item.stillPath; }
          } catch (error) {}
        }
        if (stillPath.length > 0 && item.motionPath.length > 0) {
          try {
            const motion: fs.Stat = fs.statSync(item.motionPath);
            if (motion.isFile() && motion.size > 0) { motionPath = item.motionPath; }
          } catch (error) {}
        }
        const file: LocalPreviewFile = { path: item.path, size: stat.size, stillPath: stillPath, motionPath: motionPath,
          animated: kind === 'image' && item.animated === true };
        if (kind === 'livephoto' && stillPath.length === 0) {
          if (packageOnly === undefined) { packageOnly = file; }
          continue;
        }
        return file;
      } catch (error) {}
    }
    return packageOnly;
  }
}
