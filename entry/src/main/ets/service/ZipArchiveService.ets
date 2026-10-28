import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import nativeArchive, { ArchiveInfo } from 'libarchiveextract.so';
import { DownloadItem, ZipItem } from '../model/Models';
import { DownloadStore } from './DownloadStore';
import { LivePhoto } from './LivePhoto';
import { MediaFormat } from './MediaFormat';
import { Naming } from './Naming';
import { StillFrames } from './StillFrames';
import { FolderChoice, pickFolder } from './FileActions';

export class ZipExtractResult {
  added: number = 0;
  skipped: number = 0;
  location: string = '';
}

/** Import and extract ZIPs without exposing picker URIs to the native decoder. */
export class ZipArchiveService {
  static inspect(zip: ZipItem): ArchiveInfo {
    return nativeArchive.inspect(zip.path);
  }

  static isEncrypted(zip: ZipItem): boolean {
    return nativeArchive.inspect(zip.path).encrypted;
  }

  static async importZip(context: common.UIAbilityContext): Promise<ZipItem | undefined> {
    const selector: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const options: picker.DocumentSelectOptions = {
      selectMode: picker.DocumentSelectMode.FILE,
      maxSelectNumber: 1,
      fileSuffixFilters: ['ZIP 压缩包|.zip']
    };
    const uris: string[] = await selector.select(options);
    if (uris.length === 0) { return undefined; }
    let name: string = uris[0].substring(uris[0].lastIndexOf('/') + 1);
    try { name = decodeURIComponent(name); } catch (error) {}
    if (!name.toLowerCase().endsWith('.zip')) { throw new Error('请选择 ZIP 压缩包'); }
    name = Naming.clean(name, '导入.zip');
    const dir: string = context.filesDir + '/archives';
    let candidate: string = name;
    let suffix: number = 2;
    while (fs.accessSync(dir + '/' + candidate)) {
      candidate = name.substring(0, name.length - 4) + ' (' + suffix.toString() + ').zip';
      suffix += 1;
    }
    const path: string = dir + '/' + candidate;
    try {
      await ZipArchiveService.copy(uris[0], path);
      const info: ArchiveInfo = nativeArchive.inspect(path);
      return DownloadStore.registerImportedZip(path, candidate, info.count);
    } catch (error) {
      LivePhoto.removeTree(path);
      throw new Error(String(error));
    }
  }

  static async extractToGallery(context: common.UIAbilityContext, zip: ZipItem,
    password: string): Promise<ZipExtractResult> {
    const staging: string = ZipArchiveService.staging(context, zip);
    const created: string[] = [];
    const result: ZipExtractResult = new ZipExtractResult();
    try {
      await nativeArchive.extract(zip.path, staging, password);
      const files: string[] = [];
      ZipArchiveService.collect(staging, files);
      const items: DownloadItem[] = [];
      const destination: string = context.filesDir + '/images';
      for (const source of files) {
        const leaf: string = source.substring(source.lastIndexOf('/') + 1);
        if (!MediaFormat.isImageName(leaf)) { result.skipped += 1; continue; }
        if (!await ZipArchiveService.decodes(source)) { result.skipped += 1; continue; }
        const name: string = DownloadStore.uniqueName(Naming.clean(leaf, '解压图片.png'), destination);
        const path: string = destination + '/' + name;
        await ZipArchiveService.copy(source, path);
        created.push(path);
        const item: DownloadItem = new DownloadItem();
        item.id = DownloadStore.nextId(); item.origin = 'extracted'; item.originalId = zip.id;
        item.name = name; item.path = path; item.kind = 'image'; item.status = 'completed';
        item.size = fs.statSync(path).size; item.processed = item.size; item.total = item.size;
        item.createdAt = Date.now(); item.finishedAt = item.createdAt;
        item.animated = StillFrames.isAnimatedFile(path);
        items.push(item);
      }
      if (items.length === 0) { throw new Error('压缩包中没有可加入图库的图片'); }
      DownloadStore.registerExtracted(items);
      result.added = items.length;
      return result;
    } catch (error) {
      for (const path of created) { LivePhoto.removeTree(path); }
      throw new Error(String(error));
    } finally {
      LivePhoto.removeTree(staging);
    }
  }

