#!/usr/bin/env node
/*
 * verify-harmony.mjs — conformance checks for this HarmonyOS design system.
 *
 * Every rule below replays a mistake that was actually made while building the
 * system, so a failing rule is a bug report, not a style opinion. Rules that can
 * be checked statically are checked statically; the geometry that needs a real
 * layout engine is verified by guidelines/geometry-anchors.html instead (it
 * measures itself in the browser and prints ✓/✗ per anchor).
 *
 *   R1  every var(--x) used in the CSS closure is defined in the closure
 *   R2  styles.css contains only @import statements
 *   R3  every component .jsx has a sibling .d.ts
 *   R4  no component imports from "react" / "react-dom"  (the compiler strips them)
 *   R5  every .d.ts declares the function its .jsx exports
 *   R6  the mandatory geometry tokens hold their spec values
 *   R7  data-hm-light is only on interactive elements
 *   R8  every component .jsx has a sibling .prompt.md
 *   R9  every url() in the CSS closure exists on disk
 *   R10 no !important outside the reduced-motion block
 *   R11 every <Icon name="…"> literal exists in the generated icon map
  R12 no component CSS redefines a system token
 *
 * Usage:
 *   node tools/verify-harmony.mjs [--root <dir>] [--json] [--quiet]
 * Exit code 0 when clean, 1 when any rule fails.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DS = path.resolve(HERE, '..');

const argv = process.argv.slice(2);
const flag = (name) => argv.includes(name);
const option = (name, fallback) => {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
};

const ROOT = path.resolve(option('--root', DS));
const AS_JSON = flag('--json');
const QUIET = flag('--quiet');

/* Custom properties set at runtime by JS, not by CSS. Each entry states who sets
   it — an entry without such a note would be hiding a real dangling reference. */
const RUNTIME_SET = new Map([
  ['--harmony-light-x', 'SizeFrame sets it on pointerdown for 沉浸光感'],
  ['--harmony-light-y', 'SizeFrame sets it on pointerdown for 沉浸光感'],
]);

const read = (p) => { try { return fs.readFileSync(p, 'utf8'); } catch { return null; } };
const rel = (p) => path.relative(ROOT, p).split(path.sep).join('/');
const posix = (p) => p.split(path.sep).join('/');

/** Strip /* … *\/ so rules never match inside a comment.
 *  Learned the hard way: an annotator that matched inside comments terminated
 *  the comment early and silently killed the rule that followed it. */
