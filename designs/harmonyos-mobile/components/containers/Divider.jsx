/**
 * Divider — the reference's 1px divider, in four variants:
 * `hm-divider` (full), `-inset`, `-block`, `-vertical`.
 */
export function Divider({ variant = "", className = "", ...rest }) {
  const cls = ["hm-divider", variant ? `hm-divider-${variant}` : "", className].filter(Boolean).join(" ");
  return <div className={cls} data-component="divider" role="separator" {...rest} />;
}
