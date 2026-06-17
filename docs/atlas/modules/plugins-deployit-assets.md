---
module: plugins/deployit/assets
summary: "Static payload for deployit — xcodebuild export plists, OTA install web UI templates, PWA shell, config seed"
read_when: "Changing deployit's install pages, OTA manifest, export signing options, or config seed"
sources:
  - path: plugins/deployit/assets/ExportOptions.ios.plist
    blob: 5852d63680d64c09eedc16402acb77ff8ee908b8
  - path: plugins/deployit/assets/ExportOptions.macos.plist
    blob: bb805c5092b4b96097d0f8628a3366cf10d98320
  - path: plugins/deployit/assets/ExportOptions.visionos.plist
    blob: 5852d63680d64c09eedc16402acb77ff8ee908b8
  - path: plugins/deployit/assets/app.css
    blob: 1893c1890b7c0d46c57579d26d63db1e69284d21
  - path: plugins/deployit/assets/app.js
    blob: 1e648c224aa9257c8e0ec3958377fb30021a38d1
  - path: plugins/deployit/assets/appcast.template.xml
    blob: cafd1d470f8cea90690c9cdf5adbc56e8351d714
  - path: plugins/deployit/assets/config.example.toml
    blob: 875f5c13d3a956fa9f2353997da84dfc02a75fe0
  - path: plugins/deployit/assets/icons/icon.svg
    blob: d706e39034df2f1f5838ce57beab5623d8243146
  - path: plugins/deployit/assets/index.template.html
    blob: e0b564edf11a7723473248d94a3397eed55acf27
  - path: plugins/deployit/assets/listing.template.html
    blob: 47a89ff8324958e2c7969b33a93c61b1a34a140f
  - path: plugins/deployit/assets/manifest.template.plist
    blob: 10f7a574db399eef99e0474eae3e1bfb23abd317
  - path: plugins/deployit/assets/manifest.webmanifest
    blob: 8d80244cd1bf8c8ab565ddb2b1a1e17fb4468cd0
  - path: plugins/deployit/assets/product.template.html
    blob: 1262e6f64dfb9b2abe10d9736524c8cbc18c9dc2
references_modules: [plugins-deployit-bin]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
---

# Module: plugins/deployit/assets

## Purpose

Static payload of deployit: per-platform xcodebuild export options, template sources for
the OTA install web UI, the PWA shell (including app.js client-side logic), and the
per-machine config seed. Most substitution and serving logic lives in plugins/deployit/bin;
this module holds the contracts those scripts fill and the browser-side behavior, so page
appearance and signing policy change without touching the server.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `$INSTALL_HREF` | placeholder | `plugins/deployit/assets/index.template.html:37` | Install button target; itms-services link for IPAs |
| `$IPA_URL` | placeholder | `plugins/deployit/assets/manifest.template.plist:14` | HTTPS URL of the .ipa fetched during OTA install |
| `$ITEMS` | placeholder | `plugins/deployit/assets/appcast.template.xml:8` | Pre-rendered `<item>` elements injected into the Sparkle RSS channel |
| `$ROWS` | placeholder | `plugins/deployit/assets/listing.template.html:23` | Raw pre-rendered `<li>` markup, injected unescaped |
| `a.install` | CSS selector | `plugins/deployit/assets/app.css:28` | Button style; rows use .row .title .sub .older .archived |
| `base_url` | TOML key | `plugins/deployit/assets/config.example.toml:8` | Tailnet origin incl. /deployit, no trailing slash |
| `data-href` | DOM attribute | `plugins/deployit/assets/app.js:8` | `li[data-href]` rows tap-navigate, except install button |
| `method` | plist key | `plugins/deployit/assets/ExportOptions.ios.plist:5` | iOS: `development`, automatic signing, no thinning |
| `method` | plist key | `plugins/deployit/assets/ExportOptions.macos.plist:5` | macOS: `developer-id`, automatic signing, notarizable |
| `method` | plist key | `plugins/deployit/assets/ExportOptions.visionos.plist:5` | visionOS: `development`, mirrors the iOS options |
| `scope` | webmanifest key | `plugins/deployit/assets/manifest.webmanifest:5` | Standalone portrait PWA scoped to /deployit/ |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `plugins-deployit-bin._STATIC_ASSETS -> plugins-deployit-assets.app.css (reads)`
- `plugins-deployit-bin._STATIC_ASSETS -> plugins-deployit-assets.app.js (reads)`
- `plugins-deployit-bin._STATIC_ASSETS -> plugins-deployit-assets.icon.svg (reads)`
- `plugins-deployit-bin._STATIC_ASSETS -> plugins-deployit-assets.manifest.webmanifest (reads)`
- `plugins-deployit-bin._render_appcast -> plugins-deployit-assets.appcast.template.xml (reads)`
- `plugins-deployit-bin._render_build_landing -> plugins-deployit-assets.index.template.html (reads)`
- `plugins-deployit-bin._render_listing -> plugins-deployit-assets.listing.template.html (reads)`
- `plugins-deployit-bin._render_product -> plugins-deployit-assets.product.template.html (reads)`
- `plugins-deployit-bin._stage_ios_or_visionos -> plugins-deployit-assets.manifest.template.plist (reads)`
- `plugins-deployit-bin._write_config -> plugins-deployit-assets.config.example.toml (reads)`
- `plugins-deployit-bin._xcodebuild_export -> plugins-deployit-assets.ExportOptions.ios.plist (reads)`
- `plugins-deployit-bin._xcodebuild_export -> plugins-deployit-assets.ExportOptions.macos.plist (reads)`
- `plugins-deployit-bin._xcodebuild_export -> plugins-deployit-assets.ExportOptions.visionos.plist (reads)`

