import { common } from '@kit.AbilityKit';
import { DownloadItem, ZipItem } from '../model/Models';
import { ActionOutcome, copyIntoDirectory, saveImagesToGallery } from './FileActions';
import { MediaFormat } from './MediaFormat';
import { Naming } from './Naming';
import { SaveReceipt } from '../model/SaveReceipt';

/** 相册投递的防抖窗口：把相邻完成的图片攒成一次系统确认框。 */
const GALLERY_DEBOUNCE_MS: number = 800;

/**
 * 一次投递要「往哪投」。
 *
 * 用类而不是接口：默认值要能直接构造（`new DeliveryTarget()` = 应用文件档），
 * 这样 `Delivery` 的注入项都有安全初值。
 */
export class DeliveryTarget {
  /** 'app' 应用文件（不投递）| 'gallery' 系统相册 | 'custom' 自定义目录。 */
  location: string = 'app';
  /** custom 档的目录 URI。 */
  folderUri: string = '';
}

/**
 * 下载完成后的「第二落点」：系统相册 或 用户选的目录（**投递层**）。
 *
 * 从 `service/DownloadStore.ets` 搬出来的是这一整块：投递目标的分派、相册投递的 800ms 防抖、
 * 以及退出应用时把待弹的系统框取消掉。它原来和下载队列、打包、状态持久化挤在同一个静态类里，
 * 而这一块的失败语义是**独立**的 ——
 *
 * > 应用内的那份副本永远保留（图库 / 预览 / 改名 / 导出 / 分享都指着它），
 * > 相册与目录只是用户额外要的一份拷贝，**投递失败绝不能反过来把下载判成失败**。
 *
 * 所以这里只负责「把文件送到第二落点」并如实报出结果；「怎么告诉用户」不归它 ——
 * 通过注入的 `report` 交回商店，由商店写常驻说明与 Toast（与 `service/UiPort.ets` 同一套路）。
 *
 * 注入项都是**函数**而不是值：下载位置在运行时会变（用户随时能在设置页改），
 * 每次投递都必须现读，不能在构造时定死。
 */
export class Delivery {
  changed: () => void = (): void => {};
  private foreground: boolean = true;

  setForeground(value: boolean): void {
    this.foreground = value;
    this.clearTimer();
    if (value && this.galleryQueue.length > 0) { this.scheduleGallery(); }
  }
  /** 注入：UIAbilityContext（存相册要它）。未注入时明确抛错，属于装配错误。 */
  context: () => common.UIAbilityContext = (): common.UIAbilityContext => {
    throw new Error('Delivery.context 尚未注入');
  };
  /** 注入：当前下载位置与自定义目录。 */
  target: () => DeliveryTarget = (): DeliveryTarget => new DeliveryTarget();
  /** 注入：文件是否还在（相册防抖窗口里用户可能已经删掉某张）。 */
  alive: (path: string) => boolean = (path: string): boolean => false;
  /** 注入：投递结果；由商店决定写常驻说明还是弹一次。 */
  report: (outcome: ActionOutcome, where: string) => void =
    (outcome: ActionOutcome, where: string): void => {
    };

  /** 待存相册的图片与防抖定时器。 */
  private galleryQueue: DownloadItem[] = [];
  private galleryTimer: number = -1;
  /** 一次系统确认框关闭后才开始下一组；下载仍可继续入队。 */
  private galleryChain: Promise<void> = Promise.resolve();
  private galleryGeneration: number = 0;

  /**
   * 下载完成后的投递入口。
   *
   * 打包批次里的图片不在这里投递：它们下完就被 zip 收走、随即删除，
   * 真正该进用户目录的是打完的压缩包（见 `deliverArchive`）。
   */
  async deliver(item: DownloadItem, retry: boolean = false): Promise<void> {
    if (item.batchId.length > 0) {
      return;
    }
    const target: DeliveryTarget = this.target();
    if (!retry) { this.prepare(item.receipt, target); }
    if (item.receipt.target === 'gallery') {
      item.receipt.status = 'pending';
      item.receipt.message = '等待确认保存到系统相册';
      this.changed();
      this.queueToGallery(item);
      return;
    }
    if (item.receipt.target === 'custom') {
      item.receipt.status = 'pending';
      item.receipt.message = '正在另存到自定义目录';
      this.changed();
      const outcome: ActionOutcome = await copyIntoDirectory(item.path, item.receipt.folderUri, item.name);
      this.finish(item.receipt, outcome, '自定义目录');
      this.report(outcome, '自定义目录');
    }
  }

