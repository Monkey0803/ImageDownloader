import { common } from '@kit.AbilityKit';
import { zlib } from '@kit.BasicServicesKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { MediaFormat } from './MediaFormat';
import { StillFrames } from './StillFrames';

/*
 * LivePhoto.ets — Apple 实况照片包（`.livp` / `.livephoto`）的解包与播放。
 *
 * 文件层的事实：Apple 的实况照片是 **静图 + 视频** 一对（HEIC/JPEG + HEVC MOV），
 * 导出成 `.livp` 时就是一个 ZIP；应用要「当动图看」，就必须先把这对文件解出来，
 * 再用系统的 MovingPhotoView 播放。
 *
 * 两个平台约束写在这里，别人不用再踩：
 *   1. `zlib.decompressFile` 的入参**扩展名必须是 `.zip`**，所以先把包复制成
 *      `<targetDir>.zip` 再解，解完立刻删掉；
 *   2. `loadMovingPhoto` 只认**应用沙箱内**的一对文件 URI，所以解包结果必须落在
 *      `filesDir/livephotos/<下载记录 id>/` 里，不能图省事留在缓存目录。
 */

/** 一次解包的结果；`message` 是给用户看的一句话，成功时为空。 */
export interface LivePhotoContent {
  ok: boolean;
  stillPath: string;
  motionPath: string;
  /** 解出来的静图 + 视频总字节数，计入图库占用。 */
  auxSize: number;
  message: string;
}

export class LivePhoto {
  /**
   * 把实况照片包解到 targetDir，返回静图与视频的路径。
   *
   * 任何一步失败都返回 `ok: false` + 一句人话，并把半成品目录删掉：
   * 原包会由调用方继续保留，用户至少还能导出 / 分享这个文件。
   */
  static async unpack(packagePath: string, targetDir: string): Promise<LivePhotoContent> {
    const signature: Uint8Array | undefined = StillFrames.readHeader(packagePath, 2);
    if (signature === undefined || !MediaFormat.isZipSignature(signature)) {
      return LivePhoto.failure('这个文件不是实况照片包（不是 ZIP），已保留原文件');
    }
    const zipPath: string = targetDir + '.zip';
    LivePhoto.removeTree(targetDir);
    LivePhoto.removeTree(zipPath);
    try {
      // decompressFile 要求输出目录**已存在**，且入参扩展名必须是 .zip，两步都不能省。
      fs.mkdirSync(targetDir, true);
      fs.copyFileSync(packagePath, zipPath);
      await zlib.decompressFile(zipPath, targetDir);
    } catch (error) {
      LivePhoto.removeTree(targetDir);
      LivePhoto.removeTree(zipPath);
      return LivePhoto.failure('实况照片包解压失败，已保留原文件');
    }
    LivePhoto.removeTree(zipPath);
    const entries: string[] = [];
    LivePhoto.collect(targetDir, 0, entries);
    const stillPath: string = LivePhoto.pick(entries, MediaFormat.STILL_EXTENSIONS);
    const motionPath: string = LivePhoto.pick(entries, MediaFormat.MOTION_EXTENSIONS);
    if (stillPath.length === 0 || motionPath.length === 0) {
      LivePhoto.removeTree(targetDir);
      return LivePhoto.failure('实况照片包里缺少静图或视频，已保留原文件');
    }
    return {
      ok: true,
      stillPath: stillPath,
      motionPath: motionPath,
      auxSize: LivePhoto.sizeOf(stillPath) + LivePhoto.sizeOf(motionPath),
      message: ''
    };
  }

  /**
   * 把沙箱内的一对文件装成系统动态照片对象，交给 MovingPhotoView 播放。
   *
   * 设备不支持（无 syscap）或文件不可解码时返回 undefined，调用方降级显示静图。
   */
  static async load(context: common.UIAbilityContext, stillPath: string,
    motionPath: string): Promise<photoAccessHelper.MovingPhoto | undefined> {
    if (stillPath.length === 0 || motionPath.length === 0) {
      return undefined;
    }
    if (!canIUse('SystemCapability.FileManagement.PhotoAccessHelper.Core')) {
      return undefined;
    }
    try {
      return await photoAccessHelper.MediaAssetManager.loadMovingPhoto(
        context,
        fileUri.getUriFromPath(stillPath),
        fileUri.getUriFromPath(motionPath));
    } catch (error) {
      return undefined;
    }
  }

  /** 递归删除一个文件或目录；不存在、删不掉都不抛。 */
  static removeTree(path: string): void {
    let isDirectory: boolean = false;
    try {
      isDirectory = fs.statSync(path).isDirectory();
    } catch (error) {
      return;
    }
    if (!isDirectory) {
      try {
        fs.unlinkSync(path);
      } catch (error) {
      }
      return;
    }
    let entries: string[] = [];
    try {
      entries = fs.listFileSync(path);
    } catch (error) {
      entries = [];
    }
    for (const entry of entries) {
      LivePhoto.removeTree(path + '/' + entry);
    }
    try {
      fs.rmdirSync(path);
    } catch (error) {
    }
  }

  private static failure(message: string): LivePhotoContent {
    return { ok: false, stillPath: '', motionPath: '', auxSize: 0, message: message };
  }

  /** 按优先级挑一个符合扩展名的条目（静图 HEIC 优先，视频 MOV 优先）。 */
  private static pick(entries: string[], preferred: string[]): string {
    for (const extension of preferred) {
      for (const path of entries) {
        if (MediaFormat.extensionOf(path) === extension) {
          return path;
        }
      }
    }
    return '';
  }

  /** 递归收集文件（跳过目录本身）；深度上限 3 层，解包工具多套一层也不会漏。 */
  private static collect(directory: string, depth: number, out: string[]): void {
    if (depth > 3) {
      return;
    }
    let entries: string[] = [];
    try {
      entries = fs.listFileSync(directory);
    } catch (error) {
      return;
    }
    for (const entry of entries) {
      const path: string = directory + '/' + entry;
      let isDirectory: boolean = false;
      try {
        isDirectory = fs.statSync(path).isDirectory();
      } catch (error) {
        continue;
      }
      if (isDirectory) {
        LivePhoto.collect(path, depth + 1, out);
      } else {
        out.push(path);
      }
    }
  }

  private static sizeOf(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (error) {
      return 0;
    }
  }
}
