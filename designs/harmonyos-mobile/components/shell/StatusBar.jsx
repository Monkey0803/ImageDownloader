/**
 * StatusBar — the reference's 状态栏 (360×36).
 *
 * The four glyphs are PNG assets referenced from the sheet
 * (.hm-statusbar-icon-wifi / -single-card / -dual-card / -battery); they are
 * NEVER drawn here. The reference's statusbar spec forbids hand-drawn wifi /
 * signal / battery marks, so this component only places the slots.
 */
export function StatusBar({ time = "08:08", theme = "light", className = "", ...rest }) {
  const cls = ["hm-statusbar", `hm-statusbar-${theme}`, className].filter(Boolean).join(" ");
  return (
    <div className={cls} data-component="statusbar" {...rest}>
      <span className="hm-statusbar-time">{time}</span>
      <span className="hm-statusbar-icons" aria-hidden="true">
        <i className="hm-statusbar-icon hm-statusbar-icon-wifi" />
        <i className="hm-statusbar-icon hm-statusbar-icon-single-card" />
        <i className="hm-statusbar-icon hm-statusbar-icon-dual-card" />
        <i className="hm-statusbar-icon hm-statusbar-icon-battery" />
      </span>
    </div>
  );
}
