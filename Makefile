# Test entrypoint for the agentics marketplace.
# Repository-owned testing: this target covers every headless plugin suite.
# Agentics installs no global test-enforcement hook (AGE-102 / SH-682).

.PHONY: test test-store-isolation test-gate-integrity test-hook-retirement test-storyhook-version-pin test-root-bats test-plugin-versions test-plugin-content-drift test-storyhook-path-guard test-storyhook-contract-root test-sigpipe-shape-guard test-bounded-capture-guard test-forge-integrity-isolation test-prompt-hygiene test-agents test-council test-semver test-deployit test-deployit-capture-diagnostics test-forge test-hook-guard test-greenlight test-freshen test-issue test-reconcile-pr test-rca

test: test-store-isolation test-gate-integrity test-hook-retirement test-storyhook-version-pin test-root-bats test-plugin-versions test-plugin-content-drift test-storyhook-path-guard test-storyhook-contract-root test-sigpipe-shape-guard test-bounded-capture-guard test-forge-integrity-isolation test-prompt-hygiene test-agents test-council test-semver test-deployit test-deployit-capture-diagnostics test-forge test-hook-guard test-greenlight test-freshen test-issue test-reconcile-pr test-rca

# Every test target must run against a storyhook store of its own. Pinned
# mechanically: a target added without the wrapper is how 394 fixture projects
# reached a real store on 2026-07-30.
test-store-isolation:
	bash tests/store-isolation.sh

# The gate must mean what it reports: a missing tool has to FAIL the pre-push
# gate, never skip it into a vacuous green (AGE-18). Runs early and takes ~15s —
# a green `make test` from here on is a claim that every suite actually ran.
test-gate-integrity:
	bash tests/with-isolated-store.sh bash tests/gate-integrity.sh

# Exercises retirement only against private fixture homes.
test-hook-retirement:
	bash tests/with-isolated-store.sh bash tests/retire-pre-push-hook.sh

# storyhook is an out-of-repo CLI resolved from PATH, so upgrading it changes
# this repo's test outcome with no commit here — which is why git bisect cannot
# attribute the result. Measured (AGE-19): the real v1.0.0 binary produces 87
# failing assertions across forge, the now-retired storywork, and
# storyhook-contract-root, and
# not one of 2,693 log lines names a version; 59 of them say "unknown command
# `project`", which blames the caller. This declares the supported major once
# and fails first with one sentence. Runs after gate-integrity so the meta-gate
# still certifies the run before a subject-matter gate speaks. Plain bash so it
# always runs.
test-storyhook-version-pin:
	bash tests/with-isolated-store.sh bash tests/storyhook-version-pin.sh

# Root bats suite (storyhook state machine).
#
# Tool availability is the RUNNER's policy, not this recipe's: every runner below
# already exits 1 with an actionable "install bats-core" message. Do not wrap
# these in `if command -v bats` — that swallow made the sole pre-push gate exit 0
# having verified nothing (AGE-18), and a Makefile-level check would miss the
# direct `bash <runner>` entry path anyway. tests/gate-integrity.sh pins this.
test-root-bats:
	bash tests/with-isolated-store.sh bash tests/run-tests.sh

# Marketplace-wide plugin.json version-sync drift guard + sync-hook behaviour.
# Plain bash (no bats) so it always runs as part of the pre-push gate.
test-plugin-versions:
	bash tests/with-isolated-store.sh bash tests/plugin-versions.sh

# Test both identity policies, then disclose the candidate's release state.
# Candidate success never certifies publication or version-keyed installation.
test-plugin-content-drift:
	bash tests/with-isolated-store.sh bash tests/plugin-content-drift.sh
	bash tests/with-isolated-store.sh bash scripts/check-plugin-content.sh --mode candidate

# Mandatory release/install-source preflight, outside the candidate test graph.
# Keep the strict checker last so successful manifest tests cannot mask drift.
.PHONY: validate-release
validate-release: test-plugin-versions
	bash tests/with-isolated-store.sh bash scripts/check-plugin-content.sh --mode release

