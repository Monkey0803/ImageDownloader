import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { DownloadItem } from '../model/Models';
import { DownloadStore } from '../service/DownloadStore';
import {
  ActionOutcome, exportFile, shareFile, shareLivePhoto
} from '../service/FileActions';
import { kindOf, Palette, Space } from '../theme/Tokens';
import { ToastLatch } from '../util/Toast';
import { ImageViewer, ViewerSlide } from '../view/Cards';
import { EmptyState, PillButton, RenameDialog, ToastPill } from '../view/Widgets';

/*
 * Viewer.ets — 图片大图预览，一个**独立页面**。
 *
 * 为什么不是 Index 里的浮层：系统返回键只处理页面栈。原来图库预览是 Index 上的一层浮层，
 * 页面栈里始终只有 Index，用户按返回键就直接退出应用了。改成 router.pushUrl 推一个新页面后，
 * 返回键（以及页面自带的关闭按钮）都是 router.back()，只会退回图库。
 *
 * 参数：`{ id, rename, ids }` —— id 是 DownloadStore.downloads 里的记录 id，rename 表示这一页
 * 是否给改名入口，ids 是**调用方列表里的全部 id（按显示顺序）**，用来支持左右滑动换图。
 * 图库进来可以改名、可以滑动看下一张；任务页进来不给改名，ids 只有被点的那一张（滑不动）。
 */

interface ViewerParams {
  id?: string;
  rename?: boolean;
  ids?: string[];
}

@Entry
@ComponentV2
struct Viewer {
  /** 页面是否在前台；不在前台时不要把商店里的提示取走，否则那条提示谁也看不见。 */
  private visible: boolean = false;
  /**
   * 提示的定时器与「销毁后不再弹」的守卫。
   *
   * 导出 / 分享 / 存相册都是异步的，`.then` 回来时页面可能已经被返回键关掉了 ——
   * 那时再写 @State 就是往已销毁的组件上打回调。`ToastLatch.release()` 之后
   * `show()` 一律空操作，所以这里不需要再自己记一个 destroyed 标志。
   */
  private toast: ToastLatch = new ToastLatch();
  /** 商店的刷新回调；箭头函数属性，注册和注销用的是同一个引用。 */
  private listener: () => void = (): void => {
    this.refresh();
  };

  /**
   * 滑动顺序（id 列表）。
   *
   * 不直接用商店里的全部记录：调用方传进来的才是它**正在显示**的那一批 ——
   * 图库搜索后点开预览，左右滑动的范围也该是搜索出来的这几张。
   */
  @Local private order: string[] = [];
  /** 交给 ImageViewer 画的页数据；随商店刷新重建，交给 @Link 推给子组件。 */
  @Local private slides: ViewerSlide[] = [];
  /** 当前是第几张；滑动时由子组件写回。 */
  @Local private index: number = 0;
  @Local private renameAllowed: boolean = true;
  @Local private missing: boolean = false;
  /** 文件真的落在应用沙箱里（任务还没下完 / 已失败时只有远程地址）。 */
  @Local private local: boolean = false;
  /** 记录已经是「已完成」；用来区分「还没下完」和「下完了但沙箱里的文件没了」。 */
  @Local private completed: boolean = false;
  @Local private notice: string = '';
  @Local private renaming: boolean = false;
  @Local private renameDraft: string = '';

  aboutToAppear(): void {
    this.toast.bind((text: string): void => {
      this.notice = text;
    });
    // UIContext 上的 Router：全局 router 模块在 API 18 起已废弃。
    const params: ViewerParams = this.getUIContext().getRouter().getParams() as ViewerParams;
    let startId: string = '';
    if (params !== undefined && params !== null) {
      startId = typeof params.id === 'string' ? params.id : '';
      this.renameAllowed = params.rename !== false;
      const passed: string[] = params.ids !== undefined ? params.ids : [];
      this.order = passed.length > 0 ? passed : (startId.length > 0 ? [startId] : []);
    } else {
      this.order = [];
    }
    /*
     * 起点：调用方点的那一张就是当前这一张（`order` 里找不到时退回第一张）。
     *
     * 必须在 `refresh()` **之前**定下来：refresh 里算的 `local` / `completed` 是跟着
     * 「当前这一张」走的，先按 0 算再改索引，从第 N 张进来时会带着第 1 张的文件状态
     * （操作区收起 / 提示文案错位）。
     */
    const at: number = this.order.indexOf(startId);
    this.index = at >= 0 ? at : 0;
    DownloadStore.subscribe(this.listener);
    this.refresh();
  }

  aboutToDisappear(): void {
    DownloadStore.unsubscribe(this.listener);
    // 定时器与「销毁后不再弹」一起收掉（异步文件操作的晚到回调也走这里挡）。
    this.toast.release();
  }

