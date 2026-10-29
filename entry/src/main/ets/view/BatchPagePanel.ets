import { DiscoverViewModel } from '../viewmodel/DiscoverViewModel';
import { HdsNavDestination, HdsNavigation } from '@kit.UIDesignKit';
import { BatchPageGroup } from '../service/BatchPageGroups';
import { BatchLinkRow, BatchLinkStatus } from '../service/BatchLinks';
import { PictureItem } from '../model/Models';
import { Thumb } from './Thumb';
import { PillButton, PictureSelectionButton, Segmented, MODE_OPTIONS } from './Widgets';
import { Font, Palette, Radius, Space } from '../theme/Tokens';
import { SCREEN_INSETS, ScreenMetrics } from '../theme/Metrics';

export const BATCH_PAGE_NAME: string = 'batch';

/**
 * 批量链接页：编辑、审核、网页处理都在同一个 HDS 页面里完成。
 *
 * 页面跟着 `batchOpen` 出栈；入栈由发现页的入口按钮直接 push（走 HDS 默认转场动画）。
 * Web 随页面存在而挂载，审核阶段的解析直接用同一块 Web，「打开网页处理」只是把工作区
 * 让开、把 Web 露出来，不重建组件（控制器一旦解绑 17100001）。
 */
@ComponentV2
export struct BatchFlowHost {
  @Require @Param discover: DiscoverViewModel;
  /** 栈由发现页持有：入栈发生在入口点击里，走 HDS 导航默认转场动画。 */
  @Require @Param pages: NavPathStack;
  @Local private preview: PictureItem | undefined = undefined;
  @Local private previewReferer: string = '';

  @Monitor('discover.batchOpen')
  private onBatchOpenChanged(monitor: IMonitor): void {
    if (!this.discover.batchOpen && this.pages.size() > 0) {
      this.pages.pop();
    }
  }

  @Builder
  private pageMap(name: string) {
    if (name === BATCH_PAGE_NAME) {
      HdsNavDestination() {
        this.batchPage()
      }
      .titleBar({
        avoidLayoutSafeArea: true,
        enableComponentSafeArea: true,
        content: {
          title: {
            mainTitle: this.discover.batchHandling ? '网页处理' : '批量链接',
            subTitle: this.discover.batchHandling ? '登录或验证后返回重试'
              : '每行一条链接，解析后选择要下载的图片'
          }
        }
      })
      .onBackPressed((): boolean => {
        if (this.discover.batchHandling) { this.discover.finishBatchHandling(); return true; }
        // 审核态返回 = 返回修改；编辑态返回 = 关闭批量页。状态变化会驱动出栈。
        if (this.discover.batchStage === 'review') { this.discover.cancelBatchReview(); return true; }
        this.discover.setBatchPanel(false);
        return true;
      })
      .width('100%')
      .height('100%')
      .backgroundColor(Palette.bg)
    }
  }

