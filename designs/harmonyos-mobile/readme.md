# HarmonyOS Mobile Design System

A design system for building **HarmonyOS mobile apps** in the native visual language:
a 360×792 canvas, floating glass title bars and pill tab bars, the three MaterialLevels,
MaterialType light edges, immersive light feedback, and the platform's own HMSymbol
icon font.

It exists to make one thing hard to get wrong: **the geometry and the token layer**.
The reference's mandatory values (the 8px titlebar gap, `100 = 16 + 56 + 28`, the
locked pill widths) are encoded once and then *measured*, not restated in prose.

> **Design-time only.** `_ds_bundle.js` is React/DOM code. It does not generate ArkTS
> and cannot be shipped in an app. What crosses into a real project is the token layer
> — see [`guidelines/arkui-mapping.md`](guidelines/arkui-mapping.md) and
> `tools/emit-ohos-resources.mjs`.

---

## Start here

| If you want to… | Read |
|---|---|
| know the rules and the traps they came from | [`compliance.md`](compliance.md) |
| build a screen that is correct by construction | [`ui_kits/card`](ui_kits/card/index.html) · `grid` · `list` · `settings` |
| see a value's measured proof | the card that measures it, e.g. [`guidelines/geometry-anchors.html`](guidelines/geometry-anchors.html) |
| ship tokens into an ArkTS app | [`guidelines/arkui-mapping.md`](guidelines/arkui-mapping.md) |
| check the system is still conformant | `node tools/verify-harmony.mjs` |

---

## Sources

Everything here is derived from the in-repo HarmonyOS reference library at
`~/.agents/skills/hmos-design-visual-mobile/` (read-only; never modified):

- `references/0.governance/` — `HarmonyOS Design.md`, `component.json` (13 components),
  `icon_role.md`, `emoji_role.md`, and the official `hmsymbol-map.json` (v2.1, 404 icons)
- `references/1.layout/` — `layout-card.md`, `layout-grid.md`, `layout-list.md`
- `references/2.theme/` — `harmony-tokens.css`, `mobile-scale.css`, `theme.md`
  (which documents colours as **ARGB**)
- `references/3.component/` — 13 component specs
- `references/4.template/` — 13 component HTML templates, translated byte-for-byte
- `references/assets/` — `HMSymbolVF_1.ttf`, the eight status bar PNGs

The component CSS is **not retyped**: `tools/import-template-css.mjs` translates the
templates (`.harmony-` → `.hm-`) and strips their `@import`/`@font-face`, leaving every
value identical. What the bridge changes is listed, with reasons, in
`components/theme-bridge.css`.

---

## CONTENT FUNDAMENTALS

The reference library is Chinese and its copy style is consistent, so new screens
should match it rather than invent a voice.

- **Language**: Simplified Chinese for UI copy. Numbers and units stay Latin
  (`148.3 MB`, `12 张`, `08:08`), separated from Chinese by a space.
- **Tone**: plain, operational, no exclamation marks, no marketing voice. A settings
  row says what it does: `同时下载数量` / `并发槽位，队列共用`.
- **Sub-labels**: a second line is lowercase-normal and factual — a unit, a count, a
  time (`1.8 MB · 今天 14:26`), never a second sentence of prose.
- **Titles**: short nouns, no trailing punctuation. `首页`, `发现`, `设置`, `文件`.
- **Verdicts**: one word, no colour-only meaning — `已完成` / `失败`（with the tinted
  icon as reinforcement, not as the only signal）.
- **System capabilities**: read-only demos say so. `以上为系统能力，应用只响应系统状态，不自行开关。`
- **Buttons**: verb-first and short. `新建下载任务`, `恢复默认`, `完成`. A destructive
  action is the word itself — `删除` — never `确定` on a destructive warning dialog.
- **Empty/error copy**: state the cause, not an apology. `服务器返回的不是图片`.

## VISUAL FOUNDATIONS

- **Canvas**: `360×792`, or `360×780` for the card layout. Content width `328`
  (360 − 16×2). Page padding `16` horizontally, `36` top, `28` bottom.
- **Colour**: the brand is a **fixed** blue (`#0A59F7`) and does not change with the
  theme. Everything else is semantic: `confirm` (green), `alert` (secondary warning),
  `warning` (primary warning). Text has four levels plus an emphasized level.
