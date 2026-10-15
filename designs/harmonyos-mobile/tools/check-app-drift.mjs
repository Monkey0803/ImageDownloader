#!/usr/bin/env node
/*
 * check-app-drift.mjs — compares a HarmonyOS app's resource files against this
 * design system's tokens and reports where they disagree.
 *
 * Why it exists: every app that hand-port a palette starts identical to the design
 * system and then drifts. This repository already contains a live example — the
 * ImageDownloader app carries font_fourth = #42000000 (alpha 0.26) because it was
 * ported from an older prototype that hard-coded 0.26, while the reference mandates
 * rgba(0,0,0,0.2) = #33000000 (alpha 0.20). Nothing noticed for months; the kind of
 * check this script performs would have caught it the day it was introduced.
 *
 * It also flags a defect that is worse than drift because it is INVISIBLE: an app
 * that redeclares a resource name this HAR already owns. The toolchain only warns
 * ("Warning: 'hm_brand' conflict, first declared.") and the app's value is silently
 * dropped — so the app appears rethemed and is not. That was established by building
 * such a case, not by reading documentation.
 *
 * Usage:
 *   node tools/check-app-drift.mjs --app <appProjectRoot> [--prefix hm_] [--allow-drift]
 *                                   [--json]
 *
 * Exit 0 when the app matches, 1 when anything drifts.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readTokenBlocks, convertTokens, resourceName } from './lib/ohos-tokens.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DS = path.resolve(HERE, '..');

const argv = process.argv.slice(2);
const option = (n, d) => {
  const i = argv.indexOf(n);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : d;
};
const flag = (n) => argv.includes(n);

const APP = option('--app', null);
const PREFIX = option('--prefix', 'hm_');
const AS_JSON = flag('--json');

if (!APP) {
  console.error('check-app-drift: --app <appProjectRoot> is required');
  console.error('  e.g. node tools/check-app-drift.mjs --app ../../../entry');
  process.exit(2);
}
const APP_ROOT = path.resolve(APP);

/* ---------------------------------------------------- the token side (truth) */
const tokensDir = path.join(DS, 'tokens');
if (!fs.existsSync(tokensDir)) {
  console.error(`check-app-drift: no tokens/ at ${DS}`);
  process.exit(2);
}
const { colors, darkColors, floats, allValues } = convertTokens(readTokenBlocks(tokensDir), PREFIX);

/* ------------------------------------------------------- the app's resources */
/** Read the `color` / `float` arrays of one element JSON, tolerating absence. */
function readElements(file, key) {
  if (!fs.existsSync(file)) { return null; }
  try {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    const list = parsed[key];
    if (!Array.isArray(list)) { return null; }
    return new Map(list.map((i) => [i.name, i.value]));
  } catch (e) {
    return { error: e.message };
  }
}

/* element JSON lives under <module>/src/main/resources/<base|dark>/element/.
   Accept both "point at the module" and "point at the app root". */
/** A module's declared type, from src/main/module.json5 ("entry" | "feature" | "har"
 *  | "shared"). Missing file -> assume app-side, which is the safe default for this
 *  check (a false positive is visible, a false negative is not). */
function moduleType(modRoot) {
  const file = path.join(modRoot, 'src', 'main', 'module.json5');
  if (!fs.existsSync(file)) { return 'unknown'; }
  const m = /"type"\s*:\s*"([a-z]+)"/.exec(fs.readFileSync(file, 'utf8'));
  return m ? m[1] : 'unknown';
}

function findModules(root) {
  const candidates = [];
  const direct = path.join(root, 'src', 'main', 'resources');
  if (fs.existsSync(direct)) { candidates.push(root); }
  for (const rel of ['entry', '.']) {
    const base = path.join(root, rel);
    if (!fs.existsSync(base)) { continue; }
    for (const e of fs.readdirSync(base, { withFileTypes: true })) {
      if (!e.isDirectory()) { continue; }
      if (fs.existsSync(path.join(base, e.name, 'src', 'main', 'resources'))) {
        candidates.push(path.join(base, e.name));
      }
    }
  }
  /* Skip library modules. A HAR has src/main/resources too, and its resources ARE
     the reference — comparing the token HAR against itself produced a wall of bogus
     "declared by the token HAR" findings the first time this ran. */
  return candidates.filter((c) => {
    const type = moduleType(c);
    return type !== 'har' && type !== 'shared';
  });
}

const modules = findModules(APP_ROOT);
if (modules.length === 0) {
  console.error(`check-app-drift: found no module with src/main/resources under ${APP_ROOT}`);
  process.exit(2);
}

