import { Icon } from "../controls/Icon";

/**
 * CardView — the reference's card container.
 *
 * Sizes: mini | small | medium | larger | max. Icon buttons sit at `left`,
 * `right` or `br` (bottom-right); the card body is the children slot, so the card
 * never dictates its own content.
 */
export function CardView({
  size = "medium",
  iconButtons = [],       // [{ position: 'left'|'right'|'br', glyph, label, onClick }]
  onClick,
  className = "",
  style,
  children,
  ...rest
}) {
  const cls = ["hm-cardview", `hm-cardview--${size}`, className].filter(Boolean).join(" ");
  return (
    <div className={cls} data-component="cardview" style={style} onClick={onClick} {...rest}>
      {iconButtons.map((button, index) => {
        const position = button.position || "right";
        return (
          <button
            key={button.label || index}
            className={`hm-cardview__icon-btn hm-cardview__icon-btn--${position}`}
            type="button"
            data-hm-light=""
            aria-label={button.label}
            onClick={(event) => { event.stopPropagation(); if (button.onClick) { button.onClick(event); } }}
          >
            <span className="hm-cardview__icon" aria-hidden="true"><Icon name={button.glyph} size={20} /></span>
          </button>
        );
      })}
      {children}
    </div>
  );
}
