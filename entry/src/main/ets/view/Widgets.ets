/*
 * Widgets.ets — the prototype's presentational shell components.
 *
 * Ported from designs/image-downloader-ui/ui.jsx. Each struct owns the styling
 * of one component in the design; the screens compose them and own the data.
 */

import {
  CapsuleSegmentButtonV2, ColorMetrics, LengthMetrics, SegmentButtonV2ItemOptions, SegmentButtonV2Items, uiMaterial
} from '@kit.ArkUI';
import { MaterialSupport } from '../service/MaterialSupport';
import { LIBRARY_IMAGES, LIBRARY_ZIPS, TAB_TASKS } from '../model/Navigation';
import { Font, Layout, Palette, Radius, Shadow, Space } from '../theme/Tokens';
import { Glyph } from './Icons';

/** One option of a segmented control. */
export interface SegmentOption {
  value: string;
  label: string;
}

/** One entry of the bottom tab bar. */
export interface TabItem {
  key: string;
  label: string;
  glyph: string;
}

/**
 * 底部页签，**顺序必须与 `model/Navigation.ets` 的 TAB_* 下标一一对应**。
 *
 * `active` / `onSelect` / `badge` 传的都是下标，所以这里的第 i 项就是第 i 个页签内容；
 * 页签增减时两处要一起改（`TabBar` 里的徽标判断用的是 `TAB_TASKS` 常量而不是字符串字面量，
 * 免得重排之后徽标挂到别的页签上）。
 */
export const TABS: TabItem[] = [
  { key: 'discover', label: '发现', glyph: 'scan' },
  { key: 'tasks', label: '任务', glyph: 'download' },
  { key: 'library', label: '图库', glyph: 'image' },
  { key: 'settings', label: '设置', glyph: 'sliders' }
];

/**
 * The two kinds of finished files the 图库 tab lists.
 *
 * 取值直接引用 `model/Navigation.ets` 的常量：这两个字符串同时是「状态里的分段值」和
 * 「控件的选项值」，分开写一份就会出现「点得动但筛不出来」这种不报错的错。
 */
export const LIBRARY_OPTIONS: SegmentOption[] = [
  { value: LIBRARY_IMAGES, label: '图片' },
  { value: LIBRARY_ZIPS, label: '压缩包' }
];

export const MODE_OPTIONS: SegmentOption[] = [
  { value: 'single', label: '单张' },
  { value: 'zip', label: 'ZIP' }
];

/**
 * 设置行右侧的「当前值 + 下拉」控件：收起时是一枚显示当前档位的胶囊，点开是选项菜单。
 *
 * 用 @Prop 而不是普通入参，也不是 `@Builder` 传值：ArkUI V1 不会把父组件的新值刷进没有
 * 装饰器的成员，`@Builder` 按值传参同样不刷新——而档位/类型是会变的，见 AGENT.md 的坑 3。
 */
@Component
export struct SettingSelect {
  @Prop options: SelectOption[] = [];
  @Prop selectedIndex: number = 0;
  /** 收起时显示的文字，取当前档位的界面名。 */
  @Prop label: string = '';
  /**
   * 强制这个控件重建一次的版本号，默认 0 就是「不用」。
   *
   * 原生 `Select` 被用户点选后会自己改显示的文字。如果父组件最后**没有接受**这次选择
   * （「下载位置 → 自定义目录」在选择器里被取消就是这种情况），只改状态是刷不回去的：
   * 传进来的 label 和上一次完全相同，胶囊就一直停在用户点过的那一项上
   * （模拟器实测：说明文字已经回到「应用文件 · 图片与压缩包分开存放」，胶囊却写着「自定义目录」）。
   *
   * **它必须真的出现在 `build()` 里**：ArkUI V1 是按「哪个元素读了哪个状态变量」来标记脏元素的，
   * 没人读的 `@Prop` 变化不会重跑 build —— 原来这个字段只在 `build()` 外面被声明和赋值，
   * 门面上的「重建」因此完全没发生（这一条是这次实测纠正的）。
   *
   * 下面用「奇偶两个 `if` 分支」来真正换掉节点：分支切换时 ArkUI 销毁旧 `Select`、建一个新的，
   * `value(label)` 于是在新节点上重新落回已提交的档位。两条分支共用同一个 `@Builder`，没有重复代码。
   * （试过 `.key('...' + revision)`：效果一样，但编译器会 Warn「'key' can only be used for testing
   * directories」—— 那是给测试框架定位节点用的 API，不适合放在生产路径上。）
   */
  @Prop revision: number = 0;
  onPick: (index: number) => void = () => {
  };

