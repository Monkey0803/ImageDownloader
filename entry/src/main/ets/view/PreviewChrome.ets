import { Glyph } from './Icons';
import { IconButton } from './Widgets';
import { Font, Palette, Space } from '../theme/Tokens';

/**
 * 预览页上下工具栏的暗色渐变。
 *
 * 预览页已经隐藏系统栏，工具栏直接贴在图片上；用「黑 → 透明」渐变代替整块半透明背景，
 * 图片不会被一条硬边切断，也不会在顶部/底部留下色块。
 */
export class PreviewChrome {
  static topGradient(): LinearGradientOptions {
    return {
      angle: 180,
      colors: [['#F0000000', 0], ['#A6000000', 0.45], [Color.Transparent, 1]]
    };
  }

  static bottomGradient(): LinearGradientOptions {
    return {
      angle: 180,
      colors: [[Color.Transparent, 0], [Color.Transparent, 0.08], ['#A6000000', 0.6], ['#F0000000', 1]]
    };
  }
}

/** Header shared by downloaded and discovered image previews. */
@ComponentV2
export struct PreviewHeader {
  @Require @Param title: string;
  @Param counter: string = '';
  @Param showCounter: boolean = true;
  @Param counterActive: boolean = true;
  @Param emphasized: boolean = false;
  @Param detailsLabel: string = '图片详情';
  @Event onNavigation: () => void = (): void => {};
  @Event onDetails: () => void = (): void => {};
  @Event onClose: () => void = (): void => {};

  build() {
    Row({ space: this.emphasized ? Space.s4 : Space.s8 }) {
      Text(this.title)
        .fontSize(Font.body)
        .fontWeight(this.emphasized ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(Palette.white)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      if (this.showCounter) {
        Text(this.counter)
          .fontSize(Font.aux)
          .fontColor(this.emphasized ? '#B3FFFFFF' : Palette.white)
          .margin({ right: this.emphasized ? Space.s4 : 0 })
          .padding(Space.s8).constraintSize({ minHeight: 40 })
          .accessibilityText('打开缩略图导航，' + this.counter)
          .onClick((): void => { if (this.counterActive) { this.onNavigation(); } })
      }
      IconButton({ glyph: 'info', glyphSize: this.emphasized ? 21 : 20, tone: Palette.white,
        plain: true, diameter: 40, accessibilityLabel: this.detailsLabel,
        onAction: this.onDetails })
      IconButton({ glyph: 'close', glyphSize: 20, diameter: 40, plain: true,
        tone: Palette.white, accessibilityLabel: '关闭图片预览', onAction: this.onClose })
    }
    .width('100%').alignItems(VerticalAlign.Center)
    .padding({ left: Space.s16, right: Space.s16, top: Space.s16,
      bottom: this.emphasized ? Space.s8 : Space.s12 })
  }
}

/** Controls on the dark image canvas use explicit contrast, independent of the app theme. */
@ComponentV2
export struct PreviewButton {
  @Require @Param label: string;
  @Param icon: string = '';
  @Param small: boolean = true;
  @Param variant: string = 'tonal';
  @Param active: boolean = true;
  @Event onAction: () => void = (): void => {};

  build() {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: 6 }) {
        if (this.icon.length > 0) {
          Glyph({ glyph: this.icon, glyphSize: 18, glyphTone: this.active ? '#FFFFFF' : '#B3FFFFFF' })
        }
        Text(this.label).fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(this.active ? '#FFFFFF' : '#B3FFFFFF').maxLines(1)
      }.padding({ left: 12, right: 12 })
    }
    .height(this.small ? 40 : 44)
    .backgroundColor(this.variant === 'primary' ? '#0A59F7' : '#333336')
    .enabled(this.active).accessibilityText(this.label)
    .onClick((): void => { this.onAction(); })
  }
}
