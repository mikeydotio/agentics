---
module: plugins/deployit/assets
summary: "Static web templates/styles/JS, platform export-options plists, and the default config seed deployit renders or reads."
read_when: "Changing deployit's install pages, OTA manifest, export signing options, or config seed"
sources:
  - path: plugins/deployit/assets/ExportOptions.ios.plist
    blob: 5852d63680d64c09eedc16402acb77ff8ee908b8
  - path: plugins/deployit/assets/ExportOptions.macos.plist
    blob: bb805c5092b4b96097d0f8628a3366cf10d98320
  - path: plugins/deployit/assets/ExportOptions.visionos.plist
    blob: 5852d63680d64c09eedc16402acb77ff8ee908b8
  - path: plugins/deployit/assets/app.css
    blob: e067d3a7de38b88668dde0a50176f1b29e8e3238
  - path: plugins/deployit/assets/app.js
    blob: 04c208727cd8fffa2251c407d3dcf8080d1bb483
  - path: plugins/deployit/assets/appcast.template.xml
    blob: cafd1d470f8cea90690c9cdf5adbc56e8351d714
  - path: plugins/deployit/assets/config.example.toml
    blob: 858c6553f1a133b2ff2396392367132f3007722b
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
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/deployit/assets

## Purpose

This module holds deployit's non-code rendering inputs: PWA templates and styles for the build listing/product/install-page UI (index.template.html, listing.template.html, product.template.html, app.css, app.js), an appcast.template.xml for Sparkle auto-update, manifest.template.plist for itms-services OTA install, three per-platform ExportOptions plists for xcodebuild archive export, and config.example.toml as the bootstrap-seeded default config. What unifies the set is that none carry orchestration logic of their own — each is a $-prefixed template the backend substitutes into, or a declarative plist/toml the CLI reads verbatim — making this the entirety of deployit's presentation layer and export/config surface, cleanly separated from the bash/python that drives it. Without it deployit would have no installable web UI, no Sparkle feed, no OTA manifest, and no per-platform xcodebuild export settings.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `closeRow` | function | `plugins/deployit/assets/app.js:20` | Clears li's action-track transform, visually closing its swipe row; safe no-op if the row has no track. |
| `endDrag` | function | `plugins/deployit/assets/app.js:67` | Pointerup/cancel handler: snaps the active drag's row open past half-travel or closed otherwise, then clears drag state. |
| `handleDelete` | function | `plugins/deployit/assets/app.js:83` | Confirms, then DELETEs btn's row via its data-delete URL; reloads, or navigates home if a product page emptied, on success. |
| `openRowEl` | function | `plugins/deployit/assets/app.js:24` | Translates li's action-track left by one slot width, revealing the Delete pill; caller is responsible for tracking `openRow`. |
| `slotWidth` | function | `plugins/deployit/assets/app.js:16` | Returns li's current .actions-slot width in pixels (0 if absent) — the swipe travel distance and open-row offset. |
| `trackOf` | function | `plugins/deployit/assets/app.js:15` | Returns li's .action-track element, or null if absent — the node all swipe open/close logic transforms. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

HTML templates carry $-prefixed placeholders the backend substitutes before serving, never client-rendered: $ROWS in plugins/deployit/assets/listing.template.html:27 and plugins/deployit/assets/product.template.html:29, $PROJECT/$PLATFORM in plugins/deployit/assets/product.template.html:6, $INSTALL_HREF/$INSTALL_LABEL in plugins/deployit/assets/index.template.html:37, and $ITEMS in plugins/deployit/assets/appcast.template.xml:8. app.js's swipe-to-delete state (openRow, drag, suppressClick) is scoped inside a single IIFE closure, not attached to window — plugins/deployit/assets/app.js:1-13. The swipe pill width is an owned invariant: it lives only in the --action-w custom property (plugins/deployit/assets/app.css:1) and is read from the live DOM by slotWidth() (plugins/deployit/assets/app.js:16-19) rather than duplicated as a JS constant, per the comment at plugins/deployit/assets/app.js:8-9. Only rows carrying a `data-delete` attribute are swipeable, checked per-gesture at plugins/deployit/assets/app.js:33. The three ExportOptions plists are distinct per-platform configs, not one shared file: ExportOptions.ios.plist and ExportOptions.visionos.plist both pin method=development, thinning=none, compileBitcode=false, stripSwiftSymbols=false (plugins/deployit/assets/ExportOptions.ios.plist:5-14, plugins/deployit/assets/ExportOptions.visionos.plist:5-14), while ExportOptions.macos.plist uses method=developer-id with no thinning/bitcode keys (plugins/deployit/assets/ExportOptions.macos.plist:5-8). config.example.toml is a one-shot seed, not a live source of truth: "Bootstrap writes this file the first time; subsequent runs preserve overrides" (plugins/deployit/assets/config.example.toml:2), so edits here never retroactively change an already-bootstrapped install's config.toml.

## External deps


## Gotchas

The refresh button always POSTs /deployit/_internal/refresh before reloading even on pages where it's a no-op: "the product-page GET does not pull on its own, and the listing GET pulls anyway (so the POST is a harmless belt-and-suspenders there)" (plugins/deployit/assets/app.js:135-136). After a successful delete, the reload logic special-cases navigating home instead of reloading in place when a product page would otherwise show zero rows, to dodge a 404: "A product page with no rows left would 404 on reload — go home." (plugins/deployit/assets/app.js:101). The keyboard-focus fallback that slides the swipe-delete track open relies on translateX(-50%) being exactly correct only because the track always holds exactly two equal-width pills: "-50% is exactly one slot-width — no magic number" (plugins/deployit/assets/app.css:33-35).