  @Builder
  private control() {
    Select(this.options)
      .selected(this.selectedIndex)
      .value(this.label)
      .font({ size: Font.aux, weight: FontWeight.Medium })
      .fontColor(Palette.fontPrimary)
      .selectedOptionFont({ size: Font.body, weight: FontWeight.Medium })
      .selectedOptionFontColor(Palette.brand)
      .selectedOptionBgColor(Palette.selectOnBg)
      .optionFont({ size: Font.body })
      .optionFontColor(Palette.fontPrimary)
      // 未选中项**不涂底色**，直接把菜单浮层透出来。
      //
      // 原来写的是 `Palette.card`：浅色下浮层是白的、卡片也是白的，看不出问题；深色下浮层
      // 会被弹窗的 elevation 提亮到 #2C2E30，而 card 是 #212223 —— 于是在浮层里印出一块块
      // 更深的选项块，行与行之间还夹着两条没盖住的浅线（模拟器实测）。透明才是浅色那种
      // 「一片底色、只有选中项有药丸」的观感。
      .optionBgColor(Color.Transparent)
      .menuBackgroundColor(Palette.card)
      .backgroundColor(Palette.cardSunken)
      .borderRadius(Radius.full)
      .onSelect((index: number): void => {
        this.onPick(index);
      })
  }

  build() {
    Column() {
      if (this.revision % 2 === 0) {
        this.control()
      } else {
        this.control()
      }
    }
  }
}

/**
 * Floating title bar: a big title over a translucent gradient that fades the
 * content scrolling underneath it.
 */
@Component
export struct TitleBar {
  @Prop heading: string = '';
  @Prop caption: string = '';
  /** Empty means no action button. @Prop: 图库在压缩包段要把它收起来。 */
  @Prop actionGlyph: string = '';
  /** Layout.tbLayerSecondary for screens with a subtitle, Normal without. */
  layer: number = Layout.tbLayerSecondary;
  @StorageProp('safeTop') safeTop: number = 0;
  onAction: () => void = () => {
  };

