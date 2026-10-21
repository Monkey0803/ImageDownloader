import { common } from '@kit.AbilityKit';
import { request, zlib } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { webview } from '@kit.ArkWeb';
import {
  BatchItem, DownloadItem, orNumber, PictureItem, SavedState, ZipItem
} from '../model/Models';
import { normalizeLocation, normalizeQuality } from '../model/SettingsOptions';
import { StoreState } from './StoreState';
import { GripSensor } from './GripSensor';
import { AntiPeep } from './AntiPeep';
import { Naming } from './Naming';
import { ActionOutcome, activateFolder } from './FileActions';
import { Delivery, DeliveryTarget } from './Delivery';
import { LivePhoto, LivePhotoContent } from './LivePhoto';
import { StillFrames } from './StillFrames';
import { WidgetForms } from '../widget/WidgetForms';
import { WidgetSnapshot } from '../widget/WidgetSnapshot';

interface ProgressSample {
  bytes: number;
  at: number;
}

export class DownloadStore {
  static context: common.UIAbilityContext;
  static downloads: DownloadItem[] = [];
  static zips: ZipItem[] = [];
  static batches: BatchItem[] = [];
  static concurrency: number = 3;
  static wifiOnly: boolean = false;
  /** 'system' | 'light' | 'dark' — see applyTheme(). */
  static themeMode: string = 'system';
  /** 'adaptive' | 'immersive'. */
  static materialType: string = 'adaptive';
  /** 沉浸光感材质等级：'exquisite' | 'gentle' | 'smooth' | 'adaptive'。 */
  static materialLevel: string = 'adaptive';
  /** Whether the immersive material lights up under touch. */
  static lightEffect: boolean = true;
  /** 智感握姿：主操作是否跟随握持手；开启时同时订阅系统的握持手感知。 */
  static gripEnabled: boolean = false;
  /** 防窥保护：开启时订阅系统窥视状态，检测到窥视就遮罩内容。 */
  static antiPeepEnabled: boolean = false;
  /**
   * 扫描取图策略：'original' 原图优先（默认）| 'display' 网页显示图 | 'all' 每个候选地址各收一张。
   *
   * 只在发现页扫描的那一刻被读取，下载 / 打包 / 投递都不看这个字段。
   */
  static pictureQuality: string = 'original';
  /** 下载位置：'app' 应用文件（默认）| 'gallery' 系统相册 | 'custom' 自定义目录。 */
  static downloadLocation: string = 'app';
  /** 用户选的目录；只有 downloadLocation 为 'custom' 时非空。 */
  static customDirUri: string = '';
  static customDirName: string = '';
  /** 最近一次投递到相册 / 自定义目录失败的原因；成功后清空，写在设置页那一行。 */
  static destinationProblem: string = '';
  /** 状态写盘失败的原因；成功后清空，写在设置页「数据」那一节。 */
  static saveProblem: string = '';
  /** 给界面弹一次的提示（投递失败这类商店里拿不到 UI 上下文的事），读出即清空。 */
  static pendingNotice: string = '';
  /** 投递层（第二落点：系统相册 / 自定义目录）；装配见 wireDelivery()。 */
  static delivery: Delivery = new Delivery();
  static active: Map<string, request.agent.Task> = new Map<string, request.agent.Task>();
  static progressSamples: Map<string, ProgressSample> = new Map<string, ProgressSample>();
  /** 用户的 pause() 尚未返回时，区分其 PAUSED 回调与系统自动暂停。 */
  private static pauseRequests: Set<string> = new Set<string>();
  /** 取消任务的系统清理尚未结束时，不允许同一记录立即重试。 */
  private static cancelRequests: Set<string> = new Set<string>();
  /** 在场页面的刷新回调；Index 常驻，图库预览页挂上来又摘下去。 */
  static listeners: (() => void)[] = [];
  static serial: number = 0;
  static lastProgressSaveAt: number = 0;
  private static lastWidgetProgressAt: number = 0;
  /**
   * 合并落盘的定时器；-1 表示没有排队中的写盘。
   *
   * 进度回调（见 attach）每 500ms 就 notify 一次，并发 7 个任务就是每秒十几次
   * 「整个 downloads 列表 → JSON → 写文件」。进度只是装饰性字段，晚一秒落盘没有影响，
   * 所以高频路径走 `notifyProgress()` 把写盘合并成最多每秒一次；
   * 状态跃迁与用户显式操作仍走 `notify()` 立刻落盘。
   */
  static saveTimer: number = -1;
  /** pump() 正在跑；防止 start() → fail() → pump() 的同步回调把递归压成爆栈。 */
  static pumping: boolean = false;
  /** pump() 在跑的过程中被重入过：外层那一轮结束后要再补一轮。 */
  static pumpAgain: boolean = false;
  /** 同一批次的压缩只能有一个在途调用，恢复时的回调也不能启动第二次。 */
  private static packingBatches: Set<string> = new Set<string>();

  static exists(path: string): boolean {
    try { return fs.accessSync(path); } catch (error) { return false; }
  }

  static removeFile(path: string): void {
    try { if (fs.accessSync(path)) { fs.unlinkSync(path); } } catch (error) {}
  }

  /**
   * 移动文件，返回是否真的成功。
   *
   * **必须返回结果**：调用方（改名、解散批次）原来在调用后无条件把 `item.path` 改成目标路径，
   * 一旦 `renameSync` 抛异常（源文件被外部删掉、权限、跨设备），记录就指向一个不存在的文件 ——
   * 列表里看着是「已完成」，点开是坏图，分享 / 导出全部失败，而用户毫不知情。
   */
  static moveFile(source: string, target: string): boolean {
    try {
      fs.renameSync(source, target);
      return true;
    } catch (error) {
      return false;
    }
  }