const stripComments = (css) => css.replace(/\/\*[\s\S]*?\*\//g, '');

const failures = [];
const notes = [];
const fail = (rule, file, line, message) => failures.push({ rule, file, line, message });

/* ------------------------------------------------------------ CSS closure */
function cssClosure(entry) {
  const seen = new Map();
  const order = [];
  const visit = (abs) => {
    if (seen.has(abs)) { return; }
    const src = read(abs);
    if (src === null) { return; }
    seen.set(abs, src);
    order.push(abs);
    const clean = stripComments(src);
    for (const m of clean.matchAll(/@import\s+(?:url\()?["']([^"')]+)["']\)?/g)) {
      visit(path.resolve(path.dirname(abs), m[1]));
    }
  };
  visit(entry);
  return order.map((abs) => ({ abs, src: seen.get(abs), clean: stripComments(seen.get(abs)) }));
}

const entryCss = path.join(ROOT, 'styles.css');
if (!fs.existsSync(entryCss)) {
  console.error(`verify-harmony: no styles.css at ${ROOT}`);
  process.exit(2);
}
const closure = cssClosure(entryCss);

const lineOf = (text, index) => text.slice(0, index).split('\n').length;
const relFrom = (abs) => posix(path.relative(ROOT, abs));

/* ------------------------------------------------------------------ R1 */
{
  const defined = new Set();
  for (const { clean } of closure) {
    for (const m of clean.matchAll(/(--[A-Za-z0-9_-]+)\s*:/g)) { defined.add(m[1]); }
  }
  for (const { abs, clean } of closure) {
    for (const m of clean.matchAll(/var\(\s*(--[A-Za-z0-9_-]+)\s*(,)?/g)) {
      const name = m[1];
      /* A fallback makes the reference self-sufficient: the templates expose
         consumer-set parameters this way (e.g. var(--harmony-divider-length, 100%)). */
      if (m[2] === ',' || defined.has(name) || RUNTIME_SET.has(name)) { continue; }
      fail('R1', relFrom(abs), lineOf(clean, m.index),
        `var(${name}) has no definition in the CSS closure`);
    }
  }
}

/* ------------------------------------------------------------------ R2 */
{
  const src = read(entryCss);
  const clean = stripComments(src);
  const offending = clean
    .split('\n')
    .map((line, i) => ({ line: line.trim(), n: i + 1 }))
    .filter(({ line }) => line && !line.startsWith('@import'));
  for (const { line, n } of offending) {
    fail('R2', 'styles.css', n,
      `styles.css must contain only @import statements; found "${line.slice(0, 60)}"`);
  }
  if (offending.length === 0) { notes.push('R2 styles.css is import-only'); }
}

/* --------------------------------------------------------- components R3–R8 */
const componentsDir = path.join(ROOT, 'components');
const jsxFiles = [];
if (fs.existsSync(componentsDir)) {
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const abs = path.join(dir, entry.name);
      if (entry.isDirectory()) { walk(abs); }
      else if (entry.name.endsWith('.jsx') || entry.name.endsWith('.tsx')) { jsxFiles.push(abs); }
    }
  };
  walk(componentsDir);
}

const COMPONENT_DEPS = new Set(['IconMap.jsx']);   // generated data module, not a component