  build() {
    Column() {
      Row({ space: Space.s6 }) {
        Column({ space: 1 }) {
          Text(this.heading)
            .fontSize(Font.title)
            .lineHeight(Layout.tbRow - Space.s4)
            .fontWeight(FontWeight.Bold)
            .fontColor(Palette.fontPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.caption.length > 0) {
            Text(this.caption)
              .fontSize(Font.subtitle)
              .lineHeight(Font.subtitleLine)
              .fontColor(Palette.fontSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.actionGlyph.length > 0) {
          IconButton({ glyph: this.actionGlyph, onAction: this.onAction })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ left: Layout.pagePad, right: Layout.pagePad, top: this.safeTop + Layout.tbPadTop })
    }
    .width('100%')
    .padding({ bottom: Layout.tbFade })
    .linearGradient({
      angle: 180,
      colors: [
        [Palette.fadeSolid, 0],
        [Palette.fadeSolid, 0.5],
        [Palette.fadeStrong, 0.64],
        [Palette.fadeSoft, 0.8],
        [Palette.fadeNone, 1]
      ]
    })
    // 标题栏是浮在内容之上的装饰层：不透明会把它盖住的那一条内容变成点击黑洞
    // （图库页顶部的分段控件就整块落在里面）。Transparent 让它自己不吞事件，
    // 子节点（右侧的操作按钮）照常响应。
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

/** Floating circular icon button (the HarmonyOS title bar action). */
@Component
export struct IconButton {
  glyph: string = 'dot';
  glyphSize: number = 21;
  tone: ResourceColor = $r('app.color.font_primary');
  diameter: number = 40;
  /** No glass fill or shadow — used inside cards and dark overlays. */
  plain: boolean = false;
  onAction: () => void = () => {
  };

  build() {
    Stack() {
      Glyph({ glyph: this.glyph, glyphSize: this.glyphSize, glyphTone: this.tone, glyphWeight: 1.7 })
    }
    .width(this.diameter)
    .height(this.diameter)
    .borderRadius(Radius.full)
    .backgroundColor(this.plain ? Color.Transparent : Palette.glassStrong)
    .backdropBlur(this.plain ? 1 : 30)
    .shadow(this.plain ? Shadow.none() : Shadow.action())
    .onClick(() => {
      this.onAction();
    })
  }
}

/** The glass pill bottom tab bar. */
@Component
export struct TabBar {
  @Prop active: number = 0;
  @Prop badge: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;
  onSelect: (index: number) => void = () => {
  };

  build() {
    Column() {
      Row() {
        ForEach(TABS, (item: TabItem, index: number) => {
          Column({ space: Space.s2 }) {
            Stack({ alignContent: Alignment.TopEnd }) {
              Glyph({
                glyph: item.glyph,
                glyphSize: 23,
                glyphWeight: this.active === index ? 2 : 1.7,
                glyphTone: this.active === index ? Palette.brand : Palette.fontPrimary
              })
              if (index === TAB_TASKS && this.badge > 0) {
                Text(this.badge > 99 ? '99' : this.badge.toString())
                  .fontSize(9)
                  .lineHeight(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Palette.white)
                  .textAlign(TextAlign.Center)
                  .constraintSize({ minWidth: 15 })
                  .height(15)
                  .padding({ left: 4, right: 4 })
                  .borderRadius(Radius.full)
                  .backgroundColor(Palette.warning)
                  .offset({ x: 10, y: -8 })
              }
            }
            .width(26)
            .height(26)

            Text(item.label)
              .fontSize(Font.tab)
              .lineHeight(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.active === index ? Palette.brand : Palette.fontPrimary)
          }
          .layoutWeight(1)
          .height(48)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.onSelect(index);
          })
        }, (item: TabItem) => item.key)
      }
      // The pill hugs the kit's fixed bar width instead of spanning the screen;
      // the maxWidth keeps it inside the page padding on very narrow devices.
      .width('100%')
      .constraintSize({ maxWidth: Layout.tabBarWidth })
      .height(Layout.tabBarHeight)
      .padding({ left: Space.s12, right: Space.s12 })
      .borderRadius(Radius.full)
      .backgroundColor(Palette.glass)
      .backdropBlur(30)
      .shadow(Shadow.float())
    }
    .width('100%')
    .padding({ top: Layout.tabBarTopPad, left: Layout.pagePad, right: Layout.pagePad, bottom: this.safeBottom })
    .linearGradient({
      angle: 180,
      colors: [[Palette.fadeNone, 0], [Palette.fadeSoft, 0.45], [Palette.fadeSolid, 1]]
    })
  }
}

/** Status pill: a pulsing dot while the task is in flight, a glyph when settled. */
@Component
export struct StatusChip {
  @Prop status: string = 'queued';

  private label(): string {
    if (this.status === 'queued') {
      return '排队中';
    }
    if (this.status === 'starting') {
      return '正在启动';
    }
    if (this.status === 'running' || this.status === 'downloading') {
      return '下载中';
    }
    if (this.status === 'packing') {
      return '打包中';
    }
    if (this.status === 'completed') {
      return '已完成';
    }
    if (this.status === 'failed') {
      return '失败';
    }
    if (this.status === 'cancelled') {
      return '已取消';
    }
    return this.status;
  }

  private pulsing(): boolean {
    return this.status === 'running' || this.status === 'downloading' || this.status === 'packing';
  }

  private tone(): Resource {
    if (this.pulsing()) {
      return Palette.brand;
    }
    if (this.status === 'completed') {
      return Palette.confirm;
    }
    if (this.status === 'failed') {
      return Palette.warning;
    }
    return Palette.fontSecondary;
  }

  private chipFill(): Resource {
    if (this.pulsing()) {
      return Palette.brandFaint;
    }
    if (this.status === 'completed') {
      return Palette.chipOkBg;
    }
    if (this.status === 'failed') {
      return Palette.chipWarnBg;
    }
    return Palette.cardSunken;
  }

  private glyph(): string {
    if (this.status === 'completed') {
      return 'checkCircle';
    }
    if (this.status === 'failed') {
      return 'alert';
    }
    if (this.status === 'cancelled') {
      return 'xCircle';
    }
    return 'clock';
  }

  build() {
    Row({ space: Space.s4 }) {
      if (this.pulsing()) {
        Circle().width(6).height(6).fill(this.tone())
      } else {
        Glyph({ glyph: this.glyph(), glyphSize: 12, glyphTone: this.tone(), glyphWeight: 2.2 })
      }
      Text(this.label())
        .fontSize(Font.chip)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.tone())
    }
    .height(21)
    .padding({ left: Space.s8, right: Space.s8 })
    .borderRadius(Radius.full)
    .backgroundColor(this.chipFill())
  }
}

/** Thin progress track. */
@Component
export struct ProgressBar {
  @Prop value: number = 0;
  /** 'brand' | 'ok' | 'warn' */
  tone: string = 'brand';
  /** Sweeping fill used while packing. */
  striped: boolean = false;

  private fill(): Resource {
    if (this.tone === 'ok') {
      return Palette.confirm;
    }
    if (this.tone === 'warn') {
      return Palette.warning;
    }
    return Palette.brand;
  }

  /** Diagonal stripes overlay, used while a batch is being packed. */
  private stripes(): LinearGradientOptions {
    if (!this.striped) {
      return { angle: 0, colors: [[Color.Transparent, 0], [Color.Transparent, 1]] };
    }
    return {
      angle: 115,
      repeating: true,
      colors: [['#47FFFFFF', 0], ['#47FFFFFF', 0.25], ['#00FFFFFF', 0.25], ['#00FFFFFF', 0.5]]
    };
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('100%')
        .height(4)
        .borderRadius(Radius.full)
        .backgroundColor(Palette.cardSunken)
      Row()
        .width(Math.max(2, Math.min(100, this.value)).toString() + '%')
        .height(4)
        .borderRadius(Radius.full)
        .backgroundColor(this.fill())
        .linearGradient(this.stripes())
        .animation({ duration: 400, curve: Curve.FastOutSlowIn })
    }
    .width('100%')
    .height(4)
  }
}

