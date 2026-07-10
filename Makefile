# Test entrypoint for the agentics marketplace.
# The global pre-push hook runs `make test` before any push — keep this target
# covering every plugin suite that can run headlessly on a dev machine.

.PHONY: test test-root-bats test-plugin-versions test-plugin-content-drift test-semver test-deployit test-atlas test-forge test-hook-guard test-greenlight test-freshen test-issue test-reconcile-pr

test: test-root-bats test-plugin-versions test-plugin-content-drift test-semver test-deployit test-atlas test-forge test-hook-guard test-greenlight test-freshen test-issue test-reconcile-pr

# Root bats suite (storyhook state machine). bats-core is not installed
# everywhere; skip with a notice rather than failing the whole gate.
test-root-bats:
	@if command -v bats >/dev/null 2>&1; then \
		bash tests/run-tests.sh; \
	else \
		echo "bats not installed — skipping root bats suite (tests/*.bats)"; \
	fi

# Marketplace-wide plugin.json version-sync drift guard + sync-hook behaviour.
# Plain bash (no bats) so it always runs as part of the pre-push gate.
test-plugin-versions:
	bash tests/plugin-versions.sh

# Marketplace-wide content-drift guard: shipped plugin source under plugins/**
# must not change without a version bump, or the version-keyed plugin cache
# serves stale code (issue #71). Plain bash so it always runs in the pre-push gate.
test-plugin-content-drift:
	bash tests/plugin-content-drift.sh

test-semver:
	bash plugins/semver/tests/run-tests.sh

test-deployit:
	bash plugins/deployit/tests/run-tests.sh

# issue's plain-bash suite (plugins/issue/tests/test-*.sh) — the
# list/dispatch/view/create/complete JSON contracts, owner/repo parsing, dry-run
# tmux sequencing, and the complete-verb cleanup guard rails (driven by a fake gh
# on PATH + throwaway git repos; no live tmux/claude). Always runs (no bats).
test-issue:
	bash plugins/issue/tests/run-tests.sh

# reconcile-pr's plain-bash suite (plugins/reconcile-pr/tests/test-*.sh) — the
# state-machine JSON contract, non-inverted conflict labeling, the force-push
# safety gate (protected/leased/stale), and the test gate. Driven by a fake gh
# and a local bare-origin repo; no live network. Always runs (no bats).
test-reconcile-pr:
	bash plugins/reconcile-pr/tests/run-tests.sh

test-atlas:
	bash plugins/atlas/tests/run-tests.sh

# forge's bats suites (plugins/forge/bin/*.bats, plugins/forge/hooks/*.bats).
# Same bats-not-installed-everywhere caveat as test-root-bats.
test-forge:
	@if command -v bats >/dev/null 2>&1; then \
		bash plugins/forge/tests/run-tests.sh; \
	else \
		echo "bats not installed — skipping forge bats suite (plugins/forge/bin,hooks/*.bats)"; \
	fi

# hook-guard's bats suites (plugins/hook-guard/lib/*.bats, hooks/*.bats) —
# the Stop-loop circuit breaker (F048/F043/F050/F052/F054/F055 regression
# coverage). Same bats-not-installed-everywhere caveat as test-root-bats.
test-hook-guard:
	@if command -v bats >/dev/null 2>&1; then \
		bash plugins/hook-guard/tests/run-tests.sh; \
	else \
		echo "bats not installed — skipping hook-guard bats suite (plugins/hook-guard/lib,hooks/*.bats)"; \
	fi

# greenlight's bats suite (plugins/greenlight/tests/*.bats) — the PreToolUse
# safety hook (F075/F076/F077/F078/F080/F081/F082 regression coverage).
# Same bats-not-installed-everywhere caveat as test-root-bats.
test-greenlight:
	@if command -v bats >/dev/null 2>&1; then \
		bash plugins/greenlight/tests/run-tests.sh; \
	else \
		echo "bats not installed — skipping greenlight bats suite (plugins/greenlight/tests/*.bats)"; \
	fi

# freshen's bats suites (plugins/freshen/lib/*.bats, hooks/*.bats) — the
# tmux capture-pane confirm/retry and transition-log helpers behind the
# auto-resume cycle (F045/F041/F056/F047 regression coverage). Same
# bats-not-installed-everywhere caveat as test-root-bats.
test-freshen:
	@if command -v bats >/dev/null 2>&1; then \
		bash plugins/freshen/tests/run-tests.sh; \
	else \
		echo "bats not installed — skipping freshen bats suite (plugins/freshen/lib,hooks/*.bats)"; \
	fi
