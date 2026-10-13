/**
 * @startingPoint section="Shell" subtitle="Floating toolbar, 3–6 items" viewport="700x260"
 */
export interface ToolbarItem {
  key?: string;
  /** HMSymbol name. */
  icon: string;
  label: string;
  disabled?: boolean;
}
export interface ToolbarProps {
  /** Item count, which locks the toolbar width: 3 | 4 | 5 | 6, or `vertical-icon`. */
  variant?: "3" | "4" | "5" | "6" | "vertical-icon";
  items?: ToolbarItem[];
  activeIndex?: number;
  onSelect?: (index: number) => void;
  className?: string;
}
export declare function Toolbar(props: ToolbarProps): JSX.Element;
