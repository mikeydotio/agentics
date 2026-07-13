---
module: "plugins/issue/tests (chunk 1)"
summary: "Offline test harness for the issue plugin: stateful fake gh/tmux, shared fixtures/asserts, runner."
read_when: "Changing the issue test fakes or the test runner"
sources:
  - path: plugins/issue/tests/fakes/gh
    blob: c762ce565897189d63ef650c2e2f73a3bfa0e0d8
  - path: plugins/issue/tests/fakes/tmux
    blob: 07e7ee72002196a2bf4e90976b028c54378a22f1
  - path: plugins/issue/tests/lib.sh
    blob: 2eb10a47d3045ba9e6d7c1c953d1b9952abfa360
  - path: plugins/issue/tests/run-tests.sh
    blob: c9ecbe69ff1c00f2d0108e90b1d0041fe66bf4c7
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/issue/tests (chunk 1)

## Purpose

This is the offline test harness for the issue plugin: fakes for `gh` and `tmux` (plugins/issue/tests/fakes/gh, plugins/issue/tests/fakes/tmux) let test-*.sh drive issue.sh's list/view/create/close/dispatch/complete flows deterministically, with no live GitHub or tmux server needed. lib.sh centralizes repo fixtures (mk_repo, mk_complete_repo) and assertion primitives so individual tests stay declarative, and run-tests.sh discovers and executes every test-*.sh, reporting pass/fail. The tmux fake is now stateful (issue #82): it models the Claude Code input box (paste appends, Enter submits, with an absorb-count and drop-paste knob) so a test can distinguish 'the prompt was received' from 'the prompt was submitted' — the exact race the #82 autosubmit fix guards against.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

The tmux fake's virtual state (input box, launched flag, absorb counter, paste log) lives under $STATE (FAKE_TMUX_STATE, default /tmp/issue-faketmux) and is reset only by `new-window` (plugins/issue/tests/fakes/tmux:76-82) — a dispatch's own first call starts clean but nothing purges state between unrelated invocations that skip new-window. A literal paste appends to both the input buffer and $STATE/pastes.log; an Enter clears (submits) the buffer except when FAKE_TMUX_ENTER_ABSORB still has counts left, in which case the Enter is swallowed and the counter decrements instead (plugins/issue/tests/fakes/tmux:106-118). FAKE_GH_LOG (plugins/issue/tests/fakes/gh:33) accumulates one line per `gh` invocation for the whole test process, not per-test, so assertions on call sequences must account for prior calls in the same test file. lib.sh's EXIT trap `_cleanup` (plugins/issue/tests/lib.sh:19-21) owns removal of every mk_repo/mk_complete_repo directory registered in `_TMP_REPOS`; both helpers create repos under /tmp rather than $TMPDIR specifically to dodge macOS Spotlight indexing stalls on file-intensive tests (plugins/issue/tests/lib.sh:5-7).

## External deps


## Gotchas

The first Enter tmux receives after `new-window` always submits (clears the input, sets $STATE/launched) regardless of FAKE_TMUX_ENTER_ABSORB — it's treated as the launch line, not a prompt, so absorb counts only apply to Enters that arrive afterward (plugins/issue/tests/fakes/tmux:28-31,106-110). The gh fake's default branch for an unrecognized subcommand prints a warning to stderr but still exits 0 (plugins/issue/tests/fakes/gh:82-83) — an unimplemented gh call silently 'succeeds' unless a test explicitly inspects stderr or FAKE_GH_LOG. capture-pane's default output (FAKE_TMUX_CAPTURE unset) is deliberately pinned byte-for-byte to the legacy single-line '  ? for shortcuts' fixture so every pre-#67 test keeps passing unchanged (plugins/issue/tests/fakes/tmux:13-15,159-160).
