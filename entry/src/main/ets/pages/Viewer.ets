import { PreviewOverlayState } from '../model/PreviewOverlayState';
import { PREVIEW_LIFECYCLE } from '../model/PreviewLifecycle';
import { common } from '@kit.AbilityKit';
import { DownloadItem } from '../model/Models';
import { SystemBars } from '../service/SystemBars';
import { PreviewOrientation } from '../service/PreviewOrientation';
import { ActionOutcome } from '../service/FileActions';
import { Palette, Space } from '../theme/Tokens';
import { SheetStyle } from '../theme/SheetStyle';
import { ToastLatch } from '../util/Toast';
import { ImageViewer } from '../view/Cards';
import { ViewerRequest, ViewerViewModel } from '../viewmodel/ViewerViewModel';
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

@Entry
@ComponentV2
struct Viewer {
  private orientation: PreviewOrientation = new PreviewOrientation();
  /** 页面是否在前台；不在前台时不要把商店里的提示取走，否则那条提示谁也看不见。 */
  @Local private visible: boolean = true;
  @Local private previewPanels: PreviewOverlayState = new PreviewOverlayState();
  /**
   * 提示的定时器与「销毁后不再弹」的守卫。
   *
   * 导出 / 分享 / 存相册都是异步的，`.then` 回来时页面可能已经被返回键关掉了 ——
   * 那时再写 @State 就是往已销毁的组件上打回调。`ToastLatch.release()` 之后
   * `show()` 一律空操作，所以这里不需要再自己记一个 destroyed 标志。
   */
  private toast: ToastLatch = new ToastLatch();
  private sheetMaterial: SystemUiMaterial | undefined = SheetStyle.material();
  @Local private vm: ViewerViewModel = new ViewerViewModel();
  @Local private notice: string = '';
  @Local private renaming: boolean = false;
  @Local private renameDraft: string = '';

  aboutToAppear(): void {
    this.orientation.enter(this.context());
    this.toast.bind((text: string): void => {
      this.notice = text;
    });
    const params: ViewerRequest = this.getUIContext().getRouter().getParams() as ViewerRequest;
    this.vm.start(params);
  }

  aboutToDisappear(): void {
    this.orientation.leave();
    this.vm.stop();
    // 定时器与「销毁后不再弹」一起收掉（异步文件操作的晚到回调也走这里挡）。
    this.toast.release();
  }

  onBackPress(): boolean {
    if (this.renaming) { this.renaming = false; return true; }
    return this.previewPanels.dismissTop();
  }

  @Builder
  private renameContent() {
    RenameDialog({ heading: '重命名图片', initial: this.renameDraft,
      onSave: (name: string): void => { this.applyRename(name); },
      onClose: (): void => { this.renaming = false; } })
  }

  onPageShow(): void {
    this.visible = true;
    SystemBars.enter('viewer', this.context());
    this.flushNotice();
  }

  onPageHide(): void {
    this.visible = false;
    SystemBars.leave('viewer', this.context());
  }

  /** 弹一句提示；页面销毁后 show() 自动空操作（见 util/Toast.ets）。 */
  private say(text: string): void {
    this.toast.show(text);
  }

  private flushNotice(): void {
    if (!this.visible) {
      return;
    }
    const text: string = this.vm.takeNotice();
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
    this.renaming = false;
    const message: string = this.vm.renameCurrent(name);
    if (message.length > 0) { this.say(message); }
  }

  private confirmDelete(): void {
    const item: DownloadItem | undefined = this.vm.item();
    if (item === undefined) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '删除图片',
      message: '将同时删除应用内文件和下载记录，已导出的副本不受影响。',
      backgroundColor: SheetStyle.background(),
      systemMaterial: SheetStyle.dialogMaterial(),
      primaryButton: {
        value: '取消', action: (): void => {
        }
      },
      secondaryButton: {
        fontColor: Palette.warning,
        value: '删除', action: (): void => {
          try {
            if (this.vm.deleteCurrent()) { this.close(); }
          } catch (error) { this.say(String(error)); }
        }
      }
    });
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
      if (this.vm.missing) {
        this.missingState()
      } else {
        ImageViewer({ panels: this.previewPanels, foreground: this.visible && PREVIEW_LIFECYCLE.foreground,
          slides: this.vm.slides,
          index: this.vm.index,
          // V2 没有 @Link：滑动换图由子组件回传，这里改自己的状态再传下去（单向数据流）。
          onIndexChange: (next: number): void => {
            this.vm.setIndex(next);
          },
          renameAllowed: this.vm.renameAllowed,
          actionable: this.vm.local,
          hint: this.vm.localHint(),
          onClose: (): void => {
            this.close();
          },
          onEdit: (id: string): void => {
            this.visible = false;
            this.getUIContext().getRouter().pushUrl({ url: 'pages/ImageEditor', params: { id: id } })
              .catch((error: BusinessError): void => {
                this.visible = true;
                this.toast.show('无法打开编辑页：' + error.message);
              });
          },
          onRename: (): void => {
            this.renameDraft = this.vm.item()?.name ?? '';
            this.renaming = true;
          },
          onSaveToGallery: (): void => {
            const prompt: string = this.vm.savePrompt();
            if (prompt === 'again') {
              this.getUIContext().showAlertDialog({ title: '再保存一份',
                message: '这张图片此前已存入系统相册，是否再保存一份？',
                backgroundColor: SheetStyle.background(),
                systemMaterial: SheetStyle.dialogMaterial(),
                primaryButton: { value: '取消', action: (): void => {} },
                secondaryButton: { value: '再保存', action: (): void => { this.vm.saveToGallery(true); } }
              });
            } else if (prompt === 'interrupted') {
              this.getUIContext().showAlertDialog({ title: '再次另存',
                message: '上次保存结果未确认。请先检查目标位置，避免产生重复副本。',
                backgroundColor: SheetStyle.background(),
                systemMaterial: SheetStyle.dialogMaterial(),
                primaryButton: { value: '取消', action: (): void => {} },
                secondaryButton: { value: '仍要另存', action: (): void => { this.vm.saveToGallery(); } }
              });
            } else { this.vm.saveToGallery(); }
          },
          onShare: (): void => {
            this.vm.share(this.context()).then((outcome: ActionOutcome): void => { this.report(outcome); });
          },
          onExport: (): void => {
            this.vm.export(this.context()).then((outcome: ActionOutcome): void => { this.report(outcome); });
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

    }
    .width('100%')
    .height('100%')
    .bindSheet(this.renaming, this.renameContent(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: SheetStyle.background(),
      systemMaterial: this.sheetMaterial,
      onDisappear: (): void => { this.renaming = false; }
    })
  }
}
