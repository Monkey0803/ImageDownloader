/**
 * AIBottomBar — the reference's AI bottom indicator bar.
 * A thin indicator strip that marks the AI entry point at the bottom edge.
 */
export function AIBottomBar({ theme = "light", indicator = true, className = "", ...rest }) {
  const cls = ["hm-aibottombar", `hm-aibottombar-${theme}`, className].filter(Boolean).join(" ");
  return (
    <div className={cls} data-component="aibottombar" {...rest}>
      {indicator ? <div className="hm-aibottombar-indicator" aria-hidden="true" /> : null}
    </div>
  );
}
