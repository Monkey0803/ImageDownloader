# ArkUI mapping

How this system's design tokens reach a real HarmonyOS app.

Read this before writing `.ets`. It states plainly what converts automatically, what
needs one line of ArkTS, and **what has no equivalent at all** — a design system that
pretends every CSS concept has a native twin is worse than one that admits the gaps.

---

## The boundary

This design system is a **design-time** artifact: React components rendered in a
browser. `_ds_bundle.js` is DOM code, **not** ArkTS. It does not generate page code
and it cannot be shipped in an app.

What does cross the boundary is the **token layer**:

```bash
node tools/emit-ohos-resources.mjs --out entry/src/main/resources
```

```
base/element/color.json   85 colours, #AARRGGBB
dark/element/color.json   85 colours, the dark overrides
base/element/float.json   88 dimensions (vp; unitless)
```

`float.json` lives only in `base/` — a dimension is theme-invariant, and duplicating
it into `dark/` is how the two copies drift apart.

---

## Tokens → resources

Naming: `--harmony-font-primary` → `hm_font_primary` (prefix configurable with
`--prefix`). Hyphens become underscores because resource names must be valid ArkTS
identifiers.

| Design token | Emitted resource | ArkTS |
|---|---|---|
| `--harmony-brand` | `hm_brand` = `#FF0A59F7` | `.fontColor($r('app.color.hm_brand'))` |
| `--harmony-comp-background-primary` | `hm_comp_background_primary` | `.backgroundColor($r('app.color.hm_comp_background_primary'))` |
| `--harmony-font-primary` | `hm_font_primary` | `.fontColor($r('app.color.hm_font_primary'))` |
| `--harmony-font-size-title-l` | `hm_font_size_title_l` = `30` | `.fontSize($r('app.float.hm_font_size_title_l'))` |
| `--harmony-titlebar-pad-top` | `hm_titlebar_pad_top` = `12` | `.padding({ top: $r('app.float.hm_titlebar_pad_top') })` |
| `--harmony-titlebar-layer-normal` | `hm_titlebar_layer_normal` = `52` | `.height($r('app.float.hm_titlebar_layer_normal'))` |
| `--harmony-tabbar-h` | `hm_tabbar_h` = `56` | pill height |
| `--harmony-tabbar-indicator` | `hm_tabbar_indicator` = `28` | the Home Indicator band |
| `--harmony-corner-radius-level8` | `hm_corner_radius_level8` = `16` | `.borderRadius($r('app.float.hm_corner_radius_level8'))` |

`calc()` is evaluated by the emitter, so derived geometry arrives as a number
(`--harmony-titlebar-layer-normal` is `calc(12px + 40px)` in CSS and `52` in the
resource file). **Font sizes are just numbers in `float.json`** — the unit comes from
the API: `fontSize` interprets it as fp, `width`/`height`/`padding` as vp.

### Colours are already ARGB

The reference documents colours as `#AARRGGBB` and that is also `color.json`'s native
format, so nothing is translated — `rgba(10, 89, 247, 1)` and `#FF0A59F7` are the same
value in the two notations.

---

## What needs a line of ArkTS

### Safe areas — do not port `max(env(…))`

`--harmony-safe-top` is `max(env(safe-area-inset-top), 36px)`. That CSS expression has
no ArkTS twin and is deliberately **not emitted** (`max()` is unresolvable
statically). Use the platform mechanism:

```ts
// Let the system place the content outside the avoid area.
Column() { /* … */ }
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
```

The design-time `36` / `28` are the reference's **mockup** status-bar and Home
Indicator sizes. On device the system owns both bands; you reserve space for them,
you do not draw them.

### Material — BlurStyle plus the system's own settings

The three MaterialLevels map to ArkUI blur styles:

| MaterialLevel | BlurStyle | Design-time blur |
|---|---|---|
| `EXQUISITE` | `BlurStyle.COMPONENT_ULTRA_THICK` | 120px (pill) / 18px (title bar) |
| `GENTLE` (default) | `BlurStyle.COMPONENT_THICK` | 80px / 12px |
| `SMOOTH` | `BlurStyle.COMPONENT_THIN` | 32px / 4.8px |

