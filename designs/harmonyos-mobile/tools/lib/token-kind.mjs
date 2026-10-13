// token-kind.mjs — decide a token's `@kind` from its value and name, and stamp
// that annotation into a block of CSS declarations.
//
// Why this exists: the compiler only reads a kind from a comment placed
// IMMEDIATELY after the declaration's semicolon, e.g.
//     --harmony-brand: rgba(10, 89, 247, 1); /* @kind color */
// so the reference's own trailing `/* #aarrggbb */` note has to sit behind it.
// Anything the value alone cannot settle is decided by name; whatever still does
// not resolve is stamped `other` on purpose rather than left unclassified.
//
// Shared by tools/sync-tokens.mjs and tools/import-template-css.mjs so the two
// generators can never disagree about what a token is.

const NAMED_COLORS = new Set([
  'transparent', 'currentcolor', 'black', 'white', 'red', 'green', 'blue',
  'gray', 'grey',
]);

const VAR_RE = /^var\(\s*(--[A-Za-z0-9_-]+)/;

/** Follow `var(--a)` chains — including the nested-fallback form the reference
 *  uses (`var(--a, var(--b))`), which a naive `[^)]+` capture gets wrong. */
export function resolveVar(value, decls, depth = 0) {
  if (depth > 10) { return value; }
  const m = VAR_RE.exec(String(value).trim());
  if (m && decls && decls.has(m[1])) { return resolveVar(decls.get(m[1]), decls, depth + 1); }
  return value;
}

export function kindOf(name, value, decls) {
  const raw = String(value).trim();
  if (/^url\(/.test(raw)) { return 'other'; }              // asset reference
  if (/^blur\(/.test(raw)) { return 'other'; }

  const v = String(resolveVar(raw, decls)).trim();

  const hasColor = /#[0-9a-fA-F]{3,8}\b/.test(v) ||
    /\b(rgba?|hsla?|okl?ch|oklab|lab|lch|hwb|color)\(/.test(v) ||
    NAMED_COLORS.has(v.toLowerCase());
  const hasLen = /(^|[\s,(])-?\d*\.?\d+(px|rem|em|vh|vw|vmin|vmax|%|pt)\b/.test(v);

  if (hasColor && hasLen) { return 'shadow'; }
  if (hasColor) { return 'color'; }
  if (/gradient\(|shadow|inset/.test(v)) { return 'shadow'; }

  // unitless knobs are not lengths, however much they look like numbers
  if (/^(saturate|scale|alpha|opacity|ease|duration|weight)/.test(name) ||
      /(saturate|scale|alpha|opacity)$/.test(name)) { return 'other'; }
  if (/^[-\d.]+$/.test(v) && /opacity|saturate|scale|weight|zoom|flex|order/.test(name)) { return 'other'; }
  if (/^\d*\.?\d+m?s$/.test(v) && /(duration|delay|fade|transition)/.test(name)) { return 'other'; }

  if (hasLen) { return /radius/.test(name) ? 'radius' : 'spacing'; }
  if (/font-weight|font_weight|font-family|font_stack|font-stack|font-mono/.test(name)) { return 'font'; }
  if (/font-size|font_size|line-height/.test(name)) { return 'font'; }
  if (/radius/.test(name)) { return 'radius'; }
  if (/shadow/.test(name)) { return 'shadow'; }
  if (/overlay-rgb/.test(name) || /^\s*\d+\s*,\s*\d+\s*,\s*\d+\s*$/.test(v)) { return 'other'; }
  if (/(padding|gap|margin|height|width|blur|size|thickness)/.test(name)) { return 'spacing'; }
  return 'other';
}

/**
 * Stamp `/* @kind x *\/` after every declaration's semicolon in `body`,
 * preserving any original trailing note behind it. Multi-line values (gradients,
 * calc chains) are handled because the match is on the whole body, not per line.
 * Idempotent: a previous annotation is replaced, not stacked.
 */
export function annotateBody(body) {
  const clean = String(body).replace(/\s*\/\*\s*@kind\s+[A-Za-z]+\s*\*\//g, '');

  /* Split into code / comment segments and only rewrite the CODE ones.
     This matters: CSS comments do not nest, so stamping inside a comment
     terminates it early and turns the rest of the comment into invalid CSS —
     which silently kills the rule that follows. (Observed for real: a comment
     containing `--x: calc(...)` was matched as a declaration and the annotation
     landed mid-comment, swallowing the next [data-material-level] block.) */
  const segments = clean.split(/(\/\*[\s\S]*?\*\/)/g);

  const decls = new Map();
  for (let i = 0; i < segments.length; i += 2) {
    for (const m of segments[i].matchAll(/(--[A-Za-z0-9_-]+)\s*:\s*([^;]+);/g)) {
      decls.set(m[1], m[2].trim());
    }
  }

  return segments.map((segment, index) => {
    if (index % 2 === 1) { return segment; }   // a comment — never touch it
    return segment.replace(/(\s*)(--[A-Za-z0-9_-]+)\s*:\s*([^;]+);([ \t]*\/\*[^*]*\*\/)?/g,
      (full, lead, name, value, trailing) => {
        const kind = kindOf(name, value, decls);
        const note = trailing && !/@kind/.test(trailing) ? ' ' + trailing.trim() : '';
        return `${lead}${name}: ${value.trim()}; /* @kind ${kind} */${note}`;
      });
  }).join('');
}
