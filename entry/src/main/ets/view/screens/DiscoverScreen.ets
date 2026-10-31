import { PictureSelectionButton } from '../Widgets';
import { BatchFlowHost, BATCH_PAGE_NAME } from '../BatchPagePanel';
import { PictureItem } from '../../model/Models';
import { TransparentGlass } from '../../theme/TransparentGlass';
import { DiscoverViewModel } from '../../viewmodel/DiscoverViewModel';
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
const SORT_IDS: string[] = ['page', 'name', 'size'];
const SORT_LABELS: string[] = ['页面顺序', '名称', '尺寸'];
const SORT_OPTIONS: SelectOption[] = SORT_LABELS.map((label: string): SelectOption => ({ value: label }));
const NAME_IDS: string[] = ['original', 'numbered'];
const NAME_LABELS: string[] = ['原文件名', '网页标题＋序号'];
const NAME_OPTIONS: SelectOption[] = NAME_LABELS.map((label: string): SelectOption => ({ value: label }));

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
  /** 批量页的导航栈放在入口这一层：push 发生在点击回调里，走 HDS 默认转场动画。 */
  @Local private batchPages: NavPathStack = new NavPathStack();

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
        glyphSize: 20, diameter: 36, plain: true, tone: TransparentGlass.foreground(this.glassEnabled()),
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
        tone: TransparentGlass.foreground(this.glassEnabled()),
        accessibilityLabel: '返回浏览扫描', onAction: this.onOpenBrowser }).rotate({ angle: 180 })
      Text('查看图片').fontSize(Font.body).fontWeight(FontWeight.Bold)
        .fontColor(TransparentGlass.foreground(this.glassEnabled()))
    }.width('100%').padding({ left: Layout.pagePad, right: Layout.pagePad })
  }

  @Builder
  private browserToolbar() {
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
      IconButton({ glyph: 'scan', glyphSize: 18, plain: true,
        accessibilityLabel: '重新扫描图片',
        onAction: (): void => { this.discover.scan(this.settings.pictureQuality); }
      })
      IconButton({ glyph: 'bookmark', glyphSize: 18, plain: true,
        accessibilityLabel: '收藏与历史',
        onAction: (): void => { this.discover.browserPanel = 'history'; }
      })
      IconButton({ glyph: 'list', glyphSize: 18, plain: true,
        accessibilityLabel: '批量链接',
        onAction: (): void => {
          if (this.batchPages.size() === 0) { this.batchPages.pushPath({ name: BATCH_PAGE_NAME }); }
          this.discover.setBatchPanel(true);
        }
      }).id('batch-link-entry')
    }
    .width('100%')
  }

  private glassEnabled(): boolean {
    return this.settings.lightEffect && this.settings.materialType !== 'none';
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
      this.browserToolbar()
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
                  downloadState: this.discover.downloadState(cell),
                  onOpen: (uid: string): void => { this.onOpenPreview(uid); },
                  onDimensions: (url: string, width: number, height: number): void => {
                    this.discover.recordDimensions(cell.uid, url, width, height);
                  }
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
        Text('排序').fontSize(Font.aux).fontColor(Palette.fontSecondary).layoutWeight(1)
        SettingSelect({ options: SORT_OPTIONS, selectedIndex: SORT_IDS.indexOf(this.discover.sortOrder),
          label: SORT_LABELS[SORT_IDS.indexOf(this.discover.sortOrder)],
          onPick: (index: number): void => { this.discover.sortOrder = SORT_IDS[index]; } })
      }.width('100%')
      PillButton({ label: this.discover.onlyNew ? '只看未下载 ✓' : '只看未下载', small: true,
        variant: this.discover.onlyNew ? 'primary' : 'ghost',
        onAction: (): void => { this.discover.onlyNew = !this.discover.onlyNew; } })
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
      Navigation() {
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
            TextInput({ placeholder: '搜索文件名、图片描述或链接', text: this.discover.filterText })
              .fontSize(Font.aux).fontColor(Palette.fontPrimary)
              .backgroundColor(Palette.cardSunken).borderRadius(Radius.r4).width('100%')
              .onChange((value: string): void => { this.discover.filterText = value; })
            if (this.discover.selectedTotal > 0) {
              Row({ space: Space.s8 }) {
                Text('文件命名').fontSize(Font.aux).fontColor(Palette.fontSecondary).layoutWeight(1)
                SettingSelect({ options: NAME_OPTIONS, selectedIndex: NAME_IDS.indexOf(this.discover.nameMode),
                  label: NAME_LABELS[NAME_IDS.indexOf(this.discover.nameMode)],
                  onPick: (index: number): void => { this.discover.nameMode = NAME_IDS[index]; } })
              }.width('100%')
              if (this.discover.eligibleSelectedCount() > 0) {
                Text('预计文件名：' + this.discover.namePreview().slice(0, 3).join('、')
                  + (this.discover.eligibleSelectedCount() > 3 ? '…' : ''))
                  .fontSize(Font.caption).fontColor(Palette.fontTertiary).maxLines(2).width('100%')
              }
            }
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
      .title(this.resultsTitleBar(), {
        backgroundColor: TransparentGlass.background(this.glassEnabled()),
        systemMaterial: TransparentGlass.material(this.glassEnabled())
      })
      .titleMode(NavigationTitleMode.Mini)
      .hideBackButton(true)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
      .padding({ top: SCREEN_INSETS.safeTop })
      .visibility(this.browserOpen ? Visibility.None : Visibility.Visible)

      Navigation() {
        this.browserView()
      }
      .title(this.addressTitleBar(), {
        backgroundColor: TransparentGlass.background(this.glassEnabled()),
        systemMaterial: TransparentGlass.material(this.glassEnabled())
      })
      .titleMode(NavigationTitleMode.Mini)
      .hideBackButton(true)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
      .padding({ top: SCREEN_INSETS.safeTop })
      .visibility(this.browserOpen ? Visibility.Visible : Visibility.None)

      BatchFlowHost({ discover: this.discover, pages: this.batchPages })

    }
    .width('100%')
    .height('100%')
  }
}