  @Builder
  private batchPage() {
    Stack({ alignContent: Alignment.TopStart }) {
      Web({ src: 'about:blank', controller: this.discover.batchBrowser().controller() })
        .javaScriptAccess(true).domStorageAccess(true).width('100%').height('100%')
        .onControllerAttached((): void => { this.discover.batchBrowser().ready(); })
        .onPageBegin((event): void => { this.discover.batchBrowser().pageBegan(event.url); })
        .onPageEnd((event): void => { this.discover.batchBrowser().pageEnded(event.url); })
        .onErrorReceive((event: OnErrorReceiveEvent): void => {
          if (event.request.isMainFrame()) { this.discover.batchBrowser().pageFailed(); }
        })
        .opacity(this.discover.batchHandling ? 1 : 0)
        .hitTestBehavior(this.discover.batchHandling ? HitTestMode.Default : HitTestMode.None)

      Column() {
        if (this.discover.batchStage === 'review') {
          this.reviewContent()
        } else {
          this.editorContent()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Palette.bg)
      .opacity(this.discover.batchHandling ? 0 : 1)
      .hitTestBehavior(this.discover.batchHandling ? HitTestMode.None : HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.bg)
    .bindContentCover(this.preview !== undefined, this.imagePreview, {
      onDisappear: (): void => { this.preview = undefined; }
    })
  }

  // ------------------------------------------------------------------ 编辑态

  @Builder
  private editorContent() {
    Scroll() {
      Column({ space: Space.s12 }) {
        Row({ space: Space.s8 }) {
          PillButton({ label: '粘贴多条', icon: 'paste', variant: 'tonal', small: true,
            onAction: (): void => { this.discover.pasteBatch(); } })
          if (this.discover.batchText.length > 0) {
            PillButton({ label: '清空', variant: 'ghost', small: true,
              onAction: (): void => { this.discover.setBatchText(''); } })
          }
        }
        .width('100%')

        TextArea({ placeholder: '每行一条图片直链或网页 URL', text: this.discover.batchText })
          .fontSize(Font.body).fontColor(Palette.fontPrimary)
          .backgroundColor(Palette.cardSunken).borderRadius(Radius.r4)
          .height(150).width('100%')
          .onChange((value: string): void => { this.discover.setBatchText(value); })

        Text(this.discover.batchSummary)
          .fontSize(Font.caption).fontColor(Palette.fontSecondary).width('100%')

        Segmented({ options: MODE_OPTIONS, selected: this.discover.mode,
          onSelect: (value: string): void => { this.discover.mode = value; } })

        if (this.discover.batchReport.rows.length > 0) {
          Column({ space: Space.s4 }) {
            ForEach(this.discover.batchReport.rows, (row: BatchLinkRow) => {
              this.batchRow(row)
            }, (row: BatchLinkRow): string => row.line.toString() + '|' + row.status + '|'
              + row.reason + '|' + row.url)
          }
          .width('100%')
        }

        if (this.discover.batchProbeLabel.length > 0) {
          Text(this.discover.batchProbeLabel)
            .fontSize(Font.caption)
            .fontColor(this.discover.batchProbing ? Palette.brand : Palette.fontTertiary)
            .width('100%')
        }

        Flex({ wrap: FlexWrap.Wrap }) {
          if (this.discover.batchReport.pending > 0) {
            PillButton({ label: '检查待确认 · ' + this.discover.batchReport.pending.toString(),
              variant: 'ghost', small: true, active: !this.discover.batchProbing,
              onAction: (): void => { this.discover.startBatchCheck(); } })
          }
          PillButton({ label: this.discover.batchProbing ? '正在检查…' : '解析并预览',
            variant: 'primary', small: true,
            active: this.discover.batchReport.urls.length > 0 && !this.discover.batchProbing,
            onAction: (): void => { this.discover.reviewBatch(); } })
          if (this.discover.batchProbing) {
            PillButton({ label: '跳过检查', variant: 'ghost', small: true,
              onAction: (): void => { this.discover.skipBatchProbe(); } })
          }
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      // 内容不足一屏时 Scroll 会把内容居中（顶部留出大块空白），撑到一屏高让它从顶部开始。
      .constraintSize({ minHeight: ScreenMetrics.height() })
      .padding({
        left: Space.s16, right: Space.s16, top: Space.s12,
        bottom: SCREEN_INSETS.safeBottom + Space.s12
      })
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private batchRow(row: BatchLinkRow) {
    Row({ space: Space.s8 }) {
      Text(this.batchStatusLabel(row.status))
        .fontSize(Font.caption)
        .fontColor(this.batchStatusColor(row.status))
        .width(40)
      Column({ space: Space.s2 }) {
        Text(row.url)
          .fontSize(Font.caption)
          .fontColor(Palette.fontPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (row.reason.length > 0) {
          Text(row.reason)
            .fontSize(Font.caption)
            .fontColor(Palette.fontTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: Space.s8, right: Space.s8, top: Space.s6, bottom: Space.s6 })
    .backgroundColor(Palette.card)
    .borderRadius(Radius.r6)
  }

  private batchStatusLabel(status: string): string {
    if (status === BatchLinkStatus.PAGE) { return '网页'; }
    if (status === BatchLinkStatus.VALID) { return '有效'; }
    if (status === BatchLinkStatus.PENDING) { return '待确认'; }
    if (status === BatchLinkStatus.DUPLICATE) { return '重复'; }
    return '无效';
  }

  private batchStatusColor(status: string): ResourceColor {
    if (status === BatchLinkStatus.PAGE) { return Palette.brand; }
    if (status === BatchLinkStatus.VALID) { return Palette.confirm; }
    if (status === BatchLinkStatus.PENDING) { return Palette.warning; }
    if (status === BatchLinkStatus.DUPLICATE) { return Palette.fontTertiary; }
    return Palette.alert;
  }

  // ------------------------------------------------------------------ 审核态

  @Builder
  private reviewContent() {
    Column({ space: Space.s8 }) {
      Column({ space: Space.s4 }) {
        Text(this.discover.batchReviewSummary)
          .fontSize(Font.aux).fontColor(Palette.fontPrimary).width('100%')
        if (this.discover.batchReviewExcluded.length > 0) {
          Text(this.discover.batchReviewExcluded)
            .fontSize(Font.caption).fontColor(Palette.fontTertiary).width('100%')
        }
      }
      .width('100%')
      .padding({ left: Space.s16, right: Space.s16, top: Space.s12 })

      List({ space: Space.s8 }) {
        ForEach(this.discover.batchGroups, (group: BatchPageGroup) => {
          ListItem() { this.groupCard(group) }
        }, (group: BatchPageGroup): string => group.id)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: Space.s16, right: Space.s16 })
      .scrollBar(BarState.Auto)
      .id('batch-source-groups')

      Row({ space: Space.s8 }) {
        if (this.discover.batchResolving) {
          PillButton({ label: '停止解析', variant: 'tonal', small: true,
            onAction: (): void => { this.discover.stopBatchPages(); } })
        }
        Blank()
        PillButton({ label: '加入任务 · ' + this.discover.batchSelectedCount.toString() + ' 张',
          variant: 'primary', small: true,
          active: this.discover.batchSelectedCount > 0 && !this.discover.batchResolving && !this.discover.batchHandling,
          onAction: (): void => { this.discover.confirmBatchReview(); } })
      }
      .width('100%')
      .padding({
        left: Space.s16, right: Space.s16, top: Space.s8,
        bottom: SCREEN_INSETS.safeBottom + Space.s12
      })
    }
    .width('100%').height('100%')
  }

  @Builder
  private groupCard(group: BatchPageGroup) {
    Column({ space: Space.s6 }) {
      Text(group.title).fontSize(Font.aux).fontColor(Palette.fontPrimary)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      if (group.kind !== 'direct') {
        Text('第 ' + group.line.toString() + ' 行 · ' + group.inputUrl)
          .fontSize(Font.caption).fontColor(Palette.fontTertiary).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
      Text(group.status === 'loading' ? '正在解析网页…'
        : group.status === 'waiting' ? '等待解析'
        : group.status === 'failed' ? group.message
        : '已选 ' + group.pictures.filter((picture: PictureItem): boolean => picture.selected).length.toString()
          + '/' + group.pictures.length.toString() + ' 张' + (group.message.length > 0 ? ' · ' + group.message : ''))
        .fontSize(Font.caption).fontColor(group.status === 'failed' ? Palette.warning : Palette.fontSecondary)
        .width('100%')
      if (group.pictures.length > 0) {
        List({ space: Space.s8 }) {
          ForEach(group.pictures, (picture: PictureItem, pictureIndex: number) => {
            ListItem() {
              Stack({ alignContent: Alignment.BottomEnd }) {
                Thumb({ src: picture.url, referer: group.kind === 'direct' ? picture.url : group.pageUrl,
                  fallbackText: picture.kind === 'livephoto' ? '实况照片包' : '预览失败，可尝试下载' })
                  .width(96).height(96).borderRadius(Radius.r6).clip(true)
                  .onClick((): void => {
                    this.previewReferer = group.kind === 'direct' ? picture.url : group.pageUrl;
                    this.preview = picture;
                  })
                  .accessibilityText('预览图片 ' + picture.name)
                PictureSelectionButton({ selected: picture.selected, diameter: 32,
                  onAction: (): void => { this.discover.toggleBatchPicture(group.id, picture.uid); } })
                  .id('batch-select-' + group.id + '-' + pictureIndex.toString())
                  .margin({ right: 2, bottom: 2 })
              }.width(96).height(96)
            }
          }, (picture: PictureItem): string => picture.uid)
        }.listDirection(Axis.Horizontal).height(100).width('100%').scrollBar(BarState.Auto)
        PillButton({ label: group.pictures.every((picture: PictureItem): boolean => picture.selected) ? '取消全选' : '全选本组',
          variant: 'ghost', small: true, onAction: (): void => { this.discover.selectBatchGroup(group); } })
      }
      if (group.status === 'failed' || group.status === 'waiting') {
        Flex({ wrap: FlexWrap.Wrap }) {
          PillButton({ label: '重试此页', variant: 'tonal', small: true, active: !this.discover.batchResolving,
            onAction: (): void => { this.discover.retryBatchPage(group); } })
          PillButton({ label: '打开网页处理', variant: 'ghost', small: true, active: !this.discover.batchResolving,
            onAction: (): void => { this.discover.openBatchPage(group); } })
          if (group.kind === 'pending') {
            PillButton({ label: '作为直链尝试', variant: 'ghost', small: true, active: !this.discover.batchResolving,
              onAction: (): void => { this.discover.importPendingAsDirect(group); } })
          }
        }.width('100%')
      }
    }.width('100%').padding(Space.s8).backgroundColor(Palette.card).borderRadius(Radius.r6)
    .alignItems(HorizontalAlign.Start)
  }

  // ------------------------------------------------------------------ 预览

  @Builder
  private imagePreview() {
    Column({ space: Space.s12 }) {
      Row({ space: Space.s8 }) {
        PillButton({ label: '关闭预览', variant: 'ghost', small: true,
          onAction: (): void => { this.preview = undefined; } })
        if (this.preview !== undefined) {
          PillButton({ label: this.preview.selected ? '取消选择' : '选择图片', variant: 'tonal', small: true,
            onAction: (): void => { if (this.preview !== undefined) { this.preview.selected = !this.preview.selected; } } })
        }
      }.width('100%')
      if (this.preview !== undefined) {
        Thumb({ src: this.preview.url, referer: this.previewReferer, fit: ImageFit.Contain,
          fallbackText: '预览失败，可返回后重试或尝试下载' }).layoutWeight(1).width('100%')
        Text(this.preview.name).fontSize(Font.caption).fontColor(Palette.fontSecondary).maxLines(2)
      }
    }.width('100%').height('100%').backgroundColor(Palette.bg)
    .padding({ top: SCREEN_INSETS.safeTop + 16, bottom: SCREEN_INSETS.safeBottom + 16, left: 16, right: 16 })
  }

  build() {
    HdsNavigation(this.pages) {
      Column() {}
    }
    .navDestination(this.pageMap)
    .hideNavBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.discover.batchOpen ? HitTestMode.Default : HitTestMode.None)
  }
}
