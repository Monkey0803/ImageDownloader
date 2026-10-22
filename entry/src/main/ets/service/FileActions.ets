import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileShare, fileUri, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { MediaFormat } from './MediaFormat';
import { Naming } from './Naming';
import { GALLERY_BATCH_LIMIT, GalleryBatchOutcome, GalleryCopyResult, GallerySaveOutcome,
  copyGalleryTargets, saveGalleryBatches } from './GalleryBatching';

/*
 * FileActions.ets — 对单个已落盘文件的系统级操作（导出 / 存相册 / 分享 / 拷进目录）。
 *
 * 这些动作原来写在 Index 里，图库预览改成独立页面后两个页面都要用，所以抽到这里。
 * 每个函数都**自己吞掉异常并返回一句用户看得懂的话**：调用方只负责把这句 say() 出去，
 * 不用再包一层 try/catch，也不会因为某个系统弹窗被取消就把页面搞崩。
 */

/** 一次动作的结果；`message` 是给用户看的，失败时为空表示调用方自行决定文案。 */
export interface ActionOutcome {
  ok: boolean;
  message: string;
  /** 存相册时用于区分首次取消与部分完成；其它文件操作不填写。 */
  savedCount?: number;
  remainingCount?: number;
  /**
   * 用户在系统弹窗上主动取消（目前只有「保存到相册」的确认框会走到这里）。
   *
   * 取消**不是失败**：写成 ok=false 的话，「下载位置 = 系统相册」的自动投递会把它记成
   * 「上次存入系统相册失败」并弹一次 Toast —— 用户只是不想存，不该留下故障记录。
   */
  cancelled?: boolean;
}

/** 选定目录的结果，多带 uri 与目录名。 */
export interface FolderChoice {
  ok: boolean;
  uri: string;
  name: string;
  message: string;
}

export interface ExportEntry {
  path: string;
  name: string;
}

/** URI 的末段（目录名），去掉百分号编码，拿不到时退回整串。 */
function leafOfUri(uri: string): string {
  let text: string = uri;
  try {
    text = decodeURIComponent(uri);
  } catch (error) {
  }
  const trimmed: string = text.endsWith('/') ? text.substring(0, text.length - 1) : text;
  const slash: number = trimmed.lastIndexOf('/');
  return slash >= 0 ? trimmed.substring(slash + 1) : trimmed;
}

/**
 * docs **目录** URI → 真实路径。
 *
 * 注意区别：picker 的 `save()` 返回的是**文件** URI，直接交给 `fs.openSync` 就行
 * （`exportFile` 就是这么用的，SDK 明说 openSync 支持 URI）。但把一个**目录** URI 拼上子项名
 * 再交给 `fs.openSync(…, CREATE)` 会 ENOENT（真机实测：
 * `Open failed, path is: file://docs/storage/Users/currentUser/Download/xxx.png`）。
 * 官方「保存文件到 Download 目录」示例的写法是先过一遍 `fileUri.FileUri(uri).path`，
 * 再把得到的真实路径交给 fs —— 这里照做。非 docs URI（沙箱路径等）会原样返回。
 */
function resolvedPath(uri: string): string {
  try {
    return new fileUri.FileUri(uri).path;
  } catch (error) {
    return uri;
  }
}

/**
 * 用户目录里有没有这个名字。
 *
 * 不能用 `accessSync`：在用户目录的**真实路径**上它会误报「存在」（真机实测，
 * 一份文件被排到 `xxx (3).png`），于是同名序号一路往后跳。`openSync(READ_ONLY)`
 * 打不开就是没有，这个判断是可信的。
 */
function hasFile(path: string): boolean {
  try {
    closeQuietly(fs.openSync(path, fs.OpenMode.READ_ONLY));
    return true;
  } catch (error) {
    return false;
  }
}

/**
 * 在一个目录下取不冲突的子项名（`a.png` → `a (2).png`）。
 *
 * 目录在应用沙箱之外，看不到 DownloadStore 里的记录，只能逐名探测；
 * 传进来的必须是**真实路径**（见 resolvedPath）。
 */
function uniqueChild(dirPath: string, name: string): string {
  const dot: number = name.lastIndexOf('.');
  const base: string = dot > 0 ? name.substring(0, dot) : name;
  const extension: string = dot > 0 ? name.substring(dot) : '';
  let candidate: string = name;
  let count: number = 2;
  while (hasFile(dirPath + '/' + candidate)) {
    candidate = base + ' (' + count.toString() + ')' + extension;
    count += 1;
  }
  return candidate;
}