  static async extractToFolder(context: common.UIAbilityContext, zip: ZipItem,
    password: string): Promise<ZipExtractResult | undefined> {
    const folder: FolderChoice = await pickFolder(context);
    if (!folder.ok) { return undefined; }
    return ZipArchiveService.extractIntoFolder(context, zip, password, folder.uri);
  }

  /** Kept separate from the picker so hierarchy/collision behavior can be tested on device. */
  static async extractIntoFolder(context: common.Context, zip: ZipItem, password: string,
    folderUri: string): Promise<ZipExtractResult> {
    const staging: string = ZipArchiveService.staging(context, zip);
    let destination: string = '';
    try {
      await nativeArchive.extract(zip.path, staging, password);
      let root: string = folderUri;
      try { root = new fileUri.FileUri(folderUri).path; } catch (error) {}
      const raw: string = zip.name.toLowerCase().endsWith('.zip') ? zip.name.substring(0, zip.name.length - 4) : zip.name;
      const base: string = Naming.clean(raw, '解压文件');
      destination = ZipArchiveService.uniqueFolder(root, base);
      ZipArchiveService.copyTree(staging, destination);
      const result: ZipExtractResult = new ZipExtractResult();
      result.location = destination;
      return result;
    } catch (error) {
      if (destination.length > 0) { LivePhoto.removeTree(destination); }
      throw new Error(String(error));
    } finally {
      LivePhoto.removeTree(staging);
    }
  }

  private static staging(context: common.Context, zip: ZipItem): string {
    const root: string = context.filesDir + '/archive-extract';
    if (!fs.accessSync(root)) { fs.mkdirSync(root, true); }
    return root + '/' + zip.id + '-' + DownloadStore.nextId();
  }

  private static collect(dir: string, files: string[]): void {
    for (const name of fs.listFileSync(dir)) {
      const path: string = dir + '/' + name;
      if (fs.statSync(path).isDirectory()) { ZipArchiveService.collect(path, files); }
      else { files.push(path); }
    }
  }

  private static async decodes(path: string): Promise<boolean> {
    let source: image.ImageSource | undefined = undefined;
    let preview: image.PixelMap | undefined = undefined;
    try {
      source = image.createImageSource(path);
      const info: image.ImageInfo = await source.getImageInfo();
      if (info.size.width <= 0 || info.size.height <= 0) { return false; }
      preview = await source.createPixelMap({ index: 0, desiredSize: { width: 1, height: 1 } });
      return true;
    } catch (error) {
      return false;
    } finally {
      if (preview !== undefined) { try { await preview.release(); } catch (error) {} }
      if (source !== undefined) { try { await source.release(); } catch (error) {} }
    }
  }

  private static uniqueFolder(root: string, name: string): string {
    for (let index: number = 1; index < 10000; index++) {
      const label: string = index === 1 ? name : name + ' (' + index.toString() + ')';
      const candidate: string = root + '/' + label;
      try { fs.statSync(candidate); } catch (error) {
        fs.mkdirSync(candidate);
        return candidate;
      }
    }
    throw new Error('目标目录中同名文件夹过多');
  }

  private static copyTree(source: string, destination: string): void {
    for (const name of fs.listFileSync(source)) {
      const from: string = source + '/' + name;
      const to: string = destination + '/' + name;
      if (fs.statSync(from).isDirectory()) {
        fs.mkdirSync(to);
        ZipArchiveService.copyTree(from, to);
      } else {
        fs.copyFileSync(from, to);
      }
    }
  }

  private static async copy(sourcePath: string, targetPath: string): Promise<void> {
    let source: fs.File | undefined = undefined;
    let target: fs.File | undefined = undefined;
    try {
      source = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
      target = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      await fs.copyFile(source.fd, target.fd);
    } finally {
      if (target !== undefined) { try { fs.closeSync(target); } catch (error) {} }
      if (source !== undefined) { try { fs.closeSync(source); } catch (error) {} }
    }
  }
}
