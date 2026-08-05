#!/usr/bin/env bash
# AGE-48. `_commit_and_push_index`'s DEPLOYIT_SKIP_GC_PUSH hatch touches no git
# remote, so it must not report the outcome that means "the change reached
# origin". It returns status="local_only", and `cmd_rm`/`cmd_gc` disclose that
# as `index_local_only` in the payload AND the display.
#
# The measured harm this pins is NOT test vacuity — the story claimed that and
# it is refuted: test-cli-rm.sh and test-cli-rm-pr-fallback.sh both fail loudly
# under a leaked variable. It is that a published removal and an unpublished one
# produced BYTE-IDENTICAL stdout while irreversibly deleting the serve dir in
# both, leaving a caller — human, agent, or the web UI over HTTP — no way to
# tell them apart.
#
# Five arms, because the weak version of this test is walkable. "The payload
# contains index_local_only" passes under a cosmetic fix that adds the key while
# _commit_and_push_index still returns published:True, and "the two stdouts
# differ" passes on any incidental nondeterminism. So:
#   1. dict EQUALITY on the hatch's return       — reds on a re-added `published`
#                                                  exactly as on a removed `status`
#   2. the gate predicate over its WHOLE input domain (dict | None)
#   3. a structural payload differential          — exactly one key added, every
#                                                  other shared key byte-equal
#   4. an ABSENCE arm on index_pending            — nothing else in this suite
#                                                  asserts that key absent anywhere
#   5. a display arm                              — the lie was on the channel a
#                                                  human actually reads
#
# ⚠ A green run of this file is NOT evidence the web UI's swipe-to-delete path
# is fixed. The live daemon runs a COPY at <state>/_plugin_root/bin/deployit-cli
# (deployit-backend:466-467) while test-backend-delete.sh:20 SYMLINKS it, so this
# suite is structurally immune to a stale copy and cannot detect a missed
# `/deployit redeploy`.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# Arm 3 runs a REAL push against a local bare origin. Inheriting the hatch would
# make both halves of the differential take the same branch and the set
# difference would be trivially empty — a pass proving nothing.
[[ -z "${DEPLOYIT_SKIP_GC_PUSH:-}" ]] \
    || { echo "FAIL: DEPLOYIT_SKIP_GC_PUSH is set; this test's differential needs one real push"; exit 1; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

# ---------------------------------------------------------------------------
# Arms 1 and 2 — unit pins. No git, no fixture, no subprocess.
# ---------------------------------------------------------------------------
mkdir -p "$ROOT/unit/index"
cat > "$ROOT/unit/index/builds.json" <<'JSON'
{"version": 1, "builds": [{"id": "u1"}]}
JSON

python3 - "$PLUGIN_ROOT" "$ROOT/unit" <<'PY'
import importlib.machinery, importlib.util, json, os, pathlib, sys

plugin_root, state = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("dcli", str(plugin_root / "bin" / "deployit-cli"))
spec = importlib.util.spec_from_loader("dcli", loader)
mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)

# --- Arm 1: the hatch's return, pinned by EQUALITY ---------------------------
# Equality, not membership: a fix that adds a disclosure key while leaving
# published:True in place reds here, and so does one that drops `status`.
# `msg` and the `is not None` check stop an aborted mutation (which returns
# None) from satisfying this vacuously.
os.environ["DEPLOYIT_SKIP_GC_PUSH"] = "1"

def mutate(data):
    data["builds"] = []
    return "chore(deploy): unit fixture"

result = mod._commit_and_push_index(state, mutate)
assert result is not None, "hatch returned None for a mutation that produced a message"
expected = {"status": "local_only", "pr_url": None, "branch": None,
            "msg": "chore(deploy): unit fixture"}
assert result == expected, f"hatch return\n  got      {result}\n  expected {expected}"

# The hatch's whole documented purpose is the local write — pin that it happened.
written = json.loads((state / "index" / "builds.json").read_text())
assert written["builds"] == [], f"hatch did not apply the mutation locally: {written}"

# An aborted mutation still returns None, and that is a REACHABLE input to the
# gate predicate below: cmd_gc's mutate returns None when there is nothing to
# archive (deployit-cli:2517-2518), which test-gc.sh:67 drives with `gc --keep 10`.
assert mod._commit_and_push_index(state, lambda data: None) is None, \
    "an aborted mutation must still return None"

