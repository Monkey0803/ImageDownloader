import { PictureItem } from '../../model/Models';
import { DiscoverViewModel } from '../../viewmodel/DiscoverViewModel';
import { DeviceViewModel } from '../../viewmodel/DeviceViewModel';
import { SettingsViewModel } from '../../viewmodel/SettingsViewModel';
import { chunkRows, fillerCells } from '../../util/GridMath';
import { Font, Layout, Palette, Radius, Shadow, Space } from '../../theme/Tokens';
import { ScreenMetrics } from '../../theme/Metrics';
import { Glyph } from '../Icons';
import { SelectTile } from '../Cards';
import { HintRow, IconButton, PillButton, SectionHead, TitleBar } from '../Widgets';
import { SCREEN_INSETS } from '../../theme/Metrics';

/**
 * 「发现」页：地址栏 + 内嵌浏览器 + 扫描结果网格 + 选择工具条。
 *
 * 从 Index 的 `discoverScreen()` / `browserCard()` 两个 @Builder 搬过来，只把状态来源从
 * 「页面自己的字段」换成三个 ViewModel：
 * - `discover`：地址、扫描结果、选中计数、扫描中、模式；
 * - `settings`：只有一处用 —— 扫描时要读「下载图片质量」当前档位；
 * - `device`：只有一处用 —— 左手握持时把「选择要下载的图片」那一行镜像过去。
 *
 * 安全区高度由 `@StorageProp` 直接读 `AppStorage`（EntryAbility 写入），不再层层透传。
 * 四个页面始终挂载、只切 `visibility`，所以浏览器里已加载的网页和滚动位置都留得住。
 */
@ComponentV2
export struct DiscoverScreen {
  @Require @Param discover: DiscoverViewModel;
  @Require @Param settings: SettingsViewModel;
  @Require @Param device: DeviceViewModel;

  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。
  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。

  /** 浏览器卡片：伪地址条 + Web 视图 + 页面标题与扫描结果计数。 */
  @Builder
  private browserCard() {
    Column() {
      Row({ space: Space.s4 }) {
        Row({ space: Space.s4 }) {
          Circle().width(7).height(7).fill(Palette.divider)
          Circle().width(7).height(7).fill(Palette.divider)
          Circle().width(7).height(7).fill(Palette.divider)
        }
        .flexShrink(0)

        Row({ space: Space.s6 }) {
          Glyph({ glyph: 'globe', glyphSize: 12, glyphTone: Palette.fontTertiary, glyphWeight: 2 })
          Text(this.discover.pageUrl.length > 0 ? this.discover.pageUrl : '输入网址后在这里浏览网页')
            .fontSize(11.5)
            .fontColor(Palette.fontTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .height(26)
        .padding({ left: Space.s10, right: Space.s10 })
        .borderRadius(Radius.full)
        .backgroundColor(Palette.cardSunken)
        .layoutWeight(1)

        IconButton({
          glyph: 'refresh', glyphSize: 16, diameter: 30, plain: true,
          onAction: (): void => {
            this.discover.scan(this.settings.pictureQuality);
          }
        })
      }
      .width('100%')
      .height(42)
      .padding({ left: Space.s14, right: Space.s10 })

      Stack({ alignContent: Alignment.Bottom }) {
        Web({ src: 'about:blank', controller: this.discover.browserController() })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .width('100%')
          .height('100%')
          .backgroundColor(Palette.card)
          .onPageEnd((): void => {
            this.discover.scan(this.settings.pictureQuality);
          })

        if (this.discover.scanning) {
          Row({ space: Space.s6 }) {
            LoadingProgress().width(16).height(16).color(Palette.white)
            Text('正在扫描当前网页…')
              .fontSize(Font.caption)
              .fontColor(Palette.white)
          }
          .padding({ left: Space.s10, right: Space.s12, top: Space.s6, bottom: Space.s6 })
          .borderRadius(Radius.full)
          .backgroundColor('#8C000000')
          .margin({ bottom: Space.s8 })
        }
      }
      .width('100%')
      .height(200)
      .backgroundColor(Palette.cardSunken)

      Row({ space: Space.s8 }) {
        Text(this.discover.pageTitle.length > 0 ? this.discover.pageTitle : '尚未打开网页')
          .fontSize(Font.body)
          .lineHeight(Font.bodyLine)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.fontPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Row({ space: Space.s2 }) {
          Glyph({ glyph: 'image', glyphSize: 13, glyphTone: Palette.fontTertiary, glyphWeight: 2 })
          Text(this.discover.pictures.length.toString() + ' 张')
            .fontSize(Font.caption)
            .fontColor(Palette.fontTertiary)
        }
      }
      .width('100%')
      .padding({ left: Space.s12, right: Space.s12, top: Space.s10, bottom: Space.s12 })
    }
    .width('100%')
    .borderRadius(Radius.r8)
    .backgroundColor(Palette.card)
    .shadow(Shadow.card())
    .clip(true)
  }

  /** 扫描结果的网格；空态是一句引导，不是 EmptyState 卡片（这里还在同一个滚动流里）。 */
  @Builder
  private resultGrid() {
    if (this.discover.pictures.length > 0) {
      Column({ space: Space.s8 }) {
        ForEach(chunkRows<PictureItem>(this.discover.pictures, 3), (row: PictureItem[], rowIndex: number) => {
          Row({ space: Space.s8 }) {
            ForEach(row, (cell: PictureItem, colIndex: number) => {
              Column() {
                SelectTile({
                  picture: cell,
                  index: rowIndex * 3 + colIndex,
                  // 只传 uid：子组件回传的引用上直接写字段会绕过 @Observed 代理、不发通知
                  // （见 SelectTile.onToggle 的说明）。
                  onToggle: (uid: string): void => {
                    this.discover.togglePicture(uid);
                  }
                })
              }
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
      Text('还没有扫描到图片。在上面的浏览器中打开网页，加载完成后会自动扫描。')
        .fontSize(Font.aux)
        .lineHeight(Font.subtitleLine)
        .fontColor(Palette.fontTertiary)
        .textAlign(TextAlign.Start)
        .width('100%')
        .padding({ top: Space.s20, bottom: Space.s20 })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll(this.discover.scrollController()) {
        Column({ space: Space.s16 }) {
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
              .onChange((value: string): void => {
                this.discover.address = value;
              })
              .onSubmit((key: EnterKeyType): void => {
                this.discover.visit();
              })
            // 地址栏右侧是两个圆形图标按钮：粘贴（剪贴板）与前往（箭头）。
            PillButton({
              icon: 'paste', variant: 'tonal', small: true,
              onAction: (): void => {
                this.discover.pasteAddress();
              }
            })
            PillButton({
              icon: 'arrowRight', variant: 'primary', small: true,
              active: this.discover.address.trim().length > 0,
              onAction: (): void => {
                this.discover.visit();
              }
            })
          }
          .width('100%')
          .height(44)
          .padding({ left: Space.s14, right: Space.s4 })
          .borderRadius(Radius.full)
          .backgroundColor(Palette.card)
          .shadow(Shadow.card())

          this.browserCard()

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

            this.resultGrid()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          HintRow({
            glyph: 'sparkle',
            text: '扫描只读取当前页面的图片地址；滚动页面后重新扫描可以发现更多。'
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: ScreenMetrics.height() })
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          top: ScreenMetrics.topInset(SCREEN_INSETS.safeTop, true),
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

      TitleBar({
        heading: '发现',
        caption: this.discover.scanning ? '正在扫描当前网页…' : '',
        layer: Layout.tbLayerSecondary
      })
    }
    .width('100%')
    .height('100%')
  }
}
