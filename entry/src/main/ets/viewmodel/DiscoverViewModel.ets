import { webview } from '@kit.ArkWeb';
import { PictureItem } from '../model/Models';
import { TAB_TASKS } from '../model/Navigation';
import { DownloadStore } from '../service/DownloadStore';
import { Clipboard } from '../service/Clipboard';
import { MediaFormat } from '../service/MediaFormat';
import { PictureFactory, ScanImage } from '../service/PictureFactory';
import { PageScanner, ScanData, ScanEvents } from '../service/PageScanner';
import { UiPort } from '../service/UiPort';
import { ScreenMetrics } from '../theme/Metrics';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 「发现」页的 ViewModel：地址栏 + 内嵌浏览器 + 扫描结果 + 选择与入队。
 *
 * 这一页原来的状态与逻辑（地址、页面标题、图片列表、选中计数、扫描中、模式、以及
 * 扫描重试循环与剪贴板读取）全部散在 Index 里。现在：
 *
 * - 扫描的**重试与稳定判定**交给 `service/PageScanner`（模板方法 + 策略）；
 * - `PictureItem` 的构造与按 url 合并交给 `service/PictureFactory`（工厂方法）；
 * - 剪贴板权限流程交给 `service/Clipboard`（门面）；
 * - 这里只留「这一页此刻是什么状态、用户点了之后该变成什么」。
 *
 * `browser` 与 `scroller` 是必须**先于首次 build** 存在的对象，所以在字段上直接建；
 * 它们是普通成员而不是状态 —— 组件重建时不该换控制器（换了浏览器里的网页就白加载了）。
 */
@ObservedV2
export class DiscoverViewModel {
  private ui: UiPort = new UiPort();
  private browser: webview.WebviewController = new webview.WebviewController();
  private scroller: Scroller = new Scroller();
  private scanner: PageScanner = new PageScanner();

  @Trace address: string = '';
  @Trace pageUrl: string = '';
  @Trace pageTitle: string = '';
  @Trace pictures: PictureItem[] = [];
  /**
   * 选中的张数。头部「已选 N」、底部选择条、返回顶部按钮的落点都读它 —— 必须在 build 里被
   * 真正读到，V1 才会重刷这一页（只写不读的 @State 不会触发刷新，真机实测踩过）。
   */
  @Trace selectedTotal: number = 0;
  @Trace scanning: boolean = false;
  /** 'single' | 'zip' */
  @Trace mode: string = 'single';
  /** 这一页滚远了没有；返回顶部按钮据此出现。 */
  @Trace scrolled: boolean = false;

  attach(ui: UiPort): void {
    this.ui = ui;
  }

  /** 交给 `Web({ controller })`；控制器必须自始至终是同一个实例。 */
  browserController(): webview.WebviewController {
    return this.browser;
  }

  /** 交给 `Scroll(scroller)`。 */
  scrollController(): Scroller {
    return this.scroller;
  }

  // ------------------------------------------------------------------ 返回顶部

  /**
   * 记下这一页滚远了没有。
   *
   * **不要读 `onDidScroll` 回调给的那两个 offset**：它们不是「当前总偏移」，而是这一帧的增量
   * （真机实测一次滑动里回调出 0.37 / 0.36 / 0.33… 这种小数值，直接拿去比阈值永远是 false，
   * 按钮就永远不出现）。总偏移只能从 Scroller 上取。
   */
  markScrolled(): void {
    this.scrolled = this.scroller.currentOffset().yOffset > ScreenMetrics.scrollThreshold();
  }

  scrollToTop(): void {
    this.scroller.scrollTo({
      xOffset: 0,
      yOffset: 0,
      animation: { duration: 320, curve: Curve.FastOutSlowIn }
    });
  }

  // ------------------------------------------------------------------ 浏览

  /**
   * 把剪贴板里的链接填进地址栏，并直接打开——这一步和用户在地址栏里
   * 手输/回车完全等价，所以复用 `visit()`，不再单独写一套加载逻辑。
   */
  async pasteAddress(): Promise<void> {
    let text: string = '';
    try {
      text = await Clipboard.readText(this.ui.context());
    } catch (error) {
      this.ui.say('读取剪贴板失败：' + String((error as BusinessError).message));
      return;
    }
    const link: string = text.trim();
    if (link.length === 0) {
      this.ui.say('剪贴板里没有文字');
      return;
    }
    this.address = link;
    this.visit();
  }

  /**
   * 打开地址栏里的链接。
   *
   * 三档判断只看 `MediaFormat.mediaKindOf`（扩展名白名单与命名共用一份）：
   * 实况照片包（`.livp` / `.livephoto`）和图片直链都直接建成一张选中的卡片，
   * 其余交给内嵌浏览器扫描 —— 原来这里写死了一条正则，`.livp`、`.bmp`、`.heif`
   * 这些地址都会被当成网页去 load，用户看到的是浏览器解析不了的二进制。
   */
  visit(): void {
    let input: string = this.address.trim();
    if (input.length === 0) {
      return;
    }
    // 打开新链接要立刻作废排队中的重扫与在飞结果，否则上一页的结果会落到新页面上。
    this.scanner.invalidate();
    if (!input.startsWith('http://') && !input.startsWith('https://')) {
      input = 'https://' + input;
    }
    this.address = input;
    this.pageUrl = input;
    this.pictures = [];
    this.selectedTotal = 0;
    const kind: string = MediaFormat.mediaKindOf(input);
    if (kind === 'livephoto') {
      this.pictures = [PictureFactory.fromUrl(input)];
      this.syncSelectedTotal();
      this.pageTitle = '实况照片';
      this.ui.say('这是一个实况照片包，下载后可在应用内播放');
      return;
    }
    if (kind === 'image') {
      this.pictures = [PictureFactory.fromUrl(input)];
      this.syncSelectedTotal();
      this.pageTitle = '图片';
      this.ui.say('这是一个图片地址');
      return;
    }
    this.pageTitle = '';
    this.scanning = true;
    try {
      this.browser.loadUrl(input);
    } catch (error) {
      this.scanning = false;
      this.ui.say('无法打开该链接：' + String(error));
    }
  }