del os.environ["DEPLOYIT_SKIP_GC_PUSH"]

# --- Arm 2: the gate predicate, total over its input domain ------------------
# This is the condition authorising an irreversible rmtree. It is pinned per
# case rather than as one combined expression, because a combined assertion is
# satisfiable with an individual case silently wrong (AGE-43's per-array rule).
# `None` and an unrecognised status must BOTH fail closed to "do not delete" —
# neither B nor C pinned both, and the predicate is only total if it covers the
# whole `dict | None` union the function actually returns.
cases = [
    ({"status": "published",  "pr_url": None, "branch": None}, True,
     "a change on origin/main authorises deleting the local dirs"),
    ({"status": "local_only", "pr_url": None, "branch": None}, True,
     "the documented offline hatch still authorises deletion"),
    ({"status": "pending",    "pr_url": "u",  "branch": "b"},  False,
     "an open PR has NOT landed — the world still reads unchanged main"),
    (None,                                                     False,
     "an aborted mutation authorises nothing"),
    ({"status": "wat"},                                        False,
     "an unrecognised status must fail CLOSED, so a future enum member "
     "cannot silently authorise deletion"),
]
for value, want, why in cases:
    got = mod._index_change_is_effective(value)
    assert got is want, f"_index_change_is_effective({value!r}) == {got!r}, want {want!r} — {why}"

print("unit arms ok")
PY

# ---------------------------------------------------------------------------
# Arms 3, 4, 5 — the payload differential. Two IDENTICAL fixtures, one real
# push and one hatch, comparing what a caller can actually see.
# ---------------------------------------------------------------------------
BASE="https://demo.tail.ts.net/deployit"

# $1 = fixture dir. Identical in both halves, including the bare origin: the
# hatch half gets a working remote it simply never contacts, so "origin did not
# move" is a fact about the code and not about a missing repo.
seed() {
    local d="$1"
    mkdir -p "$d/remote.git" "$d/index" "$d/serve/b1"
    cat > "$d/config.toml" <<TOML
[server]
port = 8741
base_url = "$BASE"
[index]
repo = "https://example.invalid/repo.git"
[macos]
notarize = false
notary_profile = ""
TOML
    echo fake > "$d/serve/b1/App.ipa"
    python3 - "$d" "$BASE" <<'PY'
import json, pathlib, sys
d, base = pathlib.Path(sys.argv[1]), sys.argv[2]
build = {"id": "b1", "platform": "ios", "project": "App",
         "bundle_id": "io.mikey.App", "marketing_version": "1.0",
         "build_number": "1", "commit": "c0ffee",
         "timestamp": "2026-05-01T10:00:00-07:00", "origin_host": "x",
         "origin_base_url": base,
         "install": {"kind": "itms-services", "manifest_url": "x", "ipa_url": "y"},
         "size_bytes": 1, "archived": False, "notes": None}
(d / "index" / "builds.json").write_text(
    json.dumps({"version": 1, "builds": [build]}, indent=2) + "\n")
PY
    git -C "$d/remote.git" init --bare --quiet --initial-branch=main
    git -C "$d/index" init --quiet --initial-branch=main
    git -C "$d/index" config user.email "test@example.invalid"
    git -C "$d/index" config user.name "test"
    git -C "$d/index" remote add origin "$d/remote.git"
    git -C "$d/index" add builds.json
    git -C "$d/index" commit --quiet -m "seed"
    git -C "$d/index" push --quiet --set-upstream origin main
}

seed "$ROOT/pushed"
seed "$ROOT/hatch"

CLI=("python3" "$PLUGIN_ROOT/bin/deployit-cli" "--plugin-root" "$PLUGIN_ROOT")

pushed_out=$(DEPLOYIT_STATE_DIR="$ROOT/pushed" "${CLI[@]}" rm --build b1) \
    || { echo "FAIL: real rm exited $? — the CLI said: $pushed_out"; exit 1; }
hatch_out=$(DEPLOYIT_STATE_DIR="$ROOT/hatch" DEPLOYIT_SKIP_GC_PUSH=1 "${CLI[@]}" rm --build b1) \
    || { echo "FAIL: hatch rm exited $? — the CLI said: $hatch_out"; exit 1; }