/** Segmented control. */
@Component
export struct Segmented {
  options: SegmentOption[] = [];
  @Prop selected: string = '';
  onSelect: (value: string) => void = () => {
  };

  build() {
    Row({ space: Space.s2 }) {
      ForEach(this.options, (option: SegmentOption) => {
        Text(option.label)
          .fontSize(Font.caption)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.selected === option.value ? Palette.brand : Palette.fontSecondary)
          .height(28)
          .padding({ left: Space.s12, right: Space.s12 })
          .borderRadius(Radius.full)
          .backgroundColor(this.selected === option.value ? Palette.segOn : Color.Transparent)
          .onClick(() => {
            this.onSelect(option.value);
          })
      }, (option: SegmentOption) => option.value)
    }
    .padding(Space.s2)
    .borderRadius(Radius.full)
    .backgroundColor(Palette.cardSunken)
  }
}

/**
 * 图库页顶部「图片 / 压缩包」分段：系统的 CapsuleSegmentButtonV2。
 *
 * 和上面手写的 `Segmented` 只差一件事 —— 背景板交给系统材质
 * （`backgroundSystemMaterial`）：下面是真实材质反射而不是盖一层半透明色，
 * 文字自动反色，按下还有交互形变与光感反馈。写法对应官方文档
 * 「SegmentButtonV2 → 示例6（设置背景板材质）」。
 *
 * 不用材质时（本机不支持沉浸式材质，或用户选了「无材质效果」）退回设计稿原来的不透明胶囊：
 * 浅底 + 白色药丸。
 */
@Component
export struct LibrarySegment {
  /** 当前段，取值与 LIBRARY_OPTIONS 一致。 */
  @Prop selected: string = 'images';
  /**
   * 用户在设置里选了「无材质效果」。
   *
   * **材质对象本身不从这里传进来**：`uiMaterial.Material` 是带 native 句柄的框架对象，
   * 用 @Prop 深拷贝它不可靠；而当普通成员又刷不动（AGENT.md 坑 3）—— 「无材质效果」选了
   * 以后图库分段永远保持旧观感。所以这里只收一个布尔量，材质在本组件内现算。
   */
  @Prop materialOff: boolean = false;
  onSelect: (value: string) => void = () => {
  };

  /** 选项直接由 LIBRARY_OPTIONS 生成，标签只有一处定义。 */
  private items: SegmentButtonV2Items = new SegmentButtonV2Items(
    LIBRARY_OPTIONS.map((option: SegmentOption): SegmentButtonV2ItemOptions => ({ text: option.label }))
  );

  /** `material()` 的缓存槽与它的有效性标记，见那里的说明。 */
  private materialCache: uiMaterial.Material | undefined = undefined;
  private materialCacheValid: boolean = false;
  private materialCacheOff: boolean = false;

  private hasMaterial(): boolean {
    // 设备能力探测统一走 service/MaterialSupport：原来这里另有一份同名的本地实现。
    return !this.materialOff && MaterialSupport.immersiveSupported();
  }

