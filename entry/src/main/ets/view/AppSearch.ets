/* 系统 Search 的统一入口：保留原生清除按钮与键盘搜索提交语义。 */
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { Font, Palette, Radius, Shadow } from '../theme/Tokens';

@ComponentV2
export struct AppSearch {
  @Param text: string = '';
  @Param placeholder: ResourceStr = '';
  @Param pill: boolean = false;
  @Param focusId: string = '';
  @Param focusOnAppear: boolean = false;
  @Event onChange: (value: string) => void = (value: string): void => {};
  @Event onSubmit: (value: string) => void = (value: string): void => {};
  @Event onSearchFocus: () => void = (): void => {};
  @Event onSearchBlur: () => void = (): void => {};
  private controller: SearchController = new SearchController();

  private searchSymbol(): SymbolGlyphModifier {
    const symbol: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.magnifyingglass'));
    symbol.fontColor([Palette.fontTertiary]);
    return symbol;
  }

  private clearSymbol(): SymbolGlyphModifier {
    const symbol: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.xmark_circle_fill'));
    symbol.fontColor([Palette.fontTertiary]);
    return symbol;
  }

  build() {
    Search({ value: this.text, placeholder: this.placeholder, controller: this.controller })
      .id(this.focusId)
      .width('100%')
      .height(this.pill ? 44 : 40)
      .borderRadius(this.pill ? Radius.full : Radius.r4)
      .backgroundColor(this.pill ? Palette.card : Palette.cardSunken)
      .shadow(this.pill ? Shadow.card() : Shadow.none())
      .placeholderColor(Palette.fontSecondary)
      .placeholderFont({ size: this.pill ? Font.body : Font.aux })
      .textFont({ size: this.pill ? Font.body : Font.aux })
      .fontColor(Palette.fontPrimary)
      .caretStyle({ color: Palette.brand })
      .selectedBackgroundColor(Palette.brandSoft)
      .searchIcon(this.searchSymbol())
      .cancelButton({ style: CancelButtonStyle.INPUT, icon: this.clearSymbol() })
      .onChange((value: string): void => { this.onChange(value); })
      .onSubmit((value: string): void => { this.onSubmit(value); })
      .onFocus((): void => { this.onSearchFocus(); })
      .onBlur((): void => { this.onSearchBlur(); })
      .onAppear((): void => {
        if (this.focusOnAppear) {
          focusControl.requestFocus(this.focusId);
        }
      })
  }
}
