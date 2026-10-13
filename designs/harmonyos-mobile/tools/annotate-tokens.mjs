#!/usr/bin/env node
// annotate-tokens.mjs — stamp `/* @kind x */` on the token declarations of
// HAND-WRITTEN CSS (generated files get theirs from their own generators).
//
// The compiler reads a token's kind only from a comment placed immediately after
// the declaration's semicolon, and reports anything it cannot classify by value
// as an issue. Hand-authored files therefore have to carry the annotation in
// source — which is what this tool writes, and why it is safe to re-run: it
// replaces an existing annotation instead of stacking one.
//
// Usage:
//   node tools/annotate-tokens.mjs                  # the default hand-written set
//   node tools/annotate-tokens.mjs <file.css> ...   # specific files
//   node tools/annotate-tokens.mjs --check          # report drift, write nothing

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { annotateBody } from './lib/token-kind.mjs';

const DS = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const argv = process.argv.slice(2);
const CHECK = argv.includes('--check');

/* Files a human maintains that declare tokens. Generated token files
   (tokens/{colors,typography,spacing}.css) and the imported group CSS are
   excluded — their generators annotate them. */
const DEFAULT_FILES = [
  'base.css',
  'tokens/geometry.css',
  'tokens/material.css',
  'components/theme-bridge.css',
];

const files = argv.filter((a) => !a.startsWith('--'));
const targets = (files.length ? files : DEFAULT_FILES).map((f) => path.resolve(DS, f));

let stale = 0;
let tokens = 0;
for (const abs of targets) {
  if (!fs.existsSync(abs)) {
    console.error(`annotate-tokens: missing ${path.relative(DS, abs)}`);
    process.exit(2);
  }
  const before = fs.readFileSync(abs, 'utf8');
  const after = annotateBody(before);
  tokens += (after.match(/@kind /g) || []).length;
  if (before === after) { console.log('  = ' + path.relative(DS, abs)); continue; }
  stale++;
  if (CHECK) { console.log('  ! stale: ' + path.relative(DS, abs)); continue; }
  fs.writeFileSync(abs, after);
  console.log('  ~ ' + path.relative(DS, abs));
}

console.log(`annotate-tokens: ${targets.length} files, ${tokens} tokens, ` +
  `${stale} ${CHECK ? 'stale' : 'annotated'}`);
if (CHECK && stale) { process.exit(1); }
