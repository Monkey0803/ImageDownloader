import { BatchItem, DownloadItem, orBoolean, orNumber, orString, SavedState, ZipItem } from '../model/Models';
import { normalizeLocation, normalizeQuality } from '../model/SettingsOptions';

/**
 * 落盘状态的编解码（**持久化层**）。
 *
 * 这两个动作原来长在 `service/DownloadStore.ets` 的 `adopt()` 里，一共五十多行「逐字段给默认值」
 * 的代码，和下载队列、文件系统操作混在同一个静态类中；而且它只被 `initialize()` 调用，
 * 而 `initialize` 需要 `UIAbilityContext` —— 也就是说「读到一个老版本 / 脏的状态文件会怎样」
 * 这条路径**没法写单测**。
 *
 * 拆出来之后：
 * - `parse(raw)`：纯 JSON 解析，坏了返回 `undefined`（调用方决定怎么兜）；
 * - `normalized(state)`：把任意来源的状态整成「字段齐全 + 真实模型实例 + 取值归一」；
 * - 两者都不碰 `DownloadStore` 的静态字段，所以可以单独喂字符串测（见 ohosTest 里的
 *   `StoreState` 那几组用例）。
 *
 * 为什么要把普通对象重新实例化成模型：界面用 `@ObjectLink` 绑它们，而 `@ObjectLink` 只认
 * `@Observed` 实例 —— `JSON.parse` 出来的裸对象绑不上，进度和选中都不会刷新。
 */
export class StoreState {
  /** 解析失败（空文件、被截断、根本不是 JSON）返回 `undefined`，由调用方决定兜底策略。 */
  static parse(raw: string): SavedState | undefined {
    try {
      return JSON.parse(raw) as SavedState;
    } catch (error) {
      return undefined;
    }
  }

  /**
   * 把状态整成可以直接用的样子：每条记录都是真的 `@Observed` 模型实例，每个字段都有值。
   *
   * 老版本的状态文件缺字段（`undefined`），手工改过的文件可能写着 `null` —— 两者都在这里
   * 被兜成默认值，所以下游（界面、投递、打包）都不需要再各自防御一次。
   */
  static normalized(state: SavedState): SavedState {
    const safe: SavedState = new SavedState();

    // downloads 里的 finishedAt 有个特殊默认值：老文件没这个字段时退回 createdAt，
    // 否则图库会显示成 1970 年。
    safe.downloads = (state.downloads ?? []).map((entry: DownloadItem): DownloadItem => {
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
      item.kind = orString(entry.kind, 'image');
      item.animated = orBoolean(entry.animated, false);
      item.stillPath = orString(entry.stillPath, '');
      item.motionPath = orString(entry.motionPath, '');
      item.auxSize = orNumber(entry.auxSize, 0);
      item.note = orString(entry.note, '');
      return item;
    });

    safe.zips = (state.zips ?? []).map((entry: ZipItem): ZipItem => {
      const zip: ZipItem = new ZipItem();
      zip.id = orString(entry.id, '');
      zip.name = orString(entry.name, '');
      zip.path = orString(entry.path, '');
      zip.batchId = orString(entry.batchId, '');
      zip.imageCount = orNumber(entry.imageCount, 0);
      zip.failedCount = orNumber(entry.failedCount, 0);
      zip.size = orNumber(entry.size, 0);
      zip.createdAt = orNumber(entry.createdAt, 0);
      // `??` 同时兜 undefined 与 null（`=== undefined` 放不过 null，见 model/Models.ets 的说明）。
      zip.thumbs = entry.thumbs ?? [];
      return zip;
    });

    safe.batches = (state.batches ?? []).map((entry: BatchItem): BatchItem => {
      const batch: BatchItem = new BatchItem();
      batch.id = orString(entry.id, '');
      batch.name = orString(entry.name, '');
      batch.sourcePage = orString(entry.sourcePage, '');
      batch.status = orString(entry.status, 'downloading');
      batch.error = orString(entry.error, '');
      return batch;
    });

    safe.concurrency = Math.max(1, Math.min(10, orNumber(state.concurrency, 3)));
    safe.themeMode = orString(state.themeMode, 'system');
    safe.materialType = orString(state.materialType, 'adaptive');
    safe.materialLevel = orString(state.materialLevel, 'adaptive');
    safe.lightEffect = orBoolean(state.lightEffect, true);
    safe.gripEnabled = orBoolean(state.gripEnabled, false);
    safe.antiPeepEnabled = orBoolean(state.antiPeepEnabled, false);
    safe.customDirUri = orString(state.customDirUri, '');
    safe.customDirName = orString(state.customDirName, '');
    safe.pictureQuality = normalizeQuality(orString(state.pictureQuality, 'all'));
    // 下载位置的归一依赖 customDirUri，所以放在它之后。
    safe.downloadLocation =
      normalizeLocation(orString(state.downloadLocation, 'app'), safe.customDirUri);
    return safe;
  }
}
