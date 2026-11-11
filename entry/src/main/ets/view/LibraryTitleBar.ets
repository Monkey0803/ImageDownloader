/*
 * LibraryTitleBar.ets — 图库页挂在 HDS 标题栏里的控件层（状态管理 V2）。
 *
 * 原先「图片 / 压缩包」分段、布局与筛选两个图标、整行搜索是 `LibraryScreen` 里
 * WaterFlow 的第一行，跟着照片一起滚走。现在由 `Index.rootTitleBar()` 通过
 * `TitleBarContentOptions.bottomBuilder` 挂到原生标题栏下方：分段与搜索常驻可见，
 * 内容区只剩照片本身。
 *
 * 两行的尺寸是定值（见 `Layout.tbLibraryHeader`）：40 的分段行 + 12 间距 + 48 的搜索框，
 * 标题栏的高度参数与页面的 `contentStartOffset` 都读同一个常量，改动时只改那一处。
 *
 * 材质：组件级沉浸材质「只在 Navigation 标题栏 / 底部 TabBar 生效」（AGENT.md 坑 10）。
 * 这组控件搬进标题栏之后，`AppSearch` 的 useImmersiveMaterial 与分段的 config.material
 * 才真正渲染出来 —— 之前在内容区是静默回落成不透明胶囊的。
 */
import { LibraryViewModel } from '../viewmodel/LibraryViewModel';
import { SettingsViewModel } from '../viewmodel/SettingsViewModel';
import { Font, Palette, Radius, Space } from '../theme/Tokens';
import { SCREEN_INSETS, ScreenMetrics } from '../theme/Metrics';
import { IconButton, LIBRARY_LABELS } from './Widgets';
import { AppSearch } from './AppSearch';
import { AppSegmentButton, segmentCapsuleWidth } from './AppSegmentButton';
import { LIBRARY_IMAGES, LIBRARY_ZIPS } from '../model/Navigation';

@ComponentV2
export struct LibraryTitleBar {
  @Require @Param library: LibraryViewModel;
  @Require @Param settings: SettingsViewModel;

  @Builder
  private searchPill() {
    AppSearch({
      placeholder: this.library.isZips() ? '搜索压缩包' : '搜索图片',
      text: this.library.query,
      useImmersiveMaterial: true,
      onChange: (value: string): void => { this.library.setQuery(value); }
    })
  }

  /** 布局开关：图片段切网格形态，压缩包段这一位让给「导入」。 */
  @Builder
  private leadingAction() {
    if (this.library.isZips()) {
      IconButton({ glyph: 'plus', diameter: 40, accessibilityLabel: '导入压缩包',
        onAction: (): void => { this.library.importZip(); } })
    } else {
      IconButton({ glyph: this.library.squareTiles() ? 'grid' : 'image', diameter: 40,
        accessibilityLabel: this.library.squareTiles() ? '切换为瀑布流' : '切换为三列方形',
        onAction: (): void => { this.library.toggleGridStyle(); } })
    }
  }

  @Builder
  private filterAction() {
    Stack({ alignContent: Alignment.TopEnd }) {
      IconButton({ glyph: 'sliders', diameter: 40,
        tone: this.library.filterCount() > 0 ? Palette.brand : Palette.fontPrimary,
        accessibilityLabel: this.library.filterCount() > 0
          ? '筛选，已启用 ' + this.library.filterCount().toString() + ' 项' : '筛选',
        onAction: (): void => { this.library.sheet = 'filter'; } })
      if (this.library.filterCount() > 0) {
        Text(this.library.filterCount() > 9 ? '9+' : this.library.filterCount().toString())
          .fontSize(10).fontColor(Palette.fontOnPrimary).textAlign(TextAlign.Center)
          .width(16).height(16).borderRadius(Radius.full).backgroundColor(Palette.brand)
          .hitTestBehavior(HitTestMode.None)
      }
    }
  }

  build() {
    Column({ space: Space.s12 }) {
      // 图片 / 压缩包：共享的 AppSegmentButton（内部是 CapsuleSegmentButtonV2），
      // 背景板材质由 config.material 决定 —— 用户关了光感或选了「无材质效果」，
      // 或本机不支持沉浸式材质时，它都会退回不透明胶囊。
      Row({ space: Space.s8 }) {
        AppSegmentButton({
          labels: LIBRARY_LABELS,
          selectedIndex: this.library.segment === LIBRARY_ZIPS ? 1 : 0,
          config: {
            dense: true,
            material: this.settings.lightEffect && this.settings.materialType !== 'none',
            width: segmentCapsuleWidth(LIBRARY_LABELS, Font.caption, Space.s12)
          },
          onSelectedIndexChange: (index: number): void => {
            this.library.setSegment(index === 1 ? LIBRARY_ZIPS : LIBRARY_IMAGES);
          }
        })
        Blank()
        this.leadingAction()
        this.filterAction()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      this.searchPill()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: ScreenMetrics.sideInset(SCREEN_INSETS.safeLeft),
      right: ScreenMetrics.sideInset(SCREEN_INSETS.safeRight)
    })
  }
}
