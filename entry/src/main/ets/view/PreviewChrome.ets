import { Glyph } from './Icons';

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
