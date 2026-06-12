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
    blob: 368cdb4685b143066dd49dd5b08261998eaa8850
  - path: plugins/deployit/assets/app.js
    blob: e2c124d7e0cef334558cf2d865a7cfb5eeb48385
  - path: plugins/deployit/assets/config.example.toml
    blob: 53978c9f7177eb01bdbc255ce1eee47fdc5fcc9c
  - path: plugins/deployit/assets/icons/icon.svg
    blob: d706e39034df2f1f5838ce57beab5623d8243146
  - path: plugins/deployit/assets/index.template.html
    blob: e0b564edf11a7723473248d94a3397eed55acf27
  - path: plugins/deployit/assets/listing.template.html
    blob: 18a2f1a698756ca4fc323f5502f0211d4ce70d12
  - path: plugins/deployit/assets/manifest.template.plist
    blob: 10f7a574db399eef99e0474eae3e1bfb23abd317
  - path: plugins/deployit/assets/manifest.webmanifest
    blob: 8d80244cd1bf8c8ab565ddb2b1a1e17fb4468cd0
  - path: plugins/deployit/assets/product.template.html
    blob: 7fcab5e6b7e9c7d393a34d9a00392d8deca31d1b
references_modules: [plugins-deployit-bin]
generator: cartographer/1
baseline: 0ce4ca44c3cc0b4a95d86862de8dc79914ffacbf
verified: true
---

# Module: plugins/deployit/assets

## Purpose

Code-free payload of deployit: per-platform xcodebuild export options, template sources for
the OTA install web UI, the PWA shell, and the per-machine config seed. All substitution and
serving logic lives in plugins/deployit/bin; this module holds only the contracts those
scripts fill, so page appearance and signing policy change without code.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `$INSTALL_HREF` | placeholder | `plugins/deployit/assets/index.template.html:37` | Install button target; itms-services link for IPAs |
| `$IPA_URL` | placeholder | `plugins/deployit/assets/manifest.template.plist:14` | HTTPS URL of the .ipa fetched during OTA install |
| `$ROWS` | placeholder | `plugins/deployit/assets/listing.template.html:23` | Raw pre-rendered `<li>` markup, injected unescaped |
| `a.install` | CSS selector | `plugins/deployit/assets/app.css:28` | Button style; rows use .row .title .sub .older .archived |
| `base_url` | TOML key | `plugins/deployit/assets/config.example.toml:8` | Tailnet origin incl. /deployit, no trailing slash |
| `data-href` | DOM attribute | `plugins/deployit/assets/app.js:8` | `li[data-href]` rows tap-navigate, except install button |
| `method` | plist key | `plugins/deployit/assets/ExportOptions.ios.plist:5` | iOS: `development`, automatic signing, no thinning |
| `method` | plist key | `plugins/deployit/assets/ExportOptions.macos.plist:5` | macOS: `developer-id`, automatic signing, notarizable |
| `method` | plist key | `plugins/deployit/assets/ExportOptions.visionos.plist:5` | visionOS: `development`, mirrors the iOS options |
| `ptr` | DOM id | `plugins/deployit/assets/app.js:18` | Pull-to-refresh needs `<div id="ptr">`; absent, only tap-nav runs |
| `scope` | webmanifest key | `plugins/deployit/assets/manifest.webmanifest:6` | Standalone portrait PWA scoped to /deployit/ |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `finish` | function | `plugins/deployit/assets/app.js:61` | Ends the pull gesture: POSTs refresh, reloads even on fetch failure |
| `reset` | function | `plugins/deployit/assets/app.js:29` | Sole re-arm path; every gesture exit funnels through it |

## Relationships

- `plugins-deployit-assets.app.js -> plugins-deployit-bin._dispatch_post (calls)`
- `plugins-deployit-bin._STATIC_ASSETS -> plugins-deployit-assets.app.css (reads)`
- `plugins-deployit-bin._STATIC_ASSETS -> plugins-deployit-assets.app.js (reads)`
- `plugins-deployit-bin._STATIC_ASSETS -> plugins-deployit-assets.icon.svg (reads)`
- `plugins-deployit-bin._STATIC_ASSETS -> plugins-deployit-assets.manifest.webmanifest (reads)`
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
| `plugins/deployit/assets/index.template.html` | `$TITLE $PLATFORM $ORIGIN_HOST $VERSION_LABEL $BUILD_NUMBER $COMMIT $TIMESTAMP $INSTALL_HREF $INSTALL_LABEL $TRUST_NOTE` | `_render_build_landing` |
| `plugins/deployit/assets/listing.template.html` | `$LAST_PULL $TOTAL_PRODUCTS $TOTAL_BUILDS $LOCAL_HOST $ROWS` | `_render_listing` |
| `plugins/deployit/assets/manifest.template.plist` | `$IPA_URL $BUNDLE_ID $BUNDLE_VERSION $TITLE` | `_stage_ios_or_visionos` |
| `plugins/deployit/assets/product.template.html` | `$LAST_PULL $PROJECT $PLATFORM $BUNDLE_ID $TOTAL_BUILDS $ROWS` | `_render_product` |

- Substitution is strict: every placeholder must be supplied; a literal `$` needs `$$`.
- Fillers escape text; `$ROWS`, `$INSTALL_LABEL`, and `$TRUST_NOTE` (ios/visionos only) arrive raw.
- `$BUNDLE_VERSION` receives the app's marketing version, not its build number.
- Export plists hold no placeholders; the platform name in the filename selects the file.
- `plugins/deployit/assets/config.example.toml:2`: seed written once; re-runs preserve edits.

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
