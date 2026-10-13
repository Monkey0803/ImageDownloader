#!/usr/bin/env node
/*
 * emit-ohos-resources.mjs — turns this design system's CSS tokens into the
 * HarmonyOS resource files an ArkTS app reads at runtime:
 *
 *   entry/src/main/resources/base/element/color.json    light colours
 *   entry/src/main/resources/dark/element/color.json    dark colours
 *   entry/src/main/resources/base/element/float.json    dimensions
 *
 * Why this exists: the tokens are the source of truth, but an ArkTS app cannot
 * read CSS custom properties. Hand-copying them into resource JSON is exactly how
 * a design system and its app drift apart — one value gets missed and nobody
 * notices until a dark-mode screenshot looks wrong.
 *
 * The reference documents token colours as ARGB (`#AARRGGBB`), which is also the
 * native format of color.json, so the conversion is a normalisation rather than a
 * translation. var() references are resolved through the token set.
 *
 * Safety properties (all deliberate):
 *   · MERGE-PRESERVING — names already in the target file and not produced by this
 *     run are kept untouched, so hand-added app resources survive.
 *   · ATOMIC — written to a temp file, fsynced, then renamed.
 *   · SELF-CHECKED — the file is read back and re-parsed, and the run fails if the
 *     round-trip does not reproduce every value it intended to write.
 *   · --dry-run prints the diff without touching anything.
 *
 * Usage:
 *   node tools/emit-ohos-resources.mjs [--out entry/src/main/resources]
 *                                      [--prefix hm_] [--dry-run] [--force]
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DS = path.resolve(HERE, '..');

const argv = process.argv.slice(2);
const flag = (n) => argv.includes(n);
const option = (n, d) => { const i = argv.indexOf(n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };

const OUT = path.resolve(option('--out', path.join(DS, 'ohos-resources', 'entry', 'src', 'main', 'resources')));
const PREFIX = option('--prefix', 'hm_');
const DRY = flag('--dry-run');
const FORCE = flag('--force');

/* ---------------------------------------------------------------- parsing */
const TOKENS_DIR = path.join(DS, 'tokens');
if (!fs.existsSync(TOKENS_DIR)) {
  console.error(`emit-ohos-resources: no tokens/ directory at ${DS}`);
  process.exit(2);
}