## Type notes

| Template | Placeholders | Filler |
| --- | --- | --- |
| `plugins/deployit/assets/appcast.template.xml` | `$TITLE $LINK $ITEMS` | `_render_appcast` |
| `plugins/deployit/assets/index.template.html` | `$TITLE $PLATFORM $ORIGIN_HOST $VERSION_LABEL $BUILD_NUMBER $COMMIT $TIMESTAMP $INSTALL_HREF $INSTALL_LABEL $TRUST_NOTE` | `_render_build_landing` |
| `plugins/deployit/assets/listing.template.html` | `$LAST_PULL $TOTAL_PRODUCTS $TOTAL_BUILDS $LOCAL_HOST $ROWS` | `_render_listing` |
| `plugins/deployit/assets/manifest.template.plist` | `$IPA_URL $BUNDLE_ID $BUNDLE_VERSION $TITLE` | `_stage_ios_or_visionos` |
| `plugins/deployit/assets/product.template.html` | `$LAST_PULL $PROJECT $PLATFORM $BUNDLE_ID $TOTAL_BUILDS $SPARKLE_BLOCK $ROWS` | `_render_product` |

- Substitution is strict: every placeholder must be supplied; a literal `$` needs `$$`.
- Fillers escape text; `$ROWS`, `$INSTALL_LABEL`, and `$TRUST_NOTE` (ios/visionos only) arrive raw.
- `$BUNDLE_VERSION` receives the app's marketing version, not its build number.
- Export plists hold no placeholders; the platform name in the filename selects the file.
- `plugins/deployit/assets/config.example.toml:2`: seed written once; re-runs preserve edits.
- `plugins/deployit/assets/app.js:28`: the Refresh button POSTs to `/deployit/_internal/refresh` (HTTP, no JS function call); the backend routes that path internally. No in-grammar verb applies, so this is not a Relationships edge.

## External deps

- xcodebuild — ExportOptions plists are `-exportArchive -exportOptionsPlist` inputs
- itms-services — manifest.template.plist is Apple's OTA software-package manifest shape
- Python string.Template — placeholder grammar of the *.template.* files
- No frameworks — plain DOM, Fetch, Touch Events, CSS custom properties

## Gotchas

- Rewording `plugins/deployit/assets/config.example.toml:8` breaks bootstrap's literal-line rewrite.
- `plugins/deployit/assets/ExportOptions.ios.plist:10`: thinning `&lt;none&gt;` is a literal token.
- Landing pages carry inline CSS and no JS (`plugins/deployit/assets/index.template.html:15`).
- PNG icons cited at `plugins/deployit/assets/manifest.webmanifest:11` are binaries beside icon.svg.
