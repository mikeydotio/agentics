---
module: "plugins/issue/tests/test*"
summary: "Per-verb regression tests for issue-cli (dispatch, complete, create, view, list) using fake gh/tmux harnesses."
read_when: "Debugging issue-cli per-verb regression tests"
sources:
  - path: plugins/issue/tests/test-arg-validation.sh
    blob: 52aa1da180368a683c351421dce3d79fc7c24e1d
  - path: plugins/issue/tests/test-autosubmit.sh
    blob: 81841a48492c4dbebaf32c43cb09a597fda9f112
  - path: plugins/issue/tests/test-complete-execute.sh
    blob: 38287da1cc8334b5553d2f08a673943f2809d509
  - path: plugins/issue/tests/test-complete-plan.sh
    blob: b8cb085a2740ac6a4600d7fdaf960625efb717b2
  - path: plugins/issue/tests/test-create.sh
    blob: 170d6c086487159620f780be54b39bafe0309fc4
  - path: plugins/issue/tests/test-dispatch-dryrun.sh
    blob: 960e0b1f4fdd347cc91f45958f3544df089eb6ca
  - path: plugins/issue/tests/test-gitignore.sh
    blob: a32b8a684522fbb84cc53c71afc4a464d762fad8
  - path: plugins/issue/tests/test-list-shaping.sh
    blob: 6d544dd4a10a7fc64543767287cfc966d398b5c9
  - path: plugins/issue/tests/test-owner-repo.sh
    blob: 0badffd1d9e8bed05f6a865910a503466446f935
  - path: plugins/issue/tests/test-preconditions.sh
    blob: 5ab10ab525d49d2197a578e88ec7640ff926f480
  - path: plugins/issue/tests/test-readiness.sh
    blob: 2a7d77036470431e49371c1c57f1866202d8b419
  - path: plugins/issue/tests/test-view.sh
    blob: b9659671bf365ecf8cbcdfe8d6e3ecfaa3a0438c
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/issue/tests/test*

## Purpose

This module is the black-box regression suite for the issue-cli tool (a separate module under plugins/issue/bin), split one file per verb or failure mode rather than one monolithic script — each sources lib.sh for assert_eq/assert_contains/jqf helpers and mk_repo/mk_complete_repo git fixtures, then drives `bash "$SCRIPT" <verb> ...` and inspects the emitted JSON plus on-disk repo state. Several files exist specifically to pin down race conditions in issue-cli's terminal automation that a bare exit-code check would miss: test-readiness.sh guards against Claude Code footer-copy drift (issue #67) across multiple detection tiers, and test-autosubmit.sh is a paste/Enter-race regression (issue #82) whose absorb=1 and absorb=99 cases were checked in RED before the fix landed. Losing this module removes the only proof that issue-cli's destructive path (complete execute's safe-set branch/worktree deletion) and its precondition/argument-validation guard rails behave correctly without ever touching a real gh or tmux.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Every script sources `"$(dirname "$0")/lib.sh"` as its first statement and ends by calling `finish` (e.g. plugins/issue/tests/test-view.sh:5,36) — the shared assert_eq/assert_contains/jqf/mk_repo contract every file in this module depends on. The three tests that drive a REAL (non-dry-run) dispatch against tmux — test-autosubmit.sh, test-gitignore.sh, test-readiness.sh — share one harness shape: prepend tests/fakes onto PATH, set dummy TMUX/TMUX_PANE, disable labeling via ISSUE_LABEL="", and zero every poll/settle delay so the run returns immediately (plugins/issue/tests/test-gitignore.sh:18-27; mirrored plugins/issue/tests/test-readiness.sh:23-35 and plugins/issue/tests/test-autosubmit.sh:28-42). Per-case FAKE_TMUX_STATE scratch dirs are created with `mktemp -d /tmp/issue-*.XXXXXX` and explicitly `rm -rf`'d after each case's assertions rather than via a shared trap/teardown (plugins/issue/tests/test-autosubmit.sh:59,66,74,80,88,95,104,109). FAKE_GH_* and FAKE_TMUX_* env vars are this module's sole channel for scripting the out-of-module fakes/gh and fakes/tmux binaries' canned responses (e.g. FAKE_GH_CLOSED_BY_PRS at plugins/issue/tests/test-complete-execute.sh:8, FAKE_TMUX_CAPTURE mode selection at plugins/issue/tests/test-readiness.sh:29).

## External deps


## Gotchas

Extra `KEY=VAL` env overrides passed to dispatch_ready/dispatch_autosubmit must go through `env "$@"` rather than a bare shell-assignment prefix, because a KEY=VAL string held in a positional parameter isn't recognized as an assignment prefix by bash (plugins/issue/tests/test-readiness.sh:20-22,33; mirrored plugins/issue/tests/test-autosubmit.sh:40). test-autosubmit.sh's absorb=1 and absorb=99 cases were checked in deliberately RED against the pre-fix script — asserting exactly one paste on retry, which the old re-paste-on-retry code fails (plugins/issue/tests/test-autosubmit.sh:71-72,85-86) — and only go green once issue #82's fix lands. test-gitignore.sh's unwritable-.gitignore case is skipped when running as root, since root bypasses Unix permission bits and can't reproduce the add-failed path (plugins/issue/tests/test-gitignore.sh:65-66). test-dispatch-dryrun.sh pins that ISSUE_LABEL="" must use bash's `-` parameter-expansion form (not `:-`) so an explicit empty value disables labeling while an unset variable still defaults (plugins/issue/tests/test-dispatch-dryrun.sh:101-102).