Query the device before assuming support, and degrade rather than fail:

```ts
import { uiMaterial } from '@kit.ArkUI';

let types: uiMaterial.MaterialType[] = [];
try {
  types = uiMaterial.getSystemMaterialTypes();   // may throw 801 if unsupported
} catch (e) {
  // 801 = capability not supported: fall back to ADAPTIVE and no light edge
}
const level = uiMaterial.getGlobalMaterialLevel();
```

The light edge (双边流光 / MaterialType `IMMERSIVE`) **must be dropped on the SMOOTH
tier** — that graceful degradation is verified on the design side by
`guidelines/material-types.html`.

### 沉浸光感 — no direct ArkUI call

The design-time glow is a radial gradient driven by a pointer listener on
`data-hm-light` elements. ArkUI has no equivalent "light the touched object" API; the
system draws this itself when the global setting is on. **Do not fake it with a
gradient overlay** — a hand-rolled glow that ignores the system setting looks wrong
exactly when the user has switched it off.

The design-side whitelist is still the rule to follow when choosing *which* elements
are focal: title bar, TabBar, dialogs, Slider / Toggle / Select. Never content.

### 智感握姿 (Multimodal Awareness Kit)

```ts
import { multimodalAwareness } from '@kit.MultimodalAwarenessKit';

// API 15: operatingHandChanged   API 20: holdingHandChanged
multimodalAwareness.on('operatingHandChanged', (data) => {
  // data.operatingHand: OperatingHandStatus
  // move primary actions into the reachable half; the design system's 智感握姿
  // rows exist to demonstrate the reaction, not to own the switch
});
```

Requires the `ohos.permission.ACTIVITY_MOTION` permission, and the API throws
**801** when the device cannot report it — so wrap it and keep the default layout.
**The app never toggles this.** It is a system setting; the app only reacts.

### 防窥保护 (privacy veil)

Also a system capability. The app is told that content should be hidden and must
respond — it cannot detect the observer itself. The design-time `防窥保护` row is a
read-only demonstration for the same reason.

### Icons — SymbolGlyph, never a drawn SVG

The design system's 40 curated names come from the official HMSymbol dictionary
(`assets/hmsymbol-map.json`, v2.1, 404 entries). On the ArkTS side use the system
symbol resources:

```ts
SymbolGlyph($r('sys.symbol.chevron_right'))
  .fontSize($r('app.float.hm_icon_size_24'))
```

Two recorded dictionary gaps, carried over honestly rather than papered over with an
SVG:

- a **line variant of the notification bell does not exist** (only `bell_fill`,
  `bell_slash`, `bell_slash_fill`) — the design system records the gap instead of
  inventing a glyph;
- the semantic name for close is `xmark` and for settings is `gearshape`; `close` and
  `gear` do not resolve.

`tools/gen-icon-map.mjs` **fails the build** on an unknown name, so a typo cannot
reach a screen.

---

## Verifying the two sides agree

```bash
node tools/verify-harmony.mjs                 # 12 design-side rules
node tools/emit-ohos-resources.mjs --dry-run  # what the resource files would become
```

`emit-ohos-resources.mjs` is **merge-preserving** (hand-added app resources survive),
**atomic** (temp file + rename), and **read-back self-checked**: it re-parses what it
wrote and fails if the round-trip does not reproduce every value. Run it in CI so a
token change that breaks the resource files cannot be merged.

### The gap this does not close

Nothing here verifies that an ArkTS screen *looks* the same as the HTML design. The
token values are guaranteed identical; the layout is not, because the two engines are
different. `guidelines/geometry-anchors.html` measures the design-side geometry
(36 / 12 / 40 / 8 / 96 and 100 = 16 + 56 + 28) and prints ✓/✗ per anchor — use the
same numbers as the acceptance checklist when reviewing a native build.
