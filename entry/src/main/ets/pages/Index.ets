import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DownloadItem } from '../model/Models';
import { TAB_DISCOVER, TAB_LIBRARY, TAB_TASKS, TAB_SETTINGS } from '../model/Navigation';
import { DownloadStore } from '../service/DownloadStore';
import { UiPort } from '../service/UiPort';
import { DiscoverViewModel } from '../viewmodel/DiscoverViewModel';
import { DeviceViewModel } from '../viewmodel/DeviceViewModel';
import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { SettingsViewModel } from '../viewmodel/SettingsViewModel';
import { TasksViewModel } from '../viewmodel/TasksViewModel';
import { Layout, Palette, Space } from '../theme/Tokens';
import { ScreenMetrics } from '../theme/Metrics';
import { ToastLatch } from '../util/Toast';
import { DiscoverScreen } from '../view/screens/DiscoverScreen';
import { LibraryScreen } from '../view/screens/LibraryScreen';
import { SettingsScreen } from '../view/screens/SettingsScreen';
import { TasksScreen } from '../view/screens/TasksScreen';
import { GripChip, PrivacyVeil, SelectionDock, ToTopButton } from '../view/shell/Chrome';
import { RenameDialog, TabBar, ToastPill } from '../view/Widgets';

/**
 * 应用外壳（Index）。
 *
 * 这里**只做四件事**，页面内容全部交给四个 Screen 组件：
 *
 * 1. **壳层状态**：当前页签、Toast 文案与它的定时器、页面是否在前台；
 * 2. **装配 ViewModel**：五个 ViewModel 在这里各建一次，并共用一个 `UiPort`
 *    （提示、Context、推预览页、切页签、确认框的唯一出口，见 service/UiPort.ets）；
 * 3. **数据同步**：订阅 `DownloadStore` 的变更，把 ViewModel 拉回一致；
 * 4. **浮层与页签栏**：返回顶部按钮、选择条、握姿胶囊、防窥遮罩、Toast、改名弹窗 ——
 *    这些定位在滚动内容之外，只能由壳来画。
 *
 * 拆分前这个文件有 2393 行，四个页面加全部业务逻辑都长在同一个 `struct` 里；
 * 现在它只负责「谁在什么时候显示」。
 */
@Entry
@Component
struct Index {
  /** 页面是否在前台：图库预览页盖在上面时不要把这边的提示取走。 */
  private pageVisible: boolean = true;
  /** 提示的定时器与「销毁后不再弹」的守卫都在这里，见 util/Toast.ets。 */
  private toast: ToastLatch = new ToastLatch();
  /**
   * 五个 ViewModel。必须是 `@State`：子组件用 `@ObjectLink` 收它们，而 `@ObjectLink` 只认
   * 状态变量（或另一个 `@ObjectLink`）—— 写成普通成员时编译器直接报
   * 「regular property cannot be assigned to @ObjectLink property」。
   * 类都是 `@Observed`，所以第一层属性变化会同时刷到壳和各个子组件。
   */
  @State private discover: DiscoverViewModel = new DiscoverViewModel();
  @State private tasks: TasksViewModel = new TasksViewModel();
  @State private library: LibraryViewModel = new LibraryViewModel();
  @State private settings: SettingsViewModel = new SettingsViewModel();
  @State private device: DeviceViewModel = new DeviceViewModel();

  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;
  /** 软键盘高度（vp，0 = 没弹）；由 EntryAbility 的 avoidAreaChange 写入。 */
  @StorageProp('keyboardHeight') keyboardHeight: number = 0;

  @State private currentTab: number = TAB_DISCOVER;
  @State private notice: string = '';

  /**
   * 商店的刷新回调。
   *
   * 必须是**具名字段**而不是 `initialize(context, () => ...)` 里的内联箭头函数：
   * `DownloadStore.initialize` 会把它存进 `listeners`，而注销要求传同一个引用。
   * 内联写法根本拿不到那个引用，页面销毁后回调仍会被调用（往已销毁的组件上写 @State）。
   */
  private listener: () => void = (): void => {
    this.storeChanged();
  };

  aboutToAppear(): void {
    const context: common.UIAbilityContext = this.hostContext();
    this.toast.bind((text: string): void => {
      this.notice = text;
    });
    const port: UiPort = this.buildPort();
    this.discover.attach(port);
    this.tasks.attach(port);
    this.library.attach(port);
    this.settings.attach(port);
    this.device.attach(port);
    // 先挂听握姿和防窥，再初始化数据：initialize() 会按持久化的开关恢复订阅，订阅结果要能刷到界面。
    this.device.start();
    DownloadStore.initialize(context, this.listener);
    this.storeChanged();
    this.settings.applyTheme();
  }

