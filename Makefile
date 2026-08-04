# Test entrypoint for the agentics marketplace.
# The global pre-push hook runs `make test` before any push — keep this target
# covering every plugin suite that can run headlessly on a dev machine.

.PHONY: test test-store-isolation test-gate-integrity test-root-bats test-plugin-versions test-plugin-content-drift test-semver test-deployit test-forge test-hook-guard test-greenlight test-freshen test-issue test-reconcile-pr test-rca test-storywork

test: test-store-isolation test-gate-integrity test-root-bats test-plugin-versions test-plugin-content-drift test-semver test-deployit test-forge test-hook-guard test-greenlight test-freshen test-issue test-reconcile-pr test-rca test-storywork

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

# Marketplace-wide content-drift guard: shipped plugin source under plugins/**
# must not change without a version bump, or the version-keyed plugin cache
# serves stale code (issue #71). Plain bash so it always runs in the pre-push gate.
test-plugin-content-drift:
	bash tests/with-isolated-store.sh bash tests/plugin-content-drift.sh

test-semver:
	bash tests/with-isolated-store.sh bash plugins/semver/tests/run-tests.sh

test-deployit:
	bash tests/with-isolated-store.sh bash plugins/deployit/tests/run-tests.sh

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

# storywork's plain-bash suite (plugins/storywork/tests/test-*.sh) — the
# storyhook claim-then-dispatch contract (skip-the-redundant-move when a
# caller already CAS'd the story to in-progress; refuse-before-any-side-
# effect on a lost claim race; the closed-superstate guard) and the
# complete verb's worktree/branch-only cleanup scan. Driven by a fake story
# CLI + fake tmux on PATH + throwaway git repos; no live tmux/claude/story.
# Always runs (no bats).
test-storywork:
	bash tests/with-isolated-store.sh bash plugins/storywork/tests/run-tests.sh

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