  static initialize(context: common.UIAbilityContext, listener: () => void): void {
    DownloadStore.context = context;
    DownloadStore.listeners = [listener];
    DownloadStore.wireDelivery();
    DownloadStore.ensureDirectory(context.filesDir + '/images');
    DownloadStore.ensureDirectory(context.filesDir + '/archives');
    DownloadStore.ensureDirectory(context.filesDir + '/staging');
    // 实况照片包解出来的静图与视频落在这里，目录名是下载记录的 id（改名不影响它）。
    DownloadStore.ensureDirectory(context.filesDir + '/livephotos');
    const statePath: string = context.filesDir + '/download-state.json';
    if (DownloadStore.exists(statePath)) {
      // 读文件与解析都可能失败（被截断、空文件、权限），失败就当作「没有记录」：
      // 宁可空着启动，也不要拿半份状态去渲染。解码规则全在 StoreState 里，可单独测。
      let parsed: SavedState | undefined = undefined;
      try {
        parsed = StoreState.parse(fs.readTextSync(statePath));
      } catch (error) {
        parsed = undefined;
      }
      DownloadStore.adopt(parsed ?? new SavedState());
    }
    DownloadStore.recover();
    DownloadStore.publishWidget();
    // 状态文件里记着开关：启动时把订阅恢复成和开关一致，否则重启后主操作不再跟随握持手。
    GripSensor.setEnabled(DownloadStore.gripEnabled);
    // 防窥保护同理，但这里不带 context：启动恢复订阅绝不能拉起系统弹窗去打扰用户。
    AntiPeep.setEnabled(DownloadStore.antiPeepEnabled);
    // 自定义目录的持久化授权重启后要重新激活一次；失败只标在设置页那行，不阻断启动。
    DownloadStore.rearmFolder();
  }

  /**
   * 把投递层的注入项接上。
   *
   * `target` 是**函数**而不是值：下载位置用户随时能在设置页改，每次投递都必须现读。
   * `report` 回到 `noteDelivery`，由商店决定怎么写常驻说明与 Toast —— 投递层只负责把文件送到，
   * 不负责怎么告诉用户（同 `service/UiPort.ets` 的分工）。
   *
   * 只在这里装配一次：`initialize` 之前不会有下载完成，所以不会出现「未注入就被调用」。
   */
  private static wireDelivery(): void {
    const delivery: Delivery = DownloadStore.delivery;
    delivery.context = (): common.UIAbilityContext => DownloadStore.context;
    delivery.target = (): DeliveryTarget => {
      const target: DeliveryTarget = new DeliveryTarget();
      target.location = DownloadStore.downloadLocation;
      target.folderUri = DownloadStore.customDirUri;
      return target;
    };
    delivery.alive = (path: string): boolean => DownloadStore.exists(path);
    delivery.report = (outcome: ActionOutcome, where: string): void => {
      DownloadStore.noteDelivery(outcome, where);
    };
  }

  /**
   * 重新启用自定义目录的持久化授权。
   *
   * 平台对用户目录**普遍拒绝持久化**（真机实测持久化时就返回「URI forbid to be persisted!」），
   * 所以这条路径经常是失败的那条：失败时把下载位置退回「应用文件」并在设置页那行说明原因，
   * 而不是留着 custom 档让之后每个下载都投递失败、弹一串 Toast。
   * 目录 URI 与名字保留着，用户想继续用就在设置页再选一次。
   */
  static async rearmFolder(): Promise<void> {
    if (DownloadStore.downloadLocation !== 'custom' || DownloadStore.customDirUri.length === 0) {
      return;
    }
    const active: boolean = await activateFolder(DownloadStore.customDirUri);
    if (!active) {
      DownloadStore.downloadLocation = 'app';
      DownloadStore.destinationProblem = '自定义目录授权已失效，已改回应用文件，请重新选择';
      DownloadStore.notify();
    }
  }

  /** 页面挂上刷新回调（预览页用；Index 走 initialize）。 */
  static subscribe(listener: () => void): void {
    if (!DownloadStore.listeners.includes(listener)) {
      DownloadStore.listeners.push(listener);
    }
  }

  static unsubscribe(listener: () => void): void {
    DownloadStore.listeners = DownloadStore.listeners.filter((entry: () => void): boolean => entry !== listener);
  }

  /** 读出并清空待弹的提示；页面不可见时不要调，否则这条提示就没人看见。 */
  static takeNotice(): string {
    const text: string = DownloadStore.pendingNotice;
    DownloadStore.pendingNotice = '';
    return text;
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
    // 补默认值、把裸对象变成 @Observed 实例、归一脏值 —— 全在持久化层，见 service/StoreState.ets。
    // 这里只做赋值，所以可以直接被单测喂一个手搓的 SavedState。
    const safe: SavedState = StoreState.normalized(state);
    DownloadStore.downloads = safe.downloads;
    DownloadStore.zips = safe.zips;
    DownloadStore.batches = safe.batches;
    DownloadStore.concurrency = safe.concurrency;
    DownloadStore.wifiOnly = safe.wifiOnly;
    DownloadStore.themeMode = safe.themeMode;
    DownloadStore.materialType = safe.materialType;
    DownloadStore.materialLevel = safe.materialLevel;
    DownloadStore.lightEffect = safe.lightEffect;
    DownloadStore.gripEnabled = safe.gripEnabled;
    DownloadStore.antiPeepEnabled = safe.antiPeepEnabled;
    DownloadStore.pictureQuality = safe.pictureQuality;
    DownloadStore.downloadLocation = safe.downloadLocation;
    DownloadStore.customDirUri = safe.customDirUri;
    DownloadStore.customDirName = safe.customDirName;
  }

  static ensureDirectory(path: string): void {
    try {
      if (!fs.accessSync(path)) { fs.mkdirSync(path, true); }
    } catch (error) {}
  }

  /**
   * 通知界面，并**立刻**把状态写盘。
   *
   * 默认出口：状态跃迁（完成 / 失败 / 取消 / 重试）、增删记录、改设置、清空都用它 ——
   * 这些变化晚一秒落盘都可能真的丢东西。高频的下载进度请用 `notifyProgress()`。
   */
  static notify(): void {
    // 立刻写盘就等于把排队中的那次合并写盘取代了，先撤掉定时器，免得再白写一遍。
    DownloadStore.cancelPendingSave();
    DownloadStore.save();
    DownloadStore.publishWidget();
    DownloadStore.emit();
  }

  /**
   * 进度专用的通知：界面照常刷，但**写盘合并到最多每秒一次**。
   *
   * 下载进度回调每 500ms 来一次（见 attach 里的 lastProgressSaveAt 节流），
   * 并发 7 个任务时每秒会有十几次 notify，每次都把整个 downloads 列表序列化写文件 ——
   * 而 `processed` 只是进度条上的一个数字，晚一秒落盘不影响任何持久化语义。
   */
  static notifyProgress(): void {
    DownloadStore.scheduleSave();
    const now: number = Date.now();
    if (now - DownloadStore.lastWidgetProgressAt >= 15000) {
      DownloadStore.lastWidgetProgressAt = now;
      DownloadStore.publishWidget();
    }
    DownloadStore.emit();
  }

