/*
 * Index.ets — the starter screen.
 *
 * It is a port of the design-time reference `designs/harmonyos-mobile/ui_kits/card`
 * (the `mobile-card` layout: floating title bar -> search -> stacked cards -> pill
 * tab bar). Two rules make it a template worth copying:
 *
 *   1. NO colour literal and NO layout number appears in this file. Every value is
 *      `Palette.*` or `Metrics.*`, both imported from @yostar/harmony-tokens. That is
 *      what stops this screen from drifting away from the design system.
 *   2. Icons come from the system HMSymbol set (`sys.symbol.*`). Nothing is
 *      hand-drawn — see designs/harmonyos-mobile/compliance.md.
 *
 * Safe areas: the design canvas reserves 36vp at the top and 28vp at the bottom for
 * the system bars. This template uses the design system's spec values so it renders
 * identically to the mockup. A production app should read the LIVE insets from the
 * window instead — `ImageDownloader/entry/src/main/ets/entryability/EntryAbility.ets`
 * shows how (`windowStage.getMainWindowSync().getWindowAvoidArea(...)`).
 * See designs/harmonyos-mobile/guidelines/arkui-mapping.md.
 */
import { Palette, Metrics } from '@yostar/harmony-tokens';

interface TabItem {
  icon: Resource;
  label: string;
}

interface FeedCard {
  title: string;
  meta: string;
  tint: ResourceColor;
}

interface DownloadRow {
  name: string;
  meta: string;
  verdict: string;
  badge: ResourceColor;
}

const TABS: TabItem[] = [
  { icon: $r('sys.symbol.house'), label: '首页' },
  { icon: $r('sys.symbol.magnifyingglass'), label: '发现' },
  { icon: $r('sys.symbol.heart'), label: '收藏' },
  { icon: $r('sys.symbol.person'), label: '我的' }
];

const FEED: FeedCard[] = [
  { title: '旅拍志 · 京都的秋', meta: '12 张 · 14:32', tint: Palette.brand },
  { title: '山野纪实 · 川西', meta: '8 张 · 昨天', tint: Palette.backgroundEmphasize }
];

const DOWNLOADS: DownloadRow[] = [
  { name: 'kyoto-01.jpg', meta: '1.8 MB · 今天 14:26', verdict: '已完成', badge: Palette.brand },
  { name: '清水寺素材包.zip', meta: '24 张 · 38.4 MB', verdict: '已完成', badge: Palette.confirm },
  { name: 'poster-raw.tiff', meta: '服务器返回的不是图片', verdict: '失败', badge: Palette.warning }
];

@Entry
@Component
struct Index {
  @State activeTab: number = 0;

  /** Section header: a title on the left, an optional action on the right. */
  @Builder
  SectionHeader(title: string, action: string) {
    Row() {
      Text(title)
        .fontSize(Metrics.fontSizeSubtitleM)
        .fontWeight(FontWeight.Bold)
        .fontColor(Palette.fontPrimary)
      Blank()
      if (action.length > 0) {
        Text(action)
          .fontSize(Metrics.fontSizeCaptionL)
          .fontColor(Palette.fontEmphasize)
      }
    }
    .width('100%')
    .padding({ left: Metrics.paddingLevel2, right: Metrics.paddingLevel2 })
  }

