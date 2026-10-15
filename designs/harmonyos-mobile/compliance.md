# Compliance

Two things live here: the values the reference **mandates**, and the traps that were
**actually fallen into** while building this system. The trap list is the useful half —
every entry produced a wrong pixel or a silent no-op, and every one is now either
fixed by a tool or caught by `tools/verify-harmony.mjs`.

Run the checks:

```bash
node tools/verify-harmony.mjs                  # 12 static rules
node tools/emit-ohos-resources.mjs --dry-run   # token → resource drift
```

The nine-year-old distinction to keep in mind: **a rule that is only written down is
not enforced.** Mandatory values are enforced by `R6`; dangling references by `R1`;
asset paths by `R9`; token redefinition by `R12`.

---

## A · Mandatory values (from the reference)

| Rule | Value | Enforced / verified by |
|---|---|---|
| titlebar text layer → first content | **8px** | `R6` (`--harmony-titlebar-gap`) + `geometry-anchors.html` measures it |
| `normal` variant content `padding-top` | `96px` | `geometry-anchors.html` (36 + 52 + 8) |
| bottom container | `100 = 16 + 56 + 28` | `geometry-anchors.html`, measured |
| status bar | `360×36` | `safe-areas.html`, measured |
| Home Indicator band | `28px` | `geometry-anchors.html`, measured |
| page horizontal padding | `16px` | `--harmony-page-padding-mobile` |
| fixed content width | `328px` (360 − 16×2) | `spacing-scale.html` |
| pill bar width is locked by tab count | `160 / 236 / 328 / 328 / 264` | `shell.card.html`, measured (`tabBarW=328`) |
| icons: HMSymbol only, line variants only | no inline SVG | `R11` + `gen-icon-map.mjs` fails the build on unknown names |
| `styles.css` is import-only | — | `R2` |
| a component may not redefine a system token | — | `R12` |
| the light effect goes on focal, interactive components only | — | `R7` |

### The 124px nuance worth stating out loud

The reference fixes the secondary titlebar's **fade panel** at 124px and forbids
positioning search from it: *「124 是渐隐背板底边，不是间距基准」*. That is a
**z-order/overlap** requirement, not a spacing one. The gap between the titlebar's
text layer and the first content is **8px in both variants**. This system encodes the
8px once (`--harmony-titlebar-gap`) and takes the content offset from the variant's
layer token, so the two cannot disagree.

---

## B · Traps that were actually hit

Thirteen of them. Ordered by how quietly they failed — the ones at the bottom of the
list are the ones that produced a **wrong render with no error at all**.

### 1 · Template `url()` paths are relative to the *reference* tree

Status bar PNGs resolved to nothing once the CSS moved to `components/<group>/`, so
every status glyph was a 404. `import-template-css.mjs` now rewrites every `url()`
whose basename ships in `assets/`, and **fails the build** when an asset is missing —
a silent 404 is worse than a build error. Guarded by `R9`.

### 2 · Fixed blur literals made MaterialLevel a no-op

The templates write `--titlebar-blur: 12px` and `--bt-blur: 80px` as literals. The spec
says material parameters vary with the immersion-light strength and the compute tier,
so a literal turns the three levels into decoration on the **two most visible
surfaces**. Guarded by `R6`-adjacent geometry checks and re-measured in
`material-levels.html` (120 / 80 / 32px).

### 3 · Custom properties resolve where they are DECLARED

This is the architectural one.

```css
/* wrong — the scale is frozen at :root's value (1) and inherited as calc(80px * 1) */
:root { --shell-blur: calc(80px * var(--material-blur-scale)); }
```

A custom property is substituted on the element that declares it and then inherited
**already resolved**. So a derived token at `:root` silently ignores
`data-material-level` on descendants. Composition therefore happens on the element that
carries the attributes (`.hm-size`), which also avoids a theme × level cross-product.

### 4 · CSS comments do not nest

An automated annotator stamped `/* @kind … */` **inside** an existing comment. The
comment terminated early, the rest of it became invalid CSS, and the rule that
followed — `[data-material-level="exquisite"]` — was swallowed whole. The symptom was
baffling: `exquisite` did nothing while `gentle` and `smooth` worked.

Both the annotator and the verifier now split comments out before matching anything.

### 5 · The compiler strips `react` imports

```js
import { useEffect } from "react";   // compiles fine, then:
// ReferenceError: useEffect is not defined
```

The design-system compiler removes `react` / `react-dom` imports when it builds the
bundle, so hooks must be read off the global (`React.useEffect`). This only surfaces at
mount time. Guarded by `R4`.

