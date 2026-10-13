import { HMSYMBOL, glyph } from "./IconMap";

/**
 * Icon — renders one HMSymbol glyph from the official dictionary.
 *
 * The reference forbids hand-drawn inline SVG for this system, so there is no
 * path data anywhere in this file: the glyph comes from the HMSymbol font and the
 * codepoint from IconMap.jsx (generated from the official name dictionary).
 * An unknown name is NOT silently replaced by a drawn lookalike — it renders a
 * visible placeholder and warns, so dictionary gaps surface during review.
 */
export function Icon({ name, size = 24, className = "", style, label, ...rest }) {
  const char = glyph(name);
  const cls = ["hm", `hm-${size}`, "hm-icon", className].filter(Boolean).join(" ");

  if (!char) {
    if (typeof console !== "undefined") {
      console.warn(
        `[harmonyos-mobile] Unknown HMSymbol name "${name}". Names come from the ` +
        `official dictionary (assets/hmsymbol-map.json); add it to tools/gen-icon-map.mjs ` +
        `rather than drawing an SVG.`);
    }
    return (
      <span className={cls} style={{ fontFamily: "HMSymbol", ...style }} aria-hidden="true" {...rest}>
        ?
      </span>
    );
  }

  return (
    <span
      className={cls}
      style={{ fontFamily: "HMSymbol", ...style }}
      role={label ? "img" : undefined}
      aria-label={label || undefined}
      aria-hidden={label ? undefined : "true"}
      {...rest}
    >
      {char}
    </span>
  );
}

export const ICON_NAMES = Object.keys(HMSYMBOL);