/** 关掉一个 fd；关不上（已关 / 已被系统收回）不算错误。 */
function closeQuietly(file: fs.File | undefined): void {
  if (file === undefined) {
    return;
  }
  try {
    fs.closeSync(file);
  } catch (error) {
  }
}

/**
 * 把 sourcePath 的内容写进 targetPath（可能是沙箱路径，也可能是 picker 给的 URI）。
 *
 * 两个 fd 一律在 finally 里关；这里自己吞异常并返回结果，调用方只需要决定说什么话。
 */
async function copyInto(sourcePath: string, targetPath: string): Promise<ActionOutcome> {
  let source: fs.File | undefined = undefined;
  let target: fs.File | undefined = undefined;
  try {
    source = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
    target = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    await fs.copyFile(source.fd, target.fd);
    return { ok: true, message: '' };
  } catch (error) {
    return { ok: false, message: String(error) };
  } finally {
    closeQuietly(target);
    closeQuietly(source);
  }
}

/** 存到系统文件选择器指定的位置（「导出」）。 */
export async function exportFile(context: common.UIAbilityContext, path: string,
  name: string): Promise<ActionOutcome> {
  try {
    const savePicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const options: picker.DocumentSaveOptions = { newFileNames: [name] };
    const targets: string[] = await savePicker.save(options);
    if (targets.length === 0) {
      return { ok: false, message: '' };
    }
    const copied: ActionOutcome = await copyInto(path, targets[0]);
    return copied.ok ? { ok: true, message: '已导出文件' } : { ok: false, message: '导出失败：' + copied.message };
  } catch (error) {
    return { ok: false, message: '导出失败：' + String(error) };
  }
}

/** 一次选择位置，按文件选择器返回的顺序写入多个文件。 */
export async function exportFiles(context: common.UIAbilityContext, entries: ExportEntry[]): Promise<ActionOutcome> {
  if (entries.length === 0) {
    return { ok: false, message: '请先选择文件' };
  }
  try {
    const savePicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const options: picker.DocumentSaveOptions = {
      newFileNames: entries.map((entry: ExportEntry): string => entry.name)
    };
    const targets: string[] = await savePicker.save(options);
    if (targets.length === 0) {
      return { ok: false, message: '' };
    }
    if (targets.length !== entries.length) {
      return { ok: false, message: '导出失败：系统返回的文件数量与所选文件不一致' };
    }
    let copied: number = 0;
    for (let index: number = 0; index < entries.length; index++) {
      const outcome: ActionOutcome = await copyInto(entries[index].path, targets[index]);
      if (!outcome.ok) {
        return { ok: false, message: '已导出 ' + copied.toString() + '/' + entries.length.toString()
          + ' 个文件；剩余文件失败：' + outcome.message };
      }
      copied++;
    }
    return { ok: true, message: '已导出 ' + copied.toString() + ' 个文件' };
  } catch (error) {
    return { ok: false, message: '批量导出失败：' + String(error) };
  }
}

/** 首帧转 JPEG 的临时产物；`path` 为空串表示转换失败。 */
interface GalleryJpeg {
  path: string;
  name: string;
}

/**
 * 把一张图重新编码成 JPEG 存到缓存目录，只取第 0 帧。
 *
 * 只在「相册不收 webp / gif 这种格式」时兜底用：宁可给用户一张静态图，也不要让他
 * 面对一句「保存相册失败」而手里什么都没有。临时文件由调用方用完删掉。
 */
