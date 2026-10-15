import { display } from '@kit.ArkUI';

/*
 * Icons.ets — the app's single icon surface.
 *
 * Every icon in the app goes through `Glyph`, and `Glyph` prefers the system
 * HMSymbol set (`sys.symbol.*`): those are the HarmonyOS-native glyphs, they
 * follow the system font weight and the app's own color tokens, and they cost
 * nothing to ship.
 *
 * A handful of prototype glyphs have no system equivalent (see SYMBOL_RES);
 * those fall back to the 24x24 line paths below.
 */

const ICON_PATHS: Record<string, string> = {
  'search': 'M4 11a7 7 0 1 0 14 0a7 7 0 1 0 -14 0Z M16.6 16.6 21 21',
  'globe': 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0Z M3 12h18 M12 3c2.6 3 2.6 15 0 18 M12 3c-2.6 3-2.6 15 0 18',
  'refresh': 'M20.5 12a8.5 8.5 0 1 1-2.6-6.1 M20.5 4.6V10H15',
  'check': 'M5 12.6 10 17.5 19 6.8',
  'close': 'M6 6 18 18 M18 6 6 18',
  'download': 'M12 3.5v11 M7.4 10.2 12 14.8l4.6-4.6 M4.5 19.8h15',
  'image': 'M6 4.5H18a3 3 0 0 1 3 3V16.5a3 3 0 0 1 -3 3H6a3 3 0 0 1 -3 -3V7.5a3 3 0 0 1 3 -3Z M7.1 9.6a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0 -3 0Z M4.5 18l4.8-4.6 3 2.9 3.4-3.4 3.8 3.6',
  'layers': 'M12 3.5 3.5 8l8.5 4.5L20.5 8z M3.5 12.6 12 17.1l8.5-4.5 M3.5 16.9 12 21.4l8.5-4.5',
  'archive': 'M4.8 4H19.2a1.8 1.8 0 0 1 1.8 1.8V6.8a1.8 1.8 0 0 1 -1.8 1.8H4.8a1.8 1.8 0 0 1 -1.8 -1.8V5.8a1.8 1.8 0 0 1 1.8 -1.8Z M4.8 8.6v9.2a2 2 0 0 0 2 2h10.4a2 2 0 0 0 2-2V8.6 M10 12.6h4',
  'sliders': 'M4 7.5h8.4 M18.4 7.5H20 M13.2 7.5a2.2 2.2 0 1 0 4.4 0a2.2 2.2 0 1 0 -4.4 0Z M4 16.5h3.4 M13.4 16.5H20 M8.2 16.5a2.2 2.2 0 1 0 4.4 0a2.2 2.2 0 1 0 -4.4 0Z',
  'trash': 'M4.5 7h15 M9.5 7V5.4a1.4 1.4 0 0 1 1.4-1.4h2.2a1.4 1.4 0 0 1 1.4 1.4V7 M6.6 7l0.9 11.6a2 2 0 0 0 2 1.9h5a2 2 0 0 0 2-1.9L17.4 7 M10.4 11v5.6 M13.6 11v5.6',
  'share': 'M15.2 5.6a2.6 2.6 0 1 0 5.2 0a2.6 2.6 0 1 0 -5.2 0Z M3.6 12a2.6 2.6 0 1 0 5.2 0a2.6 2.6 0 1 0 -5.2 0Z M15.2 18.4a2.6 2.6 0 1 0 5.2 0a2.6 2.6 0 1 0 -5.2 0Z M8.5 10.7 15.5 7 M8.5 13.3 15.5 17',
  'export': 'M12 15.5V4 M7.8 8.2 12 4l4.2 4.2 M4.5 15.4v2.8a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2v-2.8',
  'pencil': 'M4 20h4.2L19.4 8.8a2.6 2.6 0 0 0-3.7-3.7L4.5 16.3 4 20z M14.6 6.2l3.7 3.7',
  'chevronRight': 'M9.5 5.5 16 12l-6.5 6.5',
  'grid': 'M5.8 4H9.2a1.8 1.8 0 0 1 1.8 1.8V9.2a1.8 1.8 0 0 1 -1.8 1.8H5.8a1.8 1.8 0 0 1 -1.8 -1.8V5.8a1.8 1.8 0 0 1 1.8 -1.8Z M14.8 4H18.2a1.8 1.8 0 0 1 1.8 1.8V9.2a1.8 1.8 0 0 1 -1.8 1.8H14.8a1.8 1.8 0 0 1 -1.8 -1.8V5.8a1.8 1.8 0 0 1 1.8 -1.8Z M5.8 13H9.2a1.8 1.8 0 0 1 1.8 1.8V18.2a1.8 1.8 0 0 1 -1.8 1.8H5.8a1.8 1.8 0 0 1 -1.8 -1.8V14.8a1.8 1.8 0 0 1 1.8 -1.8Z M14.8 13H18.2a1.8 1.8 0 0 1 1.8 1.8V18.2a1.8 1.8 0 0 1 -1.8 1.8H14.8a1.8 1.8 0 0 1 -1.8 -1.8V14.8a1.8 1.8 0 0 1 1.8 -1.8Z',
  'chevronDown': 'M5.5 9.5 12 16l6.5-6.5',
  'chevronUp': 'M5.5 14.5 12 8l6.5 6.5',
  'play': 'M8.2 5.6v12.8L18.6 12z',
  'pause': 'M9.4 5.5v13 M14.6 5.5v13',
  'retry': 'M3.5 12a8.5 8.5 0 1 0 2.6-6.1 M3.5 4.6V10H9',
  'plus': 'M12 5.4v13.2 M5.4 12h13.2',
  'folder': 'M3 7.2a2 2 0 0 1 2-2h3.5l2.1 2.2H19a2 2 0 0 1 2 2v8.4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
  'sun': 'M7.8 12a4.2 4.2 0 1 0 8.4 0a4.2 4.2 0 1 0 -8.4 0Z M12 2.6v2.2 M12 19.2v2.2 M4.4 4.4 6 6 M18 18l1.6 1.6 M2.6 12h2.2 M19.2 12h2.2 M4.4 19.6 6 18 M18 6l1.6-1.6',
  'moon': 'M20.2 14.6A8.6 8.6 0 1 1 9.4 3.8a7 7 0 0 0 10.8 10.8z',
  'clock': 'M3.6 12a8.4 8.4 0 1 0 16.8 0a8.4 8.4 0 1 0 -16.8 0Z M12 7.4V12l3.4 2',
  'alert': 'M3.4 12a8.6 8.6 0 1 0 17.2 0a8.6 8.6 0 1 0 -17.2 0Z M12 7.8v4.8 M12 16.1h0.01',
  'checkCircle': 'M3.4 12a8.6 8.6 0 1 0 17.2 0a8.6 8.6 0 1 0 -17.2 0Z M8.2 12.3 11 15.1l5-5.2',
  'xCircle': 'M3.4 12a8.6 8.6 0 1 0 17.2 0a8.6 8.6 0 1 0 -17.2 0Z M9.4 9.4 14.6 14.6 M14.6 9.4 9.4 14.6',
  'scan': 'M4 9V6.5A2.5 2.5 0 0 1 6.5 4H9 M15 4h2.5A2.5 2.5 0 0 1 20 6.5V9 M20 15v2.5a2.5 2.5 0 0 1-2.5 2.5H15 M9 20H6.5A2.5 2.5 0 0 1 4 17.5V15 M4 12h16',
  'window': 'M5.6 4.5H18.4a2.6 2.6 0 0 1 2.6 2.6V16.9a2.6 2.6 0 0 1 -2.6 2.6H5.6a2.6 2.6 0 0 1 -2.6 -2.6V7.1a2.6 2.6 0 0 1 2.6 -2.6Z M3 9h18 M6.4 6.8h0.01 M9.2 6.8h0.01',
  'inbox': 'M3.6 13.6 6 5.6a2 2 0 0 1 1.9-1.4h8.2A2 2 0 0 1 18 5.6l2.4 8 M3.6 13.6H8l1.2 2.4h5.6l1.2-2.4h4.4v4.4a2 2 0 0 1-2 2H5.6a2 2 0 0 1-2-2z',
  'sparkle': 'M12 3.4l1.7 4.9 4.9 1.7-4.9 1.7L12 16.6l-1.7-4.9L5.4 10l4.9-1.7z M18.4 16.4l0.7 2 2 0.7-2 0.7-0.7 2-0.7-2-2-0.7 2-0.7z',
  'copy': 'M11.4 9H18a2.4 2.4 0 0 1 2.4 2.4V18a2.4 2.4 0 0 1 -2.4 2.4H11.4a2.4 2.4 0 0 1 -2.4 -2.4V11.4a2.4 2.4 0 0 1 2.4 -2.4Z M5.6 15.4H4.6a1.6 1.6 0 0 1-1.6-1.6V5.6A1.6 1.6 0 0 1 4.6 4h8.2a1.6 1.6 0 0 1 1.6 1.6v1',
  'grip': 'M10.3 3.2H13.7a2.7 2.7 0 0 1 2.7 2.7V18.1a2.7 2.7 0 0 1 -2.7 2.7H10.3a2.7 2.7 0 0 1 -2.7 -2.7V5.9a2.7 2.7 0 0 1 2.7 -2.7Z M10.7 6.2h2.6 M2.6 8.9a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0 -3.4 0Z M18 15.1a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0 -3.4 0Z',
  'shield': 'M12 3.2 19 5.8v5.9c0 4.2-2.9 7.6-7 9.1-4.1-1.5-7-4.9-7-9.1V5.8z M9.3 12.1 11.4 14.2l3.5-3.6',
  'eye': 'M2.9 12S6.5 5.9 12 5.9 21.1 12 21.1 12 17.5 18.1 12 18.1 2.9 12 2.9 12z M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0Z',
  'dot': 'M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0Z'
};