  /** The search pill. `backdropBlur` is the material API this project already uses. */
  @Builder
  SearchField() {
    Row({ space: Metrics.paddingLevel4 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(Metrics.fontSizeSubtitleM)
        .fontColor([Palette.fontTertiary])
      Text('搜索网页或图片')
        .fontSize(Metrics.fontSizeBodyM)
        .fontColor(Palette.fontTertiary)
    }
    .width('100%')
    .height(Metrics.controlHeight40)
    .padding({ left: Metrics.paddingLevel8, right: Metrics.paddingLevel8 })
    .backgroundColor(Palette.compBackgroundSecondary)
    .borderRadius(Metrics.cornerRadiusLevel12)
  }

  /** A feed card: tinted thumbnail, then title and meta. */
  @Builder
  FeedCardView(card: FeedCard) {
    Column() {
      Column()
        .width('100%')
        .height(96)
        .backgroundColor(card.tint)
      Column({ space: Metrics.paddingLevel1 }) {
        Text(card.title)
          .fontSize(Metrics.fontSizeCaptionL)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.fontPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(card.meta)
          .fontSize(Metrics.fontSizeCaptionS)
          .fontColor(Palette.fontTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({
        left: Metrics.paddingLevel6,
        right: Metrics.paddingLevel6,
        top: Metrics.paddingLevel6,
        bottom: Metrics.paddingLevel6
      })
    }
    .backgroundColor(Palette.compBackgroundPrimary)
    .borderRadius(Metrics.cornerRadiusLevel16)
    .clip(true)
  }

  /** A list row: app icon, two text lines, a verdict and a chevron. */
  @Builder
  DownloadRowView(row: DownloadRow, last: boolean) {
    Column() {
      Row({ space: Metrics.paddingLevel6 }) {
        Column()
          .width(Metrics.iconSize24)
          .height(Metrics.iconSize24)
          .backgroundColor(row.badge)
          .borderRadius(Metrics.cornerRadiusLevel8)
        Column({ space: Metrics.paddingLevel1 }) {
          Text(row.name)
            .fontSize(Metrics.fontSizeBodyM)
            .fontColor(Palette.fontPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(row.meta)
            .fontSize(Metrics.fontSizeCaptionS)
            .fontColor(Palette.fontTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(row.verdict)
          .fontSize(Metrics.fontSizeCaptionL)
          .fontColor(Palette.fontSecondary)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(Metrics.iconSize20)
          .fontColor([Palette.fontTertiary])
      }
      .width('100%')
      .padding({ top: Metrics.paddingLevel8, bottom: Metrics.paddingLevel8 })
      if (!last) {
        Divider().color(Palette.dividerColor)
      }
    }
    .width('100%')
  }

  /** The floating pill tab bar. Its width is locked by the tab count in the design. */
  @Builder
  TabBar() {
    Row() {
      ForEach(TABS, (item: TabItem, index: number) => {
        Column({ space: Metrics.paddingLevel1 }) {
          SymbolGlyph(item.icon)
            .fontSize(Metrics.iconSize24)
            .fontColor([this.activeTab === index ? Palette.fontEmphasize : Palette.fontSecondary])
          Text(item.label)
            .fontSize(Metrics.fontSizeCaptionS)
            .fontColor(this.activeTab === index ? Palette.fontEmphasize : Palette.fontSecondary)
        }
        .layoutWeight(1)
        .onClick(() => {
          this.activeTab = index;
        })
      }, (item: TabItem) => item.label)
    }
    .width('100%')
    .height(Metrics.tabbarH)
    .padding({ left: Metrics.paddingLevel8, right: Metrics.paddingLevel8 })
    .backgroundColor(Palette.compBackgroundPrimary)
    .backdropBlur(30)
    .borderRadius(Metrics.cornerRadiusLevel18)
    .shadow({ radius: 48, color: Palette.dividerColor, offsetY: 4 })
    /* The floating inset lives here, not at the call site: a @Builder call
       returns void, so `.margin()` cannot be chained onto `this.TabBar()`. */
    .margin({
      left: Metrics.pagePaddingMobile,
      right: Metrics.pagePaddingMobile,
      bottom: Metrics.tabbarIndicator
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        /* Title bar region: the design's safe-top area plus the title row. */
        Row() {
          Text('首页')
            .fontSize(Metrics.fontSizeTitleL)
            .fontWeight(FontWeight.Bold)
            .fontColor(Palette.fontPrimary)
          Blank()
          SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
            .fontSize(Metrics.iconSize24)
            .fontColor([Palette.fontPrimary])
        }
        .width('100%')
        .padding({
          left: Metrics.pagePaddingMobile,
          right: Metrics.pagePaddingMobile,
          top: Metrics.pagePaddingMobileTop,
          bottom: Metrics.paddingLevel4
        })

        Scroll() {
          Column({ space: Metrics.sectionGapMobile }) {
            this.SearchField()
            this.SectionHeader('今日推荐', '全部')
            Row({ space: Metrics.cardGapMobile }) {
              ForEach(FEED, (card: FeedCard) => {
                Column() {
                  this.FeedCardView(card)
                }
                .layoutWeight(1)
              }, (card: FeedCard) => card.title)
            }
            .width('100%')

            this.SectionHeader('最近下载', '更多')
            Column() {
              ForEach(DOWNLOADS, (row: DownloadRow, index: number) => {
                this.DownloadRowView(row, index === DOWNLOADS.length - 1)
              }, (row: DownloadRow) => row.name)
            }
            .width('100%')
            .padding({ left: Metrics.paddingLevel8, right: Metrics.paddingLevel8 })
            .backgroundColor(Palette.compBackgroundPrimary)
            .borderRadius(Metrics.cornerRadiusLevel16)
          }
          .width('100%')
          .padding({
            left: Metrics.pagePaddingMobile,
            right: Metrics.pagePaddingMobile,
            /* clear the floating pill: its height, its top gap and the Home Indicator band */
            bottom: Metrics.tabbarH + Metrics.tabbarTopPad + Metrics.tabbarIndicator
          })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Palette.backgroundSecondary)

      /* The one floating layer. Its inset is applied inside the builder. */
      this.TabBar()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