  /**
   * 分段控件的背景板材质。
   *
   * ULTRA_THIN 是文档示例里给浮层控件的档位：最薄、透过它能看到下面滚过的内容；
   * `colorInvert` 让文字自动反色；`lightEffect` 用系统的交互点击色，按下时光感跟着走。
   * 不支持材质时返回 undefined。
   *
   * **按 `materialOff` 缓存**：`uiMaterial.Material` 是带 native 句柄的对象，原来每个 build
   * 都新建一个，滚动时就是每帧一次原生分配。缓存键只需 materialOff —— 设备能力在一次运行里不变。
   */
  private material(): uiMaterial.Material | undefined {
    if (this.materialCacheValid && this.materialCacheOff === this.materialOff) {
      return this.materialCache;
    }
    this.materialCacheValid = true;
    this.materialCacheOff = this.materialOff;
    this.materialCache = this.hasMaterial()
      ? new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true,
        interactive: true,
        lightEffect: { color: $r('sys.color.interactive_click') }
      })
      : undefined;
    return this.materialCache;
  }

  private selectedIndex(): number {
    return this.selected === 'zips' ? 1 : 0;
  }

  /**
   * 未选中项的字色：设计稿的次级灰，**开不开材质都一样**。
   *
   * 材质档原来借用 `sys.color.font_primary`（文档给「自动反色」用的特殊资源），真机上就是
   * 纯黑，比设计稿的次级灰重一档。既然选中项已经改成固定色、不再走自动反色，这里也一并
   * 回到设计稿 —— 两个档位只有背景板不同，字色一致。
   */
  private itemFontColor(): ColorMetrics {
    return ColorMetrics.resourceColor(Palette.fontSecondary);
  }

  /**
   * 选中药丸的字色：设计稿的品牌色，**开不开材质都一样**。
   *
   * 这里原来在材质档写的是 `Color.Black`（照搬文档里「自动反色」那句），真机实测出来是
   * 系统蓝药丸上的黑字，几乎看不清。自动反色只管*未选中*项，选中项的底色并不由材质接管。
   */
  private selectedItemFontColor(): ColorMetrics {
    return ColorMetrics.resourceColor(Palette.brand);
  }

  /** 组件背景板：有材质时交给系统材质，否则用设计稿的浅底。 */
  private buttonBackground(): ColorMetrics | undefined {
    return this.hasMaterial() ? undefined : ColorMetrics.resourceColor(Palette.cardSunken);
  }

  /**
   * 选中药丸的底色：设计稿的白色药丸，**开不开材质都一样**。
   *
   * 不能像背景板那样留空 —— `itemSelectedBackgroundColor` 的默认值是
   * `$r('sys.color.segment_button_v2_tab_selected_item_background')`（系统蓝），留空就渲染成
   * 一整块蓝药丸（真机实测见 `.screenshots/library-segment-zips.jpeg`）。
   */
  private selectedItemBackground(): ColorMetrics {
    return ColorMetrics.resourceColor(Palette.segOn);
  }

  /** 一段文字的显示宽度估算（vp）：CJK 占满一个字号的宽度，Latin / 数字约六成。 */
  private advanceOf(text: string, size: number): number {
    let width: number = 0;
    for (let i: number = 0; i < text.length; i++) {
      width += text.charCodeAt(i) > 0x2e80 ? size : size * 0.6;
    }
    return width;
  }

  /**
   * 设计稿那个「跟着文字走」的窄胶囊宽度。
   *
   * 系统组件自己没有宽度参数，它内部把宽度撑满父容器 —— 只套一层自适应宽度的 `Row`
   * 也没用（测量时拿到的约束还是父级的 maxWidth，回落的仍是满宽），所以只能自己把宽度
   * 算出来、把 `Row` 钉上去。
   *
   * 而且它在内部**按项数平分**：真机实测把容器设成 114（正好是各按内容算的和）时，
   * 「图片」的药丸 53.7vp、「压缩包」只有 52vp，后者放不下 3 个字被截成「压…」。
   * 所以要按**最宽**的那一项 × 项数来算，再给每项留 2vp 余量 —— CJK 的字形步进在
   * 个别字体下会比字号大一丁点，刚好卡满也会截字。
   */
  private capsuleWidth(): number {
    let widest: number = 0;
    for (let i: number = 0; i < LIBRARY_OPTIONS.length; i++) {
      widest = Math.max(widest, this.advanceOf(LIBRARY_OPTIONS[i].label, Font.caption) + Space.s12 * 2);
    }
    return Space.s2 * 2
      + (widest + Space.s2) * LIBRARY_OPTIONS.length
      + Space.s2 * (LIBRARY_OPTIONS.length - 1);
  }

  build() {
    Row() {
      CapsuleSegmentButtonV2({
        items: this.items,
        selectedIndex: this.selectedIndex(),
        $selectedIndex: (index: number): void => {
          this.onSelect(index === 1 ? 'zips' : 'images');
        },
        // 尺寸对齐设计稿的 .seg：字 12、项高 28、项内边距 12、项间距 2、容器内边距 2。
        itemFontSize: LengthMetrics.vp(Font.caption),
        itemSelectedFontSize: LengthMetrics.vp(Font.caption),
        itemFontWeight: FontWeight.Bold,
        itemSelectedFontWeight: FontWeight.Bold,
        // 宽度是算出来的定值，文字再随系统放大就会被挤掉，所以钳住两项的字体缩放。
        itemMinFontScale: 1,
        itemMaxFontScale: 1,
        itemMinHeight: LengthMetrics.vp(28),
        // 容器的**最小高度也要一起压**，否则它会用系统默认的
        // `sys.float.segment_button_v2_singleline_background_height`（40vp）：选项仍是 28vp、
        // 顶部内边距仍是 2vp，多出来的 10vp 全堆在**底部** —— 胶囊看起来是「内容被顶到上面、
        // 底下空一条」，深色下尤其明显（浅色只差 2 个色阶，看不出来）。
        // 设计稿 .seg = padding 2 + item 28 → 容器就该是 28 + 2×2 = 32。
        buttonMinHeight: LengthMetrics.vp(28 + Space.s2 * 2),
        itemPadding: {
          // LocalizedPadding 用的是 start / end，不是 left / right（跟着语言方向走）。
          start: LengthMetrics.vp(Space.s12),
          end: LengthMetrics.vp(Space.s12)
        },
        itemSpace: LengthMetrics.vp(Space.s2),
        buttonPadding: LengthMetrics.vp(Space.s2),
        buttonBorderRadius: LengthMetrics.vp(Radius.full),
        itemFontColor: this.itemFontColor(),
        itemSelectedFontColor: this.selectedItemFontColor(),
        buttonBackgroundColor: this.buttonBackground(),
        itemSelectedBackgroundColor: this.selectedItemBackground(),
        backgroundSystemMaterial: this.material()
      })
    }
    .width(this.capsuleWidth())
  }
}

