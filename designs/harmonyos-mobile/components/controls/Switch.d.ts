/**
 * @startingPoint section="Controls" subtitle="On / off / disabled with the light effect" viewport="700x160"
 */
export interface SwitchProps {
  on?: boolean;
  disabled?: boolean;
  /** Accessible name — a bare toggle has no text of its own. */
  label?: string;
  onChange?: (next: boolean) => void;
  className?: string;
  /** Opt into 沉浸光感 (a Toggle is a focal component per the material spec). */
  light?: boolean;
}
export declare function Switch(props: SwitchProps): JSX.Element;
