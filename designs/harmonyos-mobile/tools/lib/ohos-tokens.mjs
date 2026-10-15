/*
 * ohos-tokens.mjs — shared parsing for the HarmonyOS resource layer.
 *
 * Both tools/emit-ohos-resources.mjs and tools/build-token-har.mjs build the same
 * resource values from the same CSS tokens. Keeping the conversion in one place is
 * not tidiness for its own sake: two copies of "how do we turn rgba() into ARGB"
 * WILL drift, and the whole point of this layer is that the app and the design
 * system cannot disagree.
 */
import fs from 'node:fs';
import path from 'node:path';

export const stripComments = (css) => css.replace(/\/\*[\s\S]*?\*\//g, '');

/** Parse `selector { --name: value; }` blocks out of every token file. */
export function readTokenBlocks(tokensDir) {
  if (!fs.existsSync(tokensDir)) {
    throw new Error(`no tokens/ directory at ${tokensDir}`);
  }
  const files = fs.readdirSync(tokensDir).filter((f) => f.endsWith('.css')).sort();
  const blocks = [];
  for (const file of files) {
    const clean = stripComments(fs.readFileSync(path.join(tokensDir, file), 'utf8'));
    for (const m of clean.matchAll(/([^{}]+)\{([\s\S]*?)\n\}/g)) {
      const decls = [];
      for (const d of m[2].matchAll(/(--[A-Za-z0-9_-]+)\s*:\s*([^;]+);/g)) {
        decls.push({ name: d[1], value: d[2].trim() });
      }
      blocks.push({ file, selector: m[1].trim(), decls });
    }
  }
  return blocks;
}

/** The flat name → value view used to resolve var() chains. First definition wins,
    which matches the closure order (fonts → tokens/*) the compiler uses. */
export function firstValueMap(blocks) {
  const map = new Map();
  for (const b of blocks) {
    for (const d of b.decls) { if (!map.has(d.name)) { map.set(d.name, d.value); } }
  }
  return map;
}

/** Collect declarations from blocks whose selector satisfies `match`. */
export function collect(blocks, match) {
  const out = new Map();
  for (const b of blocks) {
    if (!match(b.selector)) { continue; }
    for (const d of b.decls) { out.set(d.name, d.value); }
  }
  return out;
}

export const isLightRoot = (s) => s === ':root' && !s.includes('dark');
export const isDark = (s) => /\[data-theme=["']?dark/.test(s);

/** Resolve var(--x) chains, honouring the fallback form var(--x, fallback). */
export function resolveVar(value, allValues, depth = 0) {
  if (depth > 8) { return null; }
  const v = String(value).trim();
  const whole = /^var\(\s*(--[A-Za-z0-9_-]+)\s*(?:,\s*([\s\S]+))?\)$/.exec(v);
  if (whole) {
    const next = allValues.get(whole[1]);
    if (next !== undefined) { return resolveVar(next, allValues, depth + 1); }
    return whole[2] ? resolveVar(whole[2], allValues, depth + 1) : null;
  }
  return v;
}

const hex2 = (n) => Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, '0').toUpperCase();

/** Any CSS colour → `#AARRGGBB`, the reference's and color.json's native format. */
export function toArgb(input, allValues) {
  const value = resolveVar(input, allValues);
  if (!value) { return null; }

  const rgba = /^rgba?\(([^)]+)\)$/.exec(value);
  if (rgba) {
    const parts = rgba[1].split(/[\s,/]+/).filter(Boolean);
    if (parts.length < 3) { return null; }
    const [r, g, b] = parts.slice(0, 3).map((p) => (p.endsWith('%') ? parseFloat(p) * 2.55 : parseFloat(p)));
    let a = parts[3] !== undefined
      ? (parts[3].endsWith('%') ? parseFloat(parts[3]) / 100 : parseFloat(parts[3]))
      : 1;
    /* CSS alpha is 0..1; reference values carry float noise (0.8980392218). */
    a = Math.max(0, Math.min(1, a));
    return `#${hex2(a * 255)}${hex2(r)}${hex2(g)}${hex2(b)}`;
  }

  const hex = /^#([0-9a-fA-F]{3,8})$/.exec(value);
  if (hex) {
    let h = hex[1];
    if (h.length === 3) { h = h.split('').map((c) => c + c).join(''); }
    if (h.length === 6) { return `#FF${h.toUpperCase()}`; }
    if (h.length === 8) { return `#${h.toUpperCase()}`; }
    return null;
  }

  if (value === 'transparent') { return '#00000000'; }
  return null;
}

/** A px length → the number, with `calc()` evaluated.
 *  Those results are exactly the numbers a native screen needs
 *  (--harmony-titlebar-layer-normal is calc(12px + 40px) = 52). */
export function toNumber(input, allValues, depth = 0) {
  const value = resolveVar(input, allValues);
  if (!value || depth > 8) { return null; }
  const literal = /^(-?[\d.]+)px$/.exec(value);
  if (literal) { return parseFloat(literal[1]); }
  const calc = /^calc\(([\s\S]+)\)$/.exec(value);
  if (!calc) { return null; }
  let unresolved = false;
  const expr = calc[1]
    .replace(/\s+/g, ' ')
    .replace(/var\(\s*(--[A-Za-z0-9_-]+)\s*\)/g, (whole, ref) => {
      const inner = allValues.get(ref);
      const num = inner === undefined ? null : toNumber(inner, allValues, depth + 1);
      if (num === null) { unresolved = true; return whole; }
      return String(num);
    });
  if (unresolved || !/^[\d\s.+*()/-]+$/.test(expr)) { return null; }
  try {
    const out = Function('"use strict";return (' + expr + ');')();
    return typeof out === 'number' && Number.isFinite(out) ? out : null;
  } catch { return null; }
}

/** `--harmony-font-primary` → `hm_font_primary`. Resource names must be valid
 *  ArkTS identifiers, so hyphens become underscores and a leading digit is escaped. */
export function resourceName(token, prefix = 'hm_') {
  let base = token.replace(/^--/, '').replace(/^harmony-/, '').replace(/[^A-Za-z0-9_]/g, '_');
  if (/^\d/.test(base)) { base = '_' + base; }
  return prefix + base;
}

/** HarmonyOS float.json takes a bare number (vp) or a string with an explicit unit.
 *  The distinction is real: a bare number passed to fontSize is read as fp while the
 *  same number passed to width is read as vp. Emitting the unit removes the
 *  ambiguity at the source instead of relying on the reading API to guess. */
export const unitFor = (token) => (/font-size|font_size/.test(token) ? 'fp' : 'vp');

/** camelCase a resource base name, for the generated ArkTS binding layer. */
export function toCamel(base) {
  return base
    .split('_')
    .filter(Boolean)
    .map((part, i) => (i === 0 ? part.toLowerCase() : part.charAt(0).toUpperCase() + part.slice(1).toLowerCase()))
    .join('');
}

/** The full conversion: every token → { name, argb | number | null, unit }. */
export function convertTokens(blocks, prefix) {
  const allValues = firstValueMap(blocks);
  const light = collect(blocks, isLightRoot);
  const dark = collect(blocks, isDark);

  const colors = new Map();       // name -> #AARRGGBB
  const floats = new Map();       // name -> "52vp"
  const skipped = [];

  for (const [token, raw] of light) {
    /* Skip the reference's LEGACY ALIAS form. It spells the same token with
       underscores (--harmony-font_primary) alongside the canonical hyphenated name
       (--harmony-font-primary), and resourceName() normalises BOTH to hm_font_primary.
       The alias resolves var(--harmony-font-primary) through firstValueMap, i.e. the
       LIGHT definition, so it overwrote the correct dark value: every aliased colour
       in dark/element/color.json held the light value (near-black text on a dark
       background — invisible). 76 tokens were affected. Canonical names lose nothing
       by dropping the aliases, because hyphens become underscores anyway. */
    if (token.includes('_')) { continue; }
    const name = resourceName(token, prefix);
    const argb = toArgb(raw, allValues);
    if (argb) { colors.set(name, argb); continue; }
    const num = toNumber(raw, allValues);
    if (num !== null) { floats.set(name, `${num}${unitFor(token)}`); continue; }
    skipped.push({ token, raw, why: 'not a colour or a px length' });
  }

  const darkColors = new Map();
  for (const [token, raw] of dark) {
    if (token.includes('_')) { continue; }   // legacy aliases — see the note above
    const name = resourceName(token, prefix);
    const argb = toArgb(raw, allValues);
    /* Dark files hold colours only — a dimension is theme-invariant, so it stays in
       base/float.json and must NOT be duplicated into the dark directory. */
    if (argb && colors.has(name)) { darkColors.set(name, argb); }
  }

  return { colors, darkColors, floats, skipped, allValues };
}