/** Pill button: primary / tonal / ghost / danger. */
@Component
export struct PillButton {
  label: string = '';
  /** 'primary' | 'tonal' | 'ghost' | 'danger' */
  variant: string = 'ghost';
  /** @Prop so a caller may flip the icon at runtime (e.g. single / ZIP mode). */
  @Prop icon: string = '';
  small: boolean = false;
  /** Stretch to the full width of its parent. */
  block: boolean = false;
  /**
   * Whether the button responds; an inactive primary greys out.
   * @Prop (not a plain member) so a caller's state change re-renders the button.
   */
  @Prop active: boolean = true;
  onAction: () => void = () => {
  };

  private surfaceColor(): ResourceColor {
    if (!this.active) {
      return Palette.cardSunken;
    }
    if (this.variant === 'primary') {
      return Palette.brand;
    }
    if (this.variant === 'tonal') {
      return Palette.brandFaint;
    }
    if (this.variant === 'danger') {
      return Palette.dangerBg;
    }
    return Palette.cardSunken;
  }

  private labelColor(): ResourceColor {
    if (!this.active) {
      return Palette.fontTertiary;
    }
    if (this.variant === 'primary') {
      return Palette.fontOnPrimary;
    }
    if (this.variant === 'tonal') {
      return Palette.brand;
    }
    if (this.variant === 'danger') {
      return Palette.warning;
    }
    return Palette.fontPrimary;
  }

  /** No label + an icon: the caller wants a round icon button, not an oval pill. */
  private iconOnly(): boolean {
    return this.label.length === 0 && this.icon.length > 0;
  }

  private buttonHeight(): number {
    return this.small ? 32 : 40;
  }

  private padSide(): number {
    if (this.iconOnly()) {
      return 0;
    }
    return this.small ? Space.s12 : Space.s18;
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: this.small ? Space.s2 : Space.s6 }) {
        if (this.icon.length > 0) {
          Glyph({
            glyph: this.icon,
            glyphSize: this.small ? 15 : 17,
            glyphTone: this.labelColor(),
            glyphWeight: 1.9
          })
        }
        Text(this.label)
          .fontSize(this.small ? Font.aux : Font.body)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.labelColor())
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
    }
    .width(this.block ? '100%' : (this.iconOnly() ? this.buttonHeight() : undefined))
    .height(this.buttonHeight())
    .padding({ left: this.padSide(), right: this.padSide() })
    .backgroundColor(this.surfaceColor())
    .borderRadius(Radius.full)
    .stateEffect(this.active)
    .onClick(() => {
      if (this.active) {
        this.onAction();
      }
    })
  }
}

/** Card surface. */
@Component
export struct Card {
  pad: number = Space.s12;
  @BuilderParam content: () => void = this.slot;

  @Builder
  private slot(): void {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(this.pad)
    .borderRadius(Radius.r8)
    .backgroundColor(Palette.card)
    .shadow(Shadow.card())
  }
}

/** Section heading with up to three trailing text actions. */
@Component
export struct SectionHead {
  heading: string = '';
  /** @Prop: callers pass live counters ("已选 3" / occupancy) into this slot. */
  @Prop meta: string = '';
  actionLabel: string = '';
  secondLabel: string = '';
  thirdLabel: string = '';
  /**
   * @Prop：智感握姿开启且系统识别到握持左手时，把三个文字操作移到左侧，
   * 让它们落在拇指够得着的一侧。
   */
  @Prop mirror: boolean = false;
  onAction: () => void = () => {
  };
  onSecond: () => void = () => {
  };
  onThird: () => void = () => {
  };

  /** 标题与计数；计数永远跟在标题后面，镜像时整块靠右。 */
  @Builder
  private title() {
    Text(this.heading)
      .fontSize(Font.sectionTitle)
      .lineHeight(Font.bodyLine)
      .fontWeight(FontWeight.Bold)
      .fontColor(Palette.fontPrimary)
    if (this.meta.length > 0) {
      Text(this.meta)
        .fontSize(Font.sectionMeta)
        .lineHeight(Font.captionLine)
        .fontColor(Palette.fontTertiary)
    }
  }