  /**
   * 扫描浏览器当前页面的图片。
   *
   * `quality` 由调用方从设置里取（DiscoverScreen 直接读 SettingsViewModel）——
   * 扫描器只认档位 id，不认「谁存的档位」。
   */
  scan(quality: string): void {
    this.scanning = true;
    const events: ScanEvents = {
      onProgress: (data: ScanData): void => {
        this.pageUrl = data.url;
        this.address = data.url;
        this.pageTitle = data.title;
        this.pictures = PictureFactory.merge(this.pictures, data.images);
        // 扫描是「按 url 合并」的：上一轮选中的图会被复用，计数要跟着重算。
        this.syncSelectedTotal();
      },
      onSettled: (total: number): void => {
        this.scanning = false;
        this.ui.say(total === 0
          ? '暂未扫描到图片，滚动页面后点刷新可再试'
          : '找到 ' + this.pictures.length.toString() + ' 张图片');
      },
      onAborted: (): void => {
        this.scanning = false;
      },
      onError: (message: string): void => {
        this.scanning = false;
        this.ui.say(message);
      }
    };
    this.scanner.start(this.browser, quality, events);
  }

  /** 页面销毁 / 换页时停掉排队中的重扫（页面没了还继续注入脚本是白跑）。 */
  cancelScan(): void {
    this.scanner.cancel();
  }

  // ------------------------------------------------------------------ 选择

  private selectedCount(): number {
    return this.pictures.filter((item: PictureItem): boolean => item.selected).length;
  }

  /**
   * 选中态变化的唯一出口：头部计数、底部选择条、返回顶部按钮的落点都读 `selectedTotal`。
   *
   * 两条实测结论（都是真机上踩出来的，别照直觉改）：
   *
   * 1. **不要把整个数组重新赋值**：`this.pictures = this.pictures.slice()` 会把子组件
   *    `@ObjectLink` 的通知掐断 —— 带这次赋值的版本里磁贴的 `@Watch` 一次都不响、蒙层根本不出现。
   * 2. **改选中态必须写「父组件自己数组里的那个引用」**：从子组件回传上来的引用上写字段，
   *    值会变（这个计数跟着正确变），但通知发不出去，磁贴的蒙层会「差一拍」。
   *    具体见 `togglePicture` 的说明。
   */
  syncSelectedTotal(): void {
    this.selectedTotal = this.selectedCount();
  }

  /**
   * 切换一张图的选中态。
   *
   * 参数是 **uid 而不是 `PictureItem`**：从子组件回传上来的那个引用上直接写字段会绕过
   * `@Observed` 代理，通知发不出去 —— 值变了、计数跟着变，但磁贴自己的已选蒙层不会刷新
   * （真机实测：点一下取消勾选，勾还留在屏幕上）。所以这里按 uid 回到 `pictures` 里
   * **再取一次那个引用**，写它才会通知。
   */
  togglePicture(uid: string): void {
    const target: PictureItem | undefined =
      this.pictures.find((item: PictureItem): boolean => item.uid === uid);
    if (target === undefined) {
      return;
    }
    target.selected = !target.selected;
    this.syncSelectedTotal();
  }

  selectAll(selected: boolean): void {
    for (const item of this.pictures) {
      item.selected = selected;
    }
    this.syncSelectedTotal();
  }

  invertSelection(): void {
    if (this.pictures.length === 0) {
      this.ui.say('还没有扫描到图片');
      return;
    }
    for (const item of this.pictures) {
      item.selected = !item.selected;
    }
    this.syncSelectedTotal();
    this.ui.say('已反选，选中 ' + this.selectedTotal.toString() + ' 张');
  }

  // ------------------------------------------------------------------ 入队

  /** 把选中的图片交给下载队列；ZIP 模式只是换个打包方式，入队走同一条路。 */
  enqueue(): void {
    if (this.selectedCount() === 0) {
      this.ui.say('请先选择图片');
      return;
    }
    const zipMode: boolean = this.mode === 'zip';
    // 实况照片包不能进 ZIP：打包后剩下的只是一个压缩包，解包、播放、存相册全都无从谈起，
    // 所以 add() 会把它们按单文件走，这里的文案要跟着说清楚。
    const liveSelected: boolean = this.pictures.some((item: PictureItem): boolean =>
      item.selected && item.kind === 'livephoto');
    DownloadStore.add(this.pictures, this.pageUrl, this.pageTitle, zipMode);
    this.ui.switchTab(TAB_TASKS);
    if (zipMode && liveSelected) {
      this.ui.say('已加入任务；实况照片包按单文件下载，不参与打包');
      return;
    }
    this.ui.say(zipMode ? '已把所选图片加入打包队列' : '已加入下载任务');
  }
}
