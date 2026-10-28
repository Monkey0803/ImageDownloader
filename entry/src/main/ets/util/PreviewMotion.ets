import { PreviewGeometry, PreviewPosition, PreviewSize } from './PreviewGeometry';

export class PreviewMotionStep implements PreviewPosition {
  x: number = 0;
  y: number = 0;
  vx: number = 0;
  vy: number = 0;
  done: boolean = false;
}

/** vp / seconds. Pure motion policy shared by touch handling and deterministic tests. */
export class PreviewMotion {
  static resistance(value: number, limit: number): number {
    const excess: number = Math.max(0, Math.abs(value) - limit);
    return excess === 0 ? value : Math.sign(value) * (limit + 64 * excess / (160 + excess));
  }

  static rubber(image: PreviewSize, viewport: PreviewSize, zoom: number, value: PreviewPosition): PreviewPosition {
    const fit: PreviewSize = PreviewGeometry.fit(image, viewport);
    return { x: PreviewMotion.resistance(value.x, Math.max(0, (fit.width * zoom - viewport.width) / 2)),
      y: PreviewMotion.resistance(value.y, Math.max(0, (fit.height * zoom - viewport.height) / 2)) };
  }

  static advance(image: PreviewSize, viewport: PreviewSize, zoom: number, value: PreviewMotionStep,
    elapsed: number): PreviewMotionStep {
    const dt: number = Math.max(0.001, Math.min(0.032, elapsed));
    const bounded: PreviewPosition = PreviewGeometry.clamp(image, viewport, zoom, value);
    const result: PreviewMotionStep = new PreviewMotionStep();
    result.vx = PreviewMotion.velocity(value.x, bounded.x, value.vx, dt);
    result.vy = PreviewMotion.velocity(value.y, bounded.y, value.vy, dt);
    result.x = value.x + result.vx * dt;
    result.y = value.y + result.vy * dt;
    const next: PreviewPosition = PreviewGeometry.clamp(image, viewport, zoom, result);
    // Bounded overscroll even after a very fast fling or a delayed UI frame.
    result.x = Math.max(next.x - 64, Math.min(next.x + 64, result.x));
    result.y = Math.max(next.y - 64, Math.min(next.y + 64, result.y));
    result.done = Math.abs(result.vx) < 4 && Math.abs(result.vy) < 4
      && Math.abs(result.x - next.x) < 0.5 && Math.abs(result.y - next.y) < 0.5;
    if (result.done) { result.x = next.x; result.y = next.y; result.vx = 0; result.vy = 0; }
    return result;
  }

  private static velocity(value: number, bound: number, speed: number, dt: number): number {
    const limited: number = Number.isFinite(speed) ? Math.max(-6000, Math.min(6000, speed)) : 0;
    const friction: number = value === bound ? 5.5 : 17;
    return (limited - (value - bound) * 190 * dt) * Math.exp(0 - friction * dt);
  }

  static dismiss(distance: number, velocity: number, viewportHeight: number): boolean {
    return distance > Math.max(72, Math.min(160, viewportHeight * 0.18)) || (distance > 48 && velocity > 900);
  }

  static progress(image: PreviewSize, viewport: PreviewSize, zoom: number, y: number): number {
    const top: number = PreviewGeometry.top(image, viewport, zoom).y;
    return top > 0 ? Math.max(0, Math.min(1, (top - y) / (2 * top))) : 0;
  }

  static seek(image: PreviewSize, viewport: PreviewSize, zoom: number, progress: number): PreviewPosition {
    const top: number = PreviewGeometry.top(image, viewport, zoom).y;
    return { x: 0, y: top * (1 - 2 * Math.max(0, Math.min(1, progress))) };
  }
}
