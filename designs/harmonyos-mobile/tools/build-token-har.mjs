#!/usr/bin/env node
/*
 * build-token-har.mjs — turns this design system's tokens into a HarmonyOS HAR
 * (HarmonyOS Archive) that every app depends on, instead of each app receiving a
 * copy of the values.
 *
 * The problem it solves: without a HAR, adding an app means running the emitter
 * against that app's resources AND hand-writing its Tokens.ets binding class. That
 * cost is linear in the number of apps, and it drifts — a real example is already in
 * this repo, where the app carries font_fourth = #42000000 (alpha 0.26) because it
 * was hand-ported from an older prototype that had that value, while the reference
 * mandates rgba(0,0,0,0.2) = #33000000. Generated bindings cannot drift.
 *
 * Output (every file generated — nothing here is hand-edited):
 *
 *   harmonyos-tokens/
 *   ├── oh-package.json5              main: Index.ets
 *   ├── src/main/ets/Index.ets        the HAR's public API (Palette + Metrics)
 *   ├── README.md                     says "generated", and where to change things
 *   └── src/main/
 *       ├── resources/base/element/color.json     light colours, #AARRGGBB
 *       ├── resources/base/element/float.json     dimensions, "52vp" / "30fp"
 *       ├── resources/dark/element/color.json     dark colours
 *       └── (the binding classes live in the root Index.ets)
 *
 * Every app then writes exactly one line:
 *
 *   "dependencies": { "@yostar/harmony-tokens": "file:../../harmonyos-tokens" }
 *
 * and imports { Palette, Metrics }. Updating every app is: regenerate + ohpm install.
 * Moving to a private registry later is a one-line change (file: → ^1.0.0).
 *
 * Usage:
 *   node tools/build-token-har.mjs [--out <dir>] [--prefix hm_]
 *                                  [--name @scope/pkg] [--version 1.0.0] [--check]
 *
 * --check regenerates in memory and compares against the directory on disk, so CI
 * can prove the HAR is in sync with the tokens. Exit 1 when anything is stale.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readTokenBlocks, convertTokens, toCamel } from './lib/ohos-tokens.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DS = path.resolve(HERE, '..');

const argv = process.argv.slice(2);
const flag = (n) => argv.includes(n);
/* An explicitly empty value must be honoured — see the note in emit-ohos-resources.mjs */
const option = (n, d) => {
  const i = argv.indexOf(n);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : d;
};

const OUT = path.resolve(option('--out', path.join(DS, '..', '..', 'harmonyos-tokens')));
const PREFIX = option('--prefix', 'hm_');
const PKG_NAME = option('--name', '@yostar/harmony-tokens');
const VERSION = option('--version', '1.0.0');
const CHECK = flag('--check');

const TOKENS_DIR = path.join(DS, 'tokens');
if (!fs.existsSync(TOKENS_DIR)) {
  console.error(`build-token-har: no tokens/ directory at ${DS}`);
  process.exit(2);
}

const blocks = readTokenBlocks(TOKENS_DIR);
const { colors, darkColors, floats, skipped } = convertTokens(blocks, PREFIX);

/* ------------------------------------------------------------------ files */
const asColorJson = (entries) => JSON.stringify(
  { color: [...entries.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([name, value]) => ({ name, value })) },
  null, 2) + '\n';

const asFloatJson = (entries) => JSON.stringify(
  { float: [...entries.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([name, value]) => ({ name, value })) },
  null, 2) + '\n';

const BANNER = `/*
 * ${'Theme.ets'} — GENERATED FILE. Do not edit.
 *
 * Source of truth: designs/harmonyos-mobile/tokens/*.css
 * Regenerate:      node tools/build-token-har.mjs
 *
 * Colours are Resource references so the platform swaps in resources/dark at
 * runtime. Dimensions are plain numbers so a screen can compose them (this system's
 * bottom geometry depends on the live safe-area insets, which needs arithmetic).
 *
 * NOTE — an app CANNOT override these values by redeclaring the same resource name.
 * Verified by building a conflicting declaration: the toolchain prints
 *   "Warning: 'hm_brand' conflict, first declared."
 * and the HAR's value wins; the app's is dropped. So a resource name is owned by
 * whichever module declares it first, and this HAR is first.
 */`;

