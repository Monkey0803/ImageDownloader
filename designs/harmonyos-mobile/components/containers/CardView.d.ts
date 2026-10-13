/**
 * @startingPoint section="Containers" subtitle="Card surface in five sizes with floating icon buttons" viewport="700x420"
 */
export interface CardIconButton {
  /** `left` / `right` float at the card's top corners; `br` pins to bottom-right. */
  position?: "left" | "right" | "br";
  /** HMSymbol name. */
  glyph: string;
  label: string;
  onClick?: (event: React.MouseEvent<HTMLButtonElement>) => void;
}
export interface CardViewProps {
  size?: "mini" | "small" | "medium" | "larger" | "max";
  iconButtons?: CardIconButton[];
  onClick?: (event: React.MouseEvent<HTMLDivElement>) => void;
  className?: string;
  style?: React.CSSProperties;
  /** Card body. */
  children?: React.ReactNode;
}
export declare function CardView(props: CardViewProps): JSX.Element;
