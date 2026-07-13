---
module: plugins/rca/tests
summary: "Plain-bash test suite for rca's bin/ CLIs: git-fixture harness, fake gh/story CLIs, docs↔CLI contract guard."
read_when: "Debugging rca-*.sh CLI tests or the fixture harness"
sources:
  - path: plugins/rca/tests/fakes/gh
    blob: 3f5fcd149b316d9a4b5f7d99670b11b3897c7653
  - path: plugins/rca/tests/fakes/story
    blob: a1a043d102250be11e5d5584ed5434a4c4665317
  - path: plugins/rca/tests/lib.sh
    blob: 00588ba9dc8b10fa5e64f14160fa0ca694ed94cd
  - path: plugins/rca/tests/run-tests.sh
    blob: 77150dd1b081ab60a586ca2236db67904cbc0cbd
  - path: plugins/rca/tests/test-bisect.sh
    blob: 67d22a8b9a973f14685af297a30396c2ddaf8460
  - path: plugins/rca/tests/test-forensics.sh
    blob: 71748ca12d177c9d1ee95ff45f95d2ed343ccc24
  - path: plugins/rca/tests/test-hotspots.sh
    blob: d19fee8aa0c71c53cca89f61d2729278fb048f5f
  - path: plugins/rca/tests/test-repro.sh
    blob: ec77f8c871b709576c5b27d660a7d2e6a45e307f
  - path: plugins/rca/tests/test-scaffold.sh
    blob: e0d27ff9d4f759d3b79db540330e5f91a8e808d4
  - path: plugins/rca/tests/test-skill-contract.sh
    blob: d2141fb97212fc77f75b97d2a87a31ec0dc3f3ac
  - path: plugins/rca/tests/test-stack.sh
    blob: ca5cf3155af2bb799387432ae3693f351158a7a8
  - path: plugins/rca/tests/test-status.sh
    blob: 51f40a01111063470c5e84ed24c71b9225c52d54
  - path: plugins/rca/tests/test-worktree.sh
    blob: 20ffed9e2d17616c80b5aabb6ba6153e88a579d3
generator: cartographer/4
baseline: 7387d3614aaae8d5a5bc156cf01c251d22b1dd45
---

# Module: plugins/rca/tests

## Purpose

This is rca's bash-native test suite (no bats, the reconcile-pr harness pattern per plugins/rca/tests/lib.sh:2), giving each plugin/rca/bin/rca-*.sh script its own standalone test-*.sh built on shared fixture-repo and JSON-assertion helpers in lib.sh, discovered and run by run-tests.sh as part of the pre-push make test gate. Fixtures build throwaway git repos with planted regressions, churn patterns, or flaky/timeout-prone commands so each rca-*.sh's JSON contract (ok/error shapes) can be asserted with jq. test-skill-contract.sh additionally guards that every rca-<name>.sh flag referenced in the plugin's SKILL.md/references docs is documented in that script's own usage-comment block, catching docs/CLI drift the same way forge's WS8 guard does — without this suite, regressions in rca's CLI contracts or its doc/flag sync would ship silently.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Cleanup ownership: lib.sh's _TMP_DIRS array plus a trap on EXIT (_cleanup) owns every mktmp'd fixture dir and worktree, pruning git worktrees before rm -rf so a failed test never leaks state (plugins/rca/tests/lib.sh:24-33). Execution model: each test-*.sh is a fully standalone `bash test-*.sh` process that sources lib.sh fresh and exits non-zero on the first failed assertion — there is no shared state or ordering dependency between test files (plugins/rca/tests/lib.sh:2-4). fakes/gh and fakes/story are stub CLIs configured entirely through env vars (FAKE_GH_*, FAKE_STORY_*) and meant to be put ahead of the real gh/story on PATH for skill-level flows (plugins/rca/tests/fakes/gh:1-8, plugins/rca/tests/fakes/story:1-8), but no test-*.sh in this module currently invokes them.

## External deps


## Gotchas

Fixture trees are deliberately rooted at /private/tmp, never $TMPDIR — macOS Spotlight indexes $TMPDIR and stalls file-intensive git suites (plugins/rca/tests/lib.sh:6-7,39). test-repro.sh pins that a FAILING test command is still a SUCCESSFUL harness run (ok:true) — only harness-level errors (bad_args, timeout, cmd_not_found) set ok:false (plugins/rca/tests/test-repro.sh:2-4,8-9). test-bisect.sh pins that `git bisect reset` always runs, even proven by expecting a follow-up `git bisect log` to fail (plugins/rca/tests/test-bisect.sh:2-4,18-20). test-status.sh pins two prior defects so they can't regress: a corrupt/missing meta.json must yield state "corrupt" without a `set -u` crash, and every ladder rung must still produce a non-empty option label/description (plugins/rca/tests/test-status.sh:87,100-102). fakes/gh and fakes/story exist in this module but are not wired into any test-*.sh here — no FAKE_GH_LOG/FAKE_STORY_LOG or fakes-path reference exists outside the fakes' own definitions (plugins/rca/tests/fakes/gh:1-8, plugins/rca/tests/fakes/story:1-8), so they read as reserved for skill-level coverage this suite doesn't yet exercise.