function asIndexEts() {
  const colorLines = [...colors.keys()].sort().map((name) => {
    const camel = toCamel(name.slice(PREFIX.length)) || toCamel(name);
    return `  /** \`$r('app.color.${name}')\` */\n  static readonly ${camel}: Resource = $r('app.color.${name}');`;
  }).join('\n');

  /* Dimensions are plain numbers, NOT Resource references.
     Reason: this system's derived geometry depends on the live safe-area insets
     (the design's 100vp bottom container is 16 + 56 + 28, and 28 is the Home
     Indicator band the platform reports at runtime). Compiling a screen therefore
     needs arithmetic — `Metrics.tabbarH + Metrics.tabbarIndicator` — and
     `Resource + Resource` is an ArkTS error. float.json is still generated, so an
     app that wants resource-level indirection can use $r('app.float.<name>'). */
  const floatLines = [...floats.keys()].sort().map((name) => {
    const camel = toCamel(name.slice(PREFIX.length)) || toCamel(name);
    const num = parseFloat(String(floats.get(name)));
    return `  /** ${floats.get(name)} — \`$r('app.float.${name}')\` */\n  static readonly ${camel}: number = ${num};`;
  }).join('\n');

  return `${BANNER}

/** Theme-aware colours. The light/dark values live in resources/{base,dark}. */
export class Palette {
${colorLines}
}

/** Dimensions and type sizes, in vp (fp for the font sizes). Plain numbers so a
 *  screen can compose them — see the note in the generator. */
export class Metrics {
${floatLines}
}
`;
}

/* A HAR is a MODULE, not just a package: it needs its own module descriptor,
   build profile and hvigor task set, exactly like the app's entry module. Emitting
   only oh-package.json5 produced
   "Failed to resolve OhmUrl ... the module which Theme.ets belongs to is not
   correctly configured" — the ArkTS compiler could not tell what kind of module the
   HAR was. */
const HAR_MODULE_NAME = PKG_NAME.replace(/^@[^/]+\//, '').replace(/[^A-Za-z0-9_]/g, '_');

const files = new Map([
  ['build-profile.json5', `{
  "apiType": "stageMode",
  "buildOption": {
    "resOptions": {
      "copyCodeResource": {
        "enable": false
      }
    }
  },
  "targets": [
    { "name": "default" }
  ]
}
`],
  ['hvigorfile.ts', `// @ts-nocheck – HarmonyOS library template
import { harTasks } from '@ohos/hvigor-ohos-plugin';

export default {
  system: harTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}
`],
  ['src/main/module.json5', `{
  "module": {
    "name": "${HAR_MODULE_NAME}",
    "type": "har",
    /* A token library is device-agnostic, so it declares the form factors the
       design system covers rather than just "phone". */
    "deviceTypes": [
      "phone",
      "tablet",
      "2in1"
    ]
  }
}
`],

  ['oh-package.json5', `{
  "name": "${PKG_NAME}",
  "version": "${VERSION}",
  "description": "Generated HarmonyOS design tokens from designs/harmonyos-mobile. Do not edit by hand.",
  "main": "src/main/ets/Index.ets",
  "author": "",
  "license": "Apache-2.0",
  "dependencies": {}
}
`],
  ['src/main/ets/Index.ets', asIndexEts()],
  ['README.md', `# ${PKG_NAME}

**Generated — do not edit anything in this folder.**

Every file here is produced by \`designs/harmonyos-mobile/tools/build-token-har.mjs\`
from the design system's \`tokens/*.css\`. Change the tokens there and regenerate:

\`\`\`bash
cd designs/harmonyos-mobile
node tools/build-token-har.mjs          # write
node tools/build-token-har.mjs --check  # verify it is in sync (CI)
\`\`\`

## Use it from an app

\`\`\`json5
// <app>/entry/oh-package.json5
"dependencies": { "${PKG_NAME}": "file:../../harmonyos-tokens" }
\`\`\`

\`\`\`ts
import { Palette, Metrics } from '${PKG_NAME}';

Text('标题')
  .fontColor(Palette.fontPrimary)
  .fontSize(Metrics.fontSizeTitleL)
  .padding({ left: Metrics.pagePadH })
\`\`\`

${colors.size} colours (light + dark) and ${floats.size} dimensions, generated from
${blocks.length} token blocks.

## Overriding a token: you cannot, by redeclaring it

A resource name belongs to the module that declares it FIRST. This was verified by
building an app that redeclared \`hm_brand\`:

\`\`\`
WARN: Warning: 'hm_brand' conflict, first declared.
BUILD SUCCESSFUL
\`\`\`

The build succeeds, the HAR's value wins, and the app's declaration is silently
dropped. So do not try to retheme by shadowing a token.

If an app genuinely needs a different value for one spot:

1. **Preferred** — do not use the token there; use the app's own resource name
   (e.g. \`brand_alt\`) declared in the app, and reference it directly.
2. Or override at the call site in ArkTS for that one component.
3. If the whole app needs a different palette, that is a different design system —
   forking the tokens is more honest than shadowing a shared package.
`],
  ['src/main/resources/base/element/color.json', asColorJson(colors)],
  ['src/main/resources/dark/element/color.json', asColorJson(darkColors)],
  ['src/main/resources/base/element/float.json', asFloatJson(floats)],
]);

/* ------------------------------------------------------------------ write */
const rel = (p) => path.relative(DS, p) || p;
console.log(`build-token-har · out=${rel(OUT)} · name=${PKG_NAME}@${VERSION} · prefix="${PREFIX}"${CHECK ? ' · CHECK' : ''}`);
console.log(`  ${colors.size} colour(s) · ${darkColors.size} dark override(s) · ${floats.size} dimension(s)`);
if (skipped.length) { console.log(`  skipped ${skipped.length} token(s) that are neither colours nor px lengths`); }

if (CHECK) {
  const problems = [];
  for (const [name, content] of files) {
    const abs = path.join(OUT, name);
    const actual = fs.existsSync(abs) ? fs.readFileSync(abs, 'utf8') : null;
    if (actual === null) { problems.push(`missing  ${name}`); }
    else if (actual !== content) { problems.push(`stale    ${name}`); }
  }
  // files present on disk that the generator no longer produces
  const known = new Set(files.keys());
  const walk = (dir) => {
    if (!fs.existsSync(dir)) { return []; }
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
      const abs = path.join(dir, e.name);
      return e.isDirectory() ? walk(abs) : [path.relative(OUT, abs).split(path.sep).join('/')];
    });
  };
  for (const name of walk(OUT)) { if (!known.has(name)) { problems.push(`orphan   ${name}`); } }

  if (problems.length) {
    console.log(`\n✗ ${problems.length} problem(s) — the HAR is not in sync with the tokens:`);
    for (const p of problems) { console.log(`    ${p}`); }
    process.exit(1);
  }
  console.log(`\n  ✓ in sync (${files.size} file(s)) — clean. ✅`);
  process.exit(0);
}

