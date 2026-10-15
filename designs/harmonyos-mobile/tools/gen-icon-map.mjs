#!/usr/bin/env node
// gen-icon-map.mjs — resolve the design system's icon names against the official
// HarmonyOS Symbol name dictionary and emit the JS map the Icon component uses.
//
// The reference library forbids hand-drawn inline SVG for this system: iconography
// must come from HMSymbol (references/0.governance/icon_role.md §2). This script
// is the only sanctioned way icons enter the system.
//
// Rules enforced here, straight from icon_role.md:
//   - only LINE icons by default; `*_fill` variants are excluded unless a
//     component explicitly needs one (the bottomtab 1+bar transport controls do)
//   - every name must resolve in the official dictionary — an unresolved name is
//     a hard error, never a silently dropped icon
//
// Usage:
//   node tools/gen-icon-map.mjs [--ref <dir>] [--check]

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DS = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
const REF = path.resolve(flag('--ref', path.join(process.env.HOME || '', '.agents/skills/hmos-design-visual-mobile')));
const CHECK = argv.includes('--check');

const MAP = path.join(REF, 'references/0.governance/hmsymbol-map.json');
if (!fs.existsSync(MAP)) {
  console.error(`gen-icon-map: dictionary not found: ${MAP}`);
  process.exit(2);
}

/* The system's icon set: a curated, semantic allow-list. Line variants only,
   except the three transport controls that the bottomtab 1+bar variant names
   explicitly in its own spec. */
const WANTED = {
  // navigation & shells
  chevron_left: 'titlebar secondary leading',
  chevron_right: 'list chevron / next',
  chevron_up: 'expand',
  chevron_down: 'collapse',
  indent_right: 'titlebar drawer leading',
  xmark: 'dismiss / close',
  plus: 'create',
  more: 'overflow menu',
  sort: 'sort order',
  // list / actions
  circle_dashed: 'titlebar default action placeholder',
  trash: 'delete',
  share: 'share',
  arrow_up_and_rectangle_on_rectangle: 'export / upload',
  square_and_pencil: 'rename / edit',
  checkmark: 'select',
  checkmark_circle: 'done',
  exclamationmark_circle: 'error',
  info_circle: 'info',
  // media & content
  picture: 'image',
  /* Media transport ships FILL variants only in the official set — the sole
     deliberate exception to the line-only rule, and the same choice the
     bottomtab 1+bar spec makes for its own transport controls. */
  play_fill: 'media transport (fill: no line variant published)',
  backward_end_fill: 'bottomtab 1+bar transport (fill)',
  pause_round_triangle_fill: 'bottomtab 1+bar transport (fill)',
  forward_end_fill: 'bottomtab 1+bar transport (fill)',
  // search & tabs placeholders
  magnifyingglass: 'search',
  house: 'tab: home',
  person: 'tab: profile',
  heart: 'tab: favourite',
  gearshape: 'settings',
  // status & security
  /* NOTE: the official set publishes bell_fill / bell_slash / bell_slash_fill
     but NO line bell — so there is no line-variant notification icon. Recorded
     as a dictionary gap in README.md rather patched with a drawn SVG. */
  lock: 'privacy',
  eye: 'view',
  // misc app chrome
  arrow_down_circle: 'download',
  folder: 'files',
  calendar: 'schedule',
  camera: 'capture',
  star: 'rate',
  bookmark: 'save',
  clock: 'time',
  list_bullet: 'list',
  square_grid_2x2: 'grid',
  slider_horizontal_2: 'preferences',
};

const dict = JSON.parse(fs.readFileSync(MAP, 'utf8'));
const byName = new Map((dict.icons || []).map((i) => [i.name, i]));

const missing = Object.keys(WANTED).filter((n) => !byName.has(n));
if (missing.length) {
  const names = [...byName.keys()];
  console.error('gen-icon-map: names not present in the official dictionary:');
  for (const n of missing) {
    const tokens = n.split('_').filter((t) => t.length > 2);
    const near = names
      .map((c) => ({ c, score: tokens.filter((t) => c.includes(t)).length }))
      .filter((x) => x.score > 0)
      .sort((a, b) => b.score - a.score || a.c.length - b.c.length)
      .slice(0, 5)
      .map((x) => x.c);
    console.error(`  - ${n}${near.length ? '   did you mean: ' + near.join(', ') : ''}`);
  }
  console.error('Use a real dictionary name (see icon_role.md) — never invent a glyph.');
  process.exit(3);
}

const entries = Object.keys(WANTED).map((name) => ({
  name,
  unicode: byName.get(name).unicode,
  use: WANTED[name],
}));

const body = entries.map((e) =>
  `  ${JSON.stringify(e.name)}: { u: "0x${e.unicode}", use: ${JSON.stringify(e.use)} },`).join('\n');

/* Emitted as .jsx, not .js: the compiler only bundles .jsx/.tsx sources and
   rewrites sibling imports to read from its internal scope — a plain .js module
   would survive as an unresolved import in the compiled bundle. No sibling .d.ts
   on purpose: this is a data module, not a component with a props contract. */
const js = `/*
 * HMSymbol icon map — GENERATED by tools/gen-icon-map.mjs, do not edit by hand.
 * Source: HarmonyOS Symbol official name dictionary v${dict.version} (${dict.total_icons} icons)
 *   ${dict.source_url || 'references/0.governance/hmsymbol-map.json'}
 *
 * Usage: import { glyph } from "./IconMap";  →  <span className="hm-icon">{glyph("chevron_right")}</span>
 * or simply <Icon name="chevron_right" /> from the controls group.
 * Only LINE icons are listed by rule; the three \`*_fill\` transport controls are
 * the sole exception, because the bottomtab 1+bar spec names them explicitly.
 */

export const HMSYMBOL = {
${body}
};

export const HMSYMBOL_NAMES = Object.keys(HMSYMBOL);

/** Codepoint → the character to render. */
export function glyph(name) {
  const hit = HMSYMBOL[name];
  if (!hit) { return null; }
  return String.fromCodePoint(Number(hit.u));
}
`;

const out = path.join(DS, 'components/controls/IconMap.jsx');
const before = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : null;

// ship the full dictionary too, so consumers can look up names we did not curate
const fullOut = path.join(DS, 'assets/hmsymbol-map.json');
const fullJson = fs.readFileSync(MAP);

let stale = 0;
for (const [abs, content] of [[out, js], [fullOut, fullJson]]) {
  const cur = fs.existsSync(abs) ? fs.readFileSync(abs) : null;
  const same = cur && Buffer.compare(Buffer.from(cur), Buffer.from(content)) === 0;
  if (same) { console.log('  = ' + path.relative(DS, abs)); continue; }
  stale++;
  if (CHECK) { console.log('  ! stale: ' + path.relative(DS, abs)); continue; }
  fs.writeFileSync(abs, content);
  console.log(`  ${cur === null ? '+' : '~'} ${path.relative(DS, abs)}`);
}

console.log(`gen-icon-map: ${entries.length} icons curated from ${dict.total_icons} ` +
  `(dictionary v${dict.version}); ${stale} ${CHECK ? 'stale' : 'written'}`);
if (CHECK && stale) { process.exit(1); }
