import { DiscoverViewModel } from '../viewmodel/DiscoverViewModel';
import { BatchPageGroup } from '../service/BatchPageGroups';
import { PictureItem } from '../model/Models';
import { Thumb } from './Thumb';
import { PillButton, PictureSelectionButton } from './Widgets';
import { Font, Palette, Radius, Space } from '../theme/Tokens';
import { SCREEN_INSETS } from '../theme/Metrics';

@ComponentV2
export struct BatchPagePanel {
  @Require @Param discover: DiscoverViewModel;
  @Local private preview: PictureItem | undefined = undefined;
  @Local private previewReferer: string = '';

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

  build() {
    Column({ space: Space.s8 }) {
      Text(this.discover.batchReviewSummary).fontSize(Font.aux).fontColor(Palette.fontPrimary).width('100%')
      if (this.discover.batchReviewExcluded.length > 0) {
        Text(this.discover.batchReviewExcluded).fontSize(Font.caption).fontColor(Palette.fontTertiary).width('100%')
      }
      List({ space: Space.s8 }) {
        ForEach(this.discover.batchGroups, (group: BatchPageGroup) => {
          ListItem() { this.groupCard(group) }
        }, (group: BatchPageGroup): string => group.id)
      }.width('100%').height(240).scrollBar(BarState.Auto).id('batch-source-groups')
      Flex({ wrap: FlexWrap.Wrap }) {
        PillButton({ label: '返回修改', variant: 'ghost', small: true,
          onAction: (): void => { this.discover.cancelBatchReview(); } })
        if (this.discover.batchResolving) {
          PillButton({ label: '停止解析', variant: 'tonal', small: true,
            onAction: (): void => { this.discover.stopBatchPages(); } })
        }
        PillButton({ label: '加入任务 · ' + this.discover.batchSelectedCount.toString() + ' 张', variant: 'primary', small: true,
          active: this.discover.batchSelectedCount > 0 && !this.discover.batchResolving && !this.discover.batchHandling,
          onAction: (): void => { this.discover.confirmBatchReview(); } })
      }.width('100%')
    }.width('100%').padding(Space.s10).backgroundColor(Palette.cardSunken).borderRadius(Radius.r8)
    .bindContentCover(this.preview !== undefined, this.imagePreview, {
      onDisappear: (): void => { this.preview = undefined; }
    })
  }
}

/** Kept mounted at a real viewport size so dynamic pages and lazy images render normally. */
@ComponentV2
export struct BatchBrowserHost {
  @Require @Param discover: DiscoverViewModel;

  build() {
    Column({ space: Space.s8 }) {
      if (this.discover.batchHandling) {
        Text('在网页中完成登录或验证，返回后重试对应链接')
          .fontSize(Font.aux).fontColor(Palette.fontPrimary).width('100%')
        PillButton({ label: '返回批量结果', variant: 'tonal',
          onAction: (): void => { this.discover.finishBatchHandling(); } })
      }
      Web({ src: 'about:blank', controller: this.discover.batchBrowser().controller() })
        .javaScriptAccess(true).domStorageAccess(true).width('100%').layoutWeight(1)
        .onControllerAttached((): void => { this.discover.batchBrowser().ready(); })
        .onPageBegin((event): void => { this.discover.batchBrowser().pageBegan(event.url); })
        .onPageEnd((event): void => { this.discover.batchBrowser().pageEnded(event.url); })
        .onErrorReceive((event: OnErrorReceiveEvent): void => {
          if (event.request.isMainFrame()) { this.discover.batchBrowser().pageFailed(); }
        })
    }.width('100%').height('100%').backgroundColor(Palette.bg)
    .padding({ top: SCREEN_INSETS.safeTop, bottom: SCREEN_INSETS.safeBottom, left: 12, right: 12 })
    .opacity(this.discover.batchHandling ? 1 : 0)
    .hitTestBehavior(this.discover.batchHandling ? HitTestMode.Default : HitTestMode.None)
    .zIndex(this.discover.batchHandling ? 20 : -1)
  }
}