async function firstFrameJpeg(context: common.UIAbilityContext, path: string,
  name: string): Promise<GalleryJpeg> {
  let source: image.ImageSource | undefined = undefined;
  let packer: image.ImagePacker | undefined = undefined;
  let file: fs.File | undefined = undefined;
  try {
    source = image.createImageSource(path);
    const frame: image.PixelMap = await source.createPixelMap({ index: 0 });
    packer = image.createImagePacker();
    const target: string = context.cacheDir + '/gallery-' + Date.now().toString() + '.jpg';
    file = fs.openSync(target, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    const options: image.PackingOption = { format: 'image/jpeg', quality: 95 };
    await packer.packToFile(frame, file.fd, options);
    frame.release();
    return { path: target, name: Naming.withExtension(name, 'jpg') };
  } catch (error) {
    return { path: '', name: '' };
  } finally {
    closeQuietly(file);
    if (packer !== undefined) {
      try {
        await packer.release();
      } catch (error) {
      }
    }
    if (source !== undefined) {
      try {
        await source.release();
      } catch (error) {
      }
    }
  }
}

/**
 * 存进系统相册；超过 100 个实际文件时顺序弹出多个系统确认框。
 *
 * **为什么不用 `createAsset`**：它需要 `ohos.permission.WRITE_IMAGEVIDEO`
 * （user_grant + `availableLevel: system_basic`，声明后还得让调试证书的 allowed-acls 带上它，
 * 否则 `hdc install` 报 9568289）。本应用没有这个权限，真机上 `createAsset` 直接
 * `Permission denied / js errcode:201`（日志在 MediaLibraryNapi）。
 * 官方给免权限应用留的替代就是 `showAssetsCreationDialog`：把要保存的源文件 URI 与目标配置
 * 交给系统确认，用户同意后返回可写的相册 URI。单次最多传 100 个文件。
 *
 * 某一批失败且未保存的文件含 GIF / WebP 动图时，只重试这批尚未保存的文件；
 * 动图改用静态首帧。已成功保存的文件不再重试，避免重复资产。
 */
export async function saveImagesToGallery(context: common.UIAbilityContext, paths: string[],
  names: string[], shouldContinue: () => boolean = (): boolean => true,
  onSaved: (paths: string[], downgraded: boolean) => void = (): void => {}): Promise<ActionOutcome> {
  const outcome: GallerySaveOutcome = await saveGalleryBatches(paths, names,
    async (batchPaths: string[], batchNames: string[]): Promise<GalleryBatchOutcome> => {
      const batch: GalleryBatchOutcome = await saveGalleryChunk(context, batchPaths, batchNames);
      onSaved((batch.savedIndices ?? []).map((index: number): string => batchPaths[index]), batch.downgraded);
      return batch;
    }, shouldContinue);
  return { ok: outcome.ok, cancelled: outcome.cancelled, message: outcome.message,
    savedCount: outcome.savedCount, remainingCount: outcome.remainingCount };
}

interface GalleryRequestResult {
  savedIndices: number[];
  cancelled: boolean;
  error: string;
}

/** 一批最多 100 个文件；动图兜底只处理初次未保存的项。 */
async function saveGalleryChunk(context: common.UIAbilityContext, paths: string[],
  names: string[]): Promise<GalleryBatchOutcome> {
  const first: GalleryRequestResult = await requestGallery(context, paths, names);
  if (first.cancelled || first.savedIndices.length === paths.length) {
    return { savedIndices: first.savedIndices, savedCount: first.savedIndices.length, cancelled: first.cancelled,
      message: first.error, downgraded: false };
  }
  const saved: Set<number> = new Set<number>(first.savedIndices);
  const drafts: GalleryJpeg[] = [];
  const retryPaths: string[] = [];
  const retryNames: string[] = [];
  const retryIndices: number[] = [];
  let hasAnimated: boolean = false;
  for (let i: number = 0; i < paths.length; i++) {
    if (saved.has(i)) {
      continue;
    }
    retryIndices.push(i);
    const name: string = names[i];
    if (!MediaFormat.isAnimatedExt(MediaFormat.extensionOf(name))) {
      retryPaths.push(paths[i]);
      retryNames.push(name);
      continue;
    }
    hasAnimated = true;
    const draft: GalleryJpeg = await firstFrameJpeg(context, paths[i], name);
    if (draft.path.length === 0) {
      retryPaths.push(paths[i]);
      retryNames.push(name);
      continue;
    }
    drafts.push(draft);
    retryPaths.push(draft.path);
    retryNames.push(draft.name);
  }
  if (!hasAnimated || drafts.length === 0) {
    return { savedIndices: Array.from(saved), savedCount: saved.size, cancelled: false, message: first.error, downgraded: false };
  }
  let second: GalleryRequestResult;
  try {
    second = await requestGallery(context, retryPaths, retryNames);
  } finally {
    for (const draft of drafts) {
      try {
        fs.unlinkSync(draft.path);
      } catch (error) {
      }
    }
  }
  let downgraded: boolean = false;
  for (const index of second.savedIndices) {
    saved.add(retryIndices[index]);
    if (retryPaths[index] !== paths[retryIndices[index]]) {
      downgraded = true;
    }
  }
  return { savedIndices: Array.from(saved), savedCount: saved.size, cancelled: second.cancelled,
    message: second.error || first.error, downgraded: downgraded };
}

/**
 * 直接把至多 100 个源文件交给系统相册确认框；逐个记录真正复制成功的下标。
 */
async function requestGallery(context: common.UIAbilityContext, paths: string[],
  names: string[]): Promise<GalleryRequestResult> {
  const count: number = Math.min(paths.length, names.length, GALLERY_BATCH_LIMIT);
  if (count === 0) {
    return { savedIndices: [], cancelled: false, error: '' };
  }
  try {
    const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
    const sources: string[] = [];
    const configs: photoAccessHelper.PhotoCreationConfig[] = [];
    for (let i: number = 0; i < count; i++) {
      const dot: number = names[i].lastIndexOf('.');
      const extension: string = dot > 0 ? names[i].substring(dot + 1).toLowerCase() : 'jpg';
      sources.push(fileUri.getUriFromPath(paths[i]));
      configs.push({
        title: dot > 0 ? names[i].substring(0, dot) : names[i],
        fileNameExtension: extension,
        // 实况照片解出来的视频（mov / mp4）必须按 VIDEO 建资产，否则相册会按图片校验后缀，
        // 直接回 -2004「图片类型与文件名后缀不符」。
        photoType: MediaFormat.isMotionExt(extension)
          ? photoAccessHelper.PhotoType.VIDEO
          : photoAccessHelper.PhotoType.IMAGE
      });
    }
    const targets: string[] = await helper.showAssetsCreationDialog(sources, configs);
    if (targets.length === 0) {
      // 用户点了「禁止」：不算失败，交给调用方决定要不要说一句。
      return { savedIndices: [], cancelled: true, error: '' };
    }
    const copied: GalleryCopyResult = await copyGalleryTargets(count, targets,
      (index: number, target: string): Promise<ActionOutcome> => copyInto(paths[index], target));
    return { savedIndices: copied.savedIndices, cancelled: false, error: copied.error };
  } catch (error) {
    return { savedIndices: [], cancelled: false, error: String(error) };
  }
}

/** 单张存相册；大图预览页的「存相册」用它。 */
export async function saveImageToGallery(context: common.UIAbilityContext, path: string,
  name: string): Promise<ActionOutcome> {
  return saveImagesToGallery(context, [path], [name]);
}

/**
 * 存实况照片进相册：静图与视频**各存一份**。
 *
 * 为什么不是「实况照片」这个类型本身：免权限的 `showAssetsCreationDialog` 明确只支持
 * DEFAULT 图片（SDK 文档：「If a subtype option is passed, the configuration does not take
 * effect. Only DEFAULT images can be saved.」），而真正能建实况照片的
 * `MediaAssetChangeRequest` 需要 `ohos.permission.WRITE_IMAGEVIDEO`（本应用没有，见
 * `saveImagesToGallery` 的说明）。所以退一步：两部分都进相册，原包也留在应用里。
 */
export async function saveLivePhotoToGallery(context: common.UIAbilityContext, stillPath: string,
  motionPath: string, name: string): Promise<ActionOutcome> {
  const stillName: string = Naming.withExtension(name, MediaFormat.extensionOf(stillPath));
  const motionName: string = Naming.withExtension(name, MediaFormat.extensionOf(motionPath));
  const outcome: ActionOutcome = await saveImagesToGallery(context, [stillPath, motionPath],
    [stillName, motionName]);
  if (!outcome.ok) {
    return outcome;
  }
  return { ok: true, message: '已把静图与视频分别存入系统相册（系统暂不支持免权限写入实况照片本身）' };
}

/** 拉起系统分享面板。 */
export async function shareFile(context: common.UIAbilityContext, path: string, name: string,
  isZip: boolean): Promise<ActionOutcome> {
  try {
    const typeId: string = isZip ? utd.UniformDataType.ZIP_ARCHIVE : utd.UniformDataType.IMAGE;
    const data: systemShare.SharedData = new systemShare.SharedData({
      utd: typeId,
      uri: fileUri.getUriFromPath(path),
      title: name
    });
    const controller: systemShare.ShareController = new systemShare.ShareController(data);
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    });
    return { ok: true, message: '' };
  } catch (error) {
    return { ok: false, message: '分享失败：' + String(error) };
  }
}

