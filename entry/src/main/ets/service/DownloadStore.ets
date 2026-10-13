import { common } from '@kit.AbilityKit';
import { request, zlib } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { webview } from '@kit.ArkWeb';
import {
  BatchItem, DownloadItem, orBoolean, orNumber, orString, PictureItem, SavedState, ZipItem
} from '../model/Models';

export class DownloadStore {
  static context: common.UIAbilityContext;
  static downloads: DownloadItem[] = [];
  static zips: ZipItem[] = [];
  static batches: BatchItem[] = [];
  static concurrency: number = 3;
  /** 'system' | 'light' | 'dark' — see applyTheme(). */
  static themeMode: string = 'system';
  /** 'adaptive' | 'immersive'. */
  static materialType: string = 'adaptive';
  /** Whether the immersive material lights up under touch. */
  static lightEffect: boolean = true;
  static active: Map<string, request.agent.Task> = new Map<string, request.agent.Task>();
  static listener: (() => void) | undefined = undefined;
  static serial: number = 0;
  static lastProgressSaveAt: number = 0;

  static exists(path: string): boolean {
    try { return fs.accessSync(path); } catch (error) { return false; }
  }

  static removeFile(path: string): void {
    try { if (fs.accessSync(path)) { fs.unlinkSync(path); } } catch (error) {}
  }

  static moveFile(source: string, target: string): void {
    try { fs.renameSync(source, target); } catch (error) {}
  }

  static initialize(context: common.UIAbilityContext, listener: () => void): void {
    DownloadStore.context = context;
    DownloadStore.listener = listener;
    DownloadStore.ensureDirectory(context.filesDir + '/images');
    DownloadStore.ensureDirectory(context.filesDir + '/archives');
    DownloadStore.ensureDirectory(context.filesDir + '/staging');
    const statePath: string = context.filesDir + '/download-state.json';
    if (DownloadStore.exists(statePath)) {
      try {
        const state: SavedState = JSON.parse(fs.readTextSync(statePath)) as SavedState;
        DownloadStore.adopt(state);
      } catch (error) {
        DownloadStore.downloads = [];
        DownloadStore.zips = [];
        DownloadStore.batches = [];
      }
    }
    DownloadStore.recover();
  }

  /**
   * Load a persisted state into the live lists.
   *
   * Records are rebuilt as real model instances rather than kept as the plain
   * objects JSON.parse returns: the UI binds to them with @ObjectLink, which
   * only tracks @Observed instances. A state file written by an older build is
   * also missing fields added since, so every value is defaulted here instead
   * of being guarded at each use site.
   */
  static adopt(state: SavedState): void {
    DownloadStore.downloads = (state.downloads ?? []).map((entry: DownloadItem): DownloadItem => {
      const item: DownloadItem = new DownloadItem();
      item.id = orString(entry.id, '');
      item.url = orString(entry.url, '');
      item.name = orString(entry.name, '');
      item.userNamed = orBoolean(entry.userNamed, false);
      item.path = orString(entry.path, '');
      item.sourcePage = orString(entry.sourcePage, '');
      item.batchId = orString(entry.batchId, '');
      item.taskId = orString(entry.taskId, '');
      item.status = orString(entry.status, 'queued');
      item.processed = orNumber(entry.processed, 0);
      item.total = orNumber(entry.total, 0);
      item.size = orNumber(entry.size, 0);
      item.error = orString(entry.error, '');
      item.createdAt = orNumber(entry.createdAt, 0);
      item.finishedAt = orNumber(entry.finishedAt, item.createdAt);
      return item;
    });
    DownloadStore.zips = (state.zips ?? []).map((entry: ZipItem): ZipItem => {
      const zip: ZipItem = new ZipItem();
      zip.id = orString(entry.id, '');
      zip.name = orString(entry.name, '');
      zip.path = orString(entry.path, '');
      zip.batchId = orString(entry.batchId, '');
      zip.imageCount = orNumber(entry.imageCount, 0);
      zip.failedCount = orNumber(entry.failedCount, 0);
      zip.size = orNumber(entry.size, 0);
      zip.createdAt = orNumber(entry.createdAt, 0);
      zip.thumbs = entry.thumbs === undefined ? [] : entry.thumbs;
      return zip;
    });
    DownloadStore.batches = (state.batches ?? []).map((entry: BatchItem): BatchItem => {
      const batch: BatchItem = new BatchItem();
      batch.id = orString(entry.id, '');
      batch.name = orString(entry.name, '');
      batch.sourcePage = orString(entry.sourcePage, '');
      batch.status = orString(entry.status, 'downloading');
      batch.error = orString(entry.error, '');
      return batch;
    });
    DownloadStore.concurrency = Math.max(1, Math.min(10, orNumber(state.concurrency, 3)));
    DownloadStore.themeMode = orString(state.themeMode, 'system');
    DownloadStore.materialType = orString(state.materialType, 'adaptive');
    DownloadStore.lightEffect = orBoolean(state.lightEffect, true);
  }

