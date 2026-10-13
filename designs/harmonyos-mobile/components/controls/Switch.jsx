/**
 * Switch — the reference's Switch component (48×28 track, 24px thumb).
 *
 * The template ships this as a <div> with is-* classes; here it is a real
 * <button role="switch"> carrying the same classes, so it is focusable and
 * announced correctly. The CSS is class-based, so the tag change is safe.
 *
 * The knob is a real element (.hm-switch__thumb) rather than a pseudo-element on
 * purpose: a pseudo-element cannot be given the thumb's stroke and offset, and an
 * inline <span> would collapse to 0×0 if the sheet ever stopped setting
 * display:block on it.
 */
export function Switch({
  on = false,
  disabled = false,
  label,
  onChange,
  className = "",
  light = true,
  ...rest
}) {
  const cls = [
    "hm-switch",
    on ? "is-on" : "",
    disabled ? "is-disabled" : "",
    className,
  ].filter(Boolean).join(" ");

  return (
    <button
      className={cls}
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      disabled={disabled}
      data-hm-light={light ? "" : undefined}
      onClick={() => { if (!disabled && onChange) { onChange(!on); } }}
      {...rest}
    >
      <span className="hm-switch__thumb" aria-hidden="true" />
    </button>
  );
}
