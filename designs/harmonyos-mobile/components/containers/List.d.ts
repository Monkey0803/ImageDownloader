/**
 * @startingPoint section="Containers" subtitle="Six documented row heights with dividers that skip the icon" viewport="700x560"
 */
export interface ListProps {
  /** Row height and layout, straight from the reference matrix. */
  variant?: "single" | "icondot" | "iconsingle" | "2lines" | "icon2lines" | "3lines";
  title: React.ReactNode;
  /** First auxiliary line — rendered by the two- and three-line variants. */
  aux?: React.ReactNode;
  /** Second auxiliary line — `3lines` only. */
  aux2?: React.ReactNode;
  appIconSrc?: string;
  appIconAlt?: string;
  rightText?: React.ReactNode;
  /** `chevron` (HMSymbol) or `arrow-down` (a CSS triangle drawn by the sheet). */
  rightIcon?: "chevron" | "arrow-down" | null;
  onClick?: () => void;
  className?: string;
  children?: React.ReactNode;
}
export declare function List(props: ListProps): JSX.Element;
