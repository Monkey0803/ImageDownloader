/**
 * SizeFrame — the reference's 尺寸框架: the device canvas that every screen mounts
 * into. It owns three things:
 *
 *   1. the locked canvas (360×792, or 360×780 for the card layout);
 *   2. the theme + material attributes. Every material token is composed on THIS
 *      element, because a custom property resolves where it is declared — putting
 *      data-material-level here is what makes the whole material system reach the
 *      components (see components/theme-bridge.css);
 *   3. placement of the floating shell layers — the titlebar and the bottom bar are
 *      handed in as `titlebar` / `bottomBar` and pinned by the frame's slots. The
 *      reference leaves placement to the page (its titlebar is position: relative),
 *      which is how the 8px titlebar gap and the 100px bottom container get broken;
 *      the frame takes that responsibility away from screens.
 *
 *   4. the 沉浸光感 delegate: one pointer listener for the whole frame that lights
 *      any [data-hm-light] focal component from the touch point.
 *
 * The reference does not style per-device classes (only .hm-size), so device
 * variants are emitted as attributes for identification and the canvas size stays
 * an explicit prop. Recorded as a gap in readme.md.
 *
 * NOTE for component authors: hooks are read off the global `React`
 * (`React.useEffect`), never imported. The design-system compiler strips
 * `react` / `react-dom` imports when it builds the bundle, so a named import of a
 * hook compiles fine and then throws `ReferenceError: useEffect is not defined`
 * at render time.
 */

function useLightEffectDelegate(enabled) {
  React.useEffect(() => {
    if (!enabled || typeof document === "undefined") { return; }
    const onDown = (event) => {
      const target = event.target;
      const el = target && target.closest ? target.closest("[data-hm-light]") : null;
      if (!el) { return; }
      const rect = el.getBoundingClientRect();
      if (!rect.width || !rect.height) { return; }
      el.style.setProperty("--harmony-light-x", (((event.clientX - rect.left) / rect.width) * 100) + "%");
      el.style.setProperty("--harmony-light-y", (((event.clientY - rect.top) / rect.height) * 100) + "%");
      el.classList.add("is-lit");
      window.setTimeout(() => el.classList.remove("is-lit"), 240);
    };
    document.addEventListener("pointerdown", onDown, true);
    return () => document.removeEventListener("pointerdown", onDown, true);
  }, [enabled]);
}

export function SizeFrame({
  device = "phone-portrait",   // phone-portrait | phone-landscape | foldable | tablet-portrait | tablet-landscape
  width,
  height,
  theme = "light",             // light | dark
  materialType = "adaptive",   // adaptive | immersive  (MaterialType)
  materialLevel = "gentle",    // exquisite | gentle | smooth  (MaterialLevel)
  statusbar,
  titlebar,
  bottomBar,
  homeIndicator = false,
  lightEffect = true,
  className = "",
  style,
  children,
  ...rest
}) {
  useLightEffectDelegate(lightEffect);

  const canvasW = width || "var(--harmony-canvas-w)";
  const canvasH = height || (device === "phone-portrait" ? "var(--harmony-canvas-h)" : "var(--harmony-canvas-h)");

  const cls = ["hm-size", `hm-size-${device}`, className].filter(Boolean).join(" ");

  return (
    <div
      className={cls}
      data-component="size"
      data-device={device}
      data-theme={theme}
      data-material-type={materialType}
      data-material-level={materialLevel}
      data-hm-light-effect={lightEffect ? "on" : "off"}
      style={{ width: canvasW, height: canvasH, ...style }}
      {...rest}
    >
      <div className="hm-size-statusbar">{statusbar}</div>
      <div className="hm-size-content">{children}</div>
      {titlebar ? <div className="hm-size-titlebar">{titlebar}</div> : null}
      {bottomBar ? <div className="hm-size-bottombar">{bottomBar}</div> : null}
      {homeIndicator ? (
        <div className="hm-size-home-indicator" aria-hidden="true" />
      ) : null}
    </div>
  );
}
