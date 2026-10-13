/**
 * @startingPoint section="Shell" subtitle="Device canvas with theme + material attributes" viewport="700x820"
 */
export interface SizeFrameProps {
  /** Canvas variant from the reference. Only `phone-portrait` is documented with a
   *  styled size today; the others are identification-only (see readme gaps). */
  device?: "phone-portrait" | "phone-landscape" | "foldable" | "tablet-portrait" | "tablet-landscape";
  /** Override the canvas width (default 360px). */
  width?: number | string;
  /** Override the canvas height (default 792px; the card layout uses 780px). */
  height?: number | string;
  theme?: "light" | "dark";
  /** MaterialType — `immersive` adds the light edge where the tier can render it. */
  materialType?: "adaptive" | "immersive";
  /** MaterialLevel — the compute tier that sets glass thickness. */
  materialLevel?: "exquisite" | "gentle" | "smooth";
  /** Status bar node; pass <StatusBar /> or omit for a bare canvas. When a
   *  Titlebar is used, leave this empty — the title bar carries its own status row
   *  and adding both would reserve the 36px band twice. */
  statusbar?: React.ReactNode;
  /** Floating title bar, pinned to the top edge by the frame. */
  titlebar?: React.ReactNode;
  /** Floating bottom bar (BottomTab / AIBottomBar), pinned to the bottom edge. */
  bottomBar?: React.ReactNode;
  homeIndicator?: boolean;
  /** Installs the pooled 沉浸光感 pointer delegate for the whole frame. */
  lightEffect?: boolean;
  className?: string;
  style?: React.CSSProperties;
  children?: React.ReactNode;
}
export declare function SizeFrame(props: SizeFrameProps): JSX.Element;