/** 把同一分段内选中的文件交给一次系统分享面板。 */
export async function shareFiles(context: common.UIAbilityContext, entries: ExportEntry[],
  isZip: boolean): Promise<ActionOutcome> {
  if (entries.length === 0) {
    return { ok: false, message: '请先选择文件' };
  }
  try {
    const typeId: string = isZip ? utd.UniformDataType.ZIP_ARCHIVE : utd.UniformDataType.IMAGE;
    const data: systemShare.SharedData = new systemShare.SharedData({
      utd: typeId, uri: fileUri.getUriFromPath(entries[0].path), title: entries[0].name
    });
    for (let index: number = 1; index < entries.length; index++) {
      data.addRecord({
        utd: typeId, uri: fileUri.getUriFromPath(entries[index].path), title: entries[index].name
      });
    }
    const controller: systemShare.ShareController = new systemShare.ShareController(data);
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    });
    return { ok: true, message: '' };
  } catch (error) {
    return { ok: false, message: '批量分享失败：' + String(error) };
  }
}

/**
 * 分享实况照片：静图与视频**两条记录**一起交给系统分享面板。
 *
 * 为什么不是分享原始 `.livp`：那是一个只有 Apple 生态认识的 ZIP，接收方多半打不开；
 * 分两份给出去，图片和视频在哪儿都能直接用（与「存相册」的取舍一致）。
 * 解包结果缺失或本机拼不出两条记录时，退回分享原始包 —— 至少文件还在。
 */