/**
 * Glyph name → system HMSymbol.
 *
 * Every name here is one the official HarmonyOS Symbol dictionary publishes
 * (`designs/harmonyos-mobile/assets/hmsymbol-map.json`, 404 names) — the design
 * kit's `components/controls/IconMap.jsx` fixes the canonical symbol for each UI
 * intent (分享=share, 导出=arrow_up_and_rectangle_on_rectangle,
 * 重命名=square_and_pencil, 下载=arrow_down_circle …). Staying inside that
 * dictionary is what lets the HTML prototype draw the identical glyph from the
 * HMSymbol font; anything missing here keeps the prototype's path icon, so no
 * icon can ever disappear.
 */
const SYMBOL_RES: Record<string, Resource> = {
  'search': $r('sys.symbol.magnifyingglass'),
  'refresh': $r('sys.symbol.arrow_clockwise'),
  'check': $r('sys.symbol.checkmark'),
  'close': $r('sys.symbol.xmark'),
  'download': $r('sys.symbol.arrow_down_circle'),
  'image': $r('sys.symbol.picture'),
  'layers': $r('sys.symbol.rectangle_on_rectangle'),
  'archive': $r('sys.symbol.externaldrive'),
  'sliders': $r('sys.symbol.slider_horizontal_2'),
  'trash': $r('sys.symbol.trash'),
  'share': $r('sys.symbol.share'),
  'export': $r('sys.symbol.arrow_up_and_rectangle_on_rectangle'),
  'pencil': $r('sys.symbol.square_and_pencil'),
  'chevronRight': $r('sys.symbol.chevron_right'),
  'grid': $r('sys.symbol.square_grid_2x2'),
  'chevronDown': $r('sys.symbol.chevron_down'),
  'chevronUp': $r('sys.symbol.chevron_up'),
  'play': $r('sys.symbol.play_fill'),
  'pause': $r('sys.symbol.pause_round_triangle_fill'),
  'retry': $r('sys.symbol.arrow_counterclockwise'),
  'plus': $r('sys.symbol.plus'),
  'folder': $r('sys.symbol.folder'),
  'sun': $r('sys.symbol.sun_max'),
  'moon': $r('sys.symbol.moon_fill'),
  'clock': $r('sys.symbol.clock'),
  'alert': $r('sys.symbol.exclamationmark_circle'),
  'checkCircle': $r('sys.symbol.checkmark_circle'),
  'xCircle': $r('sys.symbol.xmark_circle'),
  'scan': $r('sys.symbol.circle_viewfinder'),
  'inbox': $r('sys.symbol.arrow_down_circle'),
  'sparkle': $r('sys.symbol.rays'),
  'eye': $r('sys.symbol.eye'),
  // 只在符号层存在的两个名字：地址栏的「粘贴」与「前往」。
  'paste': $r('sys.symbol.text_clipboard'),
  'arrowRight': $r('sys.symbol.arrow_right')
};

