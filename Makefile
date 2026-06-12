# Test entrypoint for the agentics marketplace.
# The global pre-push hook runs `make test` before any push — keep this target
# covering every plugin suite that can run headlessly on a dev machine.

.PHONY: test test-root-bats test-semver test-deployit test-atlas

test: test-root-bats test-semver test-deployit test-atlas

# Root bats suite (storyhook state machine). bats-core is not installed
# everywhere; skip with a notice rather than failing the whole gate.
test-root-bats:
	@if command -v bats >/dev/null 2>&1; then \
		bash tests/run-tests.sh; \
	else \
		echo "bats not installed — skipping root bats suite (tests/*.bats)"; \
	fi

test-semver:
	bash plugins/semver/tests/run-tests.sh

test-deployit:
	bash plugins/deployit/tests/run-tests.sh

test-atlas:
	bash plugins/atlas/tests/run-tests.sh
