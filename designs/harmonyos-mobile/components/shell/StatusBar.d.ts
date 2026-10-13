export interface StatusBarProps {
  /** Clock text. The reference renders the bar for mockups only — on a real
   *  device the system draws it and this component should be omitted. */
  time?: string;
  /** Picks the light or dark PNG set for the four glyphs. */
  theme?: "light" | "dark";
  className?: string;
}
export declare function StatusBar(props: StatusBarProps): JSX.Element;
