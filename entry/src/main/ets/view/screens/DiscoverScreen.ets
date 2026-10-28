import { PictureSelectionButton } from '../Widgets';
import { PictureItem } from '../../model/Models';
import { BlurStrategy, hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectOptions, ScrollEffectType, SystemMaterialParams, TitleBarStyleOptions } from '@kit.UIDesignKit';
import { MaterialSupport } from '../../service/MaterialSupport';
import { DiscoverViewModel } from '../../viewmodel/DiscoverViewModel';
import { BatchLinkRow, BatchLinkStatus } from '../../service/BatchLinks';
import { DeviceViewModel } from '../../viewmodel/DeviceViewModel';
import { SettingsViewModel } from '../../viewmodel/SettingsViewModel';
import { chunkRows, fillerCells } from '../../util/GridMath';
import { Font, Layout, Palette, Radius, Shadow, Space } from '../../theme/Tokens';
import { ScreenMetrics } from '../../theme/Metrics';
import { Glyph } from '../Icons';
import { SelectTile } from '../Cards';
import { IconButton, PillButton, SectionHead, SettingSelect } from '../Widgets';
import { SCREEN_INSETS } from '../../theme/Metrics';

const FILTER_FORMATS: string[] = ['', 'jpg', 'png', 'gif', 'webp', 'other'];
const FILTER_LABELS: string[] = ['全部格式', 'JPEG', 'PNG', 'GIF', 'WebP', '其他'];
const FILTER_OPTIONS: SelectOption[] = FILTER_LABELS.map((label: string): SelectOption => ({ value: label }));
const QUICK_IDS: string[] = ['', 'large', 'landscape', 'portrait'];
const QUICK_LABELS: string[] = ['全部', '大图', '横图', '竖图'];

