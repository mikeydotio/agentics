---
module: plugins/deployit/assets
summary: "deployit's served-UI assets: HTML/CSS/JS, PWA manifest/icon, and Apple export/appcast templates."
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
references_modules: [plugins-atlas-bin-chunk-1]
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/deployit/assets

## Purpose

This module is deployit's entire browser-facing and build-artifact surface: the HTML templates, CSS, and vanilla-JS behavior behind the listing/product pages the deployit web server renders, plus the static and template files those pages and an Apple build pipeline both depend on (the PWA manifest and SVG icon, per-platform Xcode `ExportOptions` plists, the OTA install manifest template, and a Sparkle appcast RSS template). Nothing here is compiled: every file is either served byte-for-byte or has `$PLACEHOLDER` tokens (e.g. plugins/deployit/assets/product.template.html:6, plugins/deployit/assets/appcast.template.xml:4-8, plugins/deployit/assets/manifest.template.plist:14-26) that some external process substitutes at render/deploy time — those token names are this module's real contract with its consumer. If this module vanished, deployit would have no UI to browse builds from and no signing/OTA/update configuration for its iOS, macOS, and visionOS deploy targets.

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

- `plugins-deployit-assets.handleDelete -> plugins-atlas-bin-chunk-1.add (calls)`

## Type notes

app.js is one self-invoking closure (IIFE, plugins/deployit/assets/app.js:1-152) whose module-scoped mutable state — `openRow`, `suppressClick`, `drag` (plugins/deployit/assets/app.js:11-13) and `refreshing` (plugins/deployit/assets/app.js:138) — is shared by every document-level pointer/click listener it registers; there is no per-instance object, so the script assumes exactly one such page per document. The `*.template.html`, `manifest.template.plist`, and `appcast.template.xml` files are plain-text `$PLACEHOLDER` substitution targets rather than a templating-engine syntax (plugins/deployit/assets/index.template.html:6, plugins/deployit/assets/product.template.html:6, plugins/deployit/assets/manifest.template.plist:14, plugins/deployit/assets/appcast.template.xml:4) — editing one means keeping its placeholder names in sync with whatever renders it. config.example.toml documents, but is not itself, the live per-machine config: comments state it is written once by a bootstrap step and preserved (not overwritten) on subsequent runs (plugins/deployit/assets/config.example.toml:2).

## External deps


## Gotchas

Deleting the last build on a product page navigates to the products list instead of reloading, because reloading an emptied product page would 404 (plugins/deployit/assets/app.js:100-104). The nav-bar Refresh button always POSTs to /deployit/_internal/refresh before reloading even though the listing page's own GET already git-pulls the shared index server-side — the POST only does real work on a product page, and is kept on both pages so one code path serves both (plugins/deployit/assets/app.js:133-137). The swipe track's keyboard-focus-open state uses `translateX(-50%)` rather than a pixel value because a track always holds exactly two equal-width pills, so -50% is exactly one slot-width (plugins/deployit/assets/app.css:33-36) — matching the comment in app.js that the pill width itself is measured from the DOM each drag and deliberately kept out of app.js so app.css stays its single source (plugins/deployit/assets/app.js:4-9).
