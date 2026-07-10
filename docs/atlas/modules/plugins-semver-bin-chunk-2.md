---
module: "plugins/semver/bin (chunk 2)"
summary: "Thin bash router dispatching /semver subcommands to the semver-cli python3 implementation."
read_when: "Touching /semver's command routing, subcommand aliases, or usage text"
sources:
  - path: plugins/semver/bin/semver-router.sh
    blob: ba1000d3924f52819a3dfa700e24b775db1aebb9
generator: cartographer/4
baseline: cb09ceb006e3fb4759a91d64d9e6655e67d04bf7
---

# Module: plugins/semver/bin (chunk 2)

## Purpose

This module is the sole dispatch point that translates `/semver` slash-command arguments into `semver-cli` subcommand invocations — a thin bash router with no versioning logic of its own; every branch just shells out to `python3 semver-cli` (plugins/semver/bin/semver-router.sh:9,17-21). It also threads `PLUGIN_ROOT` into the bump/set/init subcommands so the CLI can locate and run plugin-root-relative post-bump hooks. If it vanished, the `/semver` skill would have no way to route user commands to the underlying implementation.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

The router owns pure dispatch only: every branch of the top-level `case` (plugins/semver/bin/semver-router.sh:26-99) ultimately calls `run_cli`, which shells out to `python3 ${SCRIPT_DIR}/semver-cli` (plugins/semver/bin/semver-router.sh:9,17-21) — all versioning behavior lives in that CLI, not here. `PLUGIN_ROOT` is computed once at startup from `BASH_SOURCE` (plugins/semver/bin/semver-router.sh:7-8) and passed explicitly to `bump run`, `set run`, and `init run` (lines 36, 47, 55) so those subcommands can execute plugin-root-relative post-bump hooks. Every branch defensively shifts positional args with `shift 2>/dev/null || true` (lines 24, 32, 43, 59, 74) to tolerate missing arguments under `set -euo pipefail` (line 5) without aborting. Unrecognized commands at any nesting level (top-level, `tracking`, `auto-bump`) fall through to `usage_json` (lines 68, 83, 97), preserving the invariant that "all output is JSON to stdout" (line 4) even on user error.

## External deps


## Gotchas

`run_cli` (plugins/semver/bin/semver-router.sh:17-21) wraps every `semver-cli` invocation in `set +e` / `set -e`, so a failing CLI subprocess never aborts the router or propagates a non-zero exit code — the router itself always exits 0 as long as argument parsing succeeded, relying entirely on the CLI's own JSON `ok:false` payload (not the process exit code) to signal failure to callers. The usage text in `usage_json` (plugins/semver/bin/semver-router.sh:11-15) also omits several commands the case statement actually accepts: `recommend` (line 90) and the `check`/`fix` aliases for `validate`/`repair` (lines 87, 93) work but aren't listed.
