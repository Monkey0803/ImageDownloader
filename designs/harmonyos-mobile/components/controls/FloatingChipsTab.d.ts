/**
 * @startingPoint section="Controls" subtitle="Text / icon chips with an activated state" viewport="700x220"
 */
export interface ChipItem {
  key?: string;
  title: string;
  /** HMSymbol name — only rendered by the `tab-with-icon` variant. */
  icon?: string;
  /** Optional trailing count badge. */
  count?: number;
}
export interface FloatingChipsTabProps {
  /** `tab` text only · `tab-with-icon` icon + text · `icontab` adds a trailing button. */
  variant?: "tab" | "tab-with-icon" | "icontab";
  chips?: ChipItem[];
  activeIndex?: number;
  onSelect?: (index: number) => void;
  /** HMSymbol name for the `icontab` trailing utility button. */
  trailingIcon?: string;
  onTrailing?: () => void;
  className?: string;
}
export declare function FloatingChipsTab(props: FloatingChipsTabProps): JSX.Element;
