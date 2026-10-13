import { Icon } from "./Icon";

/**
 * FloatingSearch — the reference's Floating Search (328×40, r24).
 *
 * State machine from the template:
 *   idle     placeholder only
 *   actived  input area with a cursor, placeholder still shown
 *   typing   input area with the value + cursor
 *   output   the value as static text
 * `on` additionally reveals the trailing action region (voice icon + divider +
 * action button), and `cancel` swaps in the clear button.
 * __overlay is mandatory — it carries the hover/pressed/focus fills.
 *
 * The root is a real tap target (role="search" + onClick), which is what makes it a
 * focal component for 沉浸光感. Presentational, like the reference: the field is
 * rendered from `mode`/`value`
 * rather than being a native <input>, so every documented visual state (caret,
 * output text, cancel) is reachable from props. Wire real typing at the screen
 * level if a prototype needs it.
 */
export function FloatingSearch({
  mode = "idle",            // idle | actived | typing | output
  value = "",
  placeholder = "搜索",
  on = false,
  actionLabel = "搜索",
  voice = true,
  cancel = false,
  onAction,
  onChange,
  onActivate,
  className = "",
  light = true,
  ...rest
}) {
  const cls = [
    "hm-search",
    on ? "is-on" : "",
    mode === "actived" ? "is-actived" : "",
    mode === "typing" ? "is-typing" : "",
    className,
  ].filter(Boolean).join(" ");

  const showCancel = cancel && (mode === "typing" || mode === "output");
  const activate = onChange || onAction;

  return (
    <div
      className={cls}
      data-component="search"
      data-hm-light={light ? "" : undefined}
      role="search"
      onClick={onActivate}
      {...rest}
    >
      <span className="hm-search__overlay" aria-hidden="true" />

      <span className="hm-search__icon" aria-hidden="true">
        <svg viewBox="0 0 18 18" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.6">
          <circle cx="8" cy="8" r="5.4" />
          <path d="M12 12l4 4" strokeLinecap="round" />
        </svg>
      </span>

      {mode === "typing" ? (
        <span className="hm-search__input-area">
          <span className="hm-search__text hm-search__text--value">{value}</span>
          <span className="hm-search__cursor" aria-hidden="true" />
        </span>
      ) : mode === "actived" ? (
        <span className="hm-search__input-area">
          <span className="hm-search__cursor" aria-hidden="true" />
          <span className="hm-search__text hm-search__text--placeholder">{placeholder}</span>
        </span>
      ) : mode === "output" ? (
        <span className="hm-search__text hm-search__text--value">{value}</span>
      ) : (
        <span className="hm-search__text hm-search__text--placeholder">{placeholder}</span>
      )}

      {showCancel ? (
        <button className="hm-search__cancel" type="button" aria-label="清除" onClick={() => onChange && onChange("")}>
          <Icon name="xmark" size={16} />
        </button>
      ) : null}

      {on ? (
        <span className="hm-search__action">
          {mode === "idle" && voice ? (
            <>
              <span className="hm-search__action-icon" aria-hidden="true"><Icon name="magnifyingglass" size={20} /></span>
              <span className="hm-search__divider" aria-hidden="true" />
            </>
          ) : null}
          {showCancel ? <span className="hm-search__divider" aria-hidden="true" /> : null}
          <button className="hm-search__action-btn" type="button" onClick={onAction}>{actionLabel}</button>
        </span>
      ) : null}
    </div>
  );
}
