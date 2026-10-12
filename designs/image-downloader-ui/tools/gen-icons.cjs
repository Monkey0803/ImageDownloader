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
 * Icons.ets — one consistent 24 px line-icon set.
 *
 * Generated from designs/image-downloader-ui/icons.jsx: each prototype SVG
 * glyph was rewritten into a single 24x24 path so the app and the design
 * prototype draw exactly the same shapes. Do not hand-edit the path data;
 * run designs/image-downloader-ui/tools/gen-icons.cjs instead.
 */

const ICON_PATHS: Record<string, string> = {
${entries.join(',\n')}
};

/** Path data for a named glyph, falling back to a dot for unknown names. */
export function iconPath(name: string): string {
  return ICON_PATHS[name] ?? ICON_PATHS.dot;
}

/**
 * Line icon drawn in the prototype's 24x24 viewport.
 *
 * Path commands are measured in **px** (PathAttribute#commands) while the shape
 * viewport is measured in **vp**, so the viewport is declared as the 24-unit box
 * converted to vp. The shape then scales that box up to glyphSize by itself and
 * no path data has to be rewritten. strokeWidth is a vp length and is divided by
 * the same density, which keeps the stroke proportional to the glyph exactly the
 * way the prototype's SVG did.
 */
@Component
export struct Glyph {
  // Prefixed member names: size, name and friends are universal component
  // attributes, and a struct member may not shadow one.
  glyph: string = 'dot';
  glyphSize: number = 24;
  glyphTone: ResourceColor = $r('app.color.font_primary');
  glyphWeight: number = 1.7;

  private density: number = display.getDefaultDisplaySync().densityPixels;

  build() {
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
`;

fs.writeFileSync(process.argv[3], out);
console.log('icons:', entries.length);