  /** 最多三个文字操作，顺序固定：「全选 / 反选 / 清空」不因镜像而调换。 */
  @Builder
  private actions() {
    if (this.actionLabel.length > 0) {
      Text(this.actionLabel)
        .fontSize(Font.aux)
        .fontWeight(FontWeight.Medium)
        .fontColor(Palette.brand)
        .padding({ left: Space.s4, right: Space.s4, top: Space.s2, bottom: Space.s2 })
        .borderRadius(Radius.r4)
        .onClick(() => {
          this.onAction();
        })
    }
    if (this.secondLabel.length > 0) {
      Text(this.secondLabel)
        .fontSize(Font.aux)
        .fontWeight(FontWeight.Medium)
        .fontColor(Palette.brand)
        .padding({ left: Space.s4, right: Space.s4, top: Space.s2, bottom: Space.s2 })
        .borderRadius(Radius.r4)
        .onClick(() => {
          this.onSecond();
        })
    }
    if (this.thirdLabel.length > 0) {
      Text(this.thirdLabel)
        .fontSize(Font.aux)
        .fontWeight(FontWeight.Medium)
        .fontColor(Palette.brand)
        .padding({ left: Space.s4, right: Space.s4, top: Space.s2, bottom: Space.s2 })
        .borderRadius(Radius.r4)
        .onClick(() => {
          this.onThird();
        })
    }
  }

  build() {
    Row({ space: Space.s4 }) {
      // 不能整行 reverse：那会把「0 张」也翻到标题前面。这里显式换位置，
      // 操作组的内部顺序保持不变，镜像只改变它在行里的左右。
      if (this.mirror) {
        this.actions()
        Blank()
        this.title()
      } else {
        this.title()
        Blank()
        this.actions()
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: Space.s2, right: Space.s2 })
  }
}

/** Centred empty state. */
@Component
export struct EmptyState {
  glyph: string = 'inbox';
  /** @Prop: the gallery swaps this between "图库还是空的" and "没有匹配的图片". */
  @Prop heading: string = '';
  @Prop body: string = '';

  build() {
    Column({ space: Space.s12 }) {
      Stack() {
        Glyph({ glyph: this.glyph, glyphSize: 30, glyphTone: Palette.fontTertiary, glyphWeight: 1.7 })
      }
      .width(72)
      .height(72)
      .borderRadius(Radius.full)
      .backgroundColor(Palette.cardSunken)

      Text(this.heading)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Palette.fontSecondary)
      if (this.body.length > 0) {
        Text(this.body)
          .fontSize(Font.aux)
          .lineHeight(Font.subtitleLine)
          .fontColor(Palette.fontTertiary)
          .maxLines(3)
          .textAlign(TextAlign.Center)
          .constraintSize({ maxWidth: 240 })
      }
    }
    .width('100%')
    .padding({ left: Space.s16, right: Space.s16, top: 40, bottom: 40 })
    .justifyContent(FlexAlign.Center)
  }
}

/** Transient confirmation pill. */
@Component
export struct ToastPill {
  @Prop text: string = '';

  build() {
    if (this.text.length > 0) {
      Text(this.text)
        .fontSize(Font.aux)
        .lineHeight(Font.subtitleLine)
        .fontWeight(FontWeight.Medium)
        .fontColor(Palette.white)
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: 284 })
        .padding({ left: Space.s16, right: Space.s16, top: Space.s10, bottom: Space.s10 })
        .borderRadius(Radius.full)
        .backgroundColor(Palette.toastBg)
        .backdropBlur(24)
        .shadow(Shadow.float())
    }
  }
}

/** Inline hint row with a leading glyph. */
@Component
export struct HintRow {
  glyph: string = 'sparkle';
  text: string = '';

  build() {
    Row({ space: Space.s4 }) {
      // Glyph and text are both top-aligned, so this nudge is what lines the
      // icon up with the text. The prototype asks for 2px (`.hintrow svg
      // { margin-top: 2px }`), which centres the icon on the 18vp line box; CJK
      // ink sits ~1vp below that box centre, so 3 is what actually looks level
      // (measured on device: 3px/1vp off at 2, aligned at 3).
      Glyph({ glyph: this.glyph, glyphSize: 14, glyphTone: Palette.fontTertiary, glyphWeight: 1.8 })
        .margin({ top: 3 })
      Text(this.text)
        .fontSize(Font.caption)
        .lineHeight(Font.auxLine)
        .fontColor(Palette.fontTertiary)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: Space.s2, right: Space.s2 })
  }
}

/**
 * One settings row: leading glyph, title, description, trailing control.
 *
 * 图标底色与字色**固定**是品牌色（`brandFaint` + `brand`），没有开关：设置页每一行的图标
 * 必须长成同一副样子。原来只有「沉浸光感 / 智感握姿 / 防窥保护」三行是品牌色，其余是灰底
 * 灰字，同一个卡片里两种观感；现在统一按沉浸光感那一版处理，见 README「图标」。
 */