  /** 压缩包打完后的投递；系统相册只收图片，所以这条只对自定义目录有意义。 */
  async deliverArchive(archive: ZipItem, retry: boolean = false): Promise<void> {
    const target: DeliveryTarget = this.target();
    if (!retry) { this.prepare(archive.receipt, target.location === 'gallery' ? new DeliveryTarget() : target); }
    if (archive.receipt.target !== 'custom') {
      return;
    }
    archive.receipt.status = 'pending';
    archive.receipt.message = '正在另存到自定义目录';
    this.changed();
    const outcome: ActionOutcome = await copyIntoDirectory(archive.path, archive.receipt.folderUri, archive.name);
    this.finish(archive.receipt, outcome, '自定义目录');
    this.report(outcome, '自定义目录');
  }

  /**
   * 应用退出时取消排队中的相册投递。
   *
   * 相册投递是 800ms 防抖 + 系统确认框：用户下完一张图立刻退出应用时，定时器还挂着，
   * flush 会在**别的应用上面**弹一个系统框。文件的应用内副本已经安全落盘，
   * 这次「第二落点」不做了，下次下载会重新触发。
   */
  stop(): void {
    this.clearTimer();
    this.galleryQueue = [];
    this.galleryGeneration++;
  }

  private prepare(receipt: SaveReceipt, target: DeliveryTarget): void {
    receipt.target = target.location;
    receipt.folderUri = target.folderUri;
    receipt.status = target.location === 'app' ? 'local' : 'pending';
    receipt.message = target.location === 'app' ? '原件保存在应用内' : '等待另存';
    receipt.parts = [];
    this.changed();
  }

  private finish(receipt: SaveReceipt, outcome: ActionOutcome, where: string): void {
    receipt.status = outcome.ok ? 'saved' : (outcome.cancelled ? 'cancelled' : 'failed');
    receipt.message = outcome.ok ? '已另存到' + where
      : (outcome.cancelled ? '已取消另存到' : '未能另存到') + where + '，应用内原件仍保留';
    if (!outcome.ok && !outcome.cancelled && outcome.message.length > 0) {
      receipt.message += '；' + outcome.message;
    }
    this.changed();
  }

  /**
   * 攒一批再存相册。
   *
   * 存相册要弹系统的「保存到相册」确认框（见 `FileActions.saveImagesToGallery`），
   * 一张一弹在批量下载时会弹到用户脸上。这里用一小段防抖把相邻完成的图片攒在一起；
   * 每 100 个实际文件确认一次，后一批等前一批完成再弹。
   */
  private queueToGallery(item: DownloadItem): void {
    this.galleryQueue.push(item);
    this.scheduleGallery();
  }

  private scheduleGallery(): void {
    this.clearTimer();
    if (!this.foreground) { return; }
    this.galleryTimer = setTimeout((): void => {
      this.galleryTimer = -1;
      const queued: DownloadItem[] = this.galleryQueue;
      this.galleryQueue = [];
      const generation: number = this.galleryGeneration;
      this.galleryChain = this.galleryChain.then(async (): Promise<void> => {
        if (generation === this.galleryGeneration) {
          if (this.foreground) { await this.flushGallery(queued, generation); }
          else { this.galleryQueue = queued.concat(this.galleryQueue); }
        }
      }).catch((error: Object): void => {
        for (const item of queued) {
          this.finish(item.receipt, { ok: false, message: '保存中断，请重试' }, '系统相册');
        }
        this.report({ ok: false, message: String(error) }, '系统相册');
      });
    }, GALLERY_DEBOUNCE_MS);
  }

