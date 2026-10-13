/**
 * @startingPoint section="Controls" subtitle="Idle / activated / typing / output, with the trailing action" viewport="700x260"
 */
export interface FloatingSearchProps {
  /** Visual state: `idle` (placeholder), `actived` (caret, no value),
   *  `typing` (value + caret), `output` (value as static text). */
  mode?: "idle" | "actived" | "typing" | "output";
  value?: string;
  placeholder?: string;
  /** Reveals the trailing action region (voice icon, divider, action button). */
  on?: boolean;
  actionLabel?: string;
  voice?: boolean;
  cancel?: boolean;
  onAction?: () => void;
  /** Fired when the field itself is tapped (focus/expand the field). */
  onActivate?: () => void;
  onChange?: (value: string) => void;
  className?: string;
  light?: boolean;
}
export declare function FloatingSearch(props: FloatingSearchProps): JSX.Element;
