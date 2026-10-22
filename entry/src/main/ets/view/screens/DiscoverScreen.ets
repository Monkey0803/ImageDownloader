import { PictureItem } from '../../model/Models';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { uiMaterial } from '@kit.ArkUI';
import { BrowserEntry } from '../../service/BrowserCollection';
import { MaterialSupport } from '../../service/MaterialSupport';
import { DiscoverViewModel } from '../../viewmodel/DiscoverViewModel';
import { DeviceViewModel } from '../../viewmodel/DeviceViewModel';
import { SettingsViewModel } from '../../viewmodel/SettingsViewModel';
import { chunkRows, fillerCells } from '../../util/GridMath';
import { Font, Layout, Palette, Radius, Shadow, Space } from '../../theme/Tokens';
import { ScreenMetrics } from '../../theme/Metrics';
import { Glyph } from '../Icons';
import { SelectTile, Thumb } from '../Cards';
import { HintRow, IconButton, PillButton, SectionHead, SettingSelect } from '../Widgets';
import { SCREEN_INSETS } from '../../theme/Metrics';

const FILTER_FORMATS: string[] = ['', 'jpg', 'png', 'gif', 'webp', 'other'];
const FILTER_LABELS: string[] = ['全部格式', 'JPEG', 'PNG', 'GIF', 'WebP', '其他'];
const FILTER_OPTIONS: SelectOption[] = FILTER_LABELS.map((label: string): SelectOption => ({ value: label }));
const QUICK_IDS: string[] = ['', 'large', 'landscape', 'portrait'];
const QUICK_LABELS: string[] = ['全部', '大图', '横图', '竖图'];

/**
 * 「发现」页：结果为主视图；浏览器持续挂载，在全屏浏览视图中显示。
 *
 * 从 Index 的 `discoverScreen()` / `browserCard()` 两个 @Builder 搬过来，只把状态来源从
 * 「页面自己的字段」换成三个 ViewModel：
 * - `discover`：地址、扫描结果、选中计数、扫描中、模式；
 * - `settings`：只有一处用 —— 扫描时要读「下载图片质量」当前档位；
 * - `device`：只有一处用 —— 左手握持时把「选择要下载的图片」那一行镜像过去。
 *
 * 安全区高度直接读 `SCREEN_INSETS` 单例（EntryAbility 写入，字段是 `@Trace`），不再层层透传；
 * 迁移前这里是 `@StorageProp` —— V2 里它非法（报 10905339）。
 * 四个页面始终挂载、只切 `visibility`，所以浏览器里已加载的网页和滚动位置都留得住。
 */
@ComponentV2
export struct DiscoverScreen {
  @Require @Param discover: DiscoverViewModel;
  @Require @Param settings: SettingsViewModel;
  @Require @Param device: DeviceViewModel;
  @Param browserOpen: boolean = false;
  @Event onOpenBrowser: () => void = (): void => {};
  @Event onShowResults: () => void = (): void => {};
  @Local private filtersOpen: boolean = false;
  private inspectionMaterial: uiMaterial.Material | undefined = undefined;
  private inspectionDialogId: number | undefined = undefined;

  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。
  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。

  @Builder
  private addressEntry() {
    Row({ space: Space.s8 }) {
      Glyph({ glyph: 'globe', glyphSize: 18, glyphTone: Palette.fontTertiary, glyphWeight: 1.7 })
      TextInput({ placeholder: '输入网页或图片链接', text: this.discover.address })
        .placeholderColor(Palette.fontSecondary)
        .caretColor(Palette.brand)
        .fontSize(Font.body)
        .fontColor(Palette.fontPrimary)
        .backgroundColor(Color.Transparent)
        .padding(0)
        .height(36)
        .layoutWeight(1)
        .onChange((value: string): void => { this.discover.address = value; })
        .onSubmit((): void => { this.discover.visit(); })
      PillButton({
        icon: 'paste', variant: 'tonal', small: true,
        onAction: (): void => { this.discover.pasteAddress(); }
      })
      PillButton({
        icon: 'arrowRight', variant: 'primary', small: true,
        active: this.discover.address.trim().length > 0,
        onAction: (): void => { this.discover.visit(); }
      })
    }
    .width('100%')
    .height(44)
    .padding({ left: Space.s14, right: Space.s4 })
    .borderRadius(Radius.full)
    .backgroundColor(Palette.card)
    .shadow(Shadow.card())
  }

