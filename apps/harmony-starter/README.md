# harmony-starter — the app template

A real, compiling HarmonyOS app that consumes the design system through a HAR. It
exists so that starting a new app is **one dependency line plus screens**, not a copy
of the token layer.

Verified build:

```bash
./build.sh          # -> entry/build/default/outputs/default/entry-default-unsigned.hap
```

`build.sh` sets three environment values that are not obvious and not on `PATH`;
they live in DevEco Studio's installation. See the comments in the script.

---

## What this app demonstrates

| | |
|---|---|
| **One dependency** | `entry/oh-package.json5` → `"@yostar/harmony-tokens": "file:../../../harmonyos-tokens"` |
| **No token literals** | `pages/Index.ets` contains zero hex colours and zero hard-coded layout numbers — every value is `Palette.*` or `Metrics.*` |
| **An almost empty resource file** | `entry/src/main/resources/base/element/color.json` declares only `start_window_background`, because all 85 colours and 91 dimensions come from the HAR |
| **System icons only** | `SymbolGlyph($r('sys.symbol.…'))` — nothing hand-drawn |
| **The screen matches the design** | a port of the design-time reference `designs/harmonyos-mobile/ui_kits/card` (floating title bar → search → stacked cards → floating pill tab bar) |

## Start a new app from this one

```bash
cp -R apps/harmony-starter apps/my-new-app
cd apps/my-new-app
```

Then change four things:

1. **`AppScope/app.json5`** — `bundleName` (currently `com.example.harmonystarter`).
2. **`AppScope/resources/base/element/string.json`** and
   **`entry/src/main/resources/base/element/string.json`** — the app label.
3. **`entry/oh-package.json5`** — the relative path to the token HAR, if the new app
   sits at a different depth.
4. **`entry/src/main/ets/pages/Index.ets`** — replace the template screen. Keep the
   `Palette` / `Metrics` habit.

Then:

```bash
cd designs/harmonyos-mobile        # if the tokens changed
node tools/build-token-har.mjs
cd ../../apps/my-new-app
ohpm install --all
./build.sh
```

**Signing:** `build-profile.json5` here has an empty `signingConfigs` on purpose. The
reference app's profile holds a real certificate with absolute paths and passwords;
copying that into a template would leak credentials and break on another machine. Let
DevEco Studio generate a signature for the new app, or fill the block in locally.

---

## Two constraints that were measured, not guessed

Both cost real debugging time; they are recorded here so the next app does not repeat it.

### `useNormalizedOHMUrl` must be `false` while the HAR is a `file:` dependency

With `true`, the ArkTS compiler fails:

```
10311002 ArkTS: ERROR
Failed to resolve OhmUrl ... imported by "null"
```

It normalises module URLs against the project root, and `ohpm` materialises a `file:`
dependency as a **symlink** whose real path is outside this project. Set it back to
`true` once the HAR comes from an ohpm registry — that is the layout it is designed for.
(The starter's `build-profile.json5` carries this note inline.)

### An app cannot override a token by redeclaring it

A resource name belongs to the module that declares it **first**. Adding
`hm_brand` to this app's `color.json` produced:

```
WARN: Warning: 'hm_brand' conflict, first declared.
BUILD SUCCESSFUL
```

The HAR wins, the app's value is **silently dropped**, and only a warning is printed.
So do not retheme by shadowing a token. If one spot needs a different value, use the
app's own resource name; if the whole app needs a different palette, that is a
different design system.

`tools/check-app-drift.mjs` flags this case as an error, because the failure is invisible:

```bash
cd designs/harmonyos-mobile
node tools/check-app-drift.mjs --app ../../apps/harmony-starter   # -> clean
node tools/check-app-drift.mjs --app ../..                        # -> the ImageDownloader drift
```