/**
 * 「发现」页：浏览扫描为首页；结果页按需进入，两者都持续挂载以保留网页与滚动位置。
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
  @Event onOpenPreview: (uid: string) => void = (uid: string): void => {};
  @Local private filtersOpen: boolean = false;

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
      if (this.discover.address.length > 0) {
        IconButton({ glyph: 'xCircle', glyphSize: 18, diameter: 32, plain: true,
          tone: Palette.fontTertiary, accessibilityLabel: '清空输入链接',
          onAction: (): void => { this.discover.address = ''; } })
      }
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
  private resultsTitleBar() {
    Row({ space: Space.s8 }) {
      IconButton({ glyph: 'chevronRight', glyphSize: 18, diameter: 36, plain: true,
        accessibilityLabel: '返回浏览扫描', onAction: this.onOpenBrowser }).rotate({ angle: 180 })
      Text('查看图片').fontSize(Font.body).fontWeight(FontWeight.Bold).fontColor(Palette.fontPrimary)
    }.width('100%').padding({ left: Layout.pagePad, right: Layout.pagePad })
  }

  @Builder
  private batchEntry() {
    Column({ space: Space.s8 }) {
      Row({ space: Space.s8 }) {
        PillButton({ label: this.discover.batchOpen ? '收起批量链接' : '批量链接',
          variant: 'ghost', small: true,
          onAction: (): void => { this.discover.setBatchPanel(!this.discover.batchOpen); } })
        if (this.discover.batchOpen) {
          PillButton({ label: '粘贴多条', icon: 'paste', variant: 'tonal', small: true,
            onAction: (): void => { this.discover.pasteBatch(); } })
        }
      }.width('100%')
      if (this.discover.batchOpen) {
        if (this.discover.batchStage === 'review') {
          this.batchReviewPanel()
        } else {
          this.batchEditor()
        }
      }
    }
    .width('100%')
  }

  @Builder
  private batchEditor() {
    Column({ space: Space.s8 }) {
      TextArea({ placeholder: '每行一条图片直链', text: this.discover.batchText })
        .fontSize(Font.body).fontColor(Palette.fontPrimary)
        .backgroundColor(Palette.cardSunken).borderRadius(Radius.r4)
        .height(96).width('100%')
        .onChange((value: string): void => { this.discover.setBatchText(value); })
      Text(this.discover.batchSummary)
        .fontSize(Font.caption).fontColor(Palette.fontSecondary)
      if (this.discover.batchReport.rows.length > 0) {
        List({ space: Space.s4 }) {
          ForEach(this.discover.batchReport.rows, (row: BatchLinkRow) => {
            ListItem() {
              this.batchRow(row)
            }
          }, (row: BatchLinkRow): string => row.line.toString() + '|' + row.status + '|'
            + row.reason + '|' + row.url)
        }
        .width('100%')
        .constraintSize({ maxHeight: 168 })
        .scrollBar(BarState.Auto)
      }
      if (this.discover.batchProbeLabel.length > 0) {
        Text(this.discover.batchProbeLabel)
          .fontSize(Font.caption)
          .fontColor(this.discover.batchProbing ? Palette.brand : Palette.fontTertiary)
      }
      Row({ space: Space.s8 }) {
        if (this.discover.batchReport.pending > 0) {
          PillButton({ label: '检查待确认 · ' + this.discover.batchReport.pending.toString(),
            variant: 'ghost', small: true, active: !this.discover.batchProbing,
            onAction: (): void => { this.discover.startBatchCheck(); } })
        }
        PillButton({ label: this.discover.batchProbing ? '正在检查…' : '确认导入',
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
  }

  @Builder
  private batchReview() {
    Column({ space: Space.s8 }) {
      Text(this.discover.batchReviewSummary)
        .fontSize(Font.caption)
        .fontColor(Palette.fontPrimary)
        .width('100%')
      if (this.discover.batchReviewExcluded.length > 0) {
        Text(this.discover.batchReviewExcluded)
          .fontSize(Font.caption)
          .fontColor(Palette.fontTertiary)
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private batchReviewPanel() {
    Column({ space: Space.s10 }) {
      this.batchReview()
      List({ space: Space.s4 }) {
        ForEach(this.discover.batchReviewRows, (row: BatchLinkRow) => {
          ListItem() {
            this.batchRow(row)
          }
        }, (row: BatchLinkRow): string => row.line.toString() + '|' + row.status + '|'
          + row.reason + '|' + row.url)
      }
      .width('100%')
      .constraintSize({ maxHeight: 180 })
      .scrollBar(BarState.Auto)
      Row({ space: Space.s8 }) {
        PillButton({ label: '返回修改', variant: 'ghost', small: true,
          onAction: (): void => { this.discover.cancelBatchReview(); } })
        PillButton({ label: '加入任务 · ' + this.discover.batchReview.urls.length.toString() + ' 条',
          variant: 'primary', small: true,
          active: this.discover.batchReview.urls.length > 0,
          onAction: (): void => { this.discover.confirmBatchReview(); } })
      }
      .width('100%')
    }
    .width('100%')
    .padding(Space.s10)
    .backgroundColor(Palette.cardSunken)
    .borderRadius(Radius.r8)
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
    if (status === BatchLinkStatus.VALID) { return '有效'; }
    if (status === BatchLinkStatus.PENDING) { return '待确认'; }
    if (status === BatchLinkStatus.DUPLICATE) { return '重复'; }
    return '无效';
  }

  private batchStatusColor(status: string): ResourceColor {
    if (status === BatchLinkStatus.VALID) { return Palette.confirm; }
    if (status === BatchLinkStatus.PENDING) { return Palette.warning; }
    if (status === BatchLinkStatus.DUPLICATE) { return Palette.fontTertiary; }
    return Palette.alert;
  }

  /**
   * 首页标题栏的「沉浸光感」样式：标题栏材质跟着下方滚动的内容透出光感，并随滚动渐进模糊。
   *
   * 门控与图片选择材质一致 —— 设备不支持、关掉「沉浸光感」开关，
   * 或「材质类型」选了「无材质效果」时返回 undefined，标题栏回退成系统默认（不强加模糊）。
   * 材质类型与等级都读设置里用户已选的那一档，和图片详情用的是同一组开关。
   */
  private titleBarStyle(): TitleBarStyleOptions | undefined {
    if (!MaterialSupport.immersiveSupported()) {
      return undefined;
    }
    if (!this.settings.lightEffect || this.settings.materialType === 'none') {
      return undefined;
    }
    const scrollEffect: ScrollEffectOptions = {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
    };
    const material: SystemMaterialParams = {
      materialType: this.materialTypeEnum(),
      materialLevel: this.materialLevelEnum()
    };
    const style: TitleBarStyleOptions = {
      blurStrategy: BlurStrategy.ADAPTIVE,
      scrollEffectOpts: scrollEffect,
      systemMaterialEffect: material
    };
    return style;
  }

  /** 设置里的材质类型 id 翻成 hdsMaterial 枚举；'adaptive' 文档上即按沉浸式材质生效。 */
  private materialTypeEnum(): hdsMaterial.MaterialType {
    if (this.settings.materialType === 'immersive') {
      return hdsMaterial.MaterialType.IMMERSIVE;
    }
    return hdsMaterial.MaterialType.ADAPTIVE;
  }

  /** 设置里的材质等级 id 翻成 hdsMaterial 枚举；未知值回退为跟随系统。 */
  private materialLevelEnum(): hdsMaterial.MaterialLevel {
    const id: string = this.settings.materialLevel;
    if (id === 'exquisite') {
      return hdsMaterial.MaterialLevel.EXQUISITE;
    }
    if (id === 'gentle') {
      return hdsMaterial.MaterialLevel.GENTLE;
    }
    if (id === 'smooth') {
      return hdsMaterial.MaterialLevel.SMOOTH;
    }
    return hdsMaterial.MaterialLevel.ADAPTIVE;
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
        PillButton({ label: '收藏/历史', variant: 'ghost', small: true,
          onAction: (): void => { this.discover.browserPanel = 'history'; }
        })
      }
      .width('100%')

      this.batchEntry()
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
      bottom: ScreenMetrics.tabBarSpace(SCREEN_INSETS.safeBottom) + Space.s12
    })
    .backgroundColor(Palette.bg)
  }

  /** 扫描结果的网格；只有筛选排空现有图片时才提示调整条件。 */
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
                  immersiveEnabled: this.settings.lightEffect && this.settings.materialType !== 'none',
                  onOpen: (uid: string): void => { this.onOpenPreview(uid); }
                })
                PictureSelectionButton({ selected: cell.selected, diameter: 36,
                  onAction: (): void => { this.discover.togglePicture(cell.uid); } })
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
    } else if (this.discover.pictures.length > 0) {
      Text('没有符合筛选条件的图片，请调整条件或清除筛选。')
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

        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: ScreenMetrics.height() })
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          top: Space.s12,
          bottom: SCREEN_INSETS.safeBottom + Space.s12
            + (this.discover.selectedTotal > 0 ? 68 : 0) + (this.device.gripChipVisible() ? 40 : 0)
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
      .titleBar({ enableComponentSafeArea: true, style: this.titleBarStyle(), content: {
        stackBuilder: (): void => { this.resultsTitleBar(); }
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
      .titleBar({ enableComponentSafeArea: true, style: this.titleBarStyle(), content: {
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