  @Builder
  private addressTitleBar() {
    Row({ space: Space.s6 }) {
      if (this.browserOpen) {
        IconButton({ glyph: 'chevronRight', glyphSize: 18, diameter: 36, plain: true,
          accessibilityLabel: '返回结果', onAction: this.onShowResults }).rotate({ angle: 180 })
      }
      Column() {
        this.addressEntry()
      }.layoutWeight(1)
      IconButton({ glyph: this.discover.isBookmarked() ? 'bookmarkFill' : 'bookmark',
        glyphSize: 20, diameter: 36, plain: true,
        accessibilityLabel: this.discover.isBookmarked() ? '取消收藏当前网页' : '收藏当前网页',
        onAction: (): void => { this.discover.toggleBookmark(); } })
    }
    .width('100%')
    .padding({ left: Layout.pagePad, right: Layout.pagePad })
  }

  @Builder
  private batchEntry() {
    Column({ space: Space.s8 }) {
      Row({ space: Space.s8 }) {
        PillButton({ label: this.discover.batchOpen ? '收起批量链接' : '批量链接',
          variant: 'ghost', small: true,
          onAction: (): void => { this.discover.batchOpen = !this.discover.batchOpen; } })
        if (this.discover.batchOpen) {
          PillButton({ label: '粘贴多条', icon: 'paste', variant: 'tonal', small: true,
            onAction: (): void => { this.discover.pasteBatch(); } })
        }
      }.width('100%')
      if (this.discover.batchOpen) {
        TextArea({ placeholder: '每行一条图片直链', text: this.discover.batchText })
          .fontSize(Font.body).fontColor(Palette.fontPrimary)
          .backgroundColor(Palette.cardSunken).borderRadius(Radius.r4)
          .height(112).width('100%')
          .onChange((value: string): void => { this.discover.batchText = value; })
        Text('可导入 ' + this.discover.batchReport.urls.length.toString() + ' 条 · 无效 '
          + this.discover.batchReport.invalid.toString() + ' 条 · 重复 '
          + this.discover.batchReport.duplicates.toString() + ' 条')
          .fontSize(Font.caption).fontColor(Palette.fontSecondary)
        PillButton({ label: '确认加入任务', variant: 'primary', small: true,
          active: this.discover.batchReport.urls.length > 0,
          onAction: (): void => { this.discover.enqueueBatch(); } })
      }
    }
    .width('100%')
  }

  @Builder
  private inspectionPanel(item: PictureItem) {
    Column({ space: Space.s8 }) {
      Row({ space: Space.s8 }) {
        Text('图片详情').fontSize(Font.body).fontWeight(FontWeight.Bold)
          .fontColor(Palette.fontPrimary).layoutWeight(1)
        IconButton({ glyph: 'close', glyphSize: 18, diameter: 36,
          accessibilityLabel: '关闭图片详情',
          onAction: (): void => { this.closeInspection(); } })
      }.width('100%')
      Thumb({ src: this.discover.previewUri, label: 'IMG', fit: ImageFit.Contain,
        fallbackText: this.discover.previewLoading ? '正在加载预览…' : '预览不可用' })
        .width('100%').height(180).borderRadius(Radius.r4)
      Text('来源地址：' + item.url).fontSize(Font.caption).fontColor(Palette.fontSecondary)
        .copyOption(CopyOptions.InApp).width('100%')
      Text('分辨率：' + (item.width > 0 && item.height > 0
        ? item.width.toString() + '×' + item.height.toString() + '（已测得）' : '未知'))
        .fontSize(Font.caption).fontColor(Palette.fontSecondary)
      Text('文件大小：' + this.discover.inspectionSizeLabel())
        .fontSize(Font.caption).fontColor(Palette.fontSecondary)
      Text(this.discover.previewMessage)
        .fontSize(Font.caption).fontColor(Palette.fontTertiary)
      if (!this.discover.previewLoading && this.discover.previewUri.length === 0 && item.kind === 'image') {
        PillButton({ label: '重试预览', variant: 'ghost', small: true,
          onAction: (): void => { this.discover.inspect(item.uid); } })
      }
      Row({ space: Space.s8 }) {
        IconButton({ glyph: item.selected ? 'xCircle' : 'checkCircle', glyphSize: 20,
          accessibilityLabel: item.selected ? '取消选择此图' : '选择此图',
          onAction: (): void => { this.discover.togglePicture(item.uid); } })
        if (this.discover.pageUrl !== item.url && this.discover.pageUrl.startsWith('http')) {
          IconButton({ glyph: 'arrowRight', glyphSize: 20,
            accessibilityLabel: '查看来源页',
            onAction: (): void => {
              this.closeInspection();
              this.discover.resumeBrowser();
            } })
        }
      }.width('100%')
    }
    .alignItems(HorizontalAlign.Start).width('100%')
    .padding(Space.s12)
  }