pushed_tip=$(git -C "$ROOT/pushed/remote.git" log -1 --format=%s refs/heads/main)
hatch_tip=$(git -C "$ROOT/hatch/remote.git" log -1 --format=%s refs/heads/main)

printf '%s' "$pushed_out" > "$ROOT/pushed.json"
printf '%s' "$hatch_out"  > "$ROOT/hatch.json"

# Positive controls, asserted in bash before the differential so a fixture that
# quietly stopped working cannot make the comparison vacuous. An all-green
# fixture asserts nothing (AGE-43): BOTH runs must still delete the serve dir —
# that is the hatch's documented behaviour and this fix does not change it.
[[ ! -d "$ROOT/pushed/serve/b1" ]] || { echo "FAIL: real rm left the serve dir"; exit 1; }
[[ ! -d "$ROOT/hatch/serve/b1" ]]  || { echo "FAIL: the hatch must STILL delete the serve dir (documented behaviour)"; exit 1; }
[[ "$pushed_tip" != "seed" ]] || { echo "FAIL: the real rm did not move origin — fixture is broken, differential would be vacuous"; exit 1; }
[[ "$hatch_tip"  == "seed" ]] || { echo "FAIL: the hatch contacted origin (tip: $hatch_tip)"; exit 1; }

python3 - "$ROOT/pushed.json" "$ROOT/hatch.json" <<'PY'
import json, pathlib, sys

pushed = json.loads(pathlib.Path(sys.argv[1]).read_text())
hatch  = json.loads(pathlib.Path(sys.argv[2]).read_text())

# --- Arm 3: structural differential ------------------------------------------
# Exactly one key is added and none removed. This is the arm that kills the
# measured defect: pre-fix these two payloads were byte-identical.
added   = set(hatch) - set(pushed)
removed = set(pushed) - set(hatch)
assert added == {"index_local_only"}, (
    f"hatch payload must add exactly index_local_only; added={sorted(added)}\n"
    f"  pushed={pushed}\n  hatch={hatch}")
assert not removed, f"hatch payload must not drop keys; removed={sorted(removed)}"
assert hatch["index_local_only"] is True, f"index_local_only must be True, got {hatch['index_local_only']!r}"

# Every other shared key is byte-equal. `display` is compared separately in arm
# 5 because it is REQUIRED to differ — asserting equality on it here would
# contradict the disclosure this test exists to pin.
for key in sorted(set(pushed) & set(hatch) - {"display"}):
    assert pushed[key] == hatch[key], (
        f"shared key {key!r} diverged: pushed={pushed[key]!r} hatch={hatch[key]!r} — "
        "the hatch must change what is DISCLOSED, not what is done")

# --- Arm 4: index_pending absence --------------------------------------------
# Load-bearing and otherwise uncovered: `index_pending` is asserted in exactly
# one place in this entire suite (test-cli-rm-pr-fallback.sh:82) and only as
# PRESENT, so a fix mapping the hatch onto the pending branch — claiming a PR
# that does not exist — is today undetectable by the whole gate.
assert "index_pending" not in hatch, (
    "the hatch reported index_pending: it never opened a PR, and the pending "
    "branch must key off status == 'pending', never `not published`")
assert "index_pr_url" not in hatch, "the hatch reported an index_pr_url that does not exist"

# --- Arm 5: display ----------------------------------------------------------
# The measured lie was on the human-readable channel, so a mutation that
# reverts only the display line while keeping the JSON key must red. The first
# line — what was actually done — stays identical; the disclosure is additive.
assert pushed["display"].splitlines()[0] == hatch["display"].splitlines()[0], (
    "the first display line reports what was DONE and must not change:\n"
    f"  pushed={pushed['display'].splitlines()[0]!r}\n  hatch={hatch['display'].splitlines()[0]!r}")
assert "DEPLOYIT_SKIP_GC_PUSH" in hatch["display"], (
    f"the hatch display must name the variable that caused it; got {hatch['display']!r}")
assert "DEPLOYIT_SKIP_GC_PUSH" not in pushed["display"], (
    f"a real push must not mention the hatch; got {pushed['display']!r}")

print("differential arms ok")
PY

echo "PASS"