  onPageShow(): void {
    this.visible = true;
    this.flushNotice();
  }

  onPageHide(): void {
    this.visible = false;
  }

  /** 当前这一张的 id；列表为空时是空串。 */
  private currentId(): string {
    if (this.index < 0 || this.index >= this.slides.length) {
      return '';
    }
    return this.slides[this.index].id;
  }

  private item(): DownloadItem | undefined {
    const id: string = this.currentId();
    if (id.length === 0) {
      return undefined;
    }
    return DownloadStore.downloads.find((entry: DownloadItem): boolean => entry.id === id);
  }

  /**
   * 画一页：落盘了就用沙箱文件，否则退回远程地址（任务没下完时只能看远程大图）。
   *
   * 实况照片多带两条沙箱路径（静图 / 视频）：`ImageViewer` 据此把这一页换成
   * `LivePhotoSlide` 播放动态。路径存在性在这里就判掉 —— 组件那边不必再管「文件在不在」。
   */
  private slideOf(item: DownloadItem): ViewerSlide {
    const landed: boolean = item.status === 'completed' && DownloadStore.exists(item.path);
    const live: boolean = item.kind === 'livephoto';
    const still: string = live && item.stillPath.length > 0 && DownloadStore.exists(item.stillPath)
      ? item.stillPath : '';
    const motion: string = live && item.motionPath.length > 0 && DownloadStore.exists(item.motionPath)
      ? item.motionPath : '';
    const slide: ViewerSlide = {
      id: item.id,
      src: landed ? fileUri.getUriFromPath(still.length > 0 ? still : item.path) : item.url,
      localPath: landed && !live ? item.path : '',
      animated: landed && item.animated,
      name: item.name,
      label: live ? '实况' : kindOf(item.name),
      stillPath: still,
      motionPath: motion
    };
    return slide;
  }

  /**
   * 从下载记录里刷新这一页。
   *
   * 记录被删掉（或本来就找不到）时不自动 back()：aboutToAppear 里 back 会撞上页面还没入栈，
   * 这里画一个空态，用户自己点返回，行为更可预期。
   *
   * 滑动列表也要在这里重建：改名会换标题、删除会少一张，索引得收敛到有效范围，
   * 否则 Swiper 会停在一个已经不存在的位置上。
   */
  private refresh(): void {
    const slides: ViewerSlide[] = [];
    const order: string[] = [];
    for (const id of this.order) {
      const item: DownloadItem | undefined =
        DownloadStore.downloads.find((entry: DownloadItem): boolean => entry.id === id);
      if (item !== undefined) {
        order.push(id);
        slides.push(this.slideOf(item));
      }
    }

    if (slides.length === 0) {
      this.order = order;
      this.slides = slides;
      this.missing = true;
      return;
    }

    // 当前这张被删了就退到它原来位置的邻居（列表已变短，索引要夹紧）。
    const at: number = order.indexOf(this.currentId());
    this.order = order;
    this.slides = slides;
    this.index = at >= 0 ? at : Math.min(Math.max(this.index, 0), slides.length - 1);
    this.missing = false;

    const item: DownloadItem | undefined = this.item();
    if (item === undefined) {
      this.missing = true;
      return;
    }
    this.completed = item.status === 'completed';
    this.local = this.completed && DownloadStore.exists(item.path);
  }

  /**
   * 操作区被收起时那句解释。
   *
   * 「没有本地文件」有三种原因，分开说：还没下完 / 下完了但沙箱里的文件没了 /
   * 这次下载失败或已取消。另外实况照片还多一种：包落盘了但解不出静图 + 视频
   * （`note` 里记着原因）—— 这时文件操作照样可用，但要说清它播不了。
   */
  private localHint(): string {
    const item: DownloadItem | undefined = this.item();
    if (this.local && item !== undefined) {
      return [item.note, item.receipt.message].filter((text: string): boolean => text.length > 0).join('；');
    }
    if (this.local) {
      return '';
    }
    if (this.completed) {
      return '应用内的文件已经不在了，只能看远程原图。';
    }
    if (item !== undefined && (item.status === 'failed' || item.status === 'cancelled')) {
      return '这次下载没有成功，只能看远程原图；重新下载后才能分享、导出或存相册。';
    }
    return '图片还没下载完成，暂时只能看大图，落盘后才能分享、导出或存相册。';
  }

  /** 弹一句提示；页面销毁后 show() 自动空操作（见 util/Toast.ets）。 */
  private say(text: string): void {
    this.toast.show(text);
  }

