# broken fixture — the verifier must FAIL here

> **Why this lives OUTSIDE the design system tree.**
> `compile-design-system.mjs` walks the whole directory and treats **any** `.jsx`
> file it finds as a component. A fixture kept inside `harmonyos-mobile/` therefore
> got bundled: an extra `Other` component appeared in `_ds_manifest.json`, built from
> a file that deliberately imports React the wrong way. The fixture is a sibling
> directory instead, so the compiler never sees it. Run it with:
>
> ```bash
> cd harmonyos-mobile && node tools/verify-harmony.mjs --root ../harmonyos-mobile-verify-fixture
> ```


This is a miniature, deliberately non-conforming design system. `tools/verify-harmony.mjs`
is run against it in CI (`--root tools/fixtures/broken`) and **must report failures and
exit non-zero**.

Why it exists: a rule set that only ever passes is indistinguishable from no rule set.
Every violation below is a mistake that was actually made while building this system.

| File | Trips | Mistake it replays |
|---|---|---|
| `styles.css` | R2, R9 | real CSS rules in the entry file; a missing asset URL |
| `base.css` | R1, R10 | a `var(--nope)` with no definition; a stray `!important` |
| `tokens/colors.css` | R6 | `--harmony-titlebar-gap: 12px` instead of the mandatory 8px |
| `components/broken/Broken.jsx` | R3, R4, R7, R8 | no `.d.ts`/`.prompt.md`; `import { useState } from "react"`; `data-hm-light` on a `<div>` |

Additional violations: `components/broken/broken.css` trips R12 (a component redefining a
system token), and `components/broken/Other.*` trips R5 (the `.d.ts` declares a different
symbol) and R11 (an icon name that is not in the generated map).
