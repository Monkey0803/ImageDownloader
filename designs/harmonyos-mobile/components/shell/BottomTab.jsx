import { Icon } from "../controls/Icon";

/**
 * BottomTab — the reference's floating pill tab bar.
 *
 * Variants and their locked bar widths (never content-driven):
 *   2 → 160 · 3 → 236 · 4 → 328 · 5 → 328 · multibar / 1bar → 264
 *
 * The container is 360×100 = 16px clearance + 56px pill + 28px Home Indicator.
 * This component renders the pill and the indicator zone but does NOT draw the
 * indicator bar's system equivalent on a real device — the mockup rules forbid a
 * second status/home chrome; the slot exists because the reference's geometry
 * reserves it.
 */
function TabButton({ item, active, onSelect }) {
  return (
    <button
      className={"hm-bottomtab__tab" + (active ? " hm-bottomtab__tab--active" : "")}
      type="button"
      data-hm-light=""
      aria-pressed={active}
      onClick={onSelect}
    >
      <span className="hm-bottomtab__tab-icon" aria-hidden="true"><Icon name={item.icon} size={24} /></span>
      <span className="hm-bottomtab__tab-label">{item.label}</span>
    </button>
  );
}

export function BottomTab({
  variant = "3",
  items = [],
  activeIndex = 0,
  onSelect,
  homeIndicatorBar = true,
  albumSrc,
  expandLabel,
  expandIcons,          // 1bar: [{ glyph, label, onClick }]
  circleIcon,           // 1bar: the leading circle's glyph
  className = "",
  ...rest
}) {
  const v = String(variant);
  const isRowVariant = v === "multibar" || v === "1bar";

  const indicator = (
    <div className="hm-bottomtab__indicator">
      {homeIndicatorBar ? <div className="hm-bottomtab__indicator-bar" aria-hidden="true" /> : null}
    </div>
  );

  const tabs = (list) => (
    <div className="hm-bottomtab__tabs">
      {list.map((item, index) => (
        <TabButton
          key={item.key || item.label || index}
          item={item}
          active={index === activeIndex}
          onSelect={() => onSelect && onSelect(index)}
        />
      ))}
    </div>
  );

  if (v === "1bar") {
    return (
      <nav className={"hm-bottomtab " + className} data-component="bottomtab" data-variant={v} {...rest}>
        <div className="hm-bottomtab__row">
          <button className="hm-bottomtab__tab-circle" type="button" data-hm-light="" aria-label={expandLabel || "播放"}>
            <span className="hm-bottomtab__tab-icon" aria-hidden="true"><Icon name={circleIcon || "play_fill"} size={24} /></span>
          </button>
          <div className="hm-bottomtab__bar hm-bottomtab__bar--single">
            <div className="hm-bottomtab__expand">
              <div className="hm-bottomtab__expand-album">
                {albumSrc ? <img className="hm-bottomtab__expand-album-img" src={albumSrc} alt="" /> : null}
              </div>
              <span className="hm-bottomtab__expand-label">{expandLabel}</span>
              <div className="hm-bottomtab__expand-group">
                {(expandIcons || []).map((entry, index) => (
                  <button key={entry.label || index} className="hm-bottomtab__expand-icon" type="button"
                          data-hm-light="" aria-label={entry.label} onClick={entry.onClick}>
                    <Icon name={entry.glyph} size={22} />
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>
        {indicator}
      </nav>
    );
  }

  if (v === "multibar") {
    return (
      <nav className={"hm-bottomtab " + className} data-component="bottomtab" data-variant={v} {...rest}>
        <div className="hm-bottomtab__row">
          <div className="hm-bottomtab__bar hm-bottomtab__bar--multi">{tabs(items.slice(0, 4))}</div>
          <div className="hm-bottomtab__fold">
            <div className="hm-bottomtab__album">
              {albumSrc ? <img className="hm-bottomtab__album-img" src={albumSrc} alt="" /> : null}
            </div>
          </div>
        </div>
        {indicator}
      </nav>
    );
  }

  return (
    <nav className={"hm-bottomtab " + className} data-component="bottomtab" data-variant={v} {...rest}>
      <div className={"hm-bottomtab__bar hm-bottomtab__bar--" + v}>{tabs(items)}</div>
      {indicator}
    </nav>
  );
}