  private flushNotice(): void {
    if (!this.visible) {
      return;
    }
    const text: string = DownloadStore.takeNotice();
    if (text.length > 0) {
      this.say(text);
    }
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private close(): void {
    this.getUIContext().getRouter().back();
  }

  private applyRename(name: string): void {
    const item: DownloadItem | undefined = this.item();
    this.renaming = false;
    if (item === undefined) {
      return;
    }
    // 失败有两种原因（重名 / 原文件已不在），说清是哪一类，别一律赖「名称已存在」。
    this.say(DownloadStore.renameDownload(item, name) ? '重命名完成' : '改名失败：名称已存在，或原文件已不在');
  }

  private confirmDelete(): void {
    const item: DownloadItem | undefined = this.item();
    if (item === undefined) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '删除图片',
      message: '将同时删除应用内文件和下载记录，已导出的副本不受影响。',
      primaryButton: {
        value: '取消', action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除', action: (): void => {
          DownloadStore.deleteDownload(item);
          this.getUIContext().getRouter().back();
        }
      }
    });
  }

  /** 当前这一页是不是「静图与视频都在」的实况照片。 */
  private livePair(item: DownloadItem): boolean {
    return item.kind === 'livephoto' && item.stillPath.length > 0 && item.motionPath.length > 0
      && DownloadStore.exists(item.stillPath) && DownloadStore.exists(item.motionPath);
  }

  /** 文件操作的返回值本身就是给用户看的话，直接 say 出去（空串表示不用吭声）。 */
  private report(outcome: ActionOutcome): void {
    if (outcome.message.length > 0) {
      this.say(outcome.message);
    }
  }

  @Builder
  private missingState() {
    Column() {
      EmptyState({
        glyph: 'image',
        heading: '图片已不存在',
        body: '它可能已经被删除，返回图库看看其它图片。'
      })
      Column() {
        PillButton({
          label: '返回', variant: 'primary', onAction: (): void => {
            this.close();
          }
        })
      }
      .padding({ top: Space.s20 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: Space.s20, right: Space.s20 })
    .backgroundColor(Palette.bg)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.missing) {
        this.missingState()
      } else {
        ImageViewer({
          slides: this.slides,
          index: this.index,
          // V2 没有 @Link：滑动换图由子组件回传，这里改自己的状态再传下去（单向数据流）。
          onIndexChange: (next: number): void => {
            this.index = next;
          },
          renameAllowed: this.renameAllowed,
          actionable: this.local,
          hint: this.localHint(),
          onClose: (): void => {
            this.close();
          },
          onRename: (): void => {
            this.renameDraft = this.item()?.name ?? '';
            this.renaming = true;
          },
          onSaveToGallery: (): void => {
            const item: DownloadItem | undefined = this.item();
            if (item === undefined) {
              return;
            }
            if (item.receipt.target === 'gallery' && item.receipt.status === 'saved') {
              this.getUIContext().showAlertDialog({ title: '再保存一份',
                message: '这张图片此前已存入系统相册，是否再保存一份？',
                primaryButton: { value: '取消', action: (): void => {} },
                secondaryButton: { value: '再保存', action: (): void => { DownloadStore.saveToGallery(item, true); } }
              });
              return;
            }
            if (item.receipt.status === 'interrupted') {
              this.getUIContext().showAlertDialog({ title: '再次另存',
                message: '上次保存结果未确认。请先检查目标位置，避免产生重复副本。',
                primaryButton: { value: '取消', action: (): void => {} },
                secondaryButton: { value: '仍要另存', action: (): void => { DownloadStore.saveToGallery(item); } }
              });
              return;
            }
            DownloadStore.saveToGallery(item);
          },
          onShare: (): void => {
            const item: DownloadItem | undefined = this.item();
            if (item === undefined) {
              return;
            }
            if (this.livePair(item)) {
              shareLivePhoto(this.context(), item.stillPath, item.motionPath, item.path, item.name)
                .then((outcome: ActionOutcome): void => {
                  this.report(outcome);
                });
              return;
            }
            shareFile(this.context(), item.path, item.name, false).then((outcome: ActionOutcome): void => {
              this.report(outcome);
            });
          },
          onExport: (): void => {
            const item: DownloadItem | undefined = this.item();
            if (item !== undefined) {
              exportFile(this.context(), item.path, item.name).then((outcome: ActionOutcome): void => {
                this.report(outcome);
              });
            }
          },
          onDelete: (): void => {
            this.confirmDelete();
          }
        })
      }

      if (this.notice.length > 0) {
        Column() {
          ToastPill({ text: this.notice })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 88 })
        .hitTestBehavior(HitTestMode.None)
      }

      if (this.renaming) {
        RenameDialog({
          heading: '重命名图片',
          initial: this.renameDraft,
          onSave: (name: string): void => {
            this.applyRename(name);
          },
          onClose: (): void => {
            this.renaming = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
