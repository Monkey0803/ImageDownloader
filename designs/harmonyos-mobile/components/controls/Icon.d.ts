/**
 * @startingPoint section="Controls" subtitle="HMSymbol glyph from the official dictionary" viewport="700x180"
 */
export interface IconProps {
  /** Official HMSymbol semantic name, e.g. "chevron_right". Must exist in the
   *  generated map — unknown names render a "?" placeholder and warn. */
  name: string;
  /** 16 | 20 | 24 (the reference's icon sizes). */
  size?: 16 | 20 | 24;
  className?: string;
  style?: React.CSSProperties;
  /** Accessible label. Omit for decorative icons (they get aria-hidden). */
  label?: string;
}
export declare function Icon(props: IconProps): JSX.Element;
export declare const ICON_NAMES: string[];
