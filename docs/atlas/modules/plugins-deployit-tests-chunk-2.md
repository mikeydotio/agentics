---
module: "plugins/deployit/tests (chunk 2)"
summary: "Sandboxed CLI tests for deployit redeploy/version/gc/metadata plus verify-live.sh, the live-deployment gate"
read_when: "Changing deployit redeploy, gc, metadata extraction, or verifying a live deployment"
sources:
  - path: plugins/deployit/tests/test-cli-redeploy.sh
    blob: 5cc4141d1c5dc1700865ec366d1304c672bd9817
  - path: plugins/deployit/tests/test-cli-version.sh
    blob: d7a1daaa409feb77dbb59b51a4c1f76b58050f79
  - path: plugins/deployit/tests/test-gc.sh
    blob: be01b59bafa19e9c5bda91c29d3ccd6101f9ad88
  - path: plugins/deployit/tests/test-metadata-single-app.sh
    blob: 1f36ebce4b6cf9363f3e6045fb7afced5dcd2ef0
  - path: plugins/deployit/tests/test-metadata.sh
    blob: 5c49e2f4a48015c86de20068bd861f6edde9103c
  - path: plugins/deployit/tests/verify-live.sh
    blob: 678de11417e159376c10cd722f2569e53f91970b
references_modules: [plugins-deployit-bin, plugins-deployit-tests-chunk-1]
generator: cartographer/1
baseline: 65c6f5e8e65713af63741fbe8d498384f530200e
verified: true
---

# Module: plugins/deployit/tests (chunk 2)

## Purpose

Black-box tests of deployit's CLI tail: redeploy, version, gc, and metadata extraction.
Fixture tests sandbox everything — mktemp state dirs, fake binaries, `DEPLOYIT_SKIP_*` flags —
so no launchd, tailscale, or network side effects occur.
`verify-live.sh` is the deliberate exception: it probes a real running backend over HTTP
and is the acceptance gate proving a deployit change is actually live.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `test-cli-redeploy.sh` | test script | `plugins/deployit/tests/test-cli-redeploy.sh:1` | Proves redeploy retargets stable symlinks, rewrites legacy hash-pinned plists, is idempotent, and rejects a `--source` lacking `bin/deployit-backend` |
| `test-cli-version.sh` | test script | `plugins/deployit/tests/test-cli-version.sh:1` | Proves `--version` returns `"ok": true` JSON carrying the CLI's pinned version string |
| `test-gc.sh` | test script | `plugins/deployit/tests/test-gc.sh:1` | Proves `gc --keep N` archives the oldest builds and prunes them locally, no-ops when under budget, and bare `gc` fails as JSON |
| `test-metadata-single-app.sh` | test script | `plugins/deployit/tests/test-metadata-single-app.sh:1` | Proves metadata extraction for a root `<Name>.xcodeproj` + `./project.yml` layout with unquoted settings |
| `test-metadata.sh` | test script | `plugins/deployit/tests/test-metadata.sh:1` | Proves metadata extraction for a workspace + `Apps/<target>/project.yml` monorepo layout |
| `verify-live.sh` | verification script | `plugins/deployit/tests/verify-live.sh:1` | Deployment acceptance gate: exits 0 only when the LIVE backend serves healthz, app.css/app.js, listing markers, and product pages; accepts `--port`/`--state-dir` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `check_static` | function | `plugins/deployit/tests/verify-live.sh:54` | Asserts a static asset returns 200 with the expected Content-Type prefix; covers app.css and app.js |
| `mk_build` | function | `plugins/deployit/tests/test-gc.sh:26` | Emits both halves of a fixture build — the `serve/<id>` dir and its `builds.json` entry — keeping gc ordering tests consistent |

## Relationships

- `plugins-deployit-tests-chunk-2.test-cli-redeploy.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-tests-chunk-2.test-cli-redeploy.sh -> plugins-deployit-tests-chunk-1.fakes/tailscale (calls)`
- `plugins-deployit-tests-chunk-2.test-cli-redeploy.sh -> plugins-deployit-tests-chunk-1.fakes/true (calls)`
- `plugins-deployit-tests-chunk-2.test-cli-version.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-tests-chunk-2.test-gc.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-tests-chunk-2.test-metadata-single-app.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-tests-chunk-2.test-metadata.sh -> plugins-deployit-bin.deployit-cli (calls)`
- `plugins-deployit-tests-chunk-2.verify-live.sh -> plugins-deployit-bin.deployit-backend (calls)`

## Type notes

- Fixture tests sandbox state via `DEPLOYIT_STATE_DIR` (`plugins/deployit/tests/test-gc.sh:8`)
- `DEPLOYIT_SKIP_*` flags disable side effects (`plugins/deployit/tests/test-cli-redeploy.sh:18`)
- Assertions grep JSON stdout; a miss exits 1 (`plugins/deployit/tests/test-gc.sh:46`)
- Tests expect CLI errors as `ok:false` JSON, nonzero exit (`plugins/deployit/tests/test-gc.sh:70`)
- `--__dump-metadata` dumps metadata JSON, no build (`plugins/deployit/tests/test-metadata.sh:29`)
- `verify-live.sh` omits `-e` so every check runs (`plugins/deployit/tests/verify-live.sh:11`)
- It exits 1 iff any check failed (`plugins/deployit/tests/verify-live.sh:122`)
- Port: `--port` flag, else `config.toml` in state dir (`plugins/deployit/tests/verify-live.sh:24`)
- Listing rows = distinct (bundle_id, platform) pairs (`plugins/deployit/tests/verify-live.sh:87`)

## External deps

- curl — all of `verify-live.sh`'s HTTP probes against the running backend
- git — metadata tests init a throwaway repo so project discovery works
- python3 — runs `deployit-cli` and inline JSON/TOML assertion snippets in every test
- tomllib/tomli — parses the backend port out of `config.toml` in `verify-live.sh`

## Gotchas

- `verify-live.sh` asserts against a live deployment (`plugins/deployit/tests/verify-live.sh:2`)
- `_healthz` ok is only check 1; trust the full pass (`plugins/deployit/tests/verify-live.sh:48`)
- `redeploy` runs `verify-live.sh` unless skipped (`plugins/deployit/tests/test-cli-redeploy.sh:35`)
- Plists pin stable paths, not cache-hash paths (`plugins/deployit/tests/test-cli-redeploy.sh:84`)
- CLI version bumps must update a pinned literal (`plugins/deployit/tests/test-cli-version.sh:7`)