for (const abs of jsxFiles) {
  const base = abs.replace(/\.(jsx|tsx)$/, '');
  const name = path.basename(base);
  const src = read(abs);
  const clean = stripComments(src);
  const isComponent = !COMPONENT_DEPS.has(path.basename(abs));

  /* R3 / R5 / R8 */
  if (isComponent) {
    const dts = base + '.d.ts';
    if (!fs.existsSync(dts)) {
      fail('R3', relFrom(abs), 1, `no sibling ${name}.d.ts`);
    } else {
      const declared = read(dts);
      if (!new RegExp(`declare function\\s+${name}\\b`).test(declared)) {
        const n = lineOf(declared, 0);
        fail('R5', relFrom(dts), n, `${name}.d.ts does not declare function ${name}`);
      }
    }
    if (!fs.existsSync(base + '.prompt.md')) {
      fail('R8', relFrom(abs), 1, `no sibling ${name}.prompt.md`);
    }
  }

  /* R4 */
  for (const m of clean.matchAll(/import\s+[^;]*from\s+["'](react|react-dom)["']/g)) {
    fail('R4', relFrom(abs), lineOf(clean, m.index),
      `imports from "${m[1]}" — the compiler strips it, so this throws at runtime. Use the global React (e.g. React.useState).`);
  }

  /* R7 — data-hm-light must sit on something interactive */
  for (const m of clean.matchAll(/<([a-zA-Z][\w.]*)\b([^>]*?\/?>)/g)) {
    const tag = m[1];
    const attrs = m[2];
    if (!/data-hm-light(?![\w-])/.test(attrs)) { continue; }
    /* Interactivity, not the tag name: a search field is a div that handles taps,
       and data-hm-light-effect on the frame is a different attribute entirely. */
    const interactive = tag === 'button' || tag === 'a' || tag === 'input'
      || /role\s*=\s*["'](switch|button|tab|checkbox|radio)["']/.test(attrs)
      || /tabIndex/.test(attrs)
      || /onClick/.test(attrs);
    if (!interactive) {
      fail('R7', relFrom(abs), lineOf(clean, m.index),
        `data-hm-light on <${tag}> — the light effect is for focal, interactive components only`);
    }
  }
}

/* ------------------------------------------------------------------ R6 */
{
  const MANDATORY = new Map([
    ['--harmony-titlebar-gap', 8],
    ['--harmony-titlebar-layer-normal', 52],
    ['--harmony-tabbar-h', 56],
    ['--harmony-tabbar-top-pad', 16],
    ['--harmony-tabbar-indicator', 28],
  ]);

  /* Every token value in the closure, so a calc is EVALUATED rather than
     text-compared. `calc(12px + 40px)` is a better spelling of 52px than the
     literal, not a violation — a literal-only rule flagged it. */
  const values = new Map();
  for (const { clean } of closure) {
    for (const m of clean.matchAll(/(--[A-Za-z0-9_-]+)\s*:\s*([^;]+);/g)) {
      values.set(m[1], m[2].trim());
    }
  }
  const px = (value, depth = 0) => {
    if (depth > 8 || value == null) { return null; }
    const v = String(value).trim();
    const literal = /^(-?[\d.]+)px$/.exec(v);
    if (literal) { return parseFloat(literal[1]); }
    const calc = /^calc\(([\s\S]+)\)$/.exec(v);
    if (!calc) { return null; }
    let expr = calc[1].replace(/\s+/g, ' ');
    /* Substitute the WHOLE var(...) call, not just the name: replacing only
       `--x` inside `var(--x)` leaves `var(12)`, which then fails the guard. */
    let unresolved = false;
    expr = expr.replace(/var\(\s*(--[A-Za-z0-9_-]+)\s*\)/g, (whole, ref) => {
      const resolved = px(values.get(ref), depth + 1);
      if (resolved === null) { unresolved = true; return whole; }
      return String(resolved);
    });
    if (unresolved) { return null; }
    if (!/^[\d\s.+*()/-]+$/.test(expr)) { return null; }
    try {
      const out = Function('"use strict";return (' + expr + ');')();
      return typeof out === 'number' && Number.isFinite(out) ? out : null;
    } catch { return null; }
  };

  for (const [name, want] of MANDATORY) {
    const resolved = px(values.get(name));
    if (resolved === null) {
      const owner = closure.find(({ clean }) => new RegExp(name + '\\s*:').test(clean));
      fail('R6', owner ? relFrom(owner.abs) : 'tokens/', 1,
        `${name} is "${values.get(name) ?? 'undefined'}", which does not resolve to a length (the reference mandates ${want}px)`);
    } else if (Math.abs(resolved - want) > 0.01) {
      const owner = closure.find(({ clean }) => new RegExp(name + '\\s*:').test(clean));
      fail('R6', owner ? relFrom(owner.abs) : 'tokens/', 1,
        `${name} resolves to ${resolved}px, the reference mandates ${want}px`);
    }
  }
  notes.push('R6 geometry anchors resolve: ' + [...MANDATORY].map(([n, w]) => `${n}=${px(values.get(n))}(want ${w})`).join(' · '));
}

/* ----------------------------------------------------------------- R12 */
{
  const system = new Set();
  const tokensDir = path.join(ROOT, 'tokens');
  if (fs.existsSync(tokensDir)) {
    for (const f of fs.readdirSync(tokensDir)) {
      if (!f.endsWith('.css')) { continue; }
      for (const m of stripComments(read(path.join(tokensDir, f))).matchAll(/(--[A-Za-z0-9_-]+)\s*:/g)) {
        system.add(m[1]);
      }
    }
  }
  for (const { abs, clean } of closure) {
    if (!relFrom(abs).startsWith('components/')) { continue; }
    for (const m of clean.matchAll(/(--[A-Za-z0-9_-]+)\s*:\s*[^;]+;/g)) {
      if (!system.has(m[1])) { continue; }
      fail('R12', relFrom(abs), lineOf(clean, m.index),
        `component CSS redefines the system token ${m[1]} — it is imported last, so this silently overrides the token layer`);
    }
  }
}

/* ------------------------------------------------------------------ R9 */
for (const { abs, clean } of closure) {
  for (const m of clean.matchAll(/url\(\s*["']?([^"')]+)["']?\s*\)/g)) {
    const href = m[1].trim();
    if (/^(data:|https?:|\/\/|#)/.test(href)) { continue; }
    const target = path.resolve(path.dirname(abs), href);
    if (!fs.existsSync(target)) {
      fail('R9', relFrom(abs), lineOf(clean, m.index), `url("${href}") does not exist`);
    }
  }
}

/* ----------------------------------------------------------------- R10 */
/* The reduced-motion block is the one sanctioned use. */
for (const { abs, clean } of closure) {
  const guarded = new Set();
  for (const m of clean.matchAll(/@media\s*\(prefers-reduced-motion[^{]*\{([\s\S]*?)\n\}/g)) {
    for (let i = 0; i < clean.length; i += 1) {
      if (clean.startsWith(m[1], i)) { guarded.add(i); break; }
    }
  }
  for (const m of clean.matchAll(/!important/g)) {
    const inGuard = [...guarded].some((start) => m.index >= start && m.index <= start + 400);
    if (!inGuard) {
      fail('R10', relFrom(abs), lineOf(clean, m.index),
        '!important outside the prefers-reduced-motion block');
    }
  }
}

/* ----------------------------------------------------------------- R11 */
{
  const mapFile = path.join(componentsDir, 'controls', 'IconMap.jsx');
  const mapSrc = read(mapFile);
  if (mapSrc) {
    const known = new Set([...mapSrc.matchAll(/"([a-z0-9_]+)"\s*:\s*\{/g)].map((m) => m[1]));
    for (const abs of jsxFiles) {
      const clean = stripComments(read(abs));
      for (const m of clean.matchAll(/<Icon\b[^>]*?\bname=\{?["']([a-z0-9_]+)["']/g)) {
        if (!known.has(m[1])) {
          fail('R11', relFrom(abs), lineOf(clean, m.index),
            `Icon name "${m[1]}" is not in the generated map — add it to tools/gen-icon-map.mjs, never draw an SVG`);
        }
      }
      for (const m of clean.matchAll(/glyph:\s*["']([a-z0-9_]+)["']/g)) {
        if (!known.has(m[1])) {
          fail('R11', relFrom(abs), lineOf(clean, m.index),
            `glyph "${m[1]}" is not in the generated map`);
        }
      }
    }
  }
}

/* ----------------------------------------------------------------- report */
const RULE_TITLES = {
  R1: 'dangling var() reference',
  R2: 'styles.css must be import-only',
  R3: 'component has no .d.ts',
  R4: 'react import (stripped by the compiler)',
  R5: '.d.ts does not declare the component',
  R6: 'mandatory geometry value changed',
  R7: 'light effect on a non-interactive element',
  R8: 'component has no .prompt.md',
  R9: 'referenced asset missing',
  R10: 'stray !important',
  R11: 'icon name not in the generated map',
  R12: 'component redefines a system token',
};

if (AS_JSON) {
  console.log(JSON.stringify({ root: ROOT, failures, notes }, null, 2));
} else {
  const byRule = new Map();
  for (const f of failures) {
    if (!byRule.has(f.rule)) { byRule.set(f.rule, []); }
    byRule.get(f.rule).push(f);
  }
  if (!QUIET) {
    console.log(`verify-harmony · ${relFrom(ROOT) || '.'}`);
    console.log(`  css closure: ${closure.length} file(s) · components: ${jsxFiles.length} file(s)\n`);
  }
  for (const [rule, list] of [...byRule].sort()) {
    console.log(`✗ ${rule} ${RULE_TITLES[rule] || ''} — ${list.length}`);
    for (const f of list) { console.log(`    ${f.file}:${f.line}  ${f.message}`); }
  }
  if (failures.length === 0) {
    console.log('No issues — clean. ✅');
    if (!QUIET) {
      for (const n of notes) { console.log(`  · ${n}`); }
    }
  } else {
    console.log(`\n${failures.length} failure(s) across ${byRule.size} rule(s).`);
  }
}

process.exit(failures.length === 0 ? 0 : 1);