const findings = [];
const notes = [];

/** Both `#RRGGBB` and `#AARRGGBB` name the same colour (`#RRGGBB` means fully
 *  opaque). The reference project uses the short form, this system emits the ARGB
 *  form the platform prefers, so comparing raw strings reported ~10 phantom drifts.
 *  Normalise before comparing, and keep reporting the real difference (alpha). */
function normalise(v) {
  const m = /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.exec(String(v));
  if (!m) { return String(v); }
  return m[1].length === 6 ? '#' + 'FF' + m[1].toUpperCase() : '#' + m[1].toUpperCase();
}

/** Compare one app map against its token counterpart, via the <prefix><name> rule. */
function compare(label, appMap, tokenMap, kind) {
  if (!appMap) { notes.push(`${label}: absent`); return; }
  if (appMap.error) { findings.push({ level: 'error', label, message: `unreadable JSON: ${appMap.error}` }); return; }

  let matched = 0;
  for (const [name, value] of appMap) {
    /* An app name is expected to correspond to a token by the prefix rule:
       `font_fourth` <-> `hm_font_fourth` (or the same name when prefix is empty). */
    const tokenName = name.startsWith(PREFIX) ? name : resourceName('--harmony-' + name, PREFIX);
    const owned = tokenMap.has(tokenName);
    if (!owned) { continue; }
    matched += 1;
    const expected = tokenMap.get(tokenName);
    if (normalise(expected) !== normalise(value)) {
      findings.push({
        level: 'error',
        label,
        message: `${name} = ${value}, but the design system says ${tokenName} = ${expected}` +
                 (kind === 'color' ? `  (alpha differs: ${alphaOf(value)} vs ${alphaOf(expected)})` : ''),
      });
    }
  }
  notes.push(`${label}: ${appMap.size} declared, ${matched} matched a token by the prefix rule`);
}

const hexAlpha = (v) => {
  const m = /^#([0-9a-fA-F]{8})$/.exec(String(v));
  return m ? (parseInt(m[1].slice(0, 2), 16) / 255).toFixed(3) : 'n/a';
};
function alphaOf(v) { return hexAlpha(v); }

for (const mod of modules) {
  const res = path.join(mod, 'src', 'main', 'resources');
  compare('base/element/color.json', readElements(path.join(res, 'base', 'element', 'color.json'), 'color'), colors, 'color');
  compare('dark/element/color.json', readElements(path.join(res, 'dark', 'element', 'color.json'), 'color'), darkColors, 'color');
  compare('base/element/float.json', readElements(path.join(res, 'base', 'element', 'float.json'), 'float'), floats, 'float');
}

/* An app name that the HAR owns is a silent no-op: the HAR wins and the app's
   declaration is dropped. Report it as an error, because the app looks rethemed
   and is not. (Names without the prefix are the app's own and are left alone.) */
for (const mod of modules) {
  const res = path.join(mod, 'src', 'main', 'resources');
  for (const [file, key, tokenMap] of [
    [path.join(res, 'base', 'element', 'color.json'), 'color', colors],
    [path.join(res, 'base', 'element', 'float.json'), 'float', floats],
  ]) {
    const appMap = readElements(file, key);
    if (!appMap || appMap.error) { continue; }
    for (const name of appMap.keys()) {
      if (tokenMap.has(name)) {
        findings.push({
          level: 'error',
          label: path.relative(APP_ROOT, file),
          message: `${name} is also declared by the token HAR — the HAR is first, so this ` +
                   `declaration is silently IGNORED (the toolchain only warns). Rename it or remove it.`,
        });
      }
    }
  }
}

/* ------------------------------------------------------------------ report */
const relApp = path.relative(DS, APP_ROOT) || APP_ROOT;
if (AS_JSON) {
  console.log(JSON.stringify({ app: APP_ROOT, prefix: PREFIX, findings, notes }, null, 2));
} else {
  console.log(`check-app-drift · app=${relApp} · prefix="${PREFIX}"`);
  console.log(`  tokens: ${colors.size} colour(s) · ${darkColors.size} dark · ${floats.size} dimension(s)\n`);
  for (const n of notes) { console.log(`  · ${n}`); }
  if (findings.length === 0) {
    console.log('\n  ✓ no drift — the app agrees with the design system. ✅');
  } else {
    console.log(`\n✗ ${findings.length} finding(s):\n`);
    for (const f of findings) { console.log(`    [${f.level}] ${f.label}: ${f.message}`); }
  }
}

process.exit(findings.length === 0 ? 0 : 1);
