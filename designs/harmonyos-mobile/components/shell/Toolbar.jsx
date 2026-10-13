import { Icon } from "../controls/Icon";

/**
 * Toolbar — the reference's floating toolbar.
 * Variants `3 | 4 | 5 | 6` set the item count (and therefore the width);
 * `vertical-icon` stacks icon over label.
 */
export function Toolbar({
  variant = "4",
  items = [],
  activeIndex = 0,
  onSelect,
  className = "",
  ...rest
}) {
  const v = String(variant);
  return (
    <div className={"hm-toolbar hm-toolbar--" + v + (className ? " " + className : "")}
         data-component="toolbar" {...rest}>
      {items.map((item, index) => (
        <button
          key={item.key || item.label || index}
          className={"hm-toolbar__item" + (index === activeIndex ? " hm-toolbar__item--active" : "")}
          type="button"
          data-hm-light=""
          aria-pressed={index === activeIndex}
          disabled={item.disabled}
          onClick={() => onSelect && onSelect(index)}
        >
          <span className="hm-toolbar__icon" aria-hidden="true"><Icon name={item.icon} size={24} /></span>
          <span className="hm-toolbar__label">{item.label}</span>
        </button>
      ))}
    </div>
  );
}
