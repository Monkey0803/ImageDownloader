/* Minimal stand-in so R11 has a map to check against. */
export const HMSYMBOL = {
  "house": { u: "0xF0027" },
};
export function glyph(name) { return HMSYMBOL[name] ? String.fromCodePoint(parseInt(HMSYMBOL[name].u, 16)) : null; }
