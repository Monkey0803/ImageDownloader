/** One image found by scanning a page, before it becomes a download. */
@ObservedV2
export class PictureItem {
  /**
   * 这个**实例**的身份，只给 ForEach 当 key 用。
   *
   * 不能拿「url + 选中状态」拼 key：那样每点一次选中/反选，key 就全变，ArkUI 会把整个网格
   * 拆掉重建 —— `Thumb` 里的 `Image` 跟着重建、远程缩略图重新下载解码，界面就闪（真机实测：
   * 19 张图点一次「全选」新建 19 个 SelectTile）。而只拿 url 当 key 又会踩另一个坑：
   * 换页后如果新旧页面有同一个图片地址，`scan()` 会建新实例，但 ForEach 见 key 没变就复用旧
   * 组件，`@ObjectLink` 仍绑着上一页的旧对象（选中态、描述全是旧的）。
   *
   * 所以身份必须来自**实例**：选中状态变它不变（原地刷新），换实例它才变（该重建就重建）。
   * `scan()` 内部按 url 复用旧对象（`found.set(old.url, old)`），所以同一张图在多次扫描之间
   * 身份是稳定的，扫到更多图时也不会整屏重建。
   *
   * 由 Index 在每次 `new` 之后用 `nextPictureUid()` 赋值 —— 不放构造函数里：构造期写字段会绕开
   * 观察代理（V1 的 `@Observed` 与 V2 的 `@ObservedV2` 都一样，只是 V2 的代理按 `@Trace` 逐个字段
   * 记录，所以下面每个字段都要单独标）。
   */
  @Trace uid: string = '';
  @Trace id: string = '';
  @Trace url: string = '';
  @Trace name: string = '';
  @Trace description: string = '';
  @Trace selected: boolean = false;
  @Trace userNamed: boolean = false;
  /** 仅当下载地址就是浏览器已解码的 currentSrc 时，尺寸才可信；0 表示未知。 */
  @Trace width: number = 0;
  @Trace height: number = 0;
  /**
   * 'image' | 'livephoto'，见 `MediaFormat.mediaKindOf`。
   *
   * 实况照片包（`.livp` / `.livephoto`）也从「发现」页选中下载，但它要按**整包单文件**处理：
   * 不进 ZIP 批次、不按图片扩展名改名、下完还要解包。类型在发现阶段就带下来，
   * 后面（下载 / 投递 / 预览）不再靠重新嗅探文件名来判断。
   */
  @Trace kind: string = 'image';
}

/** One image download, from the queue through to the finished file. */
@ObservedV2
export class DownloadItem {
  @Trace id: string = '';
  @Trace url: string = '';
  @Trace name: string = '';
  @Trace userNamed: boolean = false;
  @Trace path: string = '';
  @Trace sourcePage: string = '';
  @Trace batchId: string = '';
  @Trace taskId: string = '';
  @Trace status: string = 'queued';
  @Trace processed: number = 0;
  @Trace total: number = 0;
  /** 当前进程内的实测速度；重启后等待新采样，不从旧进度推测。 */
  @Trace speedBps: number = 0;
  @Trace etaSeconds: number = 0;
  /** Final on-disk byte count, recorded when the download completes. */
  @Trace size: number = 0;
  @Trace error: string = '';
  @Trace createdAt: number = 0;
  /** When the download finished, used for the gallery's timestamp. */
  @Trace finishedAt: number = 0;
  /**
   * 'image' | 'livephoto'。
   *
   * `path` / `name` / `size` 对两种类型语义一致：都是**用户拿到手的那个文件**
   * （实况照片就是原始 `.livp` 包，导出、分享、改名、占用统计都以它为准）；
   * 解包出来的静图与视频另外记在 stillPath / motionPath 上。
   */
  @Trace kind: string = 'image';
  /** 动图（GIF / WebP 且文件头带多帧标记）；图库网格据此改画静止首帧。 */
  @Trace animated: boolean = false;
  /** 实况照片解出来的静图（封面、相册里的图片资源）。 */
  @Trace stillPath: string = '';
  /** 实况照片解出来的视频（MovingPhotoView 的动态部分、相册里的视频资源）。 */
  @Trace motionPath: string = '';
  /** 解包出来的字节数：size 只算原始包，占用统计要两个一起加，见 DownloadStore.usedBytes。 */
  @Trace auxSize: number = 0;
  /** 非致命说明（例如「实况照片包解压失败，已保留原文件」），预览页拿来当提示文案。 */
  @Trace note: string = '';
}

/** A ZIP archive produced by packing a batch. */
@ObservedV2
export class ZipItem {
  @Trace id: string = '';
  @Trace name: string = '';
  @Trace path: string = '';
  @Trace batchId: string = '';
  @Trace imageCount: number = 0;
  @Trace failedCount: number = 0;
  @Trace size: number = 0;
  @Trace createdAt: number = 0;
  /** Source URLs of a few members, kept only to draw the stacked preview. */
  @Trace thumbs: string[] = [];
}

/** A ZIP-in-progress: the batch groups its member downloads. */
@ObservedV2
export class BatchItem {
  @Trace id: string = '';
  @Trace name: string = '';
  @Trace sourcePage: string = '';
  @Trace status: string = 'downloading';
  @Trace error: string = '';
}

/** Everything that survives a restart. */
export class SavedState {
  downloads: DownloadItem[] = [];
  zips: ZipItem[] = [];
  batches: BatchItem[] = [];
  concurrency: number = 3;
  wifiOnly: boolean = false;
  /** 'system' | 'light' | 'dark' */
  themeMode: string = 'system';
  /** 'adaptive' | 'immersive' */
  materialType: string = 'adaptive';
  /**
   * 沉浸光感材质等级，取值对应 hdsMaterial.MaterialLevel：
   * 'exquisite' 精美(0) | 'gentle' 轻柔(1) | 'smooth' 流畅(2) | 'adaptive' 自适应(10)。
   */
  materialLevel: string = 'adaptive';
  /** Whether the immersive material lights up under touch. */
  lightEffect: boolean = true;
  /** 智感握姿：主操作是否跟随握持手。 */
  gripEnabled: boolean = false;
  /** 防窥保护：检测到他人窥视时是否遮罩内容。 */
  antiPeepEnabled: boolean = false;
  /** 扫描取图策略：'original' 原图优先（默认）| 'display' 网页显示图 | 'all' 每个候选地址各收一张。 */
  pictureQuality: string = 'original';
  /** 下载位置：'app' 应用文件 | 'gallery' 系统相册 | 'custom' 自定义目录。 */
  downloadLocation: string = 'app';
  /** 自定义目录的 URI 与显示名；只有 downloadLocation 为 'custom' 时有效。 */
  customDirUri: string = '';
  customDirName: string = '';
}

/**
 * 老状态文件里可能缺字段（`undefined`），也可能显式写着 `null`（JSON 里两者都能出现）。
 *
 * 只判 `undefined` 是不够的：`null` 会原样穿过 `=== undefined` 判断，被赋给 `number` / `boolean`
 * 字段后，界面拿到的是 NaN 或空白。所以三个兜底函数都把 `null` 一起当缺失处理。
 */
export function orNumber(value: number | null | undefined, fallback: number): number {
  return value === undefined || value === null ? fallback : value;
}

export function orBoolean(value: boolean | null | undefined, fallback: boolean): boolean {
  return value === undefined || value === null ? fallback : value;
}

export function orString(value: string | null | undefined, fallback: string): string {
  return value === undefined || value === null ? fallback : value;
}