- **Theme**: light and dark, via `data-theme` on the canvas. Both sets are generated —
  132 colours each. **Never hard-code a colour in a page**: a literal cannot flip.
- **Type**: 13 steps. Display sizes are weight **300**, titles **700**, body **400**,
  subtitles **500**, captions **500**. That pairing is deliberate — do not mix them.
  Font stack is HarmonyOS Sans (a system font, so there is no binary to embed).
- **Glass and material**: every glass surface is *fill (with alpha) × backdrop blur ×
  shadow stack*. Three `MaterialLevel`s scale the thickness (`EXQUISITE` 1.5,
  `GENTLE` 1.0 the default, `SMOOTH` 0.4) and the fill alpha, so the levels are really
  different and not decoration. `MaterialType: IMMERSIVE` adds the light edge, and the
  edge is **dropped entirely** on the `SMOOTH` tier.
- **The light effect (沉浸光感)**: a radial glow that bleeds from the touch point, on
  **focal components only** — title bar, tab bar, dialogs, Slider/Toggle/Select,
  primary buttons. The reference's rule: *「满屏都是光感，就等于没有光感」*. Mark an
  element with `data-hm-light`; `SizeFrame` runs one delegated listener for the frame.
- **Interaction**: overlays are token-based (`hover` 4.7%, `pressed` 9.8%). Press
  feedback also shrinks a focal component slightly (`0.955`). Focus rings are 2px and
  never removed.
- **Elevation**: expressed with glass and shadow, not with borders. Cards sit on the
  page by surface contrast (`comp_background_primary` over `background_secondary`).
- **Radii**: `8 / 12 / 16 / 20 / 32 / 36` from `corner-radius-level*`. Pills are fully
  rounded, never a fixed small radius.
- **Floating layers**: the title bar and bottom bar **float**; content scrolls under
  the title bar's fade and above the pill's 16px clearance. They are never flex
  siblings that take layout height. Hand them to `SizeFrame`'s slots.
- **No imagery style is imposed.** Product imagery is the app's own; the system ships no
  photographic treatment, no grain, no illustration style.

## ICONOGRAPHY

- **HMSymbol only.** The reference forbids hand-drawn inline SVG for any glyph the
  official dictionary already contains. `assets/HMSymbolVF_1.ttf` (1.7 MB) is the font;
  `assets/hmsymbol-map.json` is the full official name → codepoint dictionary.
- **Line variants only.** When a semantic name has both an outline and a filled form,
  use the outline. Never mix `*_fill` into a line set.
- **40 curated names** are generated into `components/controls/IconMap.jsx` by
  `tools/gen-icon-map.mjs`, which **fails the build** on an unknown name and suggests
  near matches. A typo cannot reach a screen.
- Render with `<Icon name="chevron_right" size={24} />`. Sizes are `16 / 20 / 24`.
- **Two recorded dictionary gaps** (carried honestly rather than papered over):
  - a **line variant of the notification bell does not exist** — only `bell_fill`,
    `bell_slash`, `bell_slash_fill`;
  - the real names for close and settings are `xmark` and `gearshape`; `close` and
    `gear` do not resolve.
- The **status bar glyphs are PNGs**, not from the font (`assets/statusbar-*.png`, light
  and dark sets) — the reference ships them that way and forbids redrawing them.
- On the ArkTS side use `SymbolGlyph($r('sys.symbol.<name>'))` — see the mapping doc.

---

## Intentional additions

Five things exist here that the reference's component list of 13 does not contain. Each
is either required by the reference's own rules or explicitly sanctioned by them.

| Addition | Why it is necessary |
|---|---|
| **`Icon`** | The reference mandates HMSymbol for icons but provides no way to *render* one; a glyph needs a wrapper. The reference explicitly allows this kind of addition ("Icon wrapper for a glyph set"). Uses the font, never SVG. |
| **`SizeFrame` slot placement** (`titlebar` / `bottomBar`) | The reference leaves layer placement to each page, which is how the mandatory 8px gap and the 100px container get broken. Placement moved into the frame. |
| **`SizeFrame` light-effect delegate** | One pointer listener per frame instead of a handler on every component. Keeps `data-hm-light` declarative and honours the focal-components-only rule. |
| **`.hm-spec*` specimen chrome** | Card chrome for the guidelines pages. Ships with the system so a card renders identically from an imported copy; no component depends on it. |
| **`--harmony-icon-size-16/20/24`** | The reference encoded icon sizes only as `.hm-16/20/24` classes, so the token layer had no icon size and an ArkTS app had no resource to read. |

