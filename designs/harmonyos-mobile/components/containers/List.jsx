import { Icon } from "../controls/Icon";

/**
 * List — the reference's list row, in six documented height variants:
 *
 *   single       48  title only
 *   icondot      56  8×8 dot + title
 *   iconsingle   64  48×48 app icon + title
 *   2lines       64  title + one aux line
 *   icon2lines   72  app icon + title + aux
 *   3lines       96  title + two aux lines
 *
 * The right slot is `text` + icon, where the icon is either the HMSymbol chevron
 * or a CSS triangle (arrow-down) — the triangle is drawn by the sheet, so no glyph
 * is emitted for it.
 */
const LEFT_LAYOUT = {
  single: "vertical",
  "2lines": "vertical",
  "3lines": "vertical",
  icondot: "horizontal-sm",
  iconsingle: "horizontal",
  icon2lines: "horizontal",
};

export function List({
  variant = "single",
  title,
  aux,
  aux2,
  appIconSrc,
  appIconAlt = "",
  rightText,
  rightIcon,              // 'chevron' | 'arrow-down' | null
  onClick,
  className = "",
  children,
  ...rest
}) {
  const layout = LEFT_LAYOUT[variant] || "vertical";
  const showDot = variant === "icondot";
  const showAppIcon = variant === "iconsingle" || variant === "icon2lines";
  const lines = variant === "3lines" ? 3 : (variant === "2lines" || variant === "icon2lines") ? 2 : 1;

  const textGroup = (
    <>
      <span className="hm-list__title">{title}</span>
      {lines >= 2 && aux ? <span className="hm-list__aux">{aux}</span> : null}
      {lines >= 3 && aux2 ? <span className="hm-list__aux">{aux2}</span> : null}
    </>
  );

  return (
    <div
      className={`hm-list hm-list-${variant}${className ? " " + className : ""}`}
      data-component="list"
      data-variant={variant}
      role={onClick ? "button" : undefined}
      tabIndex={onClick ? 0 : undefined}
      data-hm-light={onClick ? "" : undefined}
      onClick={onClick}
      {...rest}
    >
      <div className={`hm-list__left hm-list__left--${layout}`}>
        {showDot ? <span className="hm-list-icon hm-list-icon--dot" aria-hidden="true" /> : null}
        {showAppIcon ? (
          <div className="hm-list__appicon">
            {appIconSrc ? <img src={appIconSrc} alt={appIconAlt} /> : null}
          </div>
        ) : null}
        {layout === "vertical" || showDot
          ? textGroup
          : <div className="hm-list__text-group">{textGroup}</div>}
        {children}
        <div className="hm-list__divider--left" aria-hidden="true" />
      </div>

      <div className="hm-list__right">
        {rightText !== undefined && rightText !== null ? (
          <span className={"hm-list__right-text" + (lines > 1 ? " hm-list__right-text--clamp2" : "")}>
            {rightText}
          </span>
        ) : null}
        {rightIcon === "chevron" ? (
          <span className="hm-list-icon hm-list-icon--chevron" aria-hidden="true">
            <Icon name="chevron_right" size={24} />
          </span>
        ) : rightIcon === "arrow-down" ? (
          <span className="hm-list-icon hm-list-icon--arrow-down" aria-hidden="true" />
        ) : null}
        <div className="hm-list__divider--right" aria-hidden="true" />
      </div>
    </div>
  );
}
