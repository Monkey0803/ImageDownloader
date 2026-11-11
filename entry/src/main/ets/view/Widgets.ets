/*
 * Widgets.ets — the prototype's presentational shell components.
 *
 * Ported from designs/image-downloader-ui/ui.jsx. Each struct owns the styling
 * of one component in the design; the screens compose them and own the data.
 */

import { TransparentGlass } from '../theme/TransparentGlass';
import { LIBRARY_IMAGES, LIBRARY_ZIPS } from '../model/Navigation';
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
 * 页签增减时两处要一起改（HDS 页签按该数组生成，保证标签和内容下标一致）。
 */
export const TABS: TabItem[] = [
  { key: 'discover', label: '发现', glyph: 'compass' },
  { key: 'tasks', label: '任务', glyph: 'list' },
  { key: 'library', label: '图库', glyph: 'image' },
  { key: 'settings', label: '设置', glyph: 'settings' }
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

/** 分段控件只吃文案；都从上面的选项表派生，选项名不会出现第二份。 */
export const LIBRARY_LABELS: string[] = LIBRARY_OPTIONS.map((option: SegmentOption): string => option.label);
export const MODE_LABELS: string[] = MODE_OPTIONS.map((option: SegmentOption): string => option.label);

/**
 * 设置行右侧的「当前值 + 下拉」控件：收起时是一枚显示当前档位的胶囊，点开是选项菜单。
 *
 * 用 @Prop 而不是普通入参，也不是 `@Builder` 传值：ArkUI V1 不会把父组件的新值刷进没有
 * 装饰器的成员，`@Builder` 按值传参同样不刷新——而档位/类型是会变的，见 AGENT.md 的坑 3。
 */
@ComponentV2
export struct SettingSelect {
  @Param options: SelectOption[] = [];
  @Param selectedIndex: number = 0;
  /** 收起时显示的文字，取当前档位的界面名。 */
  @Param label: string = '';
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
  @Param revision: number = 0;
  @Event onPick: (index: number) => void = () => {
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

/** Floating circular icon button (the HarmonyOS title bar action). */
@ComponentV2
export struct IconButton {
  @Param glyph: string = 'dot';
  @Param accessibilityLabel: string = '';
  @Param glyphSize: number = 21;
  @Param tone: ResourceColor = $r('app.color.font_primary');
  @Param diameter: number = 40;
  /** No glass fill or shadow — used inside cards and dark overlays. */
  @Param plain: boolean = false;
  @Event onAction: () => void = () => {
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
    .accessibilityText(this.accessibilityLabel)
    .onClick(() => {
      this.onAction();
    })
  }
}

/** One consistent selection state in grids and full-screen discovery preview. */
@ComponentV2
export struct PictureSelectionButton {
  @Param selected: boolean = false;
  @Param diameter: number = 36;
  @Event onAction: () => void = (): void => {};

  build() {
    Button({ type: ButtonType.Circle }) {
      Glyph({ glyph: this.selected ? 'checkCircle' : 'circle', glyphSize: this.diameter * 0.58,
        glyphTone: this.selected ? Palette.white : Palette.fontPrimary, glyphWeight: 2 })
    }
    .width(this.diameter).height(this.diameter)
    .backgroundColor(this.selected ? Palette.brand : Palette.glassStrong)
    .accessibilityText(this.selected ? '已选中，取消选择此图' : '未选中，选择此图')
    .accessibilitySelected(this.selected)
    .onClick((): void => { this.onAction(); })
  }
}

/** Status pill: a pulsing dot while the task is in flight, a glyph when settled. */
@ComponentV2
export struct StatusChip {
  @Param status: string = 'queued';

  private label(): string {
    if (this.status === 'queued') {
      return '排队中';
    }
    if (this.status === 'starting') {
      return '正在启动';
    }
    if (this.status === 'waiting') {
      return '等待中';
    }
    if (this.status === 'running' || this.status === 'downloading') {
      return '下载中';
    }
    if (this.status === 'paused') {
      return '已暂停';
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
    if (this.status === 'paused') {
      return 'pause';
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
@ComponentV2
export struct ProgressBar {
  @Param value: number = 0;
  /** 'brand' | 'ok' | 'warn' */
  tone: string = 'brand';
  /** Sweeping fill used while packing. */
  @Param striped: boolean = false;

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

/** Pill button: primary / tonal / ghost / danger. */
@ComponentV2
export struct PillButton {
  @Param label: string = '';
  /** 'primary' | 'tonal' | 'ghost' | 'danger' */
  @Param variant: string = 'ghost';
  /** @Prop so a caller may flip the icon at runtime (e.g. single / ZIP mode). */
  @Param icon: string = '';
  @Param small: boolean = false;
  /** Stretch to the full width of its parent. */
  @Param block: boolean = false;
  /**
   * Whether the button responds; an inactive primary greys out.
   * @Prop (not a plain member) so a caller's state change re-renders the button.
   */
  @Param active: boolean = true;
  @Event onAction: () => void = () => {
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
@ComponentV2
export struct Card {
  @Param pad: number = Space.s12;
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
@ComponentV2
export struct SectionHead {
  @Param heading: string = '';
  /** @Prop: callers pass live counters ("已选 3" / occupancy) into this slot. */
  @Param meta: string = '';
  @Param actionLabel: string = '';
  @Param secondLabel: string = '';
  @Param thirdLabel: string = '';
  /**
   * @Prop：智感握姿开启且系统识别到握持左手时，把三个文字操作移到左侧，
   * 让它们落在拇指够得着的一侧。
   */
  @Param mirror: boolean = false;
  @Event onAction: () => void = () => {
  };
  @Event onSecond: () => void = () => {
  };
  @Event onThird: () => void = () => {
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
@ComponentV2
export struct EmptyState {
  @Param glyph: string = 'inbox';
  /** @Prop: the gallery swaps this between "图库还是空的" and "没有匹配的图片". */
  @Param heading: string = '';
  @Param body: string = '';

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
@ComponentV2
export struct ToastPill {
  @Param text: string = '';

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
@ComponentV2
export struct HintRow {
  @Param glyph: string = 'sparkle';
  @Param text: string = '';

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
@ComponentV2
export struct ListRow {
  /** @Prop: 主题行会随深浅色在 sun / moon 之间切。 */
  @Param glyph: string = 'dot';
  @Param heading: string = '';
  /** @Prop: 少数行的描述会跟着状态变（如防窥保护、下载位置）。 */
  @Param aux: string = '';
  @BuilderParam trailing: () => void = this.slot;
  @Event onAction: () => void = () => {
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
@ComponentV2
export struct StackedRow {
  /** @Prop：入参会在运行时变时必须这样声明，V1 不会把新值刷进普通成员。 */
  @Param glyph: string = 'dot';
  @Param heading: string = '';
  /** @Prop: the subtitle describes the current value. */
  @Param aux: string = '';
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

/** 重命名表单内容，由页面的系统 bindSheet 承载。 */
@ComponentV2
export struct RenameDialog {
  @Param heading: string = '';
  @Param initial: string = '';
  @Event onSave: (name: string) => void = () => {
  };
  @Event onClose: () => void = () => {
  };

  @Local private draft: string = '';

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
    Column({ space: Space.s10 }) {
      Text(this.heading)
        .fontSize(18).lineHeight(24).fontWeight(FontWeight.Bold)
        .fontColor(TransparentGlass.foreground()).width('100%')
      TextInput({ text: this.draft })
        .fontSize(Font.body).fontColor(Palette.fontPrimary).caretColor(Palette.brand)
        .backgroundColor(Palette.cardSunken).borderRadius(Radius.r6).height(44)
        .padding({ left: Space.s14, right: Space.s14 })
        .onChange((value: string): void => { this.draft = value; })
      Row({ space: Space.s6 }) {
        Column() {
          PillButton({ label: '取消', variant: 'ghost', block: true, onAction: this.onClose })
        }.layoutWeight(1)
        Column() {
          PillButton({ label: '保存', variant: 'primary', block: true,
            active: this.draft.trim().length > 0, onAction: (): void => { this.submit(); } })
        }.layoutWeight(1)
      }.width('100%').margin({ top: Space.s4 })
    }
    .width('100%')
    .padding({ left: Space.s16, right: Space.s16, top: Space.s20, bottom: Space.s16 })
  }
}