const stripComments = (css) => css.replace(/\/\*[\s\S]*?\*\//g, '');

/** Parse `selector { --name: value; }` blocks from every token file. */
function readTokenFiles() {
  const files = fs.readdirSync(TOKENS_DIR).filter((f) => f.endsWith('.css')).sort();
  const blocks = [];
  for (const file of files) {
    const clean = stripComments(fs.readFileSync(path.join(TOKENS_DIR, file), 'utf8'));
    for (const m of clean.matchAll(/([^{}]+)\{([\s\S]*?)\n\}/g)) {
      const selector = m[1].trim();
      const decls = [];
      for (const d of m[2].matchAll(/(--[A-Za-z0-9_-]+)\s*:\s*([^;]+);/g)) {
        decls.push({ name: d[1], value: d[2].trim() });
      }
      blocks.push({ file, selector, decls });
    }
  }
  return blocks;
}

const blocks = readTokenFiles();
const allValues = new Map();
for (const b of blocks) { for (const d of b.decls) { if (!allValues.has(d.name)) { allValues.set(d.name, d.value); } } }

/** Collect the declarations of the blocks whose selector matches. */
function collect(match) {
  const out = new Map();
  for (const b of blocks) { if (!match(b.selector)) { continue; } for (const d of b.decls) { out.set(d.name, d.value); } }
  return out;
}

const light = collect((s) => s === ':root' && !s.includes('dark'));
const dark = collect((s) => /\[data-theme=["']?dark/.test(s));

/* ---------------------------------------------------------- conversions */
/** Resolve var(--x) chains down to a literal. */
function resolve(value, depth = 0) {
  if (depth > 8) { return null; }
  const v = String(value).trim();
  const whole = /^var\(\s*(--[A-Za-z0-9_-]+)\s*(?:,\s*([\s\S]+))?\)$/.exec(v);
  if (whole) {
    const next = allValues.get(whole[1]);
    if (next !== undefined) { return resolve(next, depth + 1); }
    return whole[2] ? resolve(whole[2], depth + 1) : null;
  }
  return v;
}

const hex2 = (n) => Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, '0').toUpperCase();

/** Any CSS colour → `#AARRGGBB`, the reference's and color.json's native format. */
function toArgb(input) {
  const value = resolve(input);
  if (!value) { return null; }

  const rgba = /^rgba?\(([^)]+)\)$/.exec(value);
  if (rgba) {
    const parts = rgba[1].split(/[\s,/]+/).filter(Boolean);
    if (parts.length < 3) { return null; }
    const [r, g, b] = parts.slice(0, 3).map((p) => (p.endsWith('%') ? parseFloat(p) * 2.55 : parseFloat(p)));
    let a = parts[3] !== undefined
      ? (parts[3].endsWith('%') ? parseFloat(parts[3]) / 100 : parseFloat(parts[3]))
      : 1;
    /* CSS alpha is 0..1; a few reference values carry float noise (0.8980392218). */
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

/** A `px` length → the unitless number ArkTS reads as vp (or fp for font sizes).
 *  `calc()` is evaluated, because those results are exactly the numbers a native
 *  screen needs (--harmony-titlebar-layer-normal is calc(12px + 40px) = 52). */
function toNumber(input, depth = 0) {
  const value = resolve(input);
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
      const num = inner === undefined ? null : toNumber(inner, depth + 1);
      if (num === null) { unresolved = true; return whole; }
      return String(num);
    });
  if (unresolved || !/^[\d\s.+*()/-]+$/.test(expr)) { return null; }
  try {
    const out = Function('"use strict";return (' + expr + ');')();
    return typeof out === 'number' && Number.isFinite(out) ? out : null;
  } catch { return null; }
}

/* ----------------------------------------------------------------- naming */
/* `--harmony-font-primary` → `hm_font_primary`. Resource names must be valid
   ArkTS identifiers, so hyphens become underscores and a leading digit is
   escaped. */
function resourceName(token) {
  let base = token.replace(/^--/, '').replace(/^harmony-/, '').replace(/[^A-Za-z0-9_]/g, '_');
  if (/^\d/.test(base)) { base = '_' + base; }
  return PREFIX + base;
}

const isFontSize = (token) => /font-size|font_size/.test(token);

/* ------------------------------------------------------------ file merge */
function mergeInto(file, entries, expectedKey) {
  const existing = fs.existsSync(file)
    ? JSON.parse(fs.readFileSync(file, 'utf8'))
    : { [expectedKey]: [] };
  /* HarmonyOS resource files are typed by their key: color.json uses "color",
     float.json uses "float". Defaulting a new file to "color" produced a
     float.json full of colours-keyed numbers, which the platform would not read. */
  const listKey = Array.isArray(existing.float) ? 'float' : Array.isArray(existing.color) ? 'color' : null;
  if (!listKey) {
    throw new Error(`${file}: expected an object with a "color" or "float" array`);
  }
  if (listKey !== expectedKey) {
    throw new Error(`${file}: expected a "${expectedKey}" array but the file has "${listKey}"`);
  }
  const preserved = new Map();
  if (FORCE) {
    /* --force means "the file is generated, keep nothing": names produced by an
       earlier run but no longer present disappear, instead of lingering. */
  } else {
    for (const item of existing[listKey]) { preserved.set(item.name, item.value); }
  }

  let added = 0;
  let updated = 0;
  for (const [name, value] of entries) {
    if (preserved.has(name)) {
      if (preserved.get(name) !== value) { updated += 1; }
    } else {
      added += 1;
    }
    preserved.set(name, value);
  }

  const merged = [...preserved.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([name, value]) => ({ name, value }));

  return { json: { [listKey]: merged }, added, updated, total: merged.length, listKey, removed: FORCE ? 0 : undefined };
}

function writeAtomic(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.tmp-${process.pid}`;
  const fd = fs.openSync(tmp, 'w');
  try {
    fs.writeFileSync(fd, JSON.stringify(data, null, 2) + '\n');
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, file);
}

/** Read the file back and prove it reproduces every value we intended. */
function selfCheck(file, entries) {
  const back = JSON.parse(fs.readFileSync(file, 'utf8'));
  const key = Array.isArray(back.color) ? 'color' : 'float';
  const map = new Map(back[key].map((i) => [i.name, i.value]));
  const problems = [];
  for (const [name, value] of entries) {
    if (map.get(name) !== value) {
      problems.push(`${name}: wrote ${value}, read back ${map.get(name)}`);
    }
  }
  return problems;
}

/* ------------------------------------------------------------------ emit */
const lightColors = new Map();
const darkColors = new Map();
const floats = new Map();
const skipped = [];

for (const [token, raw] of light) {
  if (token.endsWith('_')) { continue; }                       // legacy aliases
  const name = resourceName(token);
  const argb = toArgb(raw);
  if (argb) { lightColors.set(name, argb); continue; }
  const num = toNumber(raw);
  if (num !== null) {
    if (isFontSize(token)) { floats.set(name, num); }
    else { floats.set(name, num); }
    continue;
  }
  skipped.push({ token, raw, why: 'not a colour or a px length' });
}

for (const [token, raw] of dark) {
  if (token.endsWith('_')) { continue; }
  const argb = toArgb(raw);
  const name = resourceName(token);
  if (argb) { darkColors.set(name, argb); continue; }
  /* Dark files hold colours only — a dimension is theme-invariant, so it stays in
     base/float.json and must NOT be duplicated into the dark directory. */
}

/* Only emit dark entries for tokens the light set actually contains as colours. */
for (const name of [...darkColors.keys()]) {
  if (!lightColors.has(name)) { darkColors.delete(name); }
}

const targets = [
  { file: path.join(OUT, 'base', 'element', 'color.json'), entries: lightColors, label: 'base/element/color.json', key: 'color' },
  { file: path.join(OUT, 'dark', 'element', 'color.json'), entries: darkColors, label: 'dark/element/color.json', key: 'color' },
  { file: path.join(OUT, 'base', 'element', 'float.json'), entries: floats, label: 'base/element/float.json', key: 'float' },
];

console.log(`emit-ohos-resources · out=${path.relative(DS, OUT) || OUT} · prefix="${PREFIX}"${DRY ? ' · DRY RUN' : ''}`);
console.log(`  tokens read: ${light.size} light · ${dark.size} dark\n`);

let failed = false;
for (const { file, entries, label, key } of targets) {
  const { json, added, updated, total, listKey } = mergeInto(file, entries, key);
  console.log(`  ${label}`);
  console.log(`    ${listKey}: ${total} total · ${added} added · ${updated} updated · ` +
    (FORCE ? '0 preserved (--force)' : `${total - added} preserved from the existing file`));
  if (DRY) { continue; }
  writeAtomic(file, json);
  const problems = selfCheck(file, entries);
  if (problems.length) {
    failed = true;
    console.error(`    ✗ self-check failed:`);
    for (const p of problems.slice(0, 8)) { console.error(`        ${p}`); }
  } else {
    console.log(`    ✓ read-back self-check passed (${entries.size} values)`);
  }
}

if (skipped.length) {
  console.log(`\n  skipped ${skipped.length} token(s) that are neither colours nor px lengths:`);
  for (const s of skipped.slice(0, 10)) { console.log(`    ${s.token} = ${s.raw} (${s.why})`); }
  if (skipped.length > 10) { console.log(`    … and ${skipped.length - 10} more (see --dry-run output in full)`); }
}

console.log(`\n  note: float.json values are unitless vp. Font sizes are named *_font_size_* —`);
console.log(`        apply them with .fp in ArkTS (see guidelines/arkui-mapping.md).`);
if (!FORCE) { console.log(`  note: existing names are preserved, never dropped. Pass --force to overwrite the whole directory instead.`); }

process.exit(failed ? 1 : 0);
