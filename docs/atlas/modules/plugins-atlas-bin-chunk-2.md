---
module: "plugins/atlas/bin (chunk 2)"
summary: "Bash router dispatching /atlas subcommands (or a bare call) to atlas-cli, the single deterministic entrypoint."
read_when: "Touching /atlas subcommand routing or the atlas-cli invocation shim"
sources:
  - path: plugins/atlas/bin/atlas-router.sh
    blob: 29678570942b8ab90da67a22ae7445499174ec5f
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/atlas/bin (chunk 2)

## Purpose

This is the sole shell entrypoint between the `/atlas` skill and `atlas-cli`: it maps a first argument to a fixed allowlist of `atlas-cli` subcommands (status, scan, partition, ledger, doc, diffpack, lock, lint, index, extract, judge-plan, judgment, project, migrate-v1, commit, branch, verify-cache, init, remove) and forwards the remaining args verbatim (plugins/atlas/bin/atlas-router.sh:25-86). It exists so the orchestrating skill never invokes `python3 atlas-cli` directly and so any unrecognized or missing subcommand gets a defined JSON usage response instead of an ad hoc failure. If it vanished, the atlas skill would lose its single choke point for dispatching deterministic CLI work, and the Hard Rule that all such work route through one router (see plugins/atlas/skills/atlas/SKILL.md) would have no enforcement mechanism.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

No types — a single case-statement dispatcher. `run_cli` deliberately toggles `set +e` around the `$CLI "$@"` invocation before restoring `set -e` (plugins/atlas/bin/atlas-router.sh:16-20), so a non-zero `atlas-cli` exit does not abort the router under `set -euo pipefail` (plugins/atlas/bin/atlas-router.sh:5) — the CLI's own JSON `ok:false` payload is left to carry the error signal to the caller rather than the shell's exit code. `CLI` is built unquoted as `"python3 ${SCRIPT_DIR}/atlas-cli"` (plugins/atlas/bin/atlas-router.sh:8) and expanded unquoted in `run_cli` (plugins/atlas/bin/atlas-router.sh:18), relying on word-splitting to invoke `python3` with the script path as a separate argument.

## External deps


## Gotchas

`shift 2>/dev/null || true` guards against `shift` erroring under `set -euo pipefail` when the router is invoked with zero arguments (plugins/atlas/bin/atlas-router.sh:23) — without the `|| true`, a bare `/atlas` call would abort instead of falling into the `""|status` case.