# Storyhook's retired per-repo directory must not come back: no --extra-path may
# name it (any spelling, repo-wide), and shipped plugin content must not assert
# it exists. It was a dead no-op in three shipped forge call sites for over a
# year with no failure mode, because forge-step-exit.sh silently skips an
# --extra-path that isn't on disk (AGE-11). Plain bash so it always runs.
test-storyhook-path-guard:
	bash tests/with-isolated-store.sh bash tests/storyhook-path-guard.sh

# The grammar half of the same job (AGE-30). Layer 3 above greps root
# instruction files for retired storyhook SURFACES, which are fixed strings; the
# dead id-first form `story <id> is done` is pattern-shaped, so only a grammar
# guard can hold it. Points forge-contract-check.sh at AGENTS.md and CLAUDE.md
# via its --file interface, which shape-based discovery cannot reach. Kept
# separate from the path guard on purpose: this one needs the live `story` CLI
# and has an ok:false cannot-verify path. Plain bash so it always runs.
test-storyhook-contract-root:
	bash tests/with-isolated-store.sh bash tests/storyhook-contract-root.sh

# An early-exit consumer (grep -q, grep -m N, head) must not drain a producer
# that is still writing, in a file that arms pipefail: the producer dies of
# SIGPIPE and pipefail reports 141 for a match that SUCCEEDED. Three such sites
# existed on 2026-08-04 (AGE-21). Behavioral arms run against real git on a
# fixture sized past the pipe buffer, so they test a certainty and not a race.
# Plain bash so it always runs.
test-sigpipe-shape-guard:
	bash tests/with-isolated-store.sh bash tests/sigpipe-shape-guard.sh

# AGE-22: a command bounded by `timeout`/`gtimeout`, or by a wrapper around one,
# must never have its output captured through a command substitution — an
# escaped descendant holds the pipe's write end and the bound silently stops
# meaning anything (measured 30.08s against a 5s bound). Four positively-pinned
# layers, no redirect heuristic, no derived closure. Plain bash so it always runs.
test-bounded-capture-guard:
	bash tests/with-isolated-store.sh bash tests/bounded-capture-guard.sh

# AGE-34: /tmp/forge-integrity is a MACHINE-GLOBAL snapshot root holding the
# live integrity baselines of every project on the box. forge-integrity.bats's
# teardown used to `rm -rf` the whole root, deleting every concurrent run's
# baselines and any real forge session's in another repository (measured: 14/19
# red with that rm as the only concurrent actor). Bidirectional on purpose —
# deleting the teardown line entirely satisfies "the sentinel survived", so the
# under-delete arm pins that the suite still removes its own subtree. Plain
# bash so it always runs in the pre-push gate.
test-forge-integrity-isolation:
	bash tests/with-isolated-store.sh bash tests/forge-integrity-isolation.sh

# Claude 5 prompt-realignment regression guard (#118): model/effort tiering
# stays alias-only and never pinned up, no self-verification instructions or
# unresolvable finding-ID citations creep back into shipped skill/agent/
# reference prose, and every SKILL.md stays inside the body-line and
# description-char budgets. Plain bash so it always runs in the pre-push gate.
test-prompt-hygiene:
	bash tests/with-isolated-store.sh bash tests/prompt-hygiene.sh

# Structural validation for the shared agent library (frontmatter, tool/
# read-only consistency, naming, canonical-guardrail drift, model/effort
# policy) — previously invoked only ad hoc via the /agents skill and never
# part of the pre-push gate, so WS-A's model-pin and self-verification
# checks went unenforced. Plain bash so it always runs.
test-agents:
	bash tests/with-isolated-store.sh bash plugins/agents/bin/validate-agents.sh
	bash tests/with-isolated-store.sh bash plugins/agents/tests/codex-compat.sh
	bash tests/with-isolated-store.sh bash plugins/agents/tests/smoke-codex-install.sh

