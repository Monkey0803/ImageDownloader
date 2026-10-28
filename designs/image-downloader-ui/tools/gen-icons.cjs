/* Convert designs/image-downloader-ui/icons.jsx into ArkTS Path command data. */
const fs = require('fs');

const src = fs.readFileSync(process.argv[2], 'utf8');
const body = src.slice(src.indexOf('const ICONS = {'), src.indexOf('function Icon('));

const num = (v) => {
  let s = String(Math.round(Number(v) * 1000) / 1000);
  if (s.startsWith('.')) s = '0' + s;
  if (s.startsWith('-.')) s = '-0' + s.slice(1);
  return s;
};
const n = (v) => Number(v);

/** circle -> two arc halves */
function circle(cx, cy, r) {
  cx = n(cx); cy = n(cy); r = n(r);
  return `M${num(cx - r)} ${num(cy)}a${num(r)} ${num(r)} 0 1 0 ${num(2 * r)} 0a${num(r)} ${num(r)} 0 1 0 ${num(-2 * r)} 0Z`;
}

/** rounded rect -> path with arcs (or plain lines when rx = 0) */
function rect(x, y, w, h, rx) {
  x = n(x); y = n(y); w = n(w); h = n(h); rx = n(rx || 0);
  if (rx <= 0) {
    return `M${num(x)} ${num(y)}H${num(x + w)}V${num(y + h)}H${num(x)}Z`;
  }
  const a = (dx, dy) => `a${num(rx)} ${num(rx)} 0 0 1 ${num(dx)} ${num(dy)}`;
  return `M${num(x + rx)} ${num(y)}` +
    `H${num(x + w - rx)}` + a(rx, rx) +
    `V${num(y + h - rx)}` + a(-rx, rx) +
    `H${num(x + rx)}` + a(-rx, -rx) +
    `V${num(y + rx)}` + a(rx, -rx) + 'Z';
}

const attr = (tag, name) => {
  const m = new RegExp(name + '="([^"]*)"').exec(tag);
  return m ? m[1] : undefined;
};

const icons = {};
const elementRe = /<(circle|rect|path)\b([^>]*?)\/?>/g;
let m;
while ((m = elementRe.exec(body)) !== null) {
  const kind = m[1];
  const tag = m[2];
  const d =
    kind === 'circle' ? circle(attr(tag, 'cx'), attr(tag, 'cy'), attr(tag, 'r')) :
    kind === 'rect' ? rect(attr(tag, 'x'), attr(tag, 'y'), attr(tag, 'width'), attr(tag, 'height'), attr(tag, 'rx')) :
    attr(tag, 'd');
  if (!d) continue;
  // find the owning icon key: nearest preceding `name: (`
  // (the `<` of the glyph may sit exactly on the slice boundary, hence `\(<?`)
  const before = body.slice(0, m.index);
  const keyRe = /(\w+)\s*:\s*\(<?/g;
  let key = null, km;
  while ((km = keyRe.exec(before)) !== null) key = km[1];
  if (!key) continue;
  icons[key] = (icons[key] ? icons[key] + ' ' : '') + d;
}

const entries = Object.keys(icons).map((k) => {
  const cleaned = icons[k]
    .replace(/\s+/g, ' ')
    .replace(/(?<![\d.])\.(\d)/g, '0.$1') // ".01" -> "0.01"; ArkUI's path parser wants a leading zero
    .trim();
  return `  '${k}': '${cleaned}'`;
});

const out = `import { display } from '@kit.ArkUI';

/*
 * Icons.ets — the app's single icon surface.
 *
 * Every icon in the app goes through \`Glyph\`, and \`Glyph\` prefers the system
 * HMSymbol set (\`sys.symbol.*\`): those are the HarmonyOS-native glyphs, they
 * follow the system font weight and the app's own color tokens, and they cost
 * nothing to ship.
 *
 * A handful of prototype glyphs have no system equivalent (see SYMBOL_RES);
 * those fall back to the 24x24 line paths below.
 */

const ICON_PATHS: Record<string, string> = {
${entries.join(',\n')}
};

/**
 * Glyph name → system HMSymbol.
 *
 * Names are validated against the HarmonyOS SDK system resource table.
 * The prototype mirrors published codepoints from
 * \`designs/harmonyos-mobile/assets/hmsymbol-map.json\`; newer SDK symbols such
 * as compass_circle keep a matching line-path fallback in the prototype.
 * Canonical intents include 分享=share, 导出=arrow_up_and_rectangle_on_rectangle,
 * 重命名=square_and_pencil, 下载=arrow_down_circle.
 */
const SYMBOL_RES: Record<string, Resource> = {
  'compass': $r('sys.symbol.compass_circle'),
  'list': $r('sys.symbol.list_bullet'),
  'settings': $r('sys.symbol.gearshape'),
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
  'circle': $r('sys.symbol.circle'),
  'xCircle': $r('sys.symbol.xmark_circle'),
  'scan': $r('sys.symbol.circle_viewfinder'),
  'inbox': $r('sys.symbol.arrow_down_circle'),
  'sparkle': $r('sys.symbol.rays'),
  'eye': $r('sys.symbol.eye'),
  'info': $r('sys.symbol.info_circle'),
  'bookmark': $r('sys.symbol.bookmark'),
  'bookmarkFill': $r('sys.symbol.bookmark_fill'),
  'copy': $r('sys.symbol.rectangle_on_rectangle'),
  // 只在符号层存在的两个名字：地址栏的「粘贴」与「前往」。
  'paste': $r('sys.symbol.text_clipboard'),
  'arrowRight': $r('sys.symbol.arrow_right'),
  'crop': $r('sys.symbol.crop_rotate'),
  'brush': $r('sys.symbol.paintbrush'),
  'rectangle': $r('sys.symbol.rectangle'),
  'rotateLeft': $r('sys.symbol.rotate_left'),
  'undo': $r('sys.symbol.undo'),
  'palette': $r('sys.symbol.paintpalette')
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
 * System symbols are drawn at \`glyphSize\` in vp so they keep the layout the
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
`;

fs.writeFileSync(process.argv[3], out);
console.log('icons:', entries.length);
