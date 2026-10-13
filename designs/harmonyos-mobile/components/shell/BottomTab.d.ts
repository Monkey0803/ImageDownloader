/**
 * @startingPoint section="Shell" subtitle="Locked-width glass pill bar, 2–5 tabs plus 1bar / multibar" viewport="700x560"
 */
export interface BottomTabItem {
  key?: string;
  /** HMSymbol name. */
  icon: string;
  label: string;
}
export interface BottomTabProps {
  /** Tab count locks the bar width: 2→160 · 3→236 · 4/5→328 · 1bar/multibar→264. */
  variant?: "2" | "3" | "4" | "5" | "1bar" | "multibar";
  items?: BottomTabItem[];
  activeIndex?: number;
  onSelect?: (index: number) => void;
  /** The 28px Home Indicator zone; set false to leave the reserved space empty. */
  homeIndicatorBar?: boolean;
  albumSrc?: string;
  expandLabel?: string;
  /** 1bar only. */
  expandIcons?: { glyph: string; label: string; onClick?: () => void }[];
  circleIcon?: string;
  className?: string;
}
export declare function BottomTab(props: BottomTabProps): JSX.Element;