# Both hosts use the same executable liveness policy and retain native dispatch.
test-council:
	bash tests/with-isolated-store.sh bash plugins/council/tests/run-tests.sh
	bash tests/with-isolated-store.sh bash plugins/council/tests/codex-compat.sh
	bash tests/with-isolated-store.sh bash plugins/council/tests/smoke-codex-install.sh

test-semver:
	bash tests/with-isolated-store.sh bash plugins/semver/tests/run-tests.sh

test-deployit:
	bash tests/with-isolated-store.sh bash plugins/deployit/tests/run-tests.sh

# A red deployit test must SAY WHY. deployit-cli/deployit-release print their
# JSON diagnosis to STDOUT and exit 1, so a capture under `set -e` used to die
# with the diagnosis sealed in a variable — 0 bytes on both streams, and a bare
# `FAIL (exit 1)` above an empty block. That is why AGE-35's occurrence was
# never diagnosable. This injects a CLI failure at each call depth and pins what
# every covered file does about it. Behavioural, not a source census: the defect
# has four invocation shapes and only one is visible to a regex. ~140-170s,
# machine-load dependent.
test-deployit-capture-diagnostics:
	bash tests/with-isolated-store.sh bash tests/deployit-capture-diagnostics.sh

# issue's plain-bash suite (plugins/issue/tests/test-*.sh) — the
# list/dispatch/view/create/complete JSON contracts, owner/repo parsing, dry-run
# tmux sequencing, and the complete-verb cleanup guard rails (driven by a fake gh
# on PATH + throwaway git repos; no live tmux/claude). Always runs (no bats).
test-issue:
	bash tests/with-isolated-store.sh bash plugins/issue/tests/run-tests.sh

# reconcile-pr's plain-bash suite (plugins/reconcile-pr/tests/test-*.sh) — the
# state-machine JSON contract, non-inverted conflict labeling, the force-push
# safety gate (protected/leased/stale), and the test gate. Driven by a fake gh
# and a local bare-origin repo; no live network. Always runs (no bats).
test-reconcile-pr:
	bash tests/with-isolated-store.sh bash plugins/reconcile-pr/tests/run-tests.sh

# rca's plain-bash suite (plugins/rca/tests/test-*.sh) — the investigation state
# ladder, scaffold/gitignore idempotency, stack detection, the repro harness
# (flaky/timeout/cmd-not-found), the worktree lifecycle + untracked --copy, the
# git-bisect culprit finder (incl. build-skip mapping), read-only forensics, the
# hotspots/co-change ranker, and the docs<->CLI skill-contract guard. Driven by
# throwaway git repos under /private/tmp; no live network. Always runs (no bats).
test-rca:
	bash tests/with-isolated-store.sh bash plugins/rca/tests/run-tests.sh

# forge's bats suites (plugins/forge/bin/*.bats, plugins/forge/hooks/*.bats).
test-forge:
	bash tests/with-isolated-store.sh bash plugins/forge/tests/run-tests.sh

# hook-guard's bats suites (plugins/hook-guard/lib/*.bats, hooks/*.bats) —
# the Stop-loop circuit breaker (F048/F043/F050/F052/F054/F055 regression
# coverage).
test-hook-guard:
	bash tests/with-isolated-store.sh bash plugins/hook-guard/tests/run-tests.sh

# greenlight's bats suite (plugins/greenlight/tests/*.bats) — the PreToolUse
# safety hook (F075/F076/F077/F078/F080/F081/F082 regression coverage).
test-greenlight:
	bash tests/with-isolated-store.sh bash plugins/greenlight/tests/run-tests.sh

# freshen's bats suites (plugins/freshen/lib/*.bats, hooks/*.bats) — the
# tmux capture-pane confirm/retry and transition-log helpers behind the
# auto-resume cycle (F045/F041/F056/F047 regression coverage).
test-freshen:
	bash tests/with-isolated-store.sh bash plugins/freshen/tests/run-tests.sh
