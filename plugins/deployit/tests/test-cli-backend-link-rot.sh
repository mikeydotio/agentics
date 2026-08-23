#!/usr/bin/env bash
# AGE-85 (B): a pruned plugin-cache version must not silently strand the daemon.
#
# The launchd plist pins <state>/bin/deployit-backend and <state>/_plugin_root
# forever; both are symlinks into ~/.claude/plugins/cache/agentics/deployit/<v>/.
# When an old version is pruned, both dangle and launchd respawns the job into
# the same ENOENT indefinitely (34,007 runs, in the field). Nothing surfaced it:
# `status` said only "backend: DOWN", and `deploy` published a build whose
# install page 502s while still reporting ok.
#
# A dangling link is an invalid state with exactly one correct repair, and the
# CLI always knows the answer — it is invoked with --plugin-root. So it repairs
# a BROKEN link automatically, and leaves a link that resolves alone even when
# it names a different root (that may be a deliberate `redeploy --source` pin).
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

# Port isolation: bootstrap writes the default port, and the developer running
# these tests usually has a REAL daemon listening on it — which would make the
# sandbox's health probe report someone else's backend as this one's. Pin the
# sandbox to a port nothing can be on.
FREE_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")
python3 - "$ROOT/state/config.toml" "$FREE_PORT" <<'ISO'
import re, sys
path, port = sys.argv[1], sys.argv[2]
body = open(path).read()
body, n = re.subn(r'(?m)^\s*port\s*=.*$', f'port = {port}', body, count=1)
assert n == 1, f'no server.port line in {path}:\n{body}'
open(path, 'w').write(body)
ISO

LINK="$ROOT/state/bin/deployit-backend"

# --- Case 1: `status` must name the reason the backend is down.
# Simulate a pruned cache version: both stable links point into thin air.
ln -sf "$ROOT/pruned-version/bin/deployit-backend" "$LINK"
ln -sfn "$ROOT/pruned-version" "$ROOT/state/_plugin_root"

status_out=$(python3 "$PLUGIN_ROOT/bin/deployit-cli" --plugin-root "$PLUGIN_ROOT" status) \
    || { echo "FAIL: status exited $? — $status_out"; exit 1; }
python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['ok'] is True, d
assert d['backend_ok'] is False, d
assert d.get('backend_link') == 'dangling', \
    f'status must classify the stale link, got: {d.get(\"backend_link\")!r}'
disp = d['display']
assert 'dangling' in disp or 'stale' in disp, \
    f'status must say WHY the backend is down, got: {disp!r}'
assert 'redeploy' in disp, f'status must name the remedy, got: {disp!r}'
" <<<"$status_out" || exit 1

# `status` is documented read-only — it reports, it must not repair.
[[ "$(readlink "$LINK")" == "$ROOT/pruned-version/bin/deployit-backend" ]] \
    || { echo "FAIL: status must not mutate the symlink (it is read-only)"; exit 1; }

# --- Cases 2-5: the heal itself, and the refresh path that invokes it.
python3 - "$PLUGIN_ROOT" "$ROOT" <<'PY' || exit 1
import importlib.machinery, importlib.util, os, socket, sys
from pathlib import Path

plugin_root, root = Path(sys.argv[1]), Path(sys.argv[2])
# The CLI has no .py suffix, so importlib cannot infer a loader for it — name one.
cli_path = str(plugin_root / "bin" / "deployit-cli")
loader = importlib.machinery.SourceFileLoader("deployit_cli", cli_path)
spec = importlib.util.spec_from_file_location("deployit_cli", cli_path, loader=loader)
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)          # safe: main() is under an __main__ guard

state = root / "state"
link = state / "bin" / "deployit-backend"
pruned = root / "pruned-version"

def relink_dangling():
    if link.is_symlink() or link.exists():
        link.unlink()
    link.symlink_to(pruned / "bin" / "deployit-backend")

# --- Case 2: a dangling link is classified, then repaired.
relink_dangling()
assert cli._backend_link_health(state)[0] == "dangling", cli._backend_link_health(state)

note = cli._heal_backend_link(state, plugin_root)
assert note, "a dangling link must be repaired and reported"
assert link.resolve() == (plugin_root / "bin" / "deployit-backend").resolve(), link.resolve()
assert state.joinpath("_plugin_root").resolve() == plugin_root.resolve()
assert cli._backend_link_health(state)[0] == "ok"

# --- Case 3: a missing link is repaired too.
link.unlink()
assert cli._backend_link_health(state)[0] == "missing"
assert cli._heal_backend_link(state, plugin_root), "a missing link must be repaired"
assert cli._backend_link_health(state)[0] == "ok"

# --- Case 4: a link that RESOLVES is left alone, even pointing elsewhere.
# `redeploy --source <dev checkout>` is a deliberate pin; healing must never
# silently drag the daemon back to the cache copy.
other = root / "other-plugin"
(other / "bin").mkdir(parents=True, exist_ok=True)
(other / "bin" / "deployit-backend").write_text("#!/usr/bin/env python3\n")
cli._sync_plugin_root(state, other)
assert cli._backend_link_health(state)[0] == "ok"
assert cli._heal_backend_link(state, plugin_root) is None, \
    "a resolving link must not be retargeted"
assert link.resolve() == (other / "bin" / "deployit-backend").resolve(), \
    "the deliberate pin was clobbered"

# --- Case 5: a refused refresh heals the link and retries.
# This is the field failure: deploy's only symptom was "Connection refused",
# after which it reported ok and published a build whose page 502s.
relink_dangling()
with socket.socket() as s:                    # a port with nothing listening
    s.bind(("127.0.0.1", 0))
    dead_port = s.getsockname()[1]

healed = cli._refresh_local_backend(dead_port, state=state, plugin_root=plugin_root)
assert healed is not None, "refresh must report the repair it made"
assert cli._backend_link_health(state)[0] == "ok", \
    "a refused refresh must repair a broken link rather than shrug"

# ...and with no broken link to blame, it stays a plain warning, not a repair.
assert cli._refresh_local_backend(dead_port, state=state, plugin_root=plugin_root) is None

print("unit cases OK")
PY

echo "PASS"