/** Path data for a named glyph, falling back to a dot for unknown names. */
export function iconPath(name: string): string {
  return ICON_PATHS[name] ?? ICON_PATHS.dot;
}

/** System symbol for a glyph name, or undefined when only a path icon exists. */
export function symbolOf(name: string): Resource | undefined {
  return SYMBOL_RES[name];
}

/**
 * The prototype draws icons with 1.7–2.6 unit strokes; symbols express the same
 * emphasis through font weight. Three buckets cover every call site.
 */
function symbolWeight(glyphWeight: number): FontWeight {
  if (glyphWeight >= 2.4) {
    return FontWeight.Bold;
  }
  if (glyphWeight >= 1.9) {
    return FontWeight.Medium;
  }
  return FontWeight.Regular;
}

/**
 * One icon of the app.
 *
 * System symbols are drawn at `glyphSize` in vp so they keep the layout the
 * prototype specified regardless of the user's font scale. The path fallback
 * draws in the prototype's 24x24 viewport: path commands are measured in **px**
 * (PathAttribute#commands) while the shape viewport is measured in **vp**, so
 * the viewport is declared as the 24-unit box converted to vp. The shape then
 * scales that box up to glyphSize by itself and no path data has to be
 * rewritten. strokeWidth is a vp length and is divided by the same density,
 * which keeps the stroke proportional to the glyph exactly the way the
 * prototype's SVG did.
 */
