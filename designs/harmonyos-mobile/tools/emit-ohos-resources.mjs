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
/* An explicitly empty value must be honoured: `--prefix ""` is a legitimate
   request for un-prefixed resource names, and `"" || fallback` would silently
   ignore it. Check for the argument's presence, not its truthiness. */
const option = (n, d) => {
  const i = argv.indexOf(n);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : d;
};

const OUT = path.resolve(option('--out', path.join(DS, 'ohos-resources', 'entry', 'src', 'main', 'resources')));
const PREFIX = option('--prefix', 'hm_');
const DRY = flag('--dry-run');
const FORCE = flag('--force');

/* ------------------------------------------------- parsing + conversion
   Shared with build-token-har.mjs so the two cannot disagree about how a token
   becomes a resource value. */
import { readTokenBlocks, convertTokens } from './lib/ohos-tokens.mjs';

const TOKENS_DIR = path.join(DS, 'tokens');
if (!fs.existsSync(TOKENS_DIR)) {
  console.error(`emit-ohos-resources: no tokens/ directory at ${DS}`);
  process.exit(2);
}

const blocks = readTokenBlocks(TOKENS_DIR);
const { colors, darkColors, floats, skipped } = convertTokens(blocks, PREFIX);

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
const targets = [
  { file: path.join(OUT, 'base', 'element', 'color.json'), entries: colors, label: 'base/element/color.json', key: 'color' },
  { file: path.join(OUT, 'dark', 'element', 'color.json'), entries: darkColors, label: 'dark/element/color.json', key: 'color' },
  { file: path.join(OUT, 'base', 'element', 'float.json'), entries: floats, label: 'base/element/float.json', key: 'float' },
];

console.log(`emit-ohos-resources · out=${path.relative(DS, OUT) || OUT} · prefix="${PREFIX}"${DRY ? ' · DRY RUN' : ''}`);
console.log(`  tokens: ${colors.size} colour(s) · ${floats.size} dimension(s) · ${darkColors.size} dark override(s)\n`);

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
  for (const sk of skipped.slice(0, 10)) { console.log(`    ${sk.token} = ${sk.raw} (${sk.why})`); }
  if (skipped.length > 10) { console.log(`    … and ${skipped.length - 10} more`); }
}

console.log(`\n  note: float.json values carry an explicit unit (vp for dimensions, fp for font`);
console.log(`        sizes), matching the convention already used in this project.`);
if (!FORCE) { console.log(`  note: existing names are preserved, never dropped (use --force to replace).`); }

process.exit(failed ? 1 : 0);