export async function shareLivePhoto(context: common.UIAbilityContext, stillPath: string,
  motionPath: string, packagePath: string, name: string): Promise<ActionOutcome> {
  try {
    const data: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.IMAGE,
      uri: fileUri.getUriFromPath(stillPath),
      title: name
    });
    data.addRecord({
      utd: utd.UniformDataType.VIDEO,
      uri: fileUri.getUriFromPath(motionPath),
      title: name
    });
    const controller: systemShare.ShareController = new systemShare.ShareController(data);
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    });
    return { ok: true, message: '' };
  } catch (error) {
    return shareFile(context, packagePath, name, true);
  }
}

/**
 * 让用户挑一个目录（「下载位置 = 自定义目录」）。
 *
 * 选目录用 `select(selectMode: FOLDER)`，它依赖
 * `SystemCapability.FileManagement.UserFileService.FolderSelection`；把这一次的临时授权
 * 变成持久的则是 `persistPermission`，依赖
 * `SystemCapability.FileManagement.AppFileService.FolderAuthorization` 与
 * `ohos.permission.FILE_ACCESS_PERSIST`（normal + system_grant，不需要 ACL）。
 *
 * **授权常常持久化不了**：真机（PLR-AL00，HarmonyOS 7）上对
 * `file://docs/storage/Users/currentUser/Download` 和 `.../Pictures/hiddenAlbum`
 * 都返回 `13900001 / PolicyErrorCode=1「URI forbid to be persisted!」`。这时不算选目录失败 ——
 * 本次会话照样写得进去（实测能落盘），只是重启后授权就没了，所以用一句提示说清楚，
 * 启动时再由 DownloadStore.rearmFolder() 把档位退回应用文件。
 */
export async function pickFolder(context: common.UIAbilityContext): Promise<FolderChoice> {
  const uri: string = await selectFolder(context);
  if (uri.length === 0) {
    return { ok: false, uri: '', name: '', message: '' };
  }
  const name: string = leafOfUri(uri);
  if (!canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization')) {
    return { ok: true, uri: uri, name: name, message: '目录已选择，本机不支持长期授权，重启后需要重选' };
  }
  try {
    const mode: number = fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
      | fileShare.OperationMode.CREATE_MODE;
    await fileShare.persistPermission([{ uri: uri, operationMode: mode }]);
    return { ok: true, uri: uri, name: name, message: '' };
  } catch (error) {
    // 授权持久化失败不算选目录失败：本次会话仍可写入，只是重启后要重新选。
    return { ok: true, uri: uri, name: name, message: '目录已选择，但授权无法长期保存，重启后需要重选' };
  }
}

/** 只负责拉起选择器并返回目录 URI；取消 / 失败都返回空串。 */
async function selectFolder(context: common.UIAbilityContext): Promise<string> {
  try {
    const options: picker.DocumentSelectOptions = {
      selectMode: picker.DocumentSelectMode.FOLDER,
      maxSelectNumber: 1
    };
    const viewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const uris: string[] = await viewPicker.select(options);
    return uris.length > 0 ? uris[0] : '';
  } catch (error) {
    return '';
  }
}

/** 重新启用一个已持久化授权的目录；启动时调一次，失败就当成目录不可用。 */
export async function activateFolder(uri: string): Promise<boolean> {
  if (uri.length === 0) {
    return false;
  }
  try {
    const mode: number = fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
      | fileShare.OperationMode.CREATE_MODE;
    await fileShare.activatePermission([{ uri: uri, operationMode: mode }]);
    return true;
  } catch (error) {
    return false;
  }
}

/** 把一个已落盘的文件拷进用户选的目录（同名自动加序号）。 */
export async function copyIntoDirectory(sourcePath: string, dirUri: string, name: string): Promise<ActionOutcome> {
  if (dirUri.length === 0) {
    return { ok: false, message: '没有可用的自定义目录' };
  }
  const directory: string = resolvedPath(dirUri);
  return copyInto(sourcePath, directory + '/' + uniqueChild(directory, name));
}
