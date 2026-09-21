#!/usr/bin/env bash
# Real CLI contract tests; no simulated version transactions.
test_version_pre_hook_lifecycle() {
    python3 "$PLUGIN_ROOT/tests/version-pre-hooks.py" "$CLI"
}