  private async flushGallery(queued: DownloadItem[], generation: number): Promise<void> {
    // 入队到真正弹框之间有 800ms：这期间用户可能已经删掉某张、或「清空全部」，
    // 拿着不存在的路径去弹系统框只会换来一条假的投递失败，所以 flush 前先过一遍文件还在不在。
    const batch: DownloadItem[] = queued.filter((entry: DownloadItem): boolean => this.usable(entry));
    // 实况照片没解出静图 + 视频（解包失败）就等于没有可投递的内容：如实报一次失败，
    // 由商店写进设置页那行并弹一次，别让用户以为「下载成功了但相册里没有」。
    const liveDropped: boolean = queued.some((entry: DownloadItem): boolean =>
      entry.kind === 'livephoto' && !this.usable(entry));
    if (liveDropped) {
      for (const item of queued) {
        if (item.kind === 'livephoto' && !this.usable(item)) {
          this.finish(item.receipt, { ok: false, message: '实况照片包没有解出静图与视频' }, '系统相册');
        }
      }
      this.report({
        ok: false,
        message: '实况照片包没有解出静图与视频，未能存入相册（应用内已保留原包）'
      }, '系统相册');
    }
    if (batch.length === 0) {
      return;
    }
    const paths: string[] = [];
    const names: string[] = [];
    const owners: DownloadItem[] = [];
    const parts: string[] = [];
    for (const entry of batch) {
      if (entry.kind !== 'livephoto') {
        if (!entry.receipt.parts.includes('image')) {
          paths.push(entry.path);
          names.push(entry.name);
          owners.push(entry);
          parts.push('image');
        }
        continue;
      }
      // 免权限的「保存到相册」确认框只支持 DEFAULT 图片（见 FileActions.saveImagesToGallery），
      // 存不成实况照片，所以静图与视频**各存一份**：两个部分都留住了，原包也还在应用里。
      if (!entry.receipt.parts.includes('still')) {
        paths.push(entry.stillPath);
        names.push(Naming.withExtension(entry.name, MediaFormat.extensionOf(entry.stillPath)));
        owners.push(entry);
        parts.push('still');
      }
      if (!entry.receipt.parts.includes('motion')) {
        paths.push(entry.motionPath);
        names.push(Naming.withExtension(entry.name, MediaFormat.extensionOf(entry.motionPath)));
        owners.push(entry);
        parts.push('motion');
      }
    }
    const outcome: ActionOutcome = await saveImagesToGallery(this.context(), paths, names,
      (): boolean => generation === this.galleryGeneration && this.foreground,
      (savedPaths: string[], downgraded: boolean): void => {
        for (let i: number = 0; i < paths.length; i++) {
          if (!savedPaths.includes(paths[i])) { continue; }
          const receipt: SaveReceipt = owners[i].receipt;
          if (!receipt.parts.includes(parts[i])) { receipt.parts = receipt.parts.concat([parts[i]]); }
          if (downgraded) { receipt.message = '本批部分动图已按静态图保存，原件仍保留'; }
        }
        this.changed();
      });
    for (const item of batch) {
      const complete: boolean = item.kind === 'livephoto'
        ? item.receipt.parts.includes('still') && item.receipt.parts.includes('motion')
        : item.receipt.parts.includes('image');
      const warning: string = item.receipt.message.includes('静态图') ? item.receipt.message : '';
      this.finish(item.receipt, { ok: complete, cancelled: !complete && outcome.cancelled,
        message: complete ? '' : outcome.message }, '系统相册');
      if (complete && item.kind === 'livephoto') { item.receipt.message = '已将静图与视频分别保存到系统相册'; }
      if (complete && warning.length > 0) { item.receipt.message = warning; }
      if (!complete && item.receipt.parts.length > 0) { item.receipt.message += '；部分已保存，重试只处理剩余部分'; }
    }
    this.changed();
    this.report(outcome, '系统相册');
  }

  /** 这条记录此刻有没有可投递的东西：实况照片要静图与视频都在。 */
  private usable(item: DownloadItem): boolean {
    if (item.kind === 'livephoto') {
      return item.stillPath.length > 0 && item.motionPath.length > 0
        && this.alive(item.stillPath) && this.alive(item.motionPath);
    }
    return this.alive(item.path);
  }

  private clearTimer(): void {
    if (this.galleryTimer >= 0) {
      clearTimeout(this.galleryTimer);
      this.galleryTimer = -1;
    }
  }
}
