---
module: tests
summary: "Root tests/: bats suite pinning pilot/storyhook state schemas, plus a bash harness guarding marketplace version sync."
read_when: "Touching tests/*.bats, pilot/storyhook schemas, or plugin.json version-sync tests"
sources:
  - path: tests/helpers.bash
    blob: ca28a41ee9ec7cc8b278243237315d55e07e8a04
  - path: tests/init.bats
    blob: 4165667c3062581e7e3ff170335e404a87da24de
  - path: tests/plugin-versions.sh
    blob: 8bf8703bb6c6d0b0d9f3d31668392f316d65d25c
  - path: tests/run-tests.sh
    blob: 18b3f63079da9fd9dce3c88ed11500f2eadbf0c3
  - path: tests/state-machine.bats
    blob: 57349d4bcfc4676886ed90ac73cab29022d2678b
generator: cartographer/4
baseline: 50c998d53e2ed58951ac5f794afd32bfa729f658
---

# Module: tests

## Purpose

tests/ holds two independent, largely CI-free harnesses: a bats suite (helpers.bash, init.bats, state-machine.bats, run via run-tests.sh) that fabricates a throwaway git repo to pin the on-disk shape of pilot/storyhook state files — .storyhook/states.toml and .pilot/{state,config,lock}.json, verdicts.jsonl, plan-mapping.json — purely by asserting on fixtures the tests write themselves, never a production script (tests/init.bats:24-28); and a separate plain-bash harness (plugin-versions.sh) that asserts every plugin.json/marketplace.json version matches the repo's bare VERSION and exercises the real .semver post-bump sync hook against disposable fixture repos (tests/plugin-versions.sh:74-186). The latter is deliberately bash-only, per its own header, because bats-core isn't guaranteed installed and this project runs no tests in CI — a .bats file here would simply never execute (tests/plugin-versions.sh:4-8). If either half vanished, the pre-push gate would lose its pin on the pilot/storyhook file schemas or its guard against a drifted plugin manifest reaching a release.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- Every bats test gets a fresh mktemp project via setup(); teardown() removes it, and TEST_PROJECT_DIR is the single exported global every helper function paths through (tests/init.bats:6-12, tests/state-machine.bats:6-13, tests/helpers.bash:6-7).
- State-machine timestamps are ISO-8601 UTC Zulu strings across state.json, lock.json, and verdicts; heartbeat-age checks try GNU `date -d` first, falling back to BSD `date -j -f` syntax (tests/helpers.bash:55-56,77,90; tests/state-machine.bats:55,67).
- states.toml entries declare a `super` of either open or closed; add_work_states is not itself idempotent — callers must grep-guard before re-invoking it (tests/helpers.bash:17-23,96-109; tests/init.bats:26-28).
- plugin-versions.sh fixture repos are cleaned via a per-test `trap ... EXIT`, not shared setup/teardown, and each test_* function runs in its own subshell so one failing assertion doesn't abort the run (tests/plugin-versions.sh:104,157,198-212).
- plugin-versions.sh's real-repo assertions (test_every_manifest_matches_bare_version, etc.) read the live VERSION and every plugins/*/.claude-plugin/plugin.json, so they mutate nothing but depend on repo state at run time (tests/plugin-versions.sh:30-36,86-93).

## External deps


## Gotchas

- "adding pilot states is idempotent" can't actually fail: the test wraps the second add_work_states call in its own grep guard, so the assertion is tautological rather than proof the helper is idempotent (tests/init.bats:18-34, esp. :26-28).
- create_stale_lock computes stale_time via a GNU/BSD date fallback that can yield an empty string if both invocations fail, but create_lock_json's `heartbeat_at="${1:-$(date -u ...)}"` treats an empty $1 as unset and substitutes a fresh current timestamp — so a failed stale_time silently produces a lock that looks current, not one with an empty heartbeat_at, which would make "stale lock heartbeat exceeds window" (asserting age >= 30) fail rather than pass (tests/helpers.bash:76-92, tests/state-machine.bats:62-72).
- assert_json_field applied to .pilot/verdicts.jsonl assumes a single JSON object in the file — it runs plain `jq -r` with no `-s`/per-line handling, so a real multi-record JSONL log would break the assertion (tests/helpers.bash:162-170, tests/state-machine.bats:76-83).
- run-tests.sh's missing-bats error message hardcodes the Debian/apt install command even though the suite it's about to run itself branches on GNU vs BSD `date` syntax (tests/run-tests.sh:8-10, tests/state-machine.bats:55,67).
