---
module: "plugins/forge/bin (chunk 2)"
summary: "Deterministic bash+jq scripts backing forge's execute loop: session locks, integrity checks, state counters, prechecks."
read_when: "Changing forge execute-loop locking, integrity snapshots, state counters, or prechecks"
sources:
  - path: plugins/forge/bin/forge-handoff-scaffold.sh
    blob: a05f845a61da0c9bfd8477464fded51238f1a7c8
  - path: plugins/forge/bin/forge-integrity.bats
    blob: 99118eb9692463f7746916ac781e0742f2b54120
  - path: plugins/forge/bin/forge-integrity.sh
    blob: bb1e1a44a2d155bf92cb2ad0e8d18a15557ecc61
  - path: plugins/forge/bin/forge-lock.bats
    blob: 210bfbc830414237b8cd02a53d4a09dc0c521304
  - path: plugins/forge/bin/forge-lock.sh
    blob: 483c14eb7db175401e0150325f3a406ccdac2fa0
  - path: plugins/forge/bin/forge-loop-state.bats
    blob: a47f2d49b98f97c5a820d589361908abf6d441ef
  - path: plugins/forge/bin/forge-loop-state.sh
    blob: a68fd8db3a46066a470cf7f29c41e11c7d992c06
  - path: plugins/forge/bin/forge-mapping-scaffold.bats
    blob: 603250a4801f67dd4208e1fb7738584eae81564b
  - path: plugins/forge/bin/forge-mapping-scaffold.sh
    blob: f0734017a85f818408e7981492090222365cc530
  - path: plugins/forge/bin/forge-prechecks.bats
    blob: bbbca23a9d01d6d79fe31cae864edaaa56671a4b
  - path: plugins/forge/bin/forge-prechecks.sh
    blob: 548ee31ef46f8af1f8919b741e8aaf39bffc6c2d
  - path: plugins/forge/bin/forge-predecessor-diff.bats
    blob: 0f14c031b102c459f30368bccbb27064bd26d029
  - path: plugins/forge/bin/forge-predecessor-diff.sh
    blob: 467a3727cadccb520b9a8db1806b92587ad74c8c
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: plugins/forge/bin (chunk 2)

## Purpose

This is the second half of forge/bin's script library: deterministic bash+jq guardrails that keep the execute loop's steady state (generate -> evaluate -> commit, repeated per story) safe to run unattended across many stories, sessions, and concurrent tmux panes. The unifying idea is replacing prose arithmetic and human-eyeballed judgment calls that references/execution-loop.md used to describe by hand — heartbeat staleness math, tamper detection, retry/runaway counters, diff truncation, handoff/mapping-skeleton assembly — with one deterministic script per concern, each returning a JSON verdict the model branches on rather than computes. If this module vanished the loop would lose its only defenses against concurrent-session races (plugins/forge/bin/forge-lock.sh), undetected generator/evaluator tampering (plugins/forge/bin/forge-integrity.sh), and counters that reset every context clear instead of persisting (plugins/forge/bin/forge-loop-state.sh) — exactly the failure modes each script's own header cites as the F-numbered bug it was written to close.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

All mutable JSON stores in this chunk share one atomic-write idiom — write to a `.tmp` sibling then `mv` into place, never in-place — so a crash mid-write can never leave a torn file: write_lock() at plugins/forge/bin/forge-lock.sh:96 (swap at :104), write_state() at plugins/forge/bin/forge-loop-state.sh:98 (swap at :103), and the snapshot write at plugins/forge/bin/forge-integrity.sh:214. state.json's counters (stories_attempted, stories_this_session, retry_counts, total_retries, storyhook_consecutive_failures, stories_since_last_architect_review) are owned exclusively by forge-loop-state.sh's subcommands specifically because they must survive the execute loop's mandatory per-iteration context clear, which would otherwise silently discard an in-memory counter — see the storyhook-failure and architect-check subcommands' own rationale at plugins/forge/bin/forge-loop-state.sh:213-218 and :246-251. lock.json's lifecycle is holder-scoped end to end: every acquire/heartbeat/release/check subcommand keys off the on-disk `holder` field matching the caller's `--session-id` (plugins/forge/bin/forge-lock.sh:77-88), and it is removed only by its own holder or an explicit stale-break, never implicitly. forge-integrity.sh's snapshots live entirely outside the git working tree, keyed by a hash of both the project's absolute path and the caller's session id (plugins/forge/bin/forge-integrity.sh:156-157), so two concurrent runs against the same or different projects can never share or clobber one snapshot file.

## External deps

- hashlib — imported

## Gotchas

- forge-integrity.sh snapshots deliberately use a literal `/tmp` prefix instead of `$TMPDIR`: on macOS `$TMPDIR` is Spotlight-indexed and can eventually stall on `mds_stores` when many small files are created rapidly, while `/private/tmp` (what `/tmp` symlinks to) is never indexed — plugins/forge/bin/forge-integrity.sh:59-62.
- forge-lock.sh's read_lock() treats a schema-valid-but-field-incomplete lock.json (missing or unparseable `heartbeat_at`) as identical to 'no lock present' rather than erroring, because jq's unguarded `fromdate` would otherwise throw under `set -euo pipefail` and crash every acquire/check call — plugins/forge/bin/forge-lock.sh:65-88.
- forge-mapping-scaffold.sh only adopts `story list --json`'s output when the command exits 0: storyhook writes its JSON body to stdout on BOTH success and failure, so a bare `cmd || fallback` would concatenate two JSON documents into one stream — plugins/forge/bin/forge-mapping-scaffold.sh:59-66.
- forge-prechecks.sh's stub_grep check matches only whole-word `TODO`/`FIXME`/`HACK` markers and specific 'not implemented' idioms, not bare 'stub'/'placeholder'/'XXX' substrings, after those false-positived on legitimate code and hard-blocked the loop with no fix path (F105) — plugins/forge/bin/forge-prechecks.sh:171-182.
- forge-integrity.sh never auto-reverts a moved HEAD (action=manual_review_required rather than files-only auto-restore) to avoid destroying a tampering commit's own forensic trail with an automated `git reset` — plugins/forge/bin/forge-integrity.sh:259-260 (rationale at :90-93).
