#!/usr/bin/env bash
# AGE-85 (class): whatever goes wrong, the CLI answers in JSON.
#
# The orchestrator skill's whole contract is "if the CLI returns ok: false, show
# display and stop" — it has nothing to show a user when a bare Python traceback
# comes out instead. `_kickstart_daemon` was one such escape; a dozen more
# `check=True` subprocess calls in the same file can still raise. `main()` now
# backstops all of them.
#
# The trigger here is a real one, not a synthetic raise: `cmd_status` reads
# builds.json and catches only FileNotFoundError, so a corrupt index file
# raises JSONDecodeError straight out of the command.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

export DEPLOYIT_STATE_DIR="$ROOT/state"
export DEPLOYIT_TAILSCALE_BIN="$TESTS_DIR/fakes/tailscale"
export DEPLOYIT_LAUNCHCTL_BIN="$TESTS_DIR/fakes/true"
export DEPLOYIT_SKIP_LAUNCHD=1
export DEPLOYIT_SKIP_KICKSTART=1
export DEPLOYIT_SKIP_VERIFY=1
export DEPLOYIT_SKIP_TAILSCALE_SERVE=1
export DEPLOYIT_SKIP_INDEX_CLONE=1

python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" bootstrap \
    > "$ROOT/bootstrap.log" 2>&1 \
    || { echo "FAIL: bootstrap exited $? — the CLI said:"; cat "$ROOT/bootstrap.log"; exit 1; }

# Corrupt the index the way a half-written file or a killed process would.
printf '{"version": 1, "builds": [' > "$ROOT/state/index/builds.json"

set +e
out=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" status \
          2>"$ROOT/stderr.log")
rc=$?
set -e

[[ $rc -ne 0 ]] || { echo "FAIL: a corrupt index must not report success: $out"; exit 1; }

python3 -c "
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(f'FAIL: stdout is a traceback, not the JSON contract: {raw!r}')
assert d.get('ok') is False, f'expected ok=false, got: {d}'
assert d.get('unexpected') is True, f'an unexpected failure must say so: {d}'
assert d.get('command') == 'status', f'the failing command must be named: {d}'
assert 'JSONDecodeError' in d.get('display', ''), \
    f'the display must carry the real cause, got: {d.get(\"display\")!r}'
" <<<"$out" || exit 1

# Context is reframed for the caller, never destroyed: the traceback still goes
# to stderr for whoever has to diagnose it.
grep -q 'Traceback' "$ROOT/stderr.log" \
    || { echo "FAIL: the traceback must survive on stderr"; cat "$ROOT/stderr.log"; exit 1; }

# A well-behaved command must not be tagged as unexpected.
good=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" url) \
    || { echo "FAIL: url exited $? — $good"; exit 1; }
python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['ok'] is True, d
assert 'unexpected' not in d, f'a healthy command must not be tagged unexpected: {d}'
" <<<"$good" || exit 1

echo "PASS"