### 6 · The `box-sizing` reset missed the real canvas

The reset was scoped to `.hm-frame` (the card wrapper) but the device canvas is
`.hm-size`. Without `border-box`, the 56px pill became 56 + 8 padding = **64px**, which
in turn ate the container's 16px top clearance. Measured, not eyeballed:
`geometry-anchors.html` now prints `56px ✓` and `16px ✓`.

### 7 · The same space counted twice

`--tabbar-space: 84px` already contained the 28px indicator band, and `--safe-bottom`
then added 6px on top: clearance came out **34px instead of 28px**. The indicator band
now exists in exactly one place (`--safe-bottom`).

### 8 · The status bar band had three different heights

The prose said 36, the page token said 36, and the first implementation said 32 — so the
title and the content were each off by 4px in opposite directions. Everything now
derives from `--harmony-page-padding-mobile-top`.

### 9 · The reference itself has a gap: no artwork for the titlebar's status glyphs

The titlebar template defines `.harmony-titlebar__status-icon--wifi / --sig1 / --sig2 /
--battery` with **exact geometry** (15.34×12 @ 0.4, 0.5 …) and **no `background-image`**,
so its internal status row renders as four empty boxes. The statusbar template *does*
ship the artwork.

Worse, the four asset URLs were injected on `.harmony-statusbar-light / -dark` — a
**component scope**, while theme is a canvas-level concept. The bridge re-declares the
same four assets on the theme scope. **Nothing is drawn by hand.**

### 10 · The presentation host followed `prefers-color-scheme` instead of the document

A card that declares `data-theme="light"` rendered on a dark host whenever the viewing
OS was dark — unreadable, and it made every light-theme specimen look broken.
`.hm-host` now follows the document's `data-theme`.

### 11 · The shell layers are `position: relative` — placement belongs to the page

`Titlebar` and `BottomTab` are placement-agnostic in the reference: the **page** is
expected to position them. That puts the hardest geometry in every screen's hands, and
it is exactly how the 8px gap and the 100px container get broken — the first render of
the UI kits put the tab bar in the middle of the screen with the title bar over the
search field.

The frame owns placement now:

```jsx
<SizeFrame titlebar={<Titlebar … />} bottomBar={<BottomTab … />}>
```

### 12 · A component CSS file redefined system tokens

`containers.css` carried the template's `:root` token dump, re-declaring
`--harmony-brand` (light) and `--harmony-divider-color`. Because the component CSS is
imported **last**, that `:root` declaration beat the token layer at equal specificity —
so anything that set `data-theme` on `<html>` rather than on a frame got a **light
brand in dark mode**, and dividers never flipped.

The importer now drops component-level redefinitions of system tokens, and `R12`
guards it.

### 13 · Any `.jsx` in the tree becomes a component

`compile-design-system.mjs` walks the whole directory. The deliberately broken
verification fixture lived inside it, so a component named `Other` — built from a file
that imports React the wrong way — appeared in `_ds_manifest.json` and in the bundle.

The fixture is now a **sibling directory**, outside the design system tree.

---

## C · What is deliberately NOT done

| Not done | Why |
|---|---|
| Drawing the 112×5 Home Indicator bar | The reference reserves the 28px band; the real system draws the bar. Drawing a second one overlaps it. |
| Repeating the StatusBar inside the titlebar when the frame already reserves 36px | That band would be reserved twice. Use the titlebar's own status row **or** the frame's slot, not both. |
| Faking 沉浸光感 in ArkTS with a gradient | The system draws it when the setting is on; a hand-rolled glow is wrong precisely when the user disabled it. |
| Drawing a line-variant notification bell | It does not exist in the dictionary (only `bell_fill` / `bell_slash` / `bell_slash_fill`). Recorded as a gap. |
| `HMSymbolVF_1.ttf` (1.7 MB) is not vendored | It is a HarmonyOS font asset, so it stays out of the repo (referenced by relative path; drop your own copy in `assets/`). Subsetting is a possible follow-up, not a correctness issue. |

---

## D · Pre-commit checklist

1. `node tools/verify-harmony.mjs` → exit 0
2. `check-design-system.mjs designs/harmonyos-mobile` → no issues
3. all four generators `--check` → 0 stale
4. `emit-ohos-resources.mjs --dry-run` → `0 added · 0 updated`
5. `guidelines/geometry-anchors.html` → 8/8 ✓
6. no hex literals in a page's own CSS (tokens only)
7. `data-hm-light` only on interactive components
8. both themes flip, and the light effect is visible on focal components only