  private static publishWidget(): void {
    if (DownloadStore.context === undefined) { return; }
    WidgetForms.publish(DownloadStore.context.filesDir,
      WidgetSnapshot.from(DownloadStore.downloads, DownloadStore.batches, DownloadStore.antiPeepEnabled));
  }

  /** 把界面回调跑一遍；先取快照，回调里（预览页的 onDelete）可能把自己摘掉。 */
  private static emit(): void {
    for (const listener of DownloadStore.listeners.slice()) {
      listener();
    }
  }

  private static scheduleSave(): void {
    if (DownloadStore.saveTimer >= 0) {
      return;
    }
    DownloadStore.saveTimer = setTimeout((): void => {
      DownloadStore.saveTimer = -1;
      DownloadStore.save();
    }, 1000);
  }

  private static cancelPendingSave(): void {
    if (DownloadStore.saveTimer >= 0) {
      clearTimeout(DownloadStore.saveTimer);
      DownloadStore.saveTimer = -1;
    }
  }

  static save(): void {
    const state: SavedState = new SavedState();
    state.downloads = DownloadStore.downloads;
    state.zips = DownloadStore.zips;
    state.batches = DownloadStore.batches;
    state.concurrency = DownloadStore.concurrency;
    state.wifiOnly = DownloadStore.wifiOnly;
    state.themeMode = DownloadStore.themeMode;
    state.materialType = DownloadStore.materialType;
    state.materialLevel = DownloadStore.materialLevel;
    state.lightEffect = DownloadStore.lightEffect;
    state.gripEnabled = DownloadStore.gripEnabled;
    state.antiPeepEnabled = DownloadStore.antiPeepEnabled;
    state.pictureQuality = DownloadStore.pictureQuality;
    state.downloadLocation = DownloadStore.downloadLocation;
    state.customDirUri = DownloadStore.customDirUri;
    state.customDirName = DownloadStore.customDirName;
    const path: string = DownloadStore.context.filesDir + '/download-state.json';
    const temp: string = path + '.tmp';
    try {
      const file: fs.File = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, StoreState.serialize(state));
      fs.closeSync(file);
      fs.renameSync(temp, path);
      DownloadStore.saveProblem = '';
    } catch (error) {
      /*
       * 写盘失败原来被完全吞掉：磁盘满 / 权限异常时，设置与下载记录会在下次启动时**静默**
       * 退回到上一次成功写入的样子，用户只会觉得「我的设置怎么自己变了」。
       * 这里至少留两处痕迹：日志（事后可查）与 `saveProblem`（设置页那行会写出来）。
       *
       * 不弹 Toast：写盘每次数据变化都会试一次，失败会连着弹，反而盖住真正有用的提示。
       */
      DownloadStore.saveProblem = '状态保存失败，设置与记录可能在重启后丢失';
      console.error('save state failed: ' + String(error));
    }
  }

  static nextId(): string {
    DownloadStore.serial += 1;
    return Date.now().toString() + '_' + DownloadStore.serial.toString();
  }

  /**
   * 在 `directory` 里找一个不与现有文件 / 记录冲突的名字（同名就变 `a (2).png`）。
   *
   * 要查两处：磁盘上真实存在的文件，以及 `downloads` 里已占用的路径（任务刚入队、文件还没落盘）。
   * 单纯查磁盘是不够的 —— 一次入队 20 张同名图时，前面 19 条都还没有文件。
   *
   * 单条改名用它就够；**批量入队不要逐条调**，那是 O(n²)（每条都要扫一遍整张表），
   * 批量路径见 `uniqueNameIn`。
   */
  static uniqueName(name: string, directory: string): string {
    const taken: Set<string> = new Set<string>();
    for (const item of DownloadStore.downloads) {
      taken.add(item.path);
    }
    return DownloadStore.uniqueNameIn(name, directory, taken);
  }

  /**
   * `uniqueName` 的内部实现：已占用的路径由调用方一次算好并**持续维护**。
   *
   * 批量的意义在这里：`add()` 一次入队 N 张图，原来每张都 `downloads.some(...)` 扫全表，
   * 加起来是 O(N²)。现在传入的集合是增量的（每定下一个名字就加进去），整体降到 O(N)。
   */
  private static uniqueNameIn(name: string, directory: string, taken: Set<string>): string {
    const dot: number = name.lastIndexOf('.');
    const base: string = dot > 0 ? name.substring(0, dot) : name;
    const extension: string = dot > 0 ? name.substring(dot) : '';
    let candidate: string = name;
    let count: number = 2;
    while (taken.has(directory + '/' + candidate) || DownloadStore.exists(directory + '/' + candidate)) {
      candidate = base + ' (' + count.toString() + ')' + extension;
      count += 1;
      if (count > 10000) {
        // 兜底：`exists` 在个别平台上会把不存在的文件报成存在（见 AGENT.md 坑 7），
        // 真出现那种情况时这里会一直找下去 —— 宁可给一个可能冲突的名字，也不能把界面卡死。
        break;
      }
    }
    taken.add(directory + '/' + candidate);
    return candidate;
  }

  /**
   * 入队：把选中的图片（或实况照片包）变成下载记录。
   *
   * 实况照片包（`kind === 'livephoto'`）**不进 ZIP 批次**：打完包只剩下一个压缩包，
   * 解包、播放、存相册全都无从谈起。它们落在 `filesDir/livephotos`，按整包单文件下载，
   * 下完由 `finishContent()` 解包成静图 + 视频。混合选择时批次里只装真正的图片，
   * 批次号为空的那几条就是实况照片（与「单独下载的图片」同一种记录形态）。
   */
  static add(items: PictureItem[], pageUrl: string, title: string, zipMode: boolean): void {
    const selected: PictureItem[] = items.filter((item: PictureItem): boolean => item.selected);
    if (selected.length === 0) { return; }
    const packable: number = selected.filter((item: PictureItem): boolean =>
      item.kind !== 'livephoto').length;
    let batchId: string = '';
    if (zipMode && packable > 0) {
      batchId = DownloadStore.nextId();
      const batch: BatchItem = new BatchItem();
      batch.id = batchId;
      const titleName: string = Naming.clean(title, '网页图片_' + Date.now().toString());
      batch.name = titleName.toLowerCase().endsWith('.zip') ? titleName : titleName + '.zip';
      batch.sourcePage = pageUrl;
      DownloadStore.batches.unshift(batch);
      DownloadStore.ensureDirectory(DownloadStore.context.filesDir + '/staging/' + batchId);
    }
    const filesDir: string = DownloadStore.context.filesDir;
    DownloadStore.ensureDirectory(filesDir + '/livephotos');
    // 已占用的路径**一次收全**：这一步原来藏在 uniqueName 里，导致每入队一条都要扫一遍整张
    // downloads 表（一次选 200 张就是 200×200 次比较）。集合是增量的，uniqueNameIn 每定下
    // 一个名字就把它加进来，所以后面各条不会再看到重复。
    const taken: Set<string> = new Set<string>();
    for (const existing of DownloadStore.downloads) {
      taken.add(existing.path);
    }
    for (let i: number = 0; i < selected.length; i++) {
      const source: PictureItem = selected[i];
      const item: DownloadItem = new DownloadItem();
      item.id = DownloadStore.nextId();
      item.url = source.url;
      const suggested: string = Naming.suggested(source.url, source.description, i + 1);
      item.name = source.userNamed ? Naming.withExtension(source.name, suggested.substring(suggested.lastIndexOf('.') + 1)) : Naming.clean(source.name, suggested);
      item.userNamed = source.userNamed;
      // 批量直链没有共同网页；逐张用自身 URL 作 Referer，与地址栏直链行为一致。
      item.sourcePage = pageUrl.length > 0 ? pageUrl : source.url;
      item.createdAt = Date.now();
      item.kind = source.kind === 'livephoto' ? 'livephoto' : 'image';
      const packed: boolean = batchId.length > 0 && item.kind !== 'livephoto';
      item.batchId = packed ? batchId : '';
      const dir: string = item.kind === 'livephoto'
        ? filesDir + '/livephotos'
        : (packed ? filesDir + '/staging/' + batchId : filesDir + '/images');
      item.name = DownloadStore.uniqueNameIn(item.name, dir, taken);
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

  /** 只影响此后创建的请求；已经运行的请求使用创建时的网络策略。 */
  static setWifiOnly(value: boolean): void {
    DownloadStore.wifiOnly = value;
    DownloadStore.notify();
  }

  static setThemeMode(value: string): void {
    DownloadStore.themeMode = value;
    DownloadStore.notify();
  }

  static setMaterialType(value: string): void {
    DownloadStore.materialType = value;
    DownloadStore.notify();
  }

  /**
   * 沉浸光感材质等级。
   *
   * 存的是语义 id 而不是 hdsMaterial.MaterialLevel 的数值：状态文件读起来是
   * 'exquisite' / 'gentle' / 'smooth' / 'adaptive'，换 SDK 版本也不会因为枚举重排而错位。
   */
  static setMaterialLevel(value: string): void {
    DownloadStore.materialLevel = value;
    DownloadStore.notify();
  }

  static setLightEffect(value: boolean): void {
    DownloadStore.lightEffect = value;
    DownloadStore.notify();
  }

  /**
   * 智感握姿开关。
   *
   * 开关本身就是订阅的开关：打开才订阅系统握持手感知，关掉就取消订阅，
   * 不常驻监听。是否成功由 GripSensor 记录，界面读 `supported` / `problem`。
   */
  static setGripEnabled(value: boolean): void {
    DownloadStore.gripEnabled = value;
    GripSensor.setEnabled(value);
    DownloadStore.notify();
  }

  /**
   * 防窥保护开关：这里**只存值**，不顺手调 AntiPeep.setEnabled()。
   *
   * 与智感握姿的区别在于：拉订阅时若系统开关没开，要拉起 requestAntiPeepOptions 弹窗，
   * 而那需要界面手上的 UIAbilityContext。所以订阅由 Index.pickAntiPeep() 单独驱动，
   * 启动恢复那次由 initialize() 直接调（不带 context，绝不弹窗）。
   */
  static setAntiPeepEnabled(value: boolean): void {
    DownloadStore.antiPeepEnabled = value;
    DownloadStore.notify();
  }

  /**
   * 下载位置：'app' | 'gallery' | 'custom'。
   *
   * 「自定义目录」的 URI 由 Index 的 chooseCustomDir()（目录选择器回来之后）单独写
   * （setCustomDir），
   * 所以这里只切档位：选自定义却没有目录时会被 normalizeLocation 挡回应用文件，
   * 界面因此必须先把目录选出来再落档位。
   */
  static setDownloadLocation(value: string): void {
    DownloadStore.downloadLocation = normalizeLocation(value, DownloadStore.customDirUri);
    DownloadStore.destinationProblem = '';
    DownloadStore.notify();
  }

  /**
   * 扫描取图策略：'all' | 'original' | 'display'。
   *
   * 只落盘、没有任何副作用：它只在发现页下一次扫描时被读，正在下载的任务不受影响。
   */
  static setPictureQuality(value: string): void {
    DownloadStore.pictureQuality = normalizeQuality(value);
    DownloadStore.notify();
  }

  /** 记下用户选的目录，并直接把下载位置切到「自定义目录」。 */
  static setCustomDir(uri: string, name: string): void {
    DownloadStore.customDirUri = uri;
    DownloadStore.customDirName = name;
    DownloadStore.downloadLocation = normalizeLocation('custom', uri);
    DownloadStore.destinationProblem = '';
    DownloadStore.notify();
  }

  /** Bytes currently held by downloaded images and archives. */
  static usedBytes(): number {
    let total: number = 0;
    for (const item of DownloadStore.downloads) {
      // 实况照片占了两份：原始包（size）+ 解出来的静图与视频（auxSize）。
      total += orNumber(item.size, 0) + orNumber(item.auxSize, 0);
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
    // **先掐掉在飞的下载**：只清记录不停任务的话，任务还在写文件，晚到的 completed 回调
    // 会把它标成已完成、甚至再投递一份到相册 —— 用户看到的却是「已清空」。
    // 先标 cancelled 是关键：complete() / fail() 开头都会因此直接返回，晚到的回调变成空操作。
    DownloadStore.abortAll();
    for (const item of DownloadStore.downloads) {
      DownloadStore.removeFile(item.path);
      // 实况照片还有一整个解包目录（静图 + 视频），以及缓存里的首帧。
      LivePhoto.removeTree(DownloadStore.livePhotoDir(item.id));
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
    StillFrames.clear();
    DownloadStore.notify();
  }

  /**
   * 停掉所有在飞的下载（清空记录前用）。
   *
   * 不走 `cancel()`：那个是单条的用户操作，会 notify + checkBatch + pump；
   * 清空场景下列表马上就要被清空，pump 出来反而会重新拉起任务。
   *
   * `stop()` / `request.agent.remove()` 都是异步的，这里不 await —— 状态已在上面标成
   * cancelled，晚到的回调不会再生效，剩下的只是让系统把传输资源收回去。
   */
  private static abortAll(): void {
    for (const item of DownloadStore.downloads) {
      item.status = 'cancelled';
      const task: request.agent.Task | undefined = DownloadStore.active.get(item.id);
      if (task !== undefined) {
        try { task.stop(); } catch (error) {}
      }
      if (canIUse('SystemCapability.Request.FileTransferAgent') && item.taskId.length > 0) {
        try {
          request.agent.remove(item.taskId);
        } catch (error) {}
      }
    }
    DownloadStore.active.clear();
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

  /**
   * 把队列里排在前面的任务推到并发上限。
   *
   * **必须防重入**：`start()` 在「本机没有 FileTransferAgent」这条路上会**同步**走到
   * `fail()`，而 `fail()` 结尾又调 `pump()` —— 原来的写法每个排队任务都会压一层栈，
   * 几百张图的队列直接爆栈（而且每层还写一次状态文件）。这里把重入记成标记，
   * 等外层这一轮跑完再用 `do/while` 补一轮，递归就变成了迭代。
   */
  static pump(): void {
    if (DownloadStore.pumping) {
      DownloadStore.pumpAgain = true;
      return;
    }
    DownloadStore.pumping = true;
    do {
      DownloadStore.pumpAgain = false;
      DownloadStore.pumpRound();
    } while (DownloadStore.pumpAgain);
    DownloadStore.pumping = false;
  }

  private static pumpRound(): void {
    const limit: number = DownloadStore.concurrency;
    // 原来每轮 while 都要 filter 一遍整表来数在跑几个，n 个任务就是 O(n²)；
    // 这里只数一次，之后自己维护这个计数。
    let running: number = 0;
    for (const item of DownloadStore.downloads) {
      if (item.status === 'running' || item.status === 'starting' || item.status === 'waiting'
        || item.status === 'paused') {
        running++;
      }
    }
    while (running < limit) {
      const next: DownloadItem | undefined =
        DownloadStore.downloads.find((item: DownloadItem): boolean => item.status === 'queued');
      if (next === undefined) {
        break;
      }
      next.status = 'starting';
      running++;
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
          network: DownloadStore.wifiOnly ? request.agent.Network.WIFI : request.agent.Network.ANY,
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
      if (!DownloadStore.acceptsAgentEvent(item, task.tid)) { return; }
      const nextStatus: string = DownloadStore.agentStatus(item.status, progress.state,
        DownloadStore.pauseRequests.has(item.id));
      const statusChanged: boolean = nextStatus !== item.status;
      if (statusChanged) {
        item.status = nextStatus;
        item.speedBps = 0;
        item.etaSeconds = 0;
        DownloadStore.progressSamples.delete(item.id);
      }
      item.processed = progress.processed;
      item.total = progress.sizes.length > 0 ? progress.sizes[0] : 0;
      const now: number = Date.now();
      const previous: ProgressSample | undefined = DownloadStore.progressSamples.get(item.id);
      if (item.status === 'waiting' || item.status === 'paused') {
        item.speedBps = 0;
        item.etaSeconds = 0;
        DownloadStore.progressSamples.delete(item.id);
      } else if (previous === undefined || progress.processed < previous.bytes) {
        DownloadStore.progressSamples.set(item.id, { bytes: progress.processed, at: now });
        item.speedBps = 0;
        item.etaSeconds = 0;
      } else if (now - previous.at >= 1000) {
        const delta: number = progress.processed - previous.bytes;
        item.speedBps = delta > 0 ? Math.round(delta * 1000 / (now - previous.at)) : 0;
        item.etaSeconds = item.total > item.processed && item.speedBps > 0
          ? Math.ceil((item.total - item.processed) / item.speedBps) : 0;
        DownloadStore.progressSamples.set(item.id, { bytes: progress.processed, at: now });
      }
      if (statusChanged) {
        DownloadStore.notify();
      } else if (Date.now() - DownloadStore.lastProgressSaveAt >= 500) {
        DownloadStore.lastProgressSaveAt = Date.now();
        // 进度专用：界面每 500ms 刷新，但写盘合并到最多每秒一次。
        DownloadStore.notifyProgress();
      }
    });
    task.on('response', (response: request.agent.HttpResponse): void => {
      if (!DownloadStore.acceptsAgentEvent(item, task.tid)) { return; }
      if (response.statusCode >= 400) { item.error = 'HTTP ' + response.statusCode.toString(); }
      const contentTypes: string[] | undefined = response.headers.get('content-type') ?? response.headers.get('Content-Type');
      // 实况照片包不是图片：服务器一般回 application/octet-stream 或 application/zip，
      // 这里不能按「不是 image/ 就判失败」来卡，也不能按图片 Content-Type 改扩展名
      // （把 `.livp` 改成 `.zip` / `.jpg` 会让解包与用户拿到的文件名都对不上）。
      const isLivePhoto: boolean = item.kind === 'livephoto';
      if (!isLivePhoto && contentTypes !== undefined && contentTypes.length > 0
        && !contentTypes[0].toLowerCase().startsWith('image/')) {
        item.error = '服务器返回的不是图片';
      }
      const values: string[] | undefined = response.headers.get('content-disposition') ?? response.headers.get('Content-Disposition');
      if (!item.userNamed && values !== undefined && values.length > 0) {
        const match: RegExpExecArray | null = new RegExp("filename\\*?=(?:UTF-8'')?\\\"?([^\\\";]+)", 'i').exec(values[0]);
        if (match !== null && match.length > 1) {
          let proposed: string = match[1];
          try { proposed = decodeURIComponent(proposed); } catch (error) {}
          item.name = Naming.clean(proposed, item.name);
        }
      }
      if (!isLivePhoto && contentTypes !== undefined && contentTypes.length > 0
        && contentTypes[0].toLowerCase().startsWith('image/')) {
        const extension: string = Naming.imageExtension(contentTypes[0]);
        if (extension.length > 0) { item.name = Naming.withExtension(item.name, extension); }
      }
    });
    task.on('completed', (): void => {
      if (DownloadStore.acceptsAgentEvent(item, task.tid)) { DownloadStore.complete(item); }
    });
    task.on('failed', (): void => {
      if (DownloadStore.acceptsAgentEvent(item, task.tid)) {
        DownloadStore.fail(item, '下载失败，请检查链接或登录状态');
      }
    });
  }

  /** 旧任务在重试后可能迟到；已结束任务的进度与响应也不能再改写记录。 */
  static acceptsAgentEvent(item: DownloadItem, taskId: string): boolean {
    return taskId.length > 0 && item.taskId === taskId && item.status !== 'cancelled'
      && item.status !== 'failed' && item.status !== 'completed';
  }

  /** 系统等待网络或资源时暂停测速；手动暂停由用户继续，不被迟到的进度回调覆盖。 */
  static agentStatus(current: string, state: request.agent.State, userPausePending: boolean = false): string {
    if (current === 'paused') { return current; }
    if (state === request.agent.State.PAUSED && userPausePending
      && (current === 'starting' || current === 'running' || current === 'waiting')) { return 'paused'; }
    if ((state === request.agent.State.WAITING || state === request.agent.State.PAUSED)
      && (current === 'starting' || current === 'running' || current === 'waiting')) {
      return 'waiting';
    }
    if ((state === request.agent.State.RUNNING || state === request.agent.State.RETRYING)
      && current === 'waiting') {
      return 'running';
    }
    return current;
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
      // 落盘之后的「内容加工」：动图标记 / 实况照片解包。投递（存相册）跟在它后面 ——
      // 实况照片要把解出来的静图与视频一起送进相册，没解完就没有可投递的东西。
      try {
        await DownloadStore.finishContent(item);
      } catch (error) {
        item.note = '内容处理失败，已保留原文件';
        DownloadStore.pendingNotice = item.note;
        console.error('finish content failed: ' + String(error));
      }
      DownloadStore.active.delete(item.id);
      DownloadStore.progressSamples.delete(item.id);
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
      DownloadStore.delivery.deliver(item);
    } catch (error) {
      DownloadStore.fail(item, '保存下载文件失败：' + String(error));
    }
  }

  /** 实况照片解包结果的落地目录：按**记录 id** 而不是文件名，改名不会连累它。 */
  private static livePhotoDir(id: string): string {
    return DownloadStore.context.filesDir + '/livephotos/' + id;
  }

  /** 解包结果是否齐备（路径非空且文件真的还在）。 */
  private static livePhotoReady(item: DownloadItem): boolean {
    return item.stillPath.length > 0 && item.motionPath.length > 0
      && DownloadStore.exists(item.stillPath) && DownloadStore.exists(item.motionPath);
  }

  /**
   * 下载完成后的内容加工。
   *
   * - 普通图片：只判一次是不是动图（GIF / WebP 读文件头），图库据此决定画静止首帧；
   * - 实况照片包：解包成静图 + 视频。**解包失败不改变下载状态** —— 包本身已经完好落盘，
   *   用户仍能导出 / 分享这个文件，所以只记一句 `note`（预览页的提示）加一次 Toast，
   *   绝不把这一次下载判成失败（否则文件会被 discard 删掉，那才是真丢数据）。
   */
  private static async finishContent(item: DownloadItem): Promise<void> {
    if (item.kind === 'livephoto') {
      const content: LivePhotoContent = await LivePhoto.unpack(item.path, DownloadStore.livePhotoDir(item.id));
      if (content.ok) {
        item.stillPath = content.stillPath;
        item.motionPath = content.motionPath;
        item.auxSize = content.auxSize;
        item.note = '';
        return;
      }
      item.stillPath = '';
      item.motionPath = '';
      item.auxSize = 0;
      item.note = content.message;
      DownloadStore.pendingNotice = content.message;
      return;
    }
    item.animated = StillFrames.isAnimatedFile(item.path);
  }

  /**
   * 应用要退出时的收尾：取消排队中的相册投递，并把最后一次状态落盘。
   *
   * 相册投递是 800ms 防抖 + 一个系统确认框：如果用户在下完一张图之后立刻退出应用，
   * 这个定时器还挂着，`flushGallery` 会在**别的应用上面**弹一个系统框。
   * 进度路径的写盘是合并的（见 notifyProgress），最多还差不到 1 秒，这里补齐。
   */
  static shutdown(): void {
    // 排队中的相册投递由投递层自己收掉（否则它会在别的应用上面弹系统确认框）。
    DownloadStore.delivery.stop();
    if (DownloadStore.saveTimer >= 0) {
      clearTimeout(DownloadStore.saveTimer);
      DownloadStore.saveTimer = -1;
    }
    DownloadStore.save();
    DownloadStore.publishWidget();
  }

  /**
   * 记一次投递结果。
   *
   * 成功不吭声（用户自己选的目录，能看到文件就是最好的反馈）；用户在系统确认框上取消也不算失败
   * （`outcome.cancelled`），否则设置页会留下一条永远清不掉的假故障。只有真失败才同时留两个落点：
   * 设置页那行的常驻说明，和一次 Toast —— 此刻用户多半还在任务页看进度，
   * 不弹一次的话他只会以为「下载成功了但目录里没有」。
   */
  static noteDelivery(outcome: ActionOutcome, where: string): void {
    if (outcome.ok || outcome.cancelled === true) {
      // 清掉上一次的失败说明时得 notify 一次，否则设置页那行会一直挂着旧文案。
      if (DownloadStore.destinationProblem.length > 0) {
        DownloadStore.destinationProblem = '';
        DownloadStore.notify();
      }
      return;
    }
    console.error('deliver to ' + where + ' failed: ' + outcome.message);
    DownloadStore.destinationProblem = '上次存入' + where + '失败，已保留应用内文件';
    DownloadStore.pendingNotice = '存入' + where + '失败，已保留应用内文件';
    DownloadStore.notify();
  }

  static fail(item: DownloadItem, reason: string): void {
    if (item.status === 'cancelled' || item.status === 'completed') { return; }
    item.status = 'failed';
    item.error = item.error.length > 0 ? item.error : reason;
    DownloadStore.active.delete(item.id);
    DownloadStore.progressSamples.delete(item.id);
    DownloadStore.notify();
    DownloadStore.checkBatch(item.batchId);
    DownloadStore.pump();
    DownloadStore.discard(item);
  }

  static async discard(item: DownloadItem): Promise<void> {
    const taskId: string = item.taskId;
    // 先清理旧文件；等待系统移除任务期间，用户可能已经点击重试并开始写同一路径。
    DownloadStore.removeFile(item.path);
    if (taskId.length > 0) {
      if (canIUse('SystemCapability.Request.FileTransferAgent')) {
        try {
          // @SuppressWarnings syscap
          await request.agent.remove(taskId);
        } catch (error) {}
      }
      if (item.taskId === taskId) { item.taskId = ''; }
    }
  }

  static async cancel(item: DownloadItem): Promise<void> {
    if (DownloadStore.cancelRequests.has(item.id) || item.status === 'cancelled'
      || item.status === 'completed') { return; }
    const task: request.agent.Task | undefined = DownloadStore.active.get(item.id);
    const taskId: string = item.taskId;
    DownloadStore.cancelRequests.add(item.id);
    item.status = 'cancelled';
    DownloadStore.active.delete(item.id);
    DownloadStore.progressSamples.delete(item.id);
    try {
      if (task !== undefined) { try { await task.stop(); } catch (error) {} }
      if (canIUse('SystemCapability.Request.FileTransferAgent')) {
        if (taskId.length > 0) {
          try {
            // @SuppressWarnings syscap
            await request.agent.remove(taskId);
          } catch (error) {}
        }
      }
      if (item.status === 'cancelled' && item.taskId === taskId) {
        DownloadStore.removeFile(item.path);
        item.taskId = '';
      }
    } finally {
      DownloadStore.cancelRequests.delete(item.id);
    }
    DownloadStore.notify();
    DownloadStore.checkBatch(item.batchId);
    DownloadStore.pump();
  }

  static async pause(item: DownloadItem): Promise<boolean> {
    if (item.status !== 'running') { return false; }
    const task: request.agent.Task | undefined = DownloadStore.active.get(item.id);
    if (task === undefined) { return false; }
    DownloadStore.pauseRequests.add(item.id);
    try {
      // @SuppressWarnings syscap
      await task.pause();
      if (item.status !== 'running' && item.status !== 'waiting' && item.status !== 'paused') { return false; }
      item.status = 'paused';
      item.speedBps = 0;
      item.etaSeconds = 0;
      DownloadStore.progressSamples.delete(item.id);
      DownloadStore.notify();
      return true;
    } catch (error) {
      return false;
    } finally {
      DownloadStore.pauseRequests.delete(item.id);
    }
  }

  static async resume(item: DownloadItem): Promise<boolean> {
    if (item.status !== 'paused') { return false; }
    const task: request.agent.Task | undefined = DownloadStore.active.get(item.id);
    if (task === undefined) { return false; }
    try {
      // @SuppressWarnings syscap
      await task.resume();
      if (item.status !== 'paused') { return false; }
      item.status = 'running';
      item.speedBps = 0;
      item.etaSeconds = 0;
      DownloadStore.progressSamples.delete(item.id);
      DownloadStore.notify();
      return true;
    } catch (error) {
      return false;
    }
  }

  /** 重试只重置失败或已取消的任务；批次中的成功成员必须保持原样。 */
  static prepareRetry(item: DownloadItem): boolean {
    if (item.status !== 'failed' && item.status !== 'cancelled') { return false; }
    item.status = 'queued'; item.error = ''; item.processed = 0; item.total = 0; item.taskId = '';
    item.speedBps = 0; item.etaSeconds = 0;
    return true;
  }

  static retry(item: DownloadItem): boolean {
    if (DownloadStore.cancelRequests.has(item.id) || !DownloadStore.prepareRetry(item)) { return false; }
    DownloadStore.removeFile(item.path);
    const batch: BatchItem | undefined = DownloadStore.batches.find((entry: BatchItem): boolean => entry.id === item.batchId);
    if (batch !== undefined) { batch.status = 'downloading'; batch.error = ''; }
    DownloadStore.notify();
    DownloadStore.pump();
    return true;
  }

  /**
   * Retry a failed batch: re-queue its failed members, and if there are none
   * left to fetch the batch is only re-packed (a compress failure leaves every
   * member completed). Members keep their staging paths, so a retry that
   * succeeds still packs into the same archive.
   */
  static retryBatch(batchId: string): boolean {
    const batch: BatchItem | undefined = DownloadStore.batches.find((entry: BatchItem): boolean => entry.id === batchId);
    if (batch === undefined || DownloadStore.downloads.some((item: DownloadItem): boolean =>
      item.batchId === batchId && DownloadStore.cancelRequests.has(item.id))) { return false; }
    for (const item of DownloadStore.downloads) {
      if (item.batchId !== batchId) { continue; }
      if (!DownloadStore.prepareRetry(item)) { continue; }
      DownloadStore.removeFile(item.path);
    }
    batch.status = 'downloading'; batch.error = '';
    DownloadStore.notify();
    DownloadStore.pump();
    DownloadStore.checkBatch(batchId);
    return true;
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
      if (DownloadStore.exists(item.path) && DownloadStore.moveFile(item.path, target)) {
        item.name = name;
        item.path = target;
      } else {
        // 暂存文件已经不在（被删掉）或搬不过来：**不能**把 path 改成不存在的目标路径，
        // 否则它回到任务页会以「已完成」的样子出现，点开却是坏图。判成失败，原因说清楚。
        item.status = 'failed';
        item.error = '暂存文件已丢失，无法恢复到图片列表';
      }
    }
    DownloadStore.batches = DownloadStore.batches.filter((entry: BatchItem): boolean => entry.id !== batchId);
    DownloadStore.removeDirectory(DownloadStore.context.filesDir + '/staging/' + batchId);
    DownloadStore.notify();
    DownloadStore.pump();
  }

  static async recover(): Promise<void> {
    // 先处理上次进程留下的 packing。若放在逐项恢复之后，第二项的 complete()
    // 可能已启动本进程的压缩；这里再把 packing 改回 downloading 会并发压同一路径。
    for (const batch of DownloadStore.batches) {
      if (batch.status !== 'packing') { continue; }
      const partialPath: string = DownloadStore.context.filesDir + '/archives/' + batch.name;
      DownloadStore.removeFile(partialPath + '.' + batch.id + '.partial.zip');
      DownloadStore.removeFile(partialPath + '.partial.zip');
      if (!DownloadStore.zips.some((item: ZipItem): boolean => item.path === partialPath)) {
        DownloadStore.removeFile(partialPath);
      }
      batch.status = 'downloading';
    }
    for (const item of DownloadStore.downloads) {
      if (item.status === 'queued') { continue; }
      if (item.status !== 'running' && item.status !== 'starting'
        && item.status !== 'waiting' && item.status !== 'paused') { continue; }
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
          // @SuppressWarnings syscap
          if (info.progress.state === request.agent.State.WAITING
            || info.progress.state === request.agent.State.PAUSED) {
            item.status = item.status === 'paused' ? 'paused' : 'waiting';
          } else {
            item.status = 'running';
          }
        } catch (error) {
          DownloadStore.fail(item, '无法恢复任务，请重试');
        }
      } else {
        item.status = 'queued'; item.taskId = '';
      }
    }
    for (const batch of DownloadStore.batches) {
      DownloadStore.checkBatch(batch.id);
    }
    await DownloadStore.restoreContent();
    DownloadStore.notify();
    DownloadStore.pump();
  }

  /**
   * 启动时的内容补课。
   *
   * 两条记录可能缺加工结果：上一次进程在解包途中被杀（实况照片只剩原始包），
   * 以及老版本写下的记录（没有 `animated` 字段）。这里补一次，补不回来也只留 `note`，
   * 不影响启动。
   */
  private static async restoreContent(): Promise<void> {
    for (const item of DownloadStore.downloads) {
      if (item.status !== 'completed') { continue; }
      try {
        if (item.kind === 'livephoto') {
          if (DownloadStore.livePhotoReady(item)) { continue; }
          // 上一次可能是「包不合法」那种永久失败：note 非空表示已经判定过结论，包也还在，
          // 就不必每次启动都重解一遍。
          if (item.note.length > 0) { continue; }
          await DownloadStore.finishContent(item);
          continue;
        }
        if (!DownloadStore.exists(item.path)) { continue; }
        item.animated = StillFrames.isAnimatedFile(item.path);
      } catch (error) {
        item.note = '内容处理失败，已保留原文件';
        DownloadStore.pendingNotice = item.note;
        console.error('restore content failed: ' + String(error));
      }
    }
  }

  static checkBatch(batchId: string): void {
    if (batchId.length === 0) { return; }
    const batch: BatchItem | undefined = DownloadStore.batches.find((entry: BatchItem): boolean => entry.id === batchId);
    if (batch === undefined || batch.status === 'completed' || batch.status === 'packing'
      || batch.status === 'failed'
      || DownloadStore.packingBatches.has(batchId)) { return; }
    const members: DownloadItem[] = DownloadStore.downloads.filter((item: DownloadItem): boolean => item.batchId === batchId);
    if (members.some((item: DownloadItem): boolean => item.status === 'queued' || item.status === 'running'
      || item.status === 'starting' || item.status === 'waiting' || item.status === 'paused')) { return; }
    const successful: DownloadItem[] = members.filter((item: DownloadItem): boolean => item.status === 'completed' && fs.accessSync(item.path));
    if (successful.length === 0) { batch.status = 'failed'; batch.error = '没有成功下载的图片'; DownloadStore.notify(); return; }
    batch.status = 'packing';
    DownloadStore.packingBatches.add(batchId);
    DownloadStore.notify();
    DownloadStore.pack(batch, successful, members.length - successful.length);
  }

  static async pack(batch: BatchItem, members: DownloadItem[], failedCount: number): Promise<void> {
    const archivesDir: string = DownloadStore.context.filesDir + '/archives';
    const name: string = DownloadStore.uniqueName(batch.name, archivesDir);
    const path: string = archivesDir + '/' + name;
    // zlib 会为不以 .zip 结尾的输出路径自行追加扩展名；临时名也必须以 .zip 结尾。
    const tempPath: string = path + '.' + batch.id + '.partial.zip';
    const paths: string[] = members.map((item: DownloadItem): string => item.path);
    const options: zlib.Options = { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION };
    try {
      DownloadStore.removeFile(tempPath);
      await zlib.compressFiles(paths, tempPath, options);
      fs.renameSync(tempPath, path);
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
      // 压缩包也照用户的下载位置投递一份（相册不收压缩包，所以只有自定义目录会动）。
      DownloadStore.delivery.deliverArchive(archive);
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
      DownloadStore.removeFile(tempPath);
      DownloadStore.removeFile(path);
    } finally {
      DownloadStore.packingBatches.delete(batch.id);
    }
    DownloadStore.notify();
  }

  static renameDownload(item: DownloadItem, raw: string): boolean {
    if (item.status !== 'completed') { return false; }
    const extension: string = item.name.substring(item.name.lastIndexOf('.') + 1);
    const name: string = Naming.withExtension(raw, extension);
    const dir: string = item.path.substring(0, item.path.lastIndexOf('/'));
    const destination: string = dir + '/' + name;
    if (destination !== item.path && DownloadStore.exists(destination)) { return false; }
    // 移动失败就不提交新名字：记录必须一直指着真实存在的那个文件。
    if (destination !== item.path && !DownloadStore.moveFile(item.path, destination)) { return false; }
    item.name = name; item.path = destination;
    DownloadStore.notify();
    return true;
  }

  static renameZip(item: ZipItem, raw: string): boolean {
    let name: string = Naming.clean(raw, item.name);
    if (!name.toLowerCase().endsWith('.zip')) { name += '.zip'; }
    const destination: string = DownloadStore.context.filesDir + '/archives/' + name;
    if (destination !== item.path && DownloadStore.exists(destination)) { return false; }
    if (destination !== item.path && !DownloadStore.moveFile(item.path, destination)) { return false; }
    item.name = name; item.path = destination;
    DownloadStore.notify();
    return true;
  }

  static deleteDownload(item: DownloadItem): void {
    DownloadStore.removeFile(item.path);
    // 实况照片的解包目录与两份缓存都要一起收掉，否则删了记录还占着空间。
    LivePhoto.removeTree(DownloadStore.livePhotoDir(item.id));
    StillFrames.forget(item.path);
    StillFrames.forget(item.stillPath);
    DownloadStore.downloads = DownloadStore.downloads.filter((entry: DownloadItem): boolean => entry.id !== item.id);
    DownloadStore.notify();
  }

  static deleteZip(item: ZipItem): void {
    DownloadStore.removeFile(item.path);
    DownloadStore.zips = DownloadStore.zips.filter((entry: ZipItem): boolean => entry.id !== item.id);
    DownloadStore.notify();
  }
}