  /**
   * 图库预览页推上来时 Index 会 onPageHide：这一页要停掉「取走商店提示」这件事。
   * 两个页面都挂了商店的刷新回调，谁先跑谁把 pendingNotice 拿走 —— 后取的那个
   * 才有机会说出口，被盖住的 Index 先抢走就等于这条提示没人看见。
   */
  onPageShow(): void {
    this.pageVisible = true;
    this.flushNotice();
  }

  onPageHide(): void {
    this.pageVisible = false;
  }

  /**
   * 页面销毁时把挂出去的东西都摘掉：商店回调、传感器回调、排队中的重扫、Toast 定时器。
   *
   * 重扫最多 8×500ms，页面没了还继续注入脚本是白跑；
   * 商店回调不摘的话，之后每次数据变化都会打到已经销毁的组件上。
   */
  aboutToDisappear(): void {
    DownloadStore.unsubscribe(this.listener);
    this.device.stop();
    this.discover.cancelScan();
    // 提示的定时器与「销毁后不再弹」一起收掉。
    this.toast.release();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  // ------------------------------------------------------------------ 装配

  /**
   * 把 ViewModel 需要的界面能力收成一个端口交给它们。
   *
   * 用 `UiPort` 而不是五个 ViewModel 各持一堆回调，是为了让「谁能碰界面」只有一个答案；
   * 默认实现是空操作，这里逐项换成真实现。
   */
  private buildPort(): UiPort {
    const port: UiPort = new UiPort();
    port.say = (text: string): void => {
      this.say(text);
    };
    port.context = (): common.UIAbilityContext => this.hostContext();
    port.switchTab = (index: number): void => {
      this.currentTab = index;
    };
    port.focusLibrary = (name: string): void => {
      this.library.focus(name);
      this.currentTab = TAB_LIBRARY;
    };
    port.openViewer = (item: DownloadItem, rename: boolean, siblings: string[]): void => {
      this.openViewer(item, rename, siblings);
    };
    port.confirm = (title: string, message: string, confirmText: string, onConfirm: () => void): void => {
      this.getUIContext().showAlertDialog({
        title: title,
        message: message,
        primaryButton: {
          value: '取消', action: (): void => {
          }
        },
        secondaryButton: {
          value: confirmText, action: onConfirm
        }
      });
    };
    return port;
  }

  /** 商店里的数据变了：把 ViewModel 拉回一致，再取一次攒下的提示。 */
  private storeChanged(): void {
    this.tasks.sync();
    this.library.sync();
    this.settings.sync();
    this.device.sync();
    this.flushNotice();
  }

  /**
   * 打开大图预览页。
   *
   * 预览必须走 **router 新页面**，不能在 Index 上再盖一层浮层：系统返回键只认页面栈，
   * 浮层时代按返回键直接退出应用（本需求的起因）。页面自己负责取记录、改名与文件操作，
   * 这里只把「看哪一条」「给不给改名」和**可以左右滑的那一批**传过去。
   */
  private openViewer(item: DownloadItem, rename: boolean, siblings: string[]): void {
    // 先把自己标成「不在前台」再推页：pushUrl 到对面 onPageShow 之间有几毫秒，
    // 这期间若有个投递失败触发了 notify，本页会先把商店里的提示取走、弹在一个马上被盖住的
    // Toast 上，预览页再取就是空串 —— 提示等于被吞了。回来时 onPageShow 会重新置 true。
    this.pageVisible = false;
    // 用 UIContext 上的 Router，不用全局 router 模块：后者在 API 18 起已废弃。
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/Viewer',
      params: { id: item.id, rename: rename, ids: siblings }
    }).catch((error: BusinessError): void => {
      this.pageVisible = true;
      this.say('无法打开预览：' + error.message);
    });
  }

  // ------------------------------------------------------------------ 提示

  /** 商店里攒下的提示（投递失败之类）由当前可见的那一页负责弹一次。 */
  private flushNotice(): void {
    if (!this.pageVisible) {
      return;
    }
    const text: string = DownloadStore.takeNotice();
    if (text.length > 0) {
      this.say(text);
    }
  }

  /** 弹一句提示；停留时长与定时器管理都在 ToastLatch 里。 */
  private say(text: string): void {
    this.toast.show(text);
  }

  // ------------------------------------------------------------------ 返回顶部

  /** 当前页签自己的「滚远了没有」；设置页没有列表，永远 false。 */
  private topVisible(): boolean {
    if (this.currentTab === TAB_DISCOVER) {
      return this.discover.scrolled;
    }
    if (this.currentTab === TAB_TASKS) {
      return this.tasks.scrolled;
    }
    if (this.currentTab === TAB_LIBRARY) {
      return this.library.scrolled;
    }
    return false;
  }

  private scrollToTop(): void {
    if (this.currentTab === TAB_TASKS) {
      this.tasks.scrollToTop();
      return;
    }
    if (this.currentTab === TAB_LIBRARY) {
      this.library.scrollToTop();
      return;
    }
    this.discover.scrollToTop();
  }

  /**
   * 返回顶部按钮离底边的距离。
   *
   * 发现页底部还叠着握姿胶囊和选择条，按钮得排在它们上面，否则会压住下载按钮 ——
   * 用和滚动内容同一套「底部预留」算法，见 DiscoverScreen 的 padding。
   */
  private toTopBottomInset(): number {
    const extra: number = this.currentTab === TAB_DISCOVER
      ? (this.discover.selectedTotal > 0 ? 68 : 0) + (this.device.gripChipVisible() ? 40 : 0)
      : 0;
    return ScreenMetrics.tabBarSpace(this.safeBottom) + Space.s12 + extra;
  }

  // ------------------------------------------------------------------ 视图

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 四个页签一律「保持挂载 + 切 visibility」，不用 if 换节点：
      // 挂载中的 Scroll 会记住自己的滚动位置，用户从别处切回来不会跳回顶部。
      // 发现页额外要留住浏览器里已经加载的网页，所以它本来就这么挂。
      Column() {
        DiscoverScreen({
          discover: this.discover,
          settings: this.settings,
          device: this.device
        })
      }
      .width('100%')
      .height('100%')
      .visibility(this.currentTab === TAB_DISCOVER ? Visibility.Visible : Visibility.None)

      Column() {
        TasksScreen({ tasks: this.tasks })
      }
      .width('100%')
      .height('100%')
      .visibility(this.currentTab === TAB_TASKS ? Visibility.Visible : Visibility.None)

      Column() {
        LibraryScreen({ library: this.library, settings: this.settings })
      }
      .width('100%')
      .height('100%')
      .visibility(this.currentTab === TAB_LIBRARY ? Visibility.Visible : Visibility.None)

      Column() {
        SettingsScreen({
          settings: this.settings,
          device: this.device,
          tasks: this.tasks
        })
      }
      .width('100%')
      .height('100%')
      .visibility(this.currentTab === TAB_SETTINGS ? Visibility.Visible : Visibility.None)

      // 大图预览已改成独立页面（pages/Viewer.ets，见 openViewer）：
      // 这里不再画浮层，否则系统返回键会绕过预览直接退出应用。

      if (this.topVisible()) {
        ToTopButton({
          mirror: this.device.gripLeft(),
          bottomSpace: this.toTopBottomInset(),
          onTap: (): void => {
            this.scrollToTop();
          }
        })
      }

      if (this.currentTab === TAB_DISCOVER && (this.discover.selectedTotal > 0 || this.device.gripChipVisible())) {
        Column({ space: Space.s8 }) {
          if (this.device.gripChipVisible()) {
            GripChip({ device: this.device })
          }
          if (this.discover.selectedTotal > 0) {
            SelectionDock({ discover: this.discover, device: this.device })
          }
        }
        .width('100%')
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          bottom: ScreenMetrics.tabBarSpace(this.safeBottom) + Space.s12
        })
      }

      // 防窥遮罩排在页签栏之前：后画的 TabBar 落在它上面，被盖住时用户仍能切页签。
      if (this.device.peeking) {
        PrivacyVeil({ device: this.device })
      }

      TabBar({
        active: this.currentTab,
        badge: this.tasks.running,
        onSelect: (index: number): void => {
          this.currentTab = index;
        }
      })

      if (this.notice.length > 0) {
        Column() {
          ToastPill({ text: this.notice })
        }
        .width('100%')
        // 没键盘时贴在页签栏上方 88（原型 .toast 的定位）。键盘弹起时窗口被压矮，
        // 页面底部就是键盘上沿 —— 这时只留 16 的间隙让 toast 压在键盘上，
        // 否则同一段 188 的内边距会把它顶到屏幕中部去（看起来像浮在内容正中）。
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          bottom: this.keyboardHeight > 0 ? Space.s16 : ScreenMetrics.tabBarSpace(this.safeBottom) + 88
        })
        // 这层盒子横跨整屏宽：键盘收起时它还把页签栏整个盖住。它纯粹是装饰，
        // 没有任何可点内容，所以整层退出命中测试：不设的话 toast 一出现，
        // 盖住的那条区域（页签栏、浮动下载条）在 2.6 秒里点不动，像卡死。
        .hitTestBehavior(HitTestMode.None)
      }

      // 只剩压缩包会用到这个弹窗；图片改名跟着大图预览页走（pages/Viewer.ets）。
      if (this.library.renameId.length > 0) {
        RenameDialog({
          heading: '重命名压缩包',
          initial: this.library.renameName,
          onSave: (name: string): void => {
            this.library.applyZipRename(name);
          },
          onClose: (): void => {
            this.library.cancelRename();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.bg)
  }
}
