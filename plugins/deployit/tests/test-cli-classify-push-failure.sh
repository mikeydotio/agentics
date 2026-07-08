#!/usr/bin/env bash
# Unit test for _classify_push_failure: the routing verdict a failed
# `git push origin main` gets from its stderr decides whether the publisher
# falls back to a PR (ruleset/protected), re-pulls and retries (non-fast-forward),
# or preserves-and-bails (auth). No git needed.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

python3 - "$PLUGIN_ROOT" <<'PY'
import importlib.machinery, importlib.util, pathlib, sys
plugin_root = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("dcli", str(plugin_root / "bin" / "deployit-cli"))
spec = importlib.util.spec_from_loader("dcli", loader)
mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)

cases = {
    "ruleset": [
        # the exact stderr from issue #69
        ("remote: error: GH013: Repository rule violations found for refs/heads/main.\n"
         "remote: - Changes must be made through a pull request.\n"
         "! [remote rejected] main -> main (push declined due to repository rule violations)"),
        "remote: - Changes must be made through a pull request.",
    ],
    "protected": [
        "remote: error: GH006: Protected branch update failed for refs/heads/main.\n"
        "remote: error: protected branch hook declined.",
        "remote: error: At least 1 approving review is required by reviewers with write access.",
    ],
    "auth": [
        "fatal: Authentication failed for 'https://github.com/mikeydotio/deployit-index.git/'",
        "remote: Support for password authentication was removed.",
        "fatal: could not read Username for 'https://github.com': terminal prompts disabled",
    ],
    "non_fast_forward": [
        "! [rejected]        main -> main (non-fast-forward)\n"
        "error: failed to push some refs to '...'\nhint: Updates were rejected because the tip ...",
        "! [rejected] main -> main (fetch first)",
    ],
    "other": [
        "fatal: unable to access 'https://github.com/...': Could not resolve host: github.com",
        "",
    ],
}

fails = []
for expected, samples in cases.items():
    for s in samples:
        got = mod._classify_push_failure(s)
        if got != expected:
            fails.append((expected, got, s[:60]))

if fails:
    for exp, got, s in fails:
        print(f"MISMATCH: expected {exp!r} got {got!r} for {s!r}")
    sys.exit(1)
print("ok")
PY

echo "PASS"
