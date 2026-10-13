export interface DividerProps {
  /** `""` full width · `inset` indented · `block` grouped block · `vertical`. */
  variant?: "" | "inset" | "block" | "vertical";
  className?: string;
}
export declare function Divider(props: DividerProps): JSX.Element;
