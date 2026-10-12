/*
 * Tokens.ets — the design prototype's token layer, ported 1:1.
 *
 * Source of truth: designs/image-downloader-ui/index.html (`:root` and the
 * `[data-theme="dark"]` override). Colours are app resources so the light and
 * dark resource folders carry the two theme variants; every other token is a
 * plain vp number, which is what the 360 px design canvas maps to.
 */

/** Theme-aware colours. Each name mirrors a CSS custom property. */
export class Palette {
  static readonly brand: Resource = $r('app.color.brand');
  static readonly brandSoft: Resource = $r('app.color.brand_soft');
  static readonly brandFaint: Resource = $r('app.color.brand_faint');
  static readonly confirm: Resource = $r('app.color.confirm');
  static readonly alert: Resource = $r('app.color.alert');
  static readonly warning: Resource = $r('app.color.warning');

  static readonly fontPrimary: Resource = $r('app.color.font_primary');
  static readonly fontSecondary: Resource = $r('app.color.font_secondary');
  static readonly fontTertiary: Resource = $r('app.color.font_tertiary');
  static readonly fontFourth: Resource = $r('app.color.font_fourth');
  static readonly fontOnPrimary: Resource = $r('app.color.font_on_primary');

  static readonly bg: Resource = $r('app.color.bg');
  static readonly bgCanvas: Resource = $r('app.color.bg_canvas');
  static readonly card: Resource = $r('app.color.card');
  static readonly cardSunken: Resource = $r('app.color.card_sunken');
  static readonly divider: Resource = $r('app.color.divider');
  static readonly switchOff: Resource = $r('app.color.switch_off');
  static readonly hover: Resource = $r('app.color.hover');
  static readonly pressed: Resource = $r('app.color.pressed');
  static readonly scrim: Resource = $r('app.color.scrim');
  static readonly glass: Resource = $r('app.color.glass');
  static readonly glassStrong: Resource = $r('app.color.glass_strong');

  static readonly chipOkBg: Resource = $r('app.color.chip_ok_bg');
  static readonly chipWarnBg: Resource = $r('app.color.chip_warn_bg');
  static readonly chipAlertBg: Resource = $r('app.color.chip_alert_bg');
  static readonly dangerBg: Resource = $r('app.color.danger_bg');
  static readonly dangerBgPress: Resource = $r('app.color.danger_bg_press');
  static readonly toastBg: Resource = $r('app.color.toast_bg');
  static readonly viewerBg: Resource = $r('app.color.viewer_bg');
  static readonly segOn: Resource = $r('app.color.seg_on');
  static readonly sheen: Resource = $r('app.color.sheen');

  static readonly shadowCard: Resource = $r('app.color.shadow_card');
  static readonly shadowFloat: Resource = $r('app.color.shadow_float');
  static readonly shadowAction: Resource = $r('app.color.shadow_action');

  static readonly fadeSolid: Resource = $r('app.color.fade_solid');
  static readonly fadeStrong: Resource = $r('app.color.fade_strong');
  static readonly fadeSoft: Resource = $r('app.color.fade_soft');
  static readonly fadeNone: Resource = $r('app.color.fade_none');

  static readonly transparent: ResourceColor = Color.Transparent;
  static readonly white: ResourceColor = Color.White;
}

/** Spacing scale (`--sp-*`). */
export class Space {
  static readonly s2: number = 2;
  static readonly s4: number = 4;
  static readonly s6: number = 6;
  static readonly s8: number = 8;
  static readonly s10: number = 10;
  static readonly s12: number = 12;
  static readonly s14: number = 14;
  static readonly s16: number = 16;
  static readonly s18: number = 18;
  static readonly s20: number = 20;
  static readonly s24: number = 24;
  static readonly s32: number = 32;
}

/** Corner radii (`--r-*`). */
export class Radius {
  static readonly r4: number = 4;
  static readonly r6: number = 6;
  static readonly r8: number = 8;
  static readonly r10: number = 10;
  static readonly r20: number = 20;
  static readonly full: number = 100;
}

/** Page geometry. */
export class Layout {
  /** 360 px design canvas at 1x. */
  static readonly pageWidth: number = 360;
  static readonly pagePad: number = 16;
  static readonly contentWidth: number = 328;