@ComponentV2
export struct Glyph {
  // Prefixed member names: size, name and friends are universal component
  // attributes, and a struct member may not shadow one.
  //
  // All four are @Param. 它们会在运行时被调用方改（设置页「主题」行的 sun ↔ moon、
  // 任务卡片的 clock → checkCircle…），所以必须是装饰成员 —— V2 里裸成员**根本传不进来**
  // （实测报 10905324：The 'regular' property ... cannot be initialized here）。
  @Param glyph: string = 'dot';
  @Param glyphSize: number = 24;
  @Param glyphTone: ResourceColor = $r('app.color.font_primary');
  @Param glyphWeight: number = 1.7;

  private density: number = display.getDefaultDisplaySync().densityPixels;

  private hasSymbol(): boolean {
    return SYMBOL_RES[this.glyph] !== undefined;
  }

  private symbol(): Resource {
    return SYMBOL_RES[this.glyph];
  }

  build() {
    if (this.hasSymbol()) {
      SymbolGlyph(this.symbol())
        .fontSize(this.glyphSize.toString() + 'vp')
        .fontColor([this.glyphTone])
        .fontWeight(symbolWeight(this.glyphWeight))
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .effectStrategy(SymbolEffectStrategy.NONE)
    } else {
      Shape() {
        Path()
          .commands(iconPath(this.glyph))
          .fill(Color.Transparent)
          .stroke(this.glyphTone)
          .strokeWidth(this.glyphWeight / this.density)
          .strokeLineCap(LineCapStyle.Round)
          .strokeLineJoin(LineJoinStyle.Round)
      }
      .viewPort({ x: 0, y: 0, width: 24 / this.density, height: 24 / this.density })
      .width(this.glyphSize)
      .height(this.glyphSize)
    }
  }
}