## Recorded gaps

Stated plainly, because a silently narrowed rule is worse than a known gap.

1. **Device variants are identification-only.** `SizeFrame` accepts
   `phone-landscape` / `foldable` / `tablet-*` and emits them as attributes, but the
   reference defines a canvas size for `phone-portrait` only. Pass explicit
   `width` / `height` for other form factors.
2. **The bell has no line variant** (see Iconography).
3. **`HMSymbolVF_1.ttf` is 1.7 MB** and is copied into every consuming project.
   Subsetting is a possible follow-up.
4. **2.4 MB of colour-emoji fonts were deliberately omitted.** The reference ships
   `HMOSColorEmojiCompat.ttf` and `HMOSColorEmojiFlags.ttf`; emoji rendering falls back
   to the host font.
5. **`--harmony-list-dot-color: #46B1E3`** is kept as a spec literal rather than
   remapped to a semantic token — it is the one raw colour left in `tokens/`, and it is
   there because the reference gives that exact value for the list dot.
6. **The verifier does not launch a browser.** R1–R12 are static; the geometry is
   verified by `guidelines/geometry-anchors.html`, which measures itself and prints ✓/✗
   per anchor. Run both.
7. **Nothing checks that an ArkTS screen matches the HTML design.** Token values are
   guaranteed identical; layout is not, because the engines differ.

---

## Index

```
styles.css              the only entry point — a list of @import lines, nothing else
fonts.css               @font-face for HMSymbol (HarmonyOS Sans is a system font)
base.css                host/frame, page canvas, showcase slots, scoped reset, light effect

tokens/                 GENERATED (except geometry + material, which are hand-written)
  colors.css            132 light + 132 dark
  typography.css        60
  spacing.css           50
  geometry.css          27   every value tagged SPEC or DERIVED
  material.css          20   primitives only — derived values compose in the bridge

components/
  shell/                SizeFrame · StatusBar · Titlebar · BottomTab · AIBottomBar · Toolbar
  controls/             Icon · Button · Switch · FloatingSearch · FloatingChipsTab · IconMap(generated)
  containers/           CardView · List · Divider
  theme-bridge.css      the one hand-audited override layer (each override states why)

guidelines/             16 foundation cards + arkui-mapping.md
ui_kits/
  card/                 mobile-card · 360×780
  grid/                 mobile-grid · 360×792
  list/                 mobile-list · 360×792
  settings/             mobile-list, control rows

tools/
  sync-tokens.mjs           tokens ← the reference library          (--check)
  import-template-css.mjs   templates → component CSS               (--check)
  gen-icon-map.mjs          icon names → codepoints                 (--check)
  annotate-tokens.mjs       stamps @kind on the hand-written files  (--check)
  verify-harmony.mjs        12 conformance rules
  emit-ohos-resources.mjs   tokens → ArkTS resource JSON

guidelines/arkui-mapping.md   design tokens → ArkTS resources, and the honest gaps

ohos-resources/         a generated sample of what emit-ohos-resources.mjs writes:
  entry/src/main/resources/
    base/element/color.json    85 colours, #AARRGGBB
    dark/element/color.json    85 dark overrides
    base/element/float.json    91 dimensions (calc() already evaluated)

compliance.md           the rules and the 13 traps
preview.html            every card in one self-contained file
```

Sibling (deliberately outside this tree — any `.jsx` inside it would be bundled as a
component): `../harmonyos-mobile-verify-fixture/`, the fixture that
`verify-harmony.mjs` must **fail** on.

## Portable

Copy the whole `harmonyos-mobile/` folder into another repo's `designs/` and it works:
`SKILL.md` makes it downloadable as an Agent Skill, its first heading and paragraph are
what a consumer's picker shows, and no path escapes the folder.