@Component
export struct ListRow {
  /** @Prop: 主题行会随深浅色在 sun / moon 之间切。 */
  @Prop glyph: string = 'dot';
  heading: string = '';
  /** @Prop: 少数行的描述会跟着状态变（如防窥保护、下载位置）。 */
  @Prop aux: string = '';
  @BuilderParam trailing: () => void = this.slot;
  onAction: () => void = () => {
  };

  @Builder
  private slot(): void {
  }

  build() {
    Row({ space: Space.s12 }) {
      Stack() {
        Glyph({
          glyph: this.glyph,
          glyphSize: 20,
          glyphTone: Palette.brand,
          glyphWeight: 1.7
        })
      }
      .width(36)
      .height(36)
      .borderRadius(Radius.r6)
      .backgroundColor(Palette.brandFaint)

      Column({ space: Space.s2 }) {
        Text(this.heading)
          .fontSize(16)
          .lineHeight(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.fontPrimary)
        if (this.aux.length > 0) {
          Text(this.aux)
            .fontSize(Font.aux)
            .lineHeight(Font.auxLine)
            .fontColor(Palette.fontSecondary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.trailing()
    }
    .width('100%')
    .padding(Space.s12)
    .onClick(() => {
      this.onAction();
    })
  }
}

/** A settings row: leading glyph, title, description, then a control below. */
@Component
export struct StackedRow {
  /** @Prop：入参会在运行时变时必须这样声明，V1 不会把新值刷进普通成员。 */
  @Prop glyph: string = 'dot';
  heading: string = '';
  /** @Prop: the subtitle describes the current value. */
  @Prop aux: string = '';
  @BuilderParam control: () => void = this.slot;

  @Builder
  private slot(): void {
  }

  build() {
    Row({ space: Space.s12 }) {
      // 图标底色与字色和 ListRow 完全一致：设置页所有行的图标只有这一种观感。
      Stack() {
        Glyph({ glyph: this.glyph, glyphSize: 20, glyphTone: Palette.brand, glyphWeight: 1.7 })
      }
      .width(36)
      .height(36)
      .borderRadius(Radius.r6)
      .backgroundColor(Palette.brandFaint)

      Column({ space: Space.s2 }) {
        Text(this.heading)
          .fontSize(16)
          .lineHeight(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.fontPrimary)
        if (this.aux.length > 0) {
          Text(this.aux)
            .fontSize(Font.aux)
            .lineHeight(Font.auxLine)
            .fontColor(Palette.fontSecondary)
        }
        Column() {
          this.control()
        }
        .margin({ top: Space.s6 })
        .alignItems(HorizontalAlign.Start)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding(Space.s12)
  }
}

/** The prototype's rename dialog: a scrim, a card and a text field. */
@Component
export struct RenameDialog {
  heading: string = '';
  initial: string = '';
  onSave: (name: string) => void = () => {
  };
  onClose: () => void = () => {
  };

  @State private draft: string = '';

  aboutToAppear(): void {
    this.draft = this.initial;
  }

  private submit(): void {
    const next: string = this.draft.trim();
    if (next.length > 0) {
      this.onSave(next);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Palette.scrim)
        .onClick(() => {
          this.onClose();
        })

      Column({ space: Space.s10 }) {
        Text(this.heading)
          .fontSize(18)
          .lineHeight(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.fontPrimary)
          .textAlign(TextAlign.Center)
          .width('100%')

        TextInput({ text: this.draft })
          .fontSize(Font.body)
          .fontColor(Palette.fontPrimary)
          .caretColor(Palette.brand)
          .backgroundColor(Palette.cardSunken)
          .borderRadius(Radius.r6)
          .height(44)
          .padding({ left: Space.s14, right: Space.s14 })
          .onChange((value: string) => {
            this.draft = value;
          })

        Row({ space: Space.s6 }) {
          Column() {
            PillButton({
              label: '取消', variant: 'ghost', block: true,
              onAction: () => {
                this.onClose();
              }
            })
          }
          .layoutWeight(1)

          Column() {
            PillButton({
              label: '保存', variant: 'primary', block: true, active: this.draft.trim().length > 0,
              onAction: () => {
                this.submit();
              }
            })
          }
          .layoutWeight(1)
        }
        .width('100%')
        .margin({ top: Space.s4 })
      }
      .width(288)
      .padding({ left: Space.s16, right: Space.s16, top: Space.s20, bottom: Space.s10 })
      .borderRadius(Radius.r20)
      .backgroundColor(Palette.card)
      .shadow(Shadow.float())
    }
    .width('100%')
    .height('100%')
  }
}