/* Everything in OUT is declared generated (its own README says so), so a file the
   generator no longer produces is stale residue and must go — leaving it is how a
   half-migrated layout keeps compiling against the wrong sources. This is the same
   walk the --check mode uses to report orphans. */
const walkAll = (dir) => {
  if (!fs.existsSync(dir)) { return []; }
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const abs = path.join(dir, e.name);
    return e.isDirectory() ? walkAll(abs) : [path.relative(OUT, abs).split(path.sep).join('/')];
  });
};
const known = new Set(files.keys());
const pruned = walkAll(OUT).filter((name) => !known.has(name));

for (const [name, content] of files) {
  const abs = path.join(OUT, name);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, content);
  console.log(`  + ${name}  (${content.length} bytes)`);
}
for (const name of pruned) {
  fs.rmSync(path.join(OUT, name));
  console.log(`  - ${name}  (pruned: no longer generated)`);
}
/* remove now-empty directories left behind by pruning */
const pruneEmptyDirs = (dir) => {
  if (!fs.existsSync(dir)) { return; }
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) { pruneEmptyDirs(path.join(dir, e.name)); }
  }
  if (dir !== OUT && fs.readdirSync(dir).length === 0) { fs.rmdirSync(dir); }
};
pruneEmptyDirs(OUT);

/* Read every file back and prove it parses / is non-empty. */
const problems = [];
for (const [name, content] of files) {
  const actual = fs.readFileSync(path.join(OUT, name), 'utf8');
  if (actual !== content) { problems.push(`${name}: read-back differs`); }
  if (name.endsWith('.json')) {
    try { JSON.parse(actual); } catch (e) { problems.push(`${name}: invalid JSON (${e.message})`); }
  }
  if (name === 'src/main/ets/Index.ets') {
    if (!/export class Palette/.test(actual) || !/export class Metrics/.test(actual)) {
      problems.push(`${name}: missing Palette/Metrics`);
    }
    if (!/static readonly \w+: Resource = \$r\('app\.color\./.test(actual)) {
      problems.push(`${name}: no colour bindings`);
    }
    if (!/static readonly \w+: number = /.test(actual)) {
      problems.push(`${name}: no numeric dimension bindings`);
    }
    /* The entry must sit inside the module and use no cross-module relative path. */
    if (/from '\.\.\//.test(actual)) {
      problems.push(`${name}: must not import outside the module via a relative path`);
    }
  }
}
if (problems.length) {
  console.error('\n  ✗ self-check failed:');
  for (const p of problems) { console.error(`      ${p}`); }
  process.exit(1);
}
console.log(`\n  ✓ read-back self-check passed (${files.size} file(s), JSON parsed, classes exported)`);
console.log(`  next: in an app, add "${PKG_NAME}": "file:<relative path>" and run ohpm install`);