  static ensureDirectory(path: string): void {
    try {
      if (!fs.accessSync(path)) { fs.mkdirSync(path, true); }
    } catch (error) {}
  }

  static notify(): void {
    DownloadStore.save();
    if (DownloadStore.listener !== undefined) {
      DownloadStore.listener();
    }
  }

  static save(): void {
    const state: SavedState = new SavedState();
    state.downloads = DownloadStore.downloads;
    state.zips = DownloadStore.zips;
    state.batches = DownloadStore.batches;
    state.concurrency = DownloadStore.concurrency;
    state.themeMode = DownloadStore.themeMode;
    state.materialType = DownloadStore.materialType;
    state.lightEffect = DownloadStore.lightEffect;
    const path: string = DownloadStore.context.filesDir + '/download-state.json';
    const temp: string = path + '.tmp';
    try {
      const file: fs.File = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(state));
      fs.closeSync(file);
      fs.renameSync(temp, path);
    } catch (error) {}
  }

  static nextId(): string {
    DownloadStore.serial += 1;
    return Date.now().toString() + '_' + DownloadStore.serial.toString();
  }

  static cleanName(raw: string, fallback: string): string {
    let name: string = raw.trim().replace(new RegExp('[\\\\/:*?"<>|\\x00-\\x1f]', 'g'), '_');
    name = name.replace(new RegExp('^[. ]+|[. ]+$', 'g'), '');
    if (name.length > 120) {
      name = name.substring(0, 120);
    }
    return name.length > 0 ? name : fallback;
  }

  static suggestedName(url: string, description: string, index: number): string {
    const path: string = url.split('?')[0].split('#')[0];
    let leaf: string = path.substring(path.lastIndexOf('/') + 1);
    try { leaf = decodeURIComponent(leaf); } catch (error) {}
    const fallback: string = DownloadStore.cleanName(description, '图片_' + index.toString());
    leaf = DownloadStore.cleanName(leaf, fallback);
    const extension: string = leaf.substring(leaf.lastIndexOf('.') + 1).toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif', 'avif', 'bmp', 'svg', 'tif', 'tiff'].includes(extension)) {
      leaf += '.jpg';
    }
    return leaf;
  }

  static withExtension(raw: string, extension: string): string {
    const clean: string = DownloadStore.cleanName(raw, '图片');
    const dot: number = clean.lastIndexOf('.');
    const base: string = dot > 0 ? clean.substring(0, dot) : clean;
    return base + '.' + extension;
  }

  static imageExtension(contentType: string): string {
    const mime: string = contentType.toLowerCase().split(';')[0].trim();
    if (mime === 'image/png') { return 'png'; }
    if (mime === 'image/webp') { return 'webp'; }
    if (mime === 'image/gif') { return 'gif'; }
    if (mime === 'image/heic') { return 'heic'; }
    if (mime === 'image/heif') { return 'heif'; }
    if (mime === 'image/avif') { return 'avif'; }
    if (mime === 'image/bmp') { return 'bmp'; }
    if (mime === 'image/svg+xml') { return 'svg'; }
    if (mime === 'image/tiff') { return 'tiff'; }
    if (mime === 'image/jpeg' || mime === 'image/jpg') { return 'jpg'; }
    return '';
  }

  static uniqueName(name: string, directory: string): string {
    const dot: number = name.lastIndexOf('.');
    const base: string = dot > 0 ? name.substring(0, dot) : name;
    const extension: string = dot > 0 ? name.substring(dot) : '';
    let candidate: string = name;
    let count: number = 2;
    while (DownloadStore.exists(directory + '/' + candidate) || DownloadStore.downloads.some((item: DownloadItem): boolean => item.path === directory + '/' + candidate)) {
      candidate = base + ' (' + count.toString() + ')' + extension;
      count += 1;
    }
    return candidate;
  }

  static add(items: PictureItem[], pageUrl: string, title: string, zipMode: boolean): void {
    const selected: PictureItem[] = items.filter((item: PictureItem): boolean => item.selected);
    if (selected.length === 0) { return; }
    let batchId: string = '';
    if (zipMode) {
      batchId = DownloadStore.nextId();
      const batch: BatchItem = new BatchItem();
      batch.id = batchId;
      const titleName: string = DownloadStore.cleanName(title, '网页图片_' + Date.now().toString());
      batch.name = titleName.toLowerCase().endsWith('.zip') ? titleName : titleName + '.zip';
      batch.sourcePage = pageUrl;
      DownloadStore.batches.unshift(batch);
      DownloadStore.ensureDirectory(DownloadStore.context.filesDir + '/staging/' + batchId);
    }
    const filesDir: string = DownloadStore.context.filesDir;
    for (let i: number = 0; i < selected.length; i++) {
      const source: PictureItem = selected[i];
      const item: DownloadItem = new DownloadItem();
      item.id = DownloadStore.nextId();
      item.url = source.url;
      const suggested: string = DownloadStore.suggestedName(source.url, source.description, i + 1);
      item.name = source.userNamed ? DownloadStore.withExtension(source.name, suggested.substring(suggested.lastIndexOf('.') + 1)) : DownloadStore.cleanName(source.name, suggested);
      item.userNamed = source.userNamed;
      item.sourcePage = pageUrl;
      item.batchId = batchId;
      item.createdAt = Date.now();
      const dir: string = zipMode ? filesDir + '/staging/' + batchId : filesDir + '/images';
      item.name = DownloadStore.uniqueName(item.name, dir);
      item.path = dir + '/' + item.name;
      DownloadStore.downloads.unshift(item);
    }
    DownloadStore.notify();
    DownloadStore.pump();
  }

  static setConcurrency(value: number): void {
    DownloadStore.concurrency = Math.max(1, Math.min(10, value));
    DownloadStore.notify();
    DownloadStore.pump();
  }

  static setThemeMode(value: string): void {
    DownloadStore.themeMode = value;
    DownloadStore.notify();
  }

  static setMaterialType(value: string): void {
    DownloadStore.materialType = value;
    DownloadStore.notify();
  }

  static setLightEffect(value: boolean): void {
    DownloadStore.lightEffect = value;
    DownloadStore.notify();
  }

  /** Bytes currently held by downloaded images and archives. */
  static usedBytes(): number {
    let total: number = 0;
    for (const item of DownloadStore.downloads) {
      total += orNumber(item.size, 0);
    }
    for (const zip of DownloadStore.zips) {
      total += orNumber(zip.size, 0);
    }
    return total;
  }

  /**
   * Delete every downloaded file and every record.
   *
   * Staging directories of batches that are still downloading or packing are
   * left alone: their files are inputs to a pack that has not finished yet.
   */
  static clearAll(): void {
    for (const item of DownloadStore.downloads) {
      DownloadStore.removeFile(item.path);
    }
    for (const zip of DownloadStore.zips) {
      DownloadStore.removeFile(zip.path);
    }
    for (const batch of DownloadStore.batches) {
      if (batch.status === 'downloading' || batch.status === 'packing') {
        continue;
      }
      DownloadStore.removeDirectory(DownloadStore.context.filesDir + '/staging/' + batch.id);
    }
    DownloadStore.downloads = [];
    DownloadStore.zips = [];
    DownloadStore.batches = [];
    DownloadStore.notify();
  }

  /**
   * Remove staging leftovers from interrupted packs and report the bytes freed.
   * Batches that are still in flight keep their staging directory.
   */
  static cleanStaging(): number {
    const root: string = DownloadStore.context.filesDir + '/staging';
    const busy: string[] = DownloadStore.batches
      .filter((batch: BatchItem): boolean => batch.status === 'downloading' || batch.status === 'packing')
      .map((batch: BatchItem): string => batch.id);
    let freed: number = 0;
    try {
      for (const entry of fs.listFileSync(root)) {
        if (busy.includes(entry)) {
          continue;
        }
        const directory: string = root + '/' + entry;
        try {
          for (const file of fs.listFileSync(directory)) {
            const path: string = directory + '/' + file;
            try {
              freed += fs.statSync(path).size;
            } catch (error) {
            }
            DownloadStore.removeFile(path);
          }
        } catch (error) {
        }
        DownloadStore.removeDirectory(directory);
      }
    } catch (error) {
    }
    return freed;
  }

  static removeDirectory(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.rmdirSync(path);
      }
    } catch (error) {
    }
  }

  static pump(): void {
    const limit: number = DownloadStore.concurrency;
    while (DownloadStore.downloads.filter((item: DownloadItem): boolean => item.status === 'running' || item.status === 'starting').length < limit) {
      const next: DownloadItem | undefined = DownloadStore.downloads.find((item: DownloadItem): boolean => item.status === 'queued');
      if (next === undefined) { break; }
      next.status = 'starting';
      DownloadStore.notify();
      DownloadStore.start(next);
    }
  }

  static async start(item: DownloadItem): Promise<void> {
    if (canIUse('SystemCapability.Request.FileTransferAgent')) {
      try {
        const headers: Record<string, string> = {};
        if (item.sourcePage.startsWith('http')) { headers['Referer'] = item.sourcePage; }
        try {
          const cookie: string = webview.WebCookieManager.fetchCookieSync(item.url);
          if (cookie.length > 0) { headers['Cookie'] = cookie; }
        } catch (error) {}
        // @SuppressWarnings syscap
        const config: request.agent.Config = {
          action: request.agent.Action.DOWNLOAD,
          url: item.url,
          saveas: item.path,
          mode: request.agent.Mode.BACKGROUND,
          overwrite: true,
          network: request.agent.Network.ANY,
          metered: true,
          gauge: true,
          headers: headers
        };
        // @SuppressWarnings syscap
        const task: request.agent.Task = await request.agent.create(DownloadStore.context, config);
        if (item.status === 'cancelled') {
          try {
            // @SuppressWarnings syscap
            await request.agent.remove(task.tid);
          } catch (error) {}
          return;
        }
        item.taskId = task.tid;
        item.status = 'running';
        DownloadStore.attach(item, task);
        DownloadStore.notify();
        await task.start();
      } catch (error) {
        DownloadStore.fail(item, String(error));
      }
    } else {
      DownloadStore.fail(item, '当前设备不支持后台下载服务');
    }
  }

  static attach(item: DownloadItem, task: request.agent.Task): void {
    DownloadStore.active.set(item.id, task);
    task.on('progress', (progress: request.agent.Progress): void => {
      item.processed = progress.processed;
      item.total = progress.sizes.length > 0 ? progress.sizes[0] : 0;
      if (Date.now() - DownloadStore.lastProgressSaveAt >= 500) {
        DownloadStore.lastProgressSaveAt = Date.now();
        DownloadStore.notify();
      }
    });
    task.on('response', (response: request.agent.HttpResponse): void => {
      if (response.statusCode >= 400) { item.error = 'HTTP ' + response.statusCode.toString(); }
      const contentTypes: string[] | undefined = response.headers.get('content-type') ?? response.headers.get('Content-Type');
      if (contentTypes !== undefined && contentTypes.length > 0 && !contentTypes[0].toLowerCase().startsWith('image/')) {
        item.error = '服务器返回的不是图片';
      }
      const values: string[] | undefined = response.headers.get('content-disposition') ?? response.headers.get('Content-Disposition');
      if (!item.userNamed && values !== undefined && values.length > 0) {
        const match: RegExpExecArray | null = new RegExp("filename\\*?=(?:UTF-8'')?\\\"?([^\\\";]+)", 'i').exec(values[0]);
        if (match !== null && match.length > 1) {
          let proposed: string = match[1];
          try { proposed = decodeURIComponent(proposed); } catch (error) {}
          item.name = DownloadStore.cleanName(proposed, item.name);
        }
      }
      if (contentTypes !== undefined && contentTypes.length > 0 && contentTypes[0].toLowerCase().startsWith('image/')) {
        const extension: string = DownloadStore.imageExtension(contentTypes[0]);
        if (extension.length > 0) { item.name = DownloadStore.withExtension(item.name, extension); }
      }
    });
    task.on('completed', (): void => { DownloadStore.complete(item); });
    task.on('failed', (): void => { DownloadStore.fail(item, '下载失败，请检查链接或登录状态'); });
  }

  static async complete(item: DownloadItem): Promise<void> {
    if (item.status === 'completed' || item.status === 'cancelled') { return; }
    try {
      if (item.error.length > 0) {
        DownloadStore.removeFile(item.path);
        DownloadStore.fail(item, item.error);
        return;
      }
      if (!fs.accessSync(item.path)) { DownloadStore.fail(item, '下载文件不存在'); return; }
      const dir: string = item.path.substring(0, item.path.lastIndexOf('/'));
      const desired: string = dir + '/' + item.name;
      if (desired !== item.path && fs.accessSync(desired)) {
        item.name = DownloadStore.uniqueName(item.name, dir);
      }
      const finalPath: string = dir + '/' + item.name;
      if (finalPath !== item.path) { fs.renameSync(item.path, finalPath); item.path = finalPath; }
      item.status = 'completed';
      item.finishedAt = Date.now();
      try {
        item.size = fs.statSync(finalPath).size;
      } catch (error) {
        item.size = item.total;
      }
      DownloadStore.active.delete(item.id);
      DownloadStore.notify();
      if (canIUse('SystemCapability.Request.FileTransferAgent')) {
        if (item.taskId.length > 0) {
          try {
            // @SuppressWarnings syscap
            await request.agent.remove(item.taskId);
          } catch (error) {}
        }
      }
      DownloadStore.checkBatch(item.batchId);
      DownloadStore.pump();
    } catch (error) {
      DownloadStore.fail(item, '保存下载文件失败：' + String(error));
    }
  }

  static fail(item: DownloadItem, reason: string): void {
    if (item.status === 'cancelled' || item.status === 'completed') { return; }
    item.status = 'failed';
    item.error = item.error.length > 0 ? item.error : reason;
    DownloadStore.active.delete(item.id);
    DownloadStore.notify();
    DownloadStore.checkBatch(item.batchId);
    DownloadStore.pump();
    DownloadStore.discard(item);
  }

  static async discard(item: DownloadItem): Promise<void> {
    const taskId: string = item.taskId;
    if (taskId.length > 0) {
      if (canIUse('SystemCapability.Request.FileTransferAgent')) {
        try {
          // @SuppressWarnings syscap
          await request.agent.remove(taskId);
        } catch (error) {}
      }
      item.taskId = '';
    }
    DownloadStore.removeFile(item.path);
  }

  static async cancel(item: DownloadItem): Promise<void> {
    const task: request.agent.Task | undefined = DownloadStore.active.get(item.id);
    item.status = 'cancelled';
    DownloadStore.active.delete(item.id);
    if (task !== undefined) { try { await task.stop(); } catch (error) {} }
    if (canIUse('SystemCapability.Request.FileTransferAgent')) {
      if (item.taskId.length > 0) {
        try {
          // @SuppressWarnings syscap
          await request.agent.remove(item.taskId);
        } catch (error) {}
      }
    }
    DownloadStore.removeFile(item.path);
    DownloadStore.notify();
    DownloadStore.checkBatch(item.batchId);
    DownloadStore.pump();
  }

  static retry(item: DownloadItem): void {
    if (item.status !== 'failed' && item.status !== 'cancelled') { return; }
    DownloadStore.removeFile(item.path);
    item.status = 'queued'; item.error = ''; item.processed = 0; item.total = 0; item.taskId = '';
    const batch: BatchItem | undefined = DownloadStore.batches.find((entry: BatchItem): boolean => entry.id === item.batchId);
    if (batch !== undefined) { batch.status = 'downloading'; }
    DownloadStore.notify();
    DownloadStore.pump();
  }

  /**
   * Retry a failed batch: re-queue its failed members, and if there are none
   * left to fetch the batch is only re-packed (a compress failure leaves every
   * member completed). Members keep their staging paths, so a retry that
   * succeeds still packs into the same archive.
   */
  static retryBatch(batchId: string): void {
    const batch: BatchItem | undefined = DownloadStore.batches.find((entry: BatchItem): boolean => entry.id === batchId);
    if (batch === undefined) { return; }
    for (const item of DownloadStore.downloads) {
      if (item.batchId !== batchId) { continue; }
      if (item.status !== 'failed' && item.status !== 'cancelled') { continue; }
      DownloadStore.removeFile(item.path);
      item.status = 'queued'; item.error = ''; item.processed = 0; item.total = 0; item.taskId = '';
    }
    batch.status = 'downloading'; batch.error = '';
    DownloadStore.notify();
    DownloadStore.pump();
    DownloadStore.checkBatch(batchId);
  }

  /**
   * Give up on a batch and hand its images back to the task list.
   *
   * Every member is re-homed: its path moves out of the batch's staging
   * directory into the normal image directory and its batchId is cleared, so a
   * released task behaves exactly like a plain one. Without that, a retried
   * member would download into a staging directory that cleanStaging() is free
   * to delete, and the record would end up pointing at a missing file.
   */
  static dismissBatch(batchId: string): void {
    const batch: BatchItem | undefined = DownloadStore.batches.find((entry: BatchItem): boolean => entry.id === batchId);
    if (batch === undefined) { return; }
    const imagesDir: string = DownloadStore.context.filesDir + '/images';
    DownloadStore.ensureDirectory(imagesDir);
    for (const item of DownloadStore.downloads) {
      if (item.batchId !== batchId) { continue; }
      item.batchId = '';
      const name: string = DownloadStore.uniqueName(item.name, imagesDir);
      const target: string = imagesDir + '/' + name;
      if (DownloadStore.exists(item.path)) { DownloadStore.moveFile(item.path, target); }
      item.name = name;
      item.path = target;
    }
    DownloadStore.batches = DownloadStore.batches.filter((entry: BatchItem): boolean => entry.id !== batchId);
    DownloadStore.removeDirectory(DownloadStore.context.filesDir + '/staging/' + batchId);
    DownloadStore.notify();
    DownloadStore.pump();
  }

  static async recover(): Promise<void> {
    for (const item of DownloadStore.downloads) {
      if (item.status === 'queued') { continue; }
      if (item.status !== 'running' && item.status !== 'starting') { continue; }
      if (item.taskId.length === 0) { item.status = 'queued'; continue; }
      if (canIUse('SystemCapability.Request.FileTransferAgent')) {
        try {
          // @SuppressWarnings syscap
          const info: request.agent.TaskInfo = await request.agent.show(item.taskId);
          // @SuppressWarnings syscap
          if (info.progress.state === request.agent.State.COMPLETED) { await DownloadStore.complete(item); continue; }
          // @SuppressWarnings syscap
          if (info.progress.state === request.agent.State.FAILED || info.progress.state === request.agent.State.STOPPED) {
            DownloadStore.fail(item, '任务中断，请重试'); continue;
          }
          // @SuppressWarnings syscap
          const task: request.agent.Task = await request.agent.getTask(DownloadStore.context, item.taskId);
          DownloadStore.attach(item, task);
          item.status = 'running';
        } catch (error) {
          DownloadStore.fail(item, '无法恢复任务，请重试');
        }
      } else {
        item.status = 'queued'; item.taskId = '';
      }
    }
    for (const batch of DownloadStore.batches) {
      if (batch.status === 'packing') {
        const partialPath: string = DownloadStore.context.filesDir + '/archives/' + batch.name;
        if (!DownloadStore.zips.some((item: ZipItem): boolean => item.path === partialPath) && DownloadStore.exists(partialPath)) {
          DownloadStore.removeFile(partialPath);
        }
        batch.status = 'downloading';
      }
      DownloadStore.checkBatch(batch.id);
    }
    DownloadStore.notify();
    DownloadStore.pump();
  }

  static checkBatch(batchId: string): void {
    if (batchId.length === 0) { return; }
    const batch: BatchItem | undefined = DownloadStore.batches.find((entry: BatchItem): boolean => entry.id === batchId);
    if (batch === undefined || batch.status === 'completed' || batch.status === 'packing') { return; }
    const members: DownloadItem[] = DownloadStore.downloads.filter((item: DownloadItem): boolean => item.batchId === batchId);
    if (members.some((item: DownloadItem): boolean => item.status === 'queued' || item.status === 'running' || item.status === 'starting')) { return; }
    const successful: DownloadItem[] = members.filter((item: DownloadItem): boolean => item.status === 'completed' && fs.accessSync(item.path));
    if (successful.length === 0) { batch.status = 'failed'; batch.error = '没有成功下载的图片'; DownloadStore.notify(); return; }
    batch.status = 'packing';
    DownloadStore.notify();
    DownloadStore.pack(batch, successful, members.length - successful.length);
  }

  static async pack(batch: BatchItem, members: DownloadItem[], failedCount: number): Promise<void> {
    const archivesDir: string = DownloadStore.context.filesDir + '/archives';
    const name: string = DownloadStore.uniqueName(batch.name, archivesDir);
    const path: string = archivesDir + '/' + name;
    const paths: string[] = members.map((item: DownloadItem): string => item.path);
    const options: zlib.Options = { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION };
    try {
      await zlib.compressFiles(paths, path, options);
      const archive: ZipItem = new ZipItem();
      archive.id = DownloadStore.nextId(); archive.name = name; archive.path = path;
      archive.batchId = batch.id; archive.imageCount = members.length;
      archive.failedCount = failedCount; archive.createdAt = Date.now();
      try { archive.size = fs.statSync(path).size; } catch (error) { archive.size = 0; }
      // keep a few source URLs so the list can draw a stacked thumbnail; the
      // packed image files themselves are deleted right below
      archive.thumbs = members.slice(0, 3).map((item: DownloadItem): string => item.url);
      DownloadStore.zips.unshift(archive);
      batch.status = 'completed'; batch.name = name;
      // The batch has become an archive, so it leaves 任务 for 打包 — this
      // mirrors the prototype, which drops the batch once it has packed. Its
      // leftover members (the failed ones) go with it; the archive's
      // failedCount is the record of them. Keeping either behind would strand
      // a card that can never progress, since packing deletes the completed
      // members and the counts would then read as "0/0 下载中".
      for (const member of DownloadStore.downloads.filter((item: DownloadItem): boolean =>
        item.batchId === batch.id)) {
        DownloadStore.removeFile(member.path);
      }
      DownloadStore.downloads = DownloadStore.downloads.filter((item: DownloadItem): boolean =>
        item.batchId !== batch.id);
      DownloadStore.batches = DownloadStore.batches.filter((item: BatchItem): boolean => item.id !== batch.id);
      DownloadStore.removeDirectory(DownloadStore.context.filesDir + '/staging/' + batch.id);
    } catch (error) {
      batch.status = 'failed'; batch.error = '压缩失败：' + String(error);
      DownloadStore.removeFile(path);
    }
    DownloadStore.notify();
  }

  static renameDownload(item: DownloadItem, raw: string): boolean {
    if (item.status !== 'completed') { return false; }
    const extension: string = item.name.substring(item.name.lastIndexOf('.') + 1);
    const name: string = DownloadStore.withExtension(raw, extension);
    const dir: string = item.path.substring(0, item.path.lastIndexOf('/'));
    const destination: string = dir + '/' + name;
    if (destination !== item.path && DownloadStore.exists(destination)) { return false; }
    if (destination !== item.path) { DownloadStore.moveFile(item.path, destination); }
    item.name = name; item.path = destination;
    DownloadStore.notify();
    return true;
  }

  static renameZip(item: ZipItem, raw: string): boolean {
    let name: string = DownloadStore.cleanName(raw, item.name);
    if (!name.toLowerCase().endsWith('.zip')) { name += '.zip'; }
    const destination: string = DownloadStore.context.filesDir + '/archives/' + name;
    if (destination !== item.path && DownloadStore.exists(destination)) { return false; }
    if (destination !== item.path) { DownloadStore.moveFile(item.path, destination); }
    item.name = name; item.path = destination;
    DownloadStore.notify();
    return true;
  }

  static deleteDownload(item: DownloadItem): void {
    DownloadStore.removeFile(item.path);
    DownloadStore.downloads = DownloadStore.downloads.filter((entry: DownloadItem): boolean => entry.id !== item.id);
    DownloadStore.notify();
  }

  static deleteZip(item: ZipItem): void {
    DownloadStore.removeFile(item.path);
    DownloadStore.zips = DownloadStore.zips.filter((entry: ZipItem): boolean => entry.id !== item.id);
    DownloadStore.notify();
  }
}
