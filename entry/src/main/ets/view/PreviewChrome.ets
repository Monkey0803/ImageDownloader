import { Glyph } from './Icons';

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
