import { Icon } from "./Icon";

/**
 * Button — the reference's Button component.
 *
 * DOM and class names mirror references/4.template/button-tem.html exactly
 * (.hm-button--<size> + .hm-button--<type>); the sheet carries the geometry, so
 * nothing here restates padding, radius or type scale.
 * Always renders __overlay and __focus-ring — the template requires both.
 */
export function Button({
  children,
  size = "medium",          // small | medium
  type = "emphasized",      // emphasized | normal | selected | unselected | warning
  loading = false,
  disabled = false,
  icon,                     // HMSymbol name, optional
  onClick,
  className = "",
  style,
  light = true,             // opt into 沉浸光感 (focal component)
  ...rest
}) {
  const cls = [
    "hm-button",
    `hm-button--${size}`,
    `hm-button--${type}`,
    loading ? "hm-button--loading" : "",
    className,
  ].filter(Boolean).join(" ");

  return (
    <button
      className={cls}
      type="button"
      disabled={disabled}
      onClick={onClick}
      data-hm-light={light ? "" : undefined}
      style={style}
      {...rest}
    >
      <span className="hm-button__overlay" aria-hidden="true" />
      <span className="hm-button__focus-ring" aria-hidden="true" />
      {loading ? (
        <span className="hm-button__spinner" aria-hidden="true">
          <svg className="hm-button__spinner-img" viewBox="0 0 26 24" fill="none"
               xmlns="http://www.w3.org/2000/svg">
            <path d="M23.5 12C23.5 7.02944 19.4706 3 14.5 3C9.52944 3 5.5 7.02944 5.5 12C5.5 16.9706 9.52944 21 14.5 21C19.4706 21 23.5 16.9706 23.5 12ZM21.5 12C21.5 8.134 18.366 5 14.5 5C10.634 5 7.5 8.134 7.5 12C7.5 15.866 10.634 19 14.5 19C18.366 19 21.5 15.866 21.5 12Z"
                  fill="currentColor" fillRule="evenodd" />
            <circle cx="2.5" cy="14.5" r="2" fill="currentColor" />
            <circle cx="2" cy="15" r="2" fill="currentColor" />
          </svg>
        </span>
      ) : null}
      {icon ? <span className="hm-button__icon"><Icon name={icon} size={20} /></span> : null}
      <span className="hm-button__content">{children}</span>
    </button>
  );
}
