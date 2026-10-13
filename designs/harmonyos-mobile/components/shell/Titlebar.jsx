import { Icon } from "../controls/Icon";

/**
 * Titlebar — the reference's floating title bar. Four variants:
 *
 *   big        205px, three actions, 30/40 title + subtitle
 *   normal     124px, three actions, title only
 *   secondary  124px, chevron_left leading, title + subtitle
 *   drawer     124px, indent_right leading, title only
 *
 * Geometry is entirely in the sheet; the props only choose a variant and fill the
 * slots. `subtitle` is rendered ONLY by the variants that define it (big and
 * secondary) — the reference forbids inventing a subtitle inside `normal`.
 */
export function Titlebar({
  variant = "normal",
  title,
  subtitle,
  time = "08:08",
  leadingGlyph,
  onLeading,
  actions = [],           // [{ glyph, label, onClick }]
  showStatus = true,
  theme = "light",
  className = "",
  children,
  ...rest
}) {
  const cls = ["hm-titlebar", `hm-titlebar--${variant}`, className].filter(Boolean).join(" ");
  const hasLeading = variant === "secondary" || variant === "drawer";
  const leading = leadingGlyph || (variant === "secondary" ? "chevron_left"
    : variant === "drawer" ? "indent_right" : null);

  return (
    <header className={cls} data-component="titlebar" data-variant={variant} {...rest}>
      {showStatus ? (
        <div className="hm-titlebar__status" aria-hidden="true">
          <span className="hm-titlebar__time">{time}</span>
          <span className="hm-titlebar__status-icons">
            <i className="hm-titlebar__status-icon hm-titlebar__status-icon--wifi" />
            <i className="hm-titlebar__status-icon hm-titlebar__status-icon--sig1" />
            <i className="hm-titlebar__status-icon hm-titlebar__status-icon--sig2" />
            <i className="hm-titlebar__status-icon hm-titlebar__status-icon--battery" />
          </span>
        </div>
      ) : null}

      <div className="hm-titlebar__content">
        {hasLeading && leading ? (
          <button className="hm-titlebar__leading" type="button" aria-label="返回" data-hm-light="" onClick={onLeading}>
            <Icon name={leading} size={24} />
          </button>
        ) : null}

        <div className="hm-titlebar__actions">
          {actions.map((action, index) => (
            <button
              key={action.label || index}
              className="hm-titlebar__action-btn"
              type="button"
              aria-label={action.label}
              data-hm-light=""
              onClick={action.onClick}
            >
              <Icon name={action.glyph || "circle_dashed"} size={24} />
            </button>
          ))}
        </div>

        <h2 className="hm-titlebar__title">{title}</h2>
        {subtitle && (variant === "big" || variant === "secondary") ? (
          <p className="hm-titlebar__subtitle">{subtitle}</p>
        ) : null}

        {children}
      </div>
    </header>
  );
}
