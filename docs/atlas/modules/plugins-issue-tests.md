---
module: plugins/issue/tests
summary: "Bash test suite for the issue plugin (dispatch/complete/list/view) driven by fake gh & tmux binaries."
read_when: "Touching issue plugin tests, fake gh/tmux harness, or dispatch/complete/list behavior"
sources:
  - path: plugins/issue/tests/fakes/gh
    blob: c762ce565897189d63ef650c2e2f73a3bfa0e0d8
  - path: plugins/issue/tests/fakes/tmux
    blob: 1378c9a28c50ece6a7aa00ee80983a0e7f390a37
  - path: plugins/issue/tests/lib.sh
    blob: 2eb10a47d3045ba9e6d7c1c953d1b9952abfa360
  - path: plugins/issue/tests/run-tests.sh
    blob: c9ecbe69ff1c00f2d0108e90b1d0041fe66bf4c7
  - path: plugins/issue/tests/test-arg-validation.sh
    blob: 52aa1da180368a683c351421dce3d79fc7c24e1d
  - path: plugins/issue/tests/test-complete-execute.sh
    blob: 38287da1cc8334b5553d2f08a673943f2809d509
  - path: plugins/issue/tests/test-complete-plan.sh
    blob: b8cb085a2740ac6a4600d7fdaf960625efb717b2
  - path: plugins/issue/tests/test-create.sh
    blob: 170d6c086487159620f780be54b39bafe0309fc4
  - path: plugins/issue/tests/test-dispatch-dryrun.sh
    blob: ede282f4309f54ae0d0f2f7ae36f21ab6ffa3958
  - path: plugins/issue/tests/test-gitignore.sh
    blob: d27cf5681485e1fbd5e7d8272ecdefb7acfcf799
  - path: plugins/issue/tests/test-list-shaping.sh
    blob: 6d544dd4a10a7fc64543767287cfc966d398b5c9
  - path: plugins/issue/tests/test-owner-repo.sh
    blob: 0badffd1d9e8bed05f6a865910a503466446f935
  - path: plugins/issue/tests/test-preconditions.sh
    blob: 5ab10ab525d49d2197a578e88ec7640ff926f480
  - path: plugins/issue/tests/test-readiness.sh
    blob: 7abefdddf8ff0562bfce3e1d9836ddf8478ce078
  - path: plugins/issue/tests/test-view.sh
    blob: b9659671bf365ecf8cbcdfe8d6e3ecfaa3a0438c
generator: cartographer/4
baseline: a4486d2b70ad4124762f9d777af6a7dc007bdc6c
---

# Module: plugins/issue/tests

## Purpose

This suite is the executable specification for the issue plugin's CLI surface (dispatch, complete plan/execute, create, list, view, doctor), replacing a live GitHub/tmux session with two knob-driven fakes (plugins/issue/tests/fakes/gh:1-31, plugins/issue/tests/fakes/tmux:1-39) so the whole flow runs offline and deterministically. Its heaviest investment is mk_complete_repo, a single realistic git fixture (merged/unmerged branches, a pushed merged PR-head branch, a clean worktree, a locked worktree) that both complete-plan and complete-execute tests reuse to prove destructive cleanup only ever touches the safe set (plugins/issue/tests/lib.sh:38-75). Without this module the plugin's guard-rail logic — branch/worktree deletion safety, the multi-tier readiness gate's drift-proofing, gitignore idempotency — would have no regression protection at all.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

- Every test-*.sh sources lib.sh, which resolves SCRIPT to bin/issue.sh and exports ISSUE_GH_BIN to the fake gh, so every invocation of $SCRIPT under test talks to the fake, never live GitHub (plugins/issue/tests/lib.sh:13-17).
- mk_repo creates throwaway repos under /tmp, not $TMPDIR, specifically to dodge macOS Spotlight's mds_stores indexing stalls on file-heavy git fixtures (plugins/issue/tests/lib.sh:5-6).
- mk_complete_repo builds one fixed, heavily-commented fixture (issue 77, origin prefix "rep") encoding every `complete` guard-rail case — merged/unmerged branches, a pushed merged PR-head branch, a clean worktree, and a locked worktree — that test-complete-plan.sh and test-complete-execute.sh both reuse verbatim (plugins/issue/tests/lib.sh:38-75).
- fakes/tmux implements only the subcommands cmd_dispatch/cmd_doctor need and selects capture-pane output via the FAKE_TMUX_CAPTURE tiers (legacy/marker/structural/modal/busy/churn) to drive the multi-tier readiness gate under test (plugins/issue/tests/fakes/tmux:41-86).
- Real (non-dry-run) dispatch tests (test-gitignore.sh, test-readiness.sh) prepend the fake tmux's directory onto PATH and set dummy TMUX/TMUX_PANE plus zeroed poll delays so cmd_dispatch's polling loop runs headlessly and instantly (plugins/issue/tests/test-gitignore.sh:13-26, plugins/issue/tests/test-readiness.sh:23-35).
- No test framework: fail_test/assert_eq/assert_contains/assert_not_contains/finish are hand-rolled in lib.sh, and jqf wraps `jq -r` for JSON field assertions (plugins/issue/tests/lib.sh:77-108).
- run-tests.sh discovers test-*.sh by glob and accepts an optional substring filter as its sole argument (plugins/issue/tests/run-tests.sh:14-18).

## External deps


## Gotchas

- test-gitignore.sh's unwritable-.gitignore case (add-failed path) is skipped entirely when running as root, since root bypasses Unix file-permission bits and could never trigger it (plugins/issue/tests/test-gitignore.sh:64-65).
- dispatch_ready (test-readiness.sh) must route extra env overrides through `env "$@"` rather than a bare shell-assignment prefix, because a variable that expands to `name=value` is not recognized by bash as an assignment prefix (plugins/issue/tests/test-readiness.sh:20-22,33).
- test-dispatch-dryrun.sh's empty-label case depends on `ISSUE_LABEL=""` using the SUT's `-` (not `:-`) expansion, so an explicitly empty value disables labeling while an unset var still defaults — called out inline as deliberate (plugins/issue/tests/test-dispatch-dryrun.sh:93-94).
- fakes/tmux's churn capture mode is re-exec'd per call with no in-process state, so it persists a counter file under $FAKE_TMUX_STATE (falling back to $RANDOM if unset) purely to guarantee successive captures differ (plugins/issue/tests/fakes/tmux:37-39).
