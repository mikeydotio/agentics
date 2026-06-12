---
module: tests
summary: "Root bats suite pinning the pilot/storyhook state-machine file contracts via self-built temp-repo fixtures"
read_when: "Touching tests/*.bats, the bats helpers, or pilot/storyhook state-file schemas"
sources:
  - path: tests/helpers.bash
    blob: ca28a41ee9ec7cc8b278243237315d55e07e8a04
  - path: tests/init.bats
    blob: 4165667c3062581e7e3ff170335e404a87da24de
  - path: tests/run-tests.sh
    blob: 18b3f63079da9fd9dce3c88ed11500f2eadbf0c3
  - path: tests/state-machine.bats
    blob: b48e1c7812e0bb44c8ba4f41fdcb1d901f1a0b01
references_modules: [root-misc]
generator: cartographer/1
baseline: cdb99b78f7feadd24f898adb2545c7589790c375
verified: true
---

# Module: tests

## Purpose

Contract tests for the storyhook-backed pilot state machinery: the work-state vocabulary in
`.storyhook/states.toml` and the JSON files under `.pilot/` (state, config, lock, verdicts, plan
mapping). The suite is deliberately self-contained — `tests/helpers.bash` fabricates every
fixture inside a throwaway git repo, and tests assert on file shapes and heartbeat arithmetic
without executing any production script. If it vanished, nothing would pin the on-disk schemas
this machinery depends on.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `add_work_states` | function | `tests/helpers.bash:95` | Appends in-progress/verifying/blocked to states.toml; not idempotent — callers must guard |
| `assert_file_contains` | function | `tests/helpers.bash:151` | Fixed-string grep; on miss, dumps the file to stderr and returns 1 |
| `assert_json_field` | function | `tests/helpers.bash:162` | `jq -r` field $2 of file $1 must equal $3; returns 1 on mismatch |
| `create_config_json` | function | `tests/helpers.bash:62` | Writes .pilot/config.json with retry, session, and heartbeat limits |
| `create_lock_json` | function | `tests/helpers.bash:76` | Writes .pilot/lock.json; $1 overrides heartbeat_at, default is now (UTC) |
| `create_stale_lock` | function | `tests/helpers.bash:88` | Lock whose heartbeat is 35 min in the past — beyond the 30-min window |
| `create_state_json` | function | `tests/helpers.bash:40` | Writes .pilot/state.json (version 1, counters zeroed); $1 sets status, default paused |
| `create_test_design` | function | `tests/helpers.bash:135` | Writes .planning/DESIGN.md with sections matching create_test_plan's modules |
| `create_test_plan` | function | `tests/helpers.bash:113` | Writes .planning/PLAN.md: two waves of checkbox tasks with acceptance + files |
| `run-tests.sh` | script | `tests/run-tests.sh:1` | Entry point; hard-fails if bats-core missing, else runs tests/*.bats forwarding args |
| `setup_test_project` | function | `tests/helpers.bash:5` | mktemp git repo with states.toml (todo/done), .pilot, .planning; exports TEST_PROJECT_DIR |
| `teardown_test_project` | function | `tests/helpers.bash:33` | rm -rf "$TEST_PROJECT_DIR" when set and extant |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `adding pilot states is idempotent` | bats test | `tests/init.bats:18` | Pins the grep-guard-before-append contract for re-running init |
| `config.json has all required fields` | bats test | `tests/state-machine.bats:31` | Pins the config schema and its default limits (max_retries=4, trigger_interval=15m) |
| `plan-mapping.json structure is valid` | bats test | `tests/state-machine.bats:87` | Pins story→task mapping: wave, acceptance, embedded design_section, files_expected |
| `stale lock heartbeat exceeds window` | bats test | `tests/state-machine.bats:62` | Pins the 30-minute heartbeat staleness boundary (fresh-lock twin at line 50) |
| `state.json status values are valid` | bats test | `tests/state-machine.bats:24` | Pins the status enum: running, paused, complete |
| `verdict entry has required fields` | bats test | `tests/state-machine.bats:76` | Pins verdicts.jsonl shape: story, attempt, verdict, failures[] with evidence |

## Relationships

- `root-misc.Makefile -> tests.run-tests.sh (calls)`
- `tests.init.bats -> tests.helpers.bash (calls)`
- `tests.run-tests.sh -> tests.init.bats (calls)`
- `tests.run-tests.sh -> tests.state-machine.bats (calls)`
- `tests.state-machine.bats -> tests.helpers.bash (calls)`

## Type notes

- Every test gets a fresh mktemp project via setup(); teardown() removes it (tests/init.bats:6)
- `TEST_PROJECT_DIR` is the one exported global all helpers path through (tests/helpers.bash:7)
- Timestamps are ISO-8601 UTC Zulu strings (tests/helpers.bash:55)
- Heartbeat parsing tries GNU `date -d`, then BSD `date -j -f` (tests/state-machine.bats:55)
- states.toml entries declare a `super` of open or closed (tests/helpers.bash:18)

## External deps

- bats-core — test framework; runner exits 1 when absent (tests/run-tests.sh:8)
- jq — all JSON field assertions (tests/helpers.bash:165)
- git — every fixture project is an initialized repo with test identity (tests/helpers.bash:10)
- date (GNU/BSD) — dual-syntax fallbacks for stale-time fabrication (tests/helpers.bash:90)

## Gotchas

- No production script runs; the init idempotency guard is simulated in-test (tests/init.bats:26)
- `create_stale_lock` yields an empty time if both date syntaxes fail (tests/helpers.bash:90)
- `assert_json_field` on verdicts.jsonl assumes a single-line log (tests/state-machine.bats:78)
- The missing-bats hint is Debian-only: `sudo apt-get install bats` (tests/run-tests.sh:9)