  private sheetMaterial(): uiMaterial.Material | undefined {
    if (!MaterialSupport.immersiveSupported()) {
      return undefined;
    }
    if (!this.settings.lightEffect || this.settings.materialType === 'none') {
      return uiMaterial.Material.empty;
    }
    if (this.inspectionMaterial === undefined) {
      this.inspectionMaterial = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THICK,
        materialColor: Palette.sheetTint,
        interactive: true,
        lightEffect: { color: Palette.brand }
      });
    }
    return this.inspectionMaterial;
  }

  @Builder
  private inspectionSheet() {
    Scroll() {
      Column() {
        ForEach(this.discover.inspectedPicture === undefined ? [] : [this.discover.inspectedPicture!],
          (item: PictureItem) => {
            this.inspectionPanel(item)
          }, (item: PictureItem) => item.uid)
      }.width('100%')
    }
    .width('100%')
    .constraintSize({ maxHeight: ScreenMetrics.height() * 0.7 })
    .scrollBar(BarState.Auto)
  }

  private openInspection(uid: string): void {
    this.discover.inspect(uid);
    if (this.inspectionDialogId !== undefined) {
      return;
    }
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: (): void => { this.inspectionSheet(); },
      alignment: DialogAlignment.Center,
      width: '90%',
      autoCancel: true,
      backgroundColor: Palette.card,
      systemMaterial: this.sheetMaterial(),
      onWillDismiss: (action: DismissDialogAction): void => {
        this.discover.closeInspection();
        this.inspectionDialogId = undefined;
        action.dismiss();
      }
    }).then((id: number): void => { this.inspectionDialogId = id; });
  }

  private closeInspection(): void {
    this.discover.closeInspection();
    if (this.inspectionDialogId !== undefined) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.inspectionDialogId);
      this.inspectionDialogId = undefined;
    }
  }

  @Builder
  private expansionControls() {
    if (this.discover.canExpand() || this.discover.expanding) {
      Column({ space: Space.s4 }) {
        PillButton({ label: this.discover.expanding ? '停止加载' : '加载更多图片',
          variant: this.discover.expanding ? 'tonal' : 'ghost', small: true,
          onAction: (): void => {
            if (this.discover.expanding) { this.discover.stopExpansion(); }
            else { this.discover.loadMore(this.settings.pictureQuality); }
          } })
        if (this.discover.expansionMessage.length > 0) {
          Text(this.discover.expansionMessage).fontSize(Font.caption).fontColor(Palette.fontSecondary)
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private browserView() {
    Column({ space: Space.s10 }) {
      Row({ space: Space.s6 }) {
        IconButton({ glyph: 'chevronRight', glyphSize: 18, plain: true,
          accessibilityLabel: '返回上一页',
          onAction: (): void => { this.discover.navigateBack(); }
        }).rotate({ angle: 180 })
        IconButton({ glyph: 'chevronRight', glyphSize: 18, plain: true,
          accessibilityLabel: '前进到下一页',
          onAction: (): void => { this.discover.navigateForward(); }
        })
        IconButton({ glyph: 'refresh', glyphSize: 18, plain: true,
          accessibilityLabel: '重新加载当前网页',
          onAction: (): void => { this.discover.reload(); }
        })
        PillButton({ label: '重扫图片', icon: 'scan', variant: 'ghost', small: true,
          onAction: (): void => { this.discover.scan(this.settings.pictureQuality); }
        })
      }
      .width('100%')

      this.expansionControls()

      Stack({ alignContent: Alignment.Bottom }) {
        Web({ src: 'about:blank', controller: this.discover.browserController() })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .width('100%')
          .height('100%')
          .backgroundColor(Palette.card)
          .onPageBegin((): void => { this.discover.navigationStarted(); })
          .onPageEnd((): void => {
            this.discover.browserPageEnded(this.settings.pictureQuality);
          })
          .onErrorReceive((event: OnErrorReceiveEvent): void => {
            if (event.request.isMainFrame()) {
              this.discover.navigationFailed(event.error.getErrorInfo());
            }
          })
        if (this.discover.scanning) {
          Text('正在扫描当前网页…')
            .fontSize(Font.caption).fontColor(Palette.white)
            .padding({ left: Space.s10, right: Space.s10, top: Space.s6, bottom: Space.s6 })
            .borderRadius(Radius.full).backgroundColor('#8C000000')
            .margin({ bottom: Space.s8 })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(Palette.card)
      .borderRadius(Radius.r8)
      .clip(true)

      if (this.discover.browserProblem.length > 0) {
        Text('网页加载失败：' + this.discover.browserProblem)
          .fontSize(Font.caption).fontColor(Palette.warning)
      }

      Scroll() {
        this.browserLibrary()
      }
      .width('100%')
      .height(this.discover.browserPanel.length > 0 ? 180 : 64)
      .scrollBar(BarState.Off)

      PillButton({
        label: this.discover.scanning ? '正在扫描…' : '查看图片 · ' + this.discover.pictures.length.toString() + ' 张',
        icon: 'image', variant: 'primary',
        onAction: this.onShowResults
      })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: Layout.pagePad, right: Layout.pagePad,
      top: Space.s12,
      bottom: SCREEN_INSETS.safeBottom + Space.s12
    })
    .backgroundColor(Palette.bg)
  }

  @Builder
  private pageSummary() {
    Column({ space: Space.s8 }) {
      Row({ space: Space.s8 }) {
        Column({ space: Space.s4 }) {
          Text(this.discover.pageTitle.length > 0 ? this.discover.pageTitle
            : (this.discover.pageUrl.length > 0 ? '当前网页' : '尚未打开网页'))
            .fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(Palette.fontPrimary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.discover.pageUrl.length > 0 ? this.discover.pageUrl : '打开网页后自动扫描图片')
            .fontSize(Font.caption).fontColor(Palette.fontTertiary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(this.discover.pictures.length.toString() + ' 张')
          .fontSize(Font.caption).fontColor(Palette.fontSecondary)
      }
      .width('100%')
      PillButton({ label: this.discover.pageUrl.length > 0 ? '继续浏览' : '打开网页',
        icon: 'globe', variant: 'ghost', small: true, onAction: this.onOpenBrowser })
      if (this.discover.browserProblem.length > 0) {
        Text('网页加载失败：' + this.discover.browserProblem)
          .fontSize(Font.caption).fontColor(Palette.warning)
      }
    }
    .width('100%')
    .padding(Space.s12)
    .borderRadius(Radius.r8)
    .backgroundColor(Palette.card)
    .shadow(Shadow.card())
  }

  @Builder
  private browserLibrary() {
    Column({ space: Space.s8 }) {
      Row({ space: Space.s8 }) {
        PillButton({
          label: '收藏 ' + this.discover.bookmarks.length.toString(), variant: 'ghost', small: true,
          onAction: (): void => {
            this.discover.browserPanel = this.discover.browserPanel === 'bookmarks' ? '' : 'bookmarks';
          }
        })
        PillButton({
          label: '历史 ' + this.discover.history.length.toString(), variant: 'ghost', small: true,
          onAction: (): void => {
            this.discover.browserPanel = this.discover.browserPanel === 'history' ? '' : 'history';
          }
        })
      }.width('100%')

      if (this.discover.browserPanel.length > 0) {
        Row() {
          Text(this.discover.browserPanel === 'bookmarks' ? '收藏的网址' : '浏览记录')
            .fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(Palette.fontPrimary)
            .layoutWeight(1)
          if (this.discover.browserPanel === 'history' && this.discover.history.length > 0) {
            PillButton({ label: '清空历史', variant: 'ghost', small: true,
              onAction: (): void => { this.discover.clearHistory(); } })
          }
        }.width('100%')
        if ((this.discover.browserPanel === 'bookmarks' ? this.discover.bookmarks : this.discover.history).length === 0) {
          Text(this.discover.browserPanel === 'bookmarks' ? '还没有收藏网页' : '还没有浏览记录')
            .fontSize(Font.caption).fontColor(Palette.fontTertiary)
        } else {
          ForEach(this.discover.browserPanel === 'bookmarks' ? this.discover.bookmarks : this.discover.history,
            (item: BrowserEntry) => {
              Row({ space: Space.s8 }) {
                Column({ space: Space.s4 }) {
                  Text(item.title).fontSize(Font.body).fontColor(Palette.fontPrimary)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.url).fontSize(Font.caption).fontColor(Palette.fontTertiary)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1)
                .onClick((): void => {
                  this.discover.address = item.url;
                  this.discover.visit();
                  this.discover.browserPanel = '';
                })
                if (this.discover.browserPanel === 'bookmarks') {
                  PillButton({ label: '移除', variant: 'ghost', small: true,
                    onAction: (): void => { this.discover.removeBookmark(item.url); } })
                }
              }
              .width('100%')
              .padding({ top: Space.s8, bottom: Space.s8 })
            }, (item: BrowserEntry) => item.url)
        }
      }
    }
    .width('100%')
    .padding({ left: Space.s12, right: Space.s12, top: Space.s10, bottom: Space.s10 })
    .borderRadius(Radius.r8)
    .backgroundColor(Palette.card)
  }

  /** 扫描结果的网格；空态是一句引导，不是 EmptyState 卡片（这里还在同一个滚动流里）。 */
  @Builder
  private resultGrid() {
    if (this.discover.visiblePictures.length > 0) {
      Column({ space: Space.s8 }) {
        ForEach(chunkRows<PictureItem>(this.discover.visiblePictures, 3), (row: PictureItem[], rowIndex: number) => {
          Row({ space: Space.s8 }) {
            ForEach(row, (cell: PictureItem, colIndex: number) => {
              Stack({ alignContent: Alignment.BottomEnd }) {
                SelectTile({
                  picture: cell,
                  index: rowIndex * 3 + colIndex,
                  // 只传 uid：子组件回传的引用上直接写字段会绕过 @Observed 代理、不发通知
                  // （见 SelectTile.onToggle 的说明）。
                  onToggle: (uid: string): void => {
                    this.discover.togglePicture(uid);
                  }
                })
                IconButton({ glyph: 'info', glyphSize: 18, diameter: 36,
                  accessibilityLabel: '查看图片详情',
                  onAction: (): void => { this.openInspection(cell.uid); } })
                  .margin({ right: Space.s4, bottom: Space.s4 })
              }
              .width('100%')
              .layoutWeight(1)
            }, (cell: PictureItem) => cell.uid)

            ForEach(fillerCells(row.length, 3), (pad: number) => {
              Column().layoutWeight(1)
            }, (pad: number) => 'pad' + pad.toString())
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (row: PictureItem[]) => row.map((cell: PictureItem): string => cell.uid).join(','))
      }
      .width('100%')
    } else {
      Text(this.discover.pictures.length > 0
        ? '没有符合筛选条件的图片，请调整条件或清除筛选。'
        : '还没有扫描到图片。输入网页链接，或打开浏览视图后重新扫描。')
        .fontSize(Font.aux)
        .lineHeight(Font.subtitleLine)
        .fontColor(Palette.fontTertiary)
        .textAlign(TextAlign.Start)
        .width('100%')
        .padding({ top: Space.s20, bottom: Space.s20 })
    }
  }

  @Builder
  private quickFilters() {
    Row({ space: Space.s6 }) {
      ForEach(QUICK_IDS, (id: string, index: number) => {
        PillButton({ label: QUICK_LABELS[index], small: true,
          variant: this.discover.quickFilter === id ? 'tonal' : 'ghost',
          onAction: (): void => { this.discover.quickFilter = id; } })
      }, (id: string) => id)
    }.width('100%')
  }

  @Builder
  private filterPanel() {
    Column({ space: Space.s8 }) {
      Row({ space: Space.s8 }) {
        SettingSelect({
          options: FILTER_OPTIONS,
          selectedIndex: FILTER_FORMATS.indexOf(this.discover.filterFormat),
          label: FILTER_LABELS[FILTER_FORMATS.indexOf(this.discover.filterFormat)],
          onPick: (index: number): void => {
            this.discover.filterFormat = FILTER_FORMATS[index];
          }
        })
        TextInput({ placeholder: '最小宽', text: this.discover.filterWidth })
          .fontSize(Font.aux).fontColor(Palette.fontPrimary)
          .backgroundColor(Palette.cardSunken).borderRadius(Radius.r4)
          .layoutWeight(1)
          .onChange((value: string): void => {
            this.discover.filterWidth = value.replace(/[^0-9]/g, '');
          })
        TextInput({ placeholder: '最小高', text: this.discover.filterHeight })
          .fontSize(Font.aux).fontColor(Palette.fontPrimary)
          .backgroundColor(Palette.cardSunken).borderRadius(Radius.r4)
          .layoutWeight(1)
          .onChange((value: string): void => {
            this.discover.filterHeight = value.replace(/[^0-9]/g, '');
          })
      }
      .width('100%')
      Row({ space: Space.s8 }) {
        TextInput({ placeholder: '筛选来源 URL', text: this.discover.filterUrl })
          .fontSize(Font.aux).fontColor(Palette.fontPrimary)
          .backgroundColor(Palette.cardSunken).borderRadius(Radius.r4)
          .layoutWeight(1)
          .onChange((value: string): void => { this.discover.filterUrl = value; })
      }
      .width('100%')
      Text('共 ' + this.discover.pictures.length.toString() + ' 张 · 筛选后 '
        + this.discover.visiblePictures.length.toString() + ' 张 · 尺寸未知的图片仍显示')
        .fontSize(Font.caption).fontColor(Palette.fontTertiary)
    }
    .width('100%')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() {
        Scroll(this.discover.scrollController()) {
        Column({ space: Space.s16 }) {
          this.batchEntry()
          this.pageSummary()

          Column({ space: Space.s10 }) {
            SectionHead({
              heading: '选择要下载的图片',
              meta: this.discover.selectedTotal > 0
                ? '已选 ' + this.discover.selectedTotal.toString()
                : this.discover.pictures.length.toString() + ' 张',
              actionLabel: '全选',
              secondLabel: '反选',
              thirdLabel: '清空',
              mirror: this.device.gripLeft(),
              onAction: (): void => {
                this.discover.selectAll(true);
              },
              onSecond: (): void => {
                this.discover.invertSelection();
              },
              onThird: (): void => {
                this.discover.selectAll(false);
              }
            })

            Row({ space: Space.s8 }) {
              PillButton({
                label: this.filtersOpen ? '收起筛选' : '筛选图片',
                icon: 'sliders', variant: this.discover.hasFilters() ? 'tonal' : 'ghost', small: true,
                onAction: (): void => { this.filtersOpen = !this.filtersOpen; }
              })
              if (this.discover.hasFilters()) {
                Text('已筛选 · ' + this.discover.visiblePictures.length.toString() + ' 张')
                  .fontSize(Font.caption).fontColor(Palette.fontSecondary).layoutWeight(1)
                PillButton({ label: '清除筛选', variant: 'ghost', small: true,
                  onAction: (): void => { this.discover.clearFilters(); } })
              }
            }
            .width('100%')

            this.expansionControls()
            this.quickFilters()
            if (this.filtersOpen) {
              this.filterPanel()
            }

            this.resultGrid()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          HintRow({
            glyph: 'sparkle',
            text: '加载更多只滚动当前网页，可随时停止；新图片不会自动选中或下载。'
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: ScreenMetrics.height() })
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          top: Space.s12,
          bottom: ScreenMetrics.bottomInset(SCREEN_INSETS.safeBottom,
            (this.discover.selectedTotal > 0 ? 68 : 0) + (this.device.gripChipVisible() ? 40 : 0))
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onDidScroll((): void => {
        this.discover.markScrolled();
      })
      }
      .titleBar({ enableComponentSafeArea: true, content: {
        stackBuilder: (): void => { this.addressTitleBar(); }
      } })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
      .padding({ top: SCREEN_INSETS.safeTop })
      .visibility(this.browserOpen ? Visibility.None : Visibility.Visible)

      HdsNavigation() {
        this.browserView()
      }
      .titleBar({ enableComponentSafeArea: true, content: {
        stackBuilder: (): void => { this.addressTitleBar(); }
      } })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
      .padding({ top: SCREEN_INSETS.safeTop })
      .visibility(this.browserOpen ? Visibility.Visible : Visibility.None)

    }
    .width('100%')
    .height('100%')
  }
}