  /** Title bar: 12 top padding + a 40 tall title/action row + 8 to first item. */
  static readonly tbPadTop: number = 12;
  static readonly tbRow: number = 40;
  static readonly tbGap: number = 8;
  static readonly tbFade: number = 32;
  /** Text layer with a subtitle (title 35 + 1 + subtitle 19 + 12). */
  static readonly tbLayerNormal: number = 52;
  static readonly tbLayerSecondary: number = 67;

  /** Bottom tab: 16 clearance + 56 pill + the home-indicator zone. */
  static readonly tabBarHeight: number = 56;
  static readonly tabBarTopPad: number = 16;
  static readonly homeIndicator: number = 28;
}

/** Type scale used across the screens. */
export class Font {
  static readonly title: number = 26;
  static readonly titleLine: number = 35;
  static readonly subtitle: number = 14;
  static readonly subtitleLine: number = 19;
  static readonly sectionTitle: number = 15;
  static readonly sectionMeta: number = 12;
  static readonly body: number = 15;
  static readonly bodyLine: number = 21;
  static readonly aux: number = 13;
  static readonly auxLine: number = 18;
  static readonly caption: number = 12;
  static readonly captionLine: number = 17;
  static readonly tab: number = 10;
  static readonly chip: number = 11;
  static readonly hero: number = 20;
}

/** Shared shadow recipes matching `--shadow-*`. */
export class Shadow {
  static card(): ShadowOptions {
    return { radius: 10, color: $r('app.color.shadow_card'), offsetX: 0, offsetY: 2 };
  }

  static float(): ShadowOptions {
    return { radius: 32, color: $r('app.color.shadow_float'), offsetX: 0, offsetY: 8 };
  }

  static action(): ShadowOptions {
    return { radius: 48, color: $r('app.color.shadow_action'), offsetX: 0, offsetY: 8 };
  }

  static none(): ShadowOptions {
    return { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 };
  }
}

/** 0..100, guarding against a zero total. */
export function percentOf(processed: number, total: number): number {
  if (total <= 0) {
    return 0;
  }
  return Math.max(0, Math.min(100, Math.round((processed / total) * 100)));
}

/** "—" / "512 B" / "1.3 MB" / "2.10 GB", matching the prototype's formatBytes. */
export function formatBytes(bytes: number): string {
  if (bytes <= 0) {
    return '—';
  }
  if (bytes < 1024) {
    return bytes.toString() + ' B';
  }
  if (bytes < 1024 * 1024) {
    return (bytes / 1024).toFixed(0) + ' KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  }
  return (bytes / 1024 / 1024 / 1024).toFixed(2) + ' GB';
}

/** "刚刚" / "今天 14:28" / "10-09 09:24", matching the prototype's timestamps. */
export function formatMoment(at: number, now: number): string {
  if (at <= 0) {
    return '—';
  }
  const elapsed: number = now - at;
  if (elapsed < 60 * 1000) {
    return '刚刚';
  }
  const stamp: Date = new Date(at);
  const today: Date = new Date(now);
  const pad = (value: number): string => value < 10 ? '0' + value.toString() : value.toString();
  const clock: string = pad(stamp.getHours()) + ':' + pad(stamp.getMinutes());
  const sameDay: boolean = stamp.getFullYear() === today.getFullYear()
    && stamp.getMonth() === today.getMonth()
    && stamp.getDate() === today.getDate();
  if (sameDay) {
    return '今天 ' + clock;
  }
  const yesterday: Date = new Date(now - 24 * 60 * 60 * 1000);
  const wasYesterday: boolean = stamp.getFullYear() === yesterday.getFullYear()
    && stamp.getMonth() === yesterday.getMonth()
    && stamp.getDate() === yesterday.getDate();
  if (wasYesterday) {
    return '昨天 ' + clock;
  }
  return pad(stamp.getMonth() + 1) + '-' + pad(stamp.getDate()) + ' ' + clock;
}

/** Upper-case extension badge ("JPG", "WEBP"), or "IMG" when there is none. */
export function kindOf(name: string): string {
  const dot: number = name.lastIndexOf('.');
  if (dot <= 0 || dot === name.length - 1) {
    return 'IMG';
  }
  return name.substring(dot + 1).toUpperCase();
}

/** Host portion of a URL, for the compact browser chrome. */
export function hostOf(url: string): string {
  const withoutScheme: string = url.replace(new RegExp('^[a-zA-Z]+://'), '');
  const slash: number = withoutScheme.indexOf('/');
  return slash > 0 ? withoutScheme.substring(0, slash) : withoutScheme;
}
