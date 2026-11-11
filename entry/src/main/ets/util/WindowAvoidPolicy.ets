export interface WindowInsets {
  top: number;
  bottom: number;
  left: number;
  right: number;
}

/** Combine the live system bar, gesture and cutout avoid areas before converting px to vp. */
export function windowInsets(statusTop: number, indicatorBottom: number, gestureBottom: number,
  cutoutTop: number, cutoutBottom: number, cutoutLeft: number, cutoutRight: number,
  density: number): WindowInsets {
  const scale: number = density > 0 ? density : 1;
  return {
    top: Math.max(statusTop, cutoutTop, 0) / scale,
    bottom: Math.max(indicatorBottom, gestureBottom, cutoutBottom, 0) / scale,
    left: Math.max(cutoutLeft, 0) / scale,
    right: Math.max(cutoutRight, 0) / scale
  };
}
