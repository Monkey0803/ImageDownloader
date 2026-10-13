/**
 * @startingPoint section="Controls" subtitle="Emphasized / normal / warning × small / medium, with loading" viewport="700x260"
 */
export interface ButtonProps {
  children?: React.ReactNode;
  /** Control height: `small` (36) or `medium` (40). */
  size?: "small" | "medium";
  /** `emphasized` is the brand-filled primary action; `normal` is the neutral
   *  surface; `selected`/`unselected` are the toggle pair; `warning` is destructive. */
  type?: "emphasized" | "normal" | "selected" | "unselected" | "warning";
  loading?: boolean;
  disabled?: boolean;
  /** HMSymbol name for a leading icon. */
  icon?: string;
  onClick?: (event: React.MouseEvent<HTMLButtonElement>) => void;
  className?: string;
  style?: React.CSSProperties;
  /** Opt into 沉浸光感. Buttons are focal components, so this defaults to true. */
  light?: boolean;
}
export declare function Button(props: ButtonProps): JSX.Element;
