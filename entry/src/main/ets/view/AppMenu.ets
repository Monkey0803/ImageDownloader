/** Adapted from TwoFactor/common/components/AppMenu: one native bindMenu renderer. */
import { MenuItemSpec, MenuSpec } from './MenuSpec';
import { Glyph } from './Icons';
import { Font, Palette, Radius, Space } from '../theme/Tokens';

@Builder
function MenuRow(item: MenuItemSpec) {
  Stack() {
    Row({ space: Space.s8 }) {
      if (item.icon.length > 0) {
        Glyph({ glyph: item.icon, glyphSize: 20,
          glyphTone: item.danger ? Palette.warning : Palette.brand })
      }
      Text(item.label)
        .fontSize(Font.body)
        .fontColor(item.danger ? Palette.warning : Palette.fontPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%').height('100%')
    .padding({ left: Space.s12, right: Space.s12 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(16)
  }
  .width('100%').height(48)
  .onClick((): void => { if (item.enabled) { item.action(); } })
}

@Builder
export function AppMenu(spec: MenuSpec) {
  Menu() {
    ForEach(spec.items, (item: MenuItemSpec) => {
      MenuItem(MenuRow(item))
        .enabled(item.enabled)
    }, (item: MenuItemSpec) => item.id)
  }
  .width(spec.width)
  .radius(Radius.r20)
}
