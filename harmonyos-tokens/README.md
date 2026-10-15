# @yostar/harmony-tokens

**Generated — do not edit anything in this folder.**

Every file here is produced by `designs/harmonyos-mobile/tools/build-token-har.mjs`
from the design system's `tokens/*.css`. Change the tokens there and regenerate:

```bash
cd designs/harmonyos-mobile
node tools/build-token-har.mjs          # write
node tools/build-token-har.mjs --check  # verify it is in sync (CI)
```

## Use it from an app

```json5
// <app>/entry/oh-package.json5
"dependencies": { "@yostar/harmony-tokens": "file:../../harmonyos-tokens" }
```

```ts
import { Palette, Metrics } from '@yostar/harmony-tokens';

Text('标题')
  .fontColor(Palette.fontPrimary)
  .fontSize(Metrics.fontSizeTitleL)
  .padding({ left: Metrics.pagePadH })
```

85 colours (light + dark) and 91 dimensions, generated from
11 token blocks.

## Overriding a token: you cannot, by redeclaring it

A resource name belongs to the module that declares it FIRST. This was verified by
building an app that redeclared `hm_brand`:

```
WARN: Warning: 'hm_brand' conflict, first declared.
BUILD SUCCESSFUL
```

The build succeeds, the HAR's value wins, and the app's declaration is silently
dropped. So do not try to retheme by shadowing a token.

If an app genuinely needs a different value for one spot:

1. **Preferred** — do not use the token there; use the app's own resource name
   (e.g. `brand_alt`) declared in the app, and reference it directly.
2. Or override at the call site in ArkTS for that one component.
3. If the whole app needs a different palette, that is a different design system —
   forking the tokens is more honest than shadowing a shared package.
