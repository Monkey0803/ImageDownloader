import { Icon } from "./Icon";

/**
 * FloatingChipsTab — the reference's floating chip tab bar.
 *
 * Variants: `tab` (text only), `tab-with-icon` (icon + text), `icontab` (icon +
 * a trailing utility button). Chips mark their active state with `is-activated`;
 * the container's width follows the chip count, so it is never set inline.
 */
export function FloatingChipsTab({
  variant = "tab",          // tab | tab-with-icon | icontab
  chips = [],
  activeIndex = 0,
  onSelect,
  trailingIcon,             // icontab only
  onTrailing,
  className = "",
  ...rest
}) {
  const cls = ["hm-chipstab", `hm-chipstab-${variant}`, className].filter(Boolean).join(" ");

  return (
    <div className={cls} data-component="chipstab" {...rest}>
      {chips.map((chip, index) => {
        const activated = index === activeIndex;
        return (
          <button
            key={chip.key || chip.title || index}
            className={"hm-chipstab__chip" + (activated ? " is-activated" : "")}
            type="button"
            data-hm-light=""
            aria-pressed={activated}
            onClick={() => onSelect && onSelect(index)}
          >
            {variant === "tab-with-icon" && chip.icon ? (
              <span className="hm-chipstab__chip-icon" aria-hidden="true"><Icon name={chip.icon} size={16} /></span>
            ) : null}
            <span className="hm-chipstab__chip-title">{chip.title}</span>
            {chip.count !== undefined && chip.count !== null ? (
              <span className="hm-chipstab__chip-num">{chip.count}</span>
            ) : null}
          </button>
        );
      })}

      {variant === "icontab" && trailingIcon ? (
        <button className="hm-chipstab__icon-btn" type="button" data-hm-light="" onClick={onTrailing}>
          <Icon name={trailingIcon} size={24} />
        </button>
      ) : null}
    </div>
  );
}
