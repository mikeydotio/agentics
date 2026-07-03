# Test entrypoint for the agentics marketplace.
# The global pre-push hook runs `make test` before any push — keep this target
# covering every plugin suite that can run headlessly on a dev machine.

.PHONY: test test-root-bats test-plugin-versions test-semver test-deployit test-atlas test-forge test-hook-guard test-greenlight test-freshen

test: test-root-bats test-plugin-versions test-semver test-deployit test-atlas test-forge test-hook-guard test-greenlight test-freshen

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

test-semver:
	bash plugins/semver/tests/run-tests.sh

test-deployit:
	bash plugins/deployit/tests/run-tests.sh

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
