/**
 * @startingPoint section="Shell" subtitle="Big / normal / secondary / drawer floating title bar" viewport="700x520"
 */
export interface TitlebarAction {
  /** HMSymbol name; falls back to the reference's circle_dashed placeholder. */
  glyph?: string;
  label: string;
  onClick?: () => void;
}
export interface TitlebarProps {
  /** `big` 205px with subtitle · `normal` title only · `secondary` back chevron +
   *  subtitle · `drawer` leading indent. */
  variant?: "big" | "normal" | "secondary" | "drawer";
  title: React.ReactNode;
  /** Only rendered by `big` and `secondary` — the reference forbids adding a
   *  subtitle to `normal`. */
  subtitle?: React.ReactNode;
  time?: string;
  /** Override the variant's default leading glyph (secondary/drawer only). */
  leadingGlyph?: string;
  onLeading?: () => void;
  actions?: TitlebarAction[];
  /** Hide the mock status row (e.g. nested inside a frame that draws its own). */
  showStatus?: boolean;
  theme?: "light" | "dark";
  className?: string;
  children?: React.ReactNode;
}
export declare function Titlebar(props: TitlebarProps): JSX.Element;
