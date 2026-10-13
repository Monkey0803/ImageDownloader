/*
 * Widgets.ets — the prototype's presentational shell components.
 *
 * Ported from designs/image-downloader-ui/ui.jsx. Each struct owns the styling
 * of one component in the design; the screens compose them and own the data.
 */

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

export const TABS: TabItem[] = [
  { key: 'discover', label: '发现', glyph: 'scan' },
  { key: 'tasks', label: '任务', glyph: 'download' },
  { key: 'gallery', label: '图库', glyph: 'image' },
  { key: 'zip', label: '打包', glyph: 'archive' },
  { key: 'settings', label: '设置', glyph: 'sliders' }
];

export const MODE_OPTIONS: SegmentOption[] = [
  { value: 'single', label: '单张' },
  { value: 'zip', label: 'ZIP' }
];

export const THEME_OPTIONS: SegmentOption[] = [
  { value: 'system', label: '跟随系统' },
  { value: 'light', label: '浅色' },
  { value: 'dark', label: '深色' }
];

export const MATERIAL_OPTIONS: SegmentOption[] = [
  { value: 'adaptive', label: '自适应' },
  { value: 'immersive', label: '沉浸式' }
];

/**
 * Floating title bar: a big title over a translucent gradient that fades the
 * content scrolling underneath it.
 */
@Component
export struct TitleBar {
  @Prop heading: string = '';
  @Prop caption: string = '';
  /** Empty means no action button. */
  actionGlyph: string = '';
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
              if (item.key === 'tasks' && this.badge > 0) {
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
      .width('100%')
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

/** Pill button: primary / tonal / ghost / danger. */
@Component
export struct PillButton {
  label: string = '';
  /** 'primary' | 'tonal' | 'ghost' | 'danger' */
  variant: string = 'ghost';
  icon: string = '';
  small: boolean = false;
  /** Stretch to the full width of its parent. */
  block: boolean = false;
  /** Whether the button responds; an inactive primary greys out. */
  active: boolean = true;
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
    .width(this.block ? '100%' : undefined)
    .height(this.small ? 32 : 40)
    .padding({ left: this.small ? Space.s12 : Space.s18, right: this.small ? Space.s12 : Space.s18 })
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
  meta: string = '';
  actionLabel: string = '';
  secondLabel: string = '';
  thirdLabel: string = '';
  onAction: () => void = () => {
  };
  onSecond: () => void = () => {
  };
  onThird: () => void = () => {
  };

  build() {
    Row({ space: Space.s4 }) {
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
      Blank()
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
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: Space.s2, right: Space.s2 })
  }
}

/** Centred empty state. */
@Component
export struct EmptyState {
  glyph: string = 'inbox';
  heading: string = '';
  body: string = '';

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
      Glyph({ glyph: this.glyph, glyphSize: 14, glyphTone: Palette.fontTertiary, glyphWeight: 1.8 })
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

/** One settings row: leading glyph, title, description, trailing control. */
@Component
export struct ListRow {
  glyph: string = 'dot';
  brandTone: boolean = false;
  heading: string = '';
  aux: string = '';
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
          glyphTone: this.brandTone ? Palette.brand : Palette.fontSecondary,
          glyphWeight: 1.7
        })
      }
      .width(36)
      .height(36)
      .borderRadius(Radius.r6)
      .backgroundColor(this.brandTone ? Palette.brandFaint : Palette.cardSunken)

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
  glyph: string = 'dot';
  heading: string = '';
  aux: string = '';
  @BuilderParam control: () => void = this.slot;

  @Builder
  private slot(): void {
  }

  build() {
    Row({ space: Space.s12 }) {
      Stack() {
        Glyph({ glyph: this.glyph, glyphSize: 20, glyphTone: Palette.fontSecondary, glyphWeight: 1.7 })
      }
      .width(36)
      .height(36)
      .borderRadius(Radius.r6)
      .backgroundColor(Palette.cardSunken)

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
