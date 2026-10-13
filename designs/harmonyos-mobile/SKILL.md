---
name: harmonyos-mobile-design
description: Use this skill to design HarmonyOS mobile app interfaces and assets in the native HarmonyOS visual language — floating glass title bars, pill tab bars, the three MaterialLevels, MaterialType light edges, immersive light feedback, and HMSymbol iconography. Contains the token layer, 14 components, 4 layout UI kits, 16 foundation cards, conformance tooling, and an ArkTS resource emitter for production code.
user-invocable: true
---

Read the README.md file within this skill, and explore the other available files.

This system is a **design-time** artifact: its components are React/DOM and cannot ship
in a HarmonyOS app. For throwaway prototypes and mocks, copy assets out and build static
HTML pages the user can view. For production ArkTS, read `guidelines/arkui-mapping.md`
and run `tools/emit-ohos-resources.mjs` to turn the tokens into
`base|dark/element/color.json` and `base/element/float.json`.

Two things this system is strict about, because they are what actually break:

1. **Geometry.** The titlebar-to-content gap is 8px, and the bottom container is
   `100 = 16 + 56 + 28`. Put the floating layers in `SizeFrame`'s `titlebar` and
   `bottomBar` slots rather than as children — a title bar placed as a child lands in
   the content flow and breaks both numbers silently.
2. **Tokens, never literals.** Nothing in a page may carry a hard-coded colour; a
   literal cannot flip between light and dark. `compliance.md` lists the 13 real traps
   this system already fell into, and `tools/verify-harmony.mjs` enforces 12 rules.

Before calling a change done, run `node tools/verify-harmony.mjs` and confirm
`guidelines/geometry-anchors.html` shows 8/8 ✓.

If the user invokes this skill without other guidance, ask what they want to build,
whether it is a prototype or production ArkTS, and act as an expert HarmonyOS designer.
