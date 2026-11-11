import { PictureSelectionButton } from '../Widgets';
import { PictureItem } from '../../model/Models';
import { WeiboLivePhotos } from '../../service/WeiboLivePhotos';
import { DiscoverViewModel } from '../../viewmodel/DiscoverViewModel';
import { DeviceViewModel } from '../../viewmodel/DeviceViewModel';
import { SettingsViewModel } from '../../viewmodel/SettingsViewModel';
import { chunkRows, fillerCells } from '../../util/GridMath';
import { Font, Layout, Palette, Radius, Space } from '../../theme/Tokens';
import { ScreenMetrics } from '../../theme/Metrics';
import { Glyph } from '../Icons';
import { AppSearch } from '../AppSearch';
import { SelectTile } from '../Cards';
import { IconButton, PillButton, SectionHead, SettingSelect } from '../Widgets';
import { AppSegmentButton } from '../AppSegmentButton';
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
  @Event onShowResults: () => void = (): void => {};
  @Event onOpenPreview: (uid: string) => void = (uid: string): void => {};
  @Event onOpenQuickPreview: (uid: string) => void = (uid: string): void => {};
  @Local private filtersOpen: boolean = false;
  @Local private resultsSearchActive: boolean = false;
  @Local private quickImageUrl: string = '';
  private quickMenuResult: WebContextMenuResult | undefined = undefined;

  @Monitor('browserOpen')
  private onBrowserOpenChanged(monitor: IMonitor): void {
    this.resultsSearchActive = false;
    if (!this.browserOpen) {
      this.getUIContext().getFocusController().clearFocus();
    }
  }

  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。

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
          this.discover.setBatchPanel(true);
        }
      }).id('batch-link-entry')
    }
    .width('100%')
  }

  private closeQuickMenu(): void {
    if (this.quickMenuResult !== undefined) { this.quickMenuResult.closeContextMenu(); }
    this.quickMenuResult = undefined;
    this.quickImageUrl = '';
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
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
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
          .onPageBegin((): void => { this.closeQuickMenu(); this.discover.navigationStarted(); })
          .onContextMenuShow((event: OnContextMenuShowEvent): boolean => {
            if (!event.param.existsImageContents()) { return false; }
            const url: string = event.param.getSourceUrl() ?? '';
            if (!url.startsWith('https://') && !url.startsWith('http://')) { return false; }
            this.closeQuickMenu();
            this.quickImageUrl = url;
            this.quickMenuResult = event.result;
            return true;
          })
          .onPageEnd((): void => {
            this.discover.browserPageEnded(this.settings.pictureQuality);
          })
          .onErrorReceive((event: OnErrorReceiveEvent): void => {
            if (event.request.isMainFrame()) {
              this.discover.navigationFailed(event.error.getErrorInfo());
            }
          })
        if (this.quickImageUrl.length > 0) {
          Column({ space: Space.s8 }) {
            Text('当前网页图片').fontSize(Font.caption).fontColor(Palette.fontSecondary)
            Row({ space: Space.s8 }) {
              PillButton({ label: '预览图片', variant: 'tonal', small: true,
                onAction: (): void => {
                  const url: string = this.quickImageUrl;
                  this.closeQuickMenu();
                  const item: PictureItem = this.discover.prepareQuickImage(url);
                  this.onOpenQuickPreview(item.uid);
                } })
              PillButton({ label: '下载这张', variant: 'primary', small: true,
                onAction: (): void => {
                  const url: string = this.quickImageUrl;
                  this.closeQuickMenu();
                  this.discover.downloadQuickImage(url);
                } })
              IconButton({ glyph: 'close', diameter: 36, plain: true,
                accessibilityLabel: '关闭图片快捷菜单',
                onAction: (): void => { this.closeQuickMenu(); } })
            }.width('100%')
          }
          .width('100%')
          .padding(Space.s12)
          .backgroundColor(Palette.card)
          .borderRadius(Radius.r8)
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

      PillButton({
        label: this.discover.scanning ? '正在扫描…' : '查看图片 · ' + this.discover.pictures.length.toString() + ' 张',
        icon: 'image', variant: 'primary',
        onAction: this.onShowResults
      })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: ScreenMetrics.sideInset(SCREEN_INSETS.safeLeft),
      right: ScreenMetrics.sideInset(SCREEN_INSETS.safeRight),
      top: ScreenMetrics.topInsetForDiscover(SCREEN_INSETS.safeTop),
      bottom: SCREEN_INSETS.contentBottomInsetVp + Space.s12
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
                  thumbnailSource: this.discover.gridThumbnailSource(cell),
                  sourcePage: WeiboLivePhotos.isWeibo(this.discover.pageUrl) ? this.discover.pageUrl : '',
                  index: rowIndex * 3 + colIndex,
                  downloadState: this.discover.downloadState(cell),
                  onOpen: (uid: string): void => { this.onOpenPreview(uid); },
                  onDimensions: (url: string, width: number, height: number): void => {
                    this.discover.recordDimensions(cell.uid, url, width, height);
                  },
                  onThumbnail: (uid: string, url: string, uri: string): void => {
                    this.discover.rememberThumbnail(uid, url, uri);
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
    AppSegmentButton({
      labels: QUICK_LABELS,
      selectedIndex: Math.max(0, QUICK_IDS.indexOf(this.discover.quickFilter)),
      config: { dense: true },
      onSelectedIndexChange: (index: number): void => {
        this.discover.quickFilter = QUICK_IDS[index];
      }
    })
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
        AppSearch({ placeholder: '筛选来源 URL', text: this.discover.filterUrl,
          useImmersiveMaterial: true,
          onChange: (value: string): void => { this.discover.filterUrl = value; } })
          .layoutWeight(1)
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
            if (this.resultsSearchActive) {
              AppSearch({ placeholder: '搜索文件名、图片描述或链接', text: this.discover.filterText,
                inputId: 'discover-results-search', focusOnAppear: true,
                useImmersiveMaterial: true,
                onChange: (value: string): void => { this.discover.filterText = value; } })
            } else {
              Row({ space: Space.s8 }) {
                Glyph({ glyph: 'search', glyphSize: 16, glyphTone: Palette.fontTertiary })
                Text(this.discover.filterText || '搜索文件名、图片描述或链接')
                  .fontSize(Font.aux)
                  .fontColor(this.discover.filterText ? Palette.fontPrimary : Palette.fontSecondary)
              }
              .width('100%')
              .height($r('app.float.form_field_height'))
              .padding({ left: Space.s12, right: Space.s12 })
              .borderRadius($r('app.float.radius_chip'))
              .backgroundColor($r('app.color.hm_value_chip_background'))
              .onClick((): void => {
                this.resultsSearchActive = true;
              })
            }
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
          left: ScreenMetrics.sideInset(SCREEN_INSETS.safeLeft),
          right: ScreenMetrics.sideInset(SCREEN_INSETS.safeRight),
          top: ScreenMetrics.topInset(SCREEN_INSETS.safeTop, true),
          bottom: SCREEN_INSETS.safeBottom + Space.s12
            + (this.discover.selectedTotal > 0 ? 68 : 0) + (this.device.gripChipVisible() ? 40 : 0)
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .focusable(true)
      .defaultFocus(true)
      .onDidScroll((): void => {
        this.discover.markScrolled();
      })
      .visibility(this.browserOpen ? Visibility.None : Visibility.Visible)

      Column() {
        this.browserView()
      }
      .width('100%')
      .height('100%')
      .visibility(this.browserOpen ? Visibility.Visible : Visibility.None)

    }
    .width('100%')
    .height('100%')
  }
}
