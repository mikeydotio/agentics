#!/usr/bin/env bash
# rca-bisect.sh run: finds the planted culprit; refuses good_is_bad; a build-cmd
# failure at a probed commit maps to skip(125); and `git bisect reset` ALWAYS
# happens (a follow-up `git bisect log` fails).
source "$(dirname "$0")/lib.sh"

# ---- happy path: culprit == planted bad, and reset happened ------------------
REPO="$(make_fixture_repo)"
read -r GOOD BAD PLANTED <<<"$(plant_regression "$REPO")"
cd "$REPO"
mkdir -p .rca/reg
bash "$WORKTREE" create reg --ref "$BAD" >/dev/null
out=$(bash "$BISECT" run reg --good "$GOOD" --bad "$BAD" --test-cmd 'sh check.sh')
assert_json "$out" '.ok == true' "bisect ok"
assert_eq "$(jqf "$out" '.culprit_sha')" "$PLANTED" "culprit == planted bad commit"
assert_json "$out" '.culprit_subject | test("flip check")' "culprit subject matches"
assert_json "$out" '.steps >= 1' "steps recorded"
# reset happened: bisecting is over in the worktree.
WT="$REPO/.claude/worktrees/rca/reg/worktree"
git -C "$WT" bisect log >/dev/null 2>&1 && fail_test "git bisect was NOT reset after run"
bash "$WORKTREE" destroy reg >/dev/null 2>&1

# ---- good_is_bad: the good rev already fails ---------------------------------
REPO2="$(make_fixture_repo)"
read -r GOOD2 BAD2 _ <<<"$(plant_regression "$REPO2")"
cd "$REPO2"
mkdir -p .rca/gib
bash "$WORKTREE" create gib --ref "$BAD2" >/dev/null
# Use the BAD tip as --good — check.sh already exits 1 there.
out=$(bash "$BISECT" run gib --good "$BAD2" --bad "$BAD2" --test-cmd 'sh check.sh' || true)
assert_json "$out" '.ok == false and .error == "good_is_bad"' "good that fails → good_is_bad"
git -C "$REPO2/.claude/worktrees/rca/gib/worktree" bisect log >/dev/null 2>&1 && fail_test "bisect not reset after good_is_bad"
bash "$WORKTREE" destroy gib >/dev/null 2>&1

# ---- no worktree → no_worktree -----------------------------------------------
REPO3="$(make_fixture_repo)"
cd "$REPO3"
out=$(bash "$BISECT" run ghost --good HEAD --bad HEAD --test-cmd 'true' || true)
assert_json "$out" '.ok == false and .error == "no_worktree"' "missing worktree → no_worktree"

# ---- 125-skip: a build-cmd fails at a probed commit, bisect still resolves ---
# Linear history of 5 testable commits between good and bad. git bisect probes
# the MIDPOINT (c5) first; a BROKEN marker there makes --build-cmd fail so the
# step is SKIPPED. The culprit boundary (c6 good → c7 bad) sits away from the
# skip and is fully testable, so the culprit is still uniquely pinned.
REPO4="$(make_fixture_repo)"
(
  cd "$REPO4"
  printf '#!/bin/sh\nexit 0\n' > check.sh; chmod +x check.sh
  echo a > f.txt; _git add -A; _git commit -qm "c1 baseline good"
  echo b >> f.txt; _git add -A; _git commit -qm "c2 good"
) >/dev/null 2>&1
G4=$(_git -C "$REPO4" rev-parse HEAD)                 # good = c2
(
  cd "$REPO4"
  echo c >> f.txt; _git add -A; _git commit -qm "c3 good"
  echo d >> f.txt; _git add -A; _git commit -qm "c4 good"
  touch BROKEN; echo e >> f.txt; _git add -A; _git commit -qm "c5 build-broken (midpoint → skip)"
  rm -f BROKEN; echo f >> f.txt; _git add -A; _git commit -qm "c6 good, BROKEN gone"
  printf '#!/bin/sh\nexit 1\n' > check.sh; echo g >> f.txt; _git add -A; _git commit -qm "c7 CULPRIT flip"
) >/dev/null 2>&1
C7=$(_git -C "$REPO4" rev-parse HEAD)                 # culprit = c7
(
  cd "$REPO4"
  echo h >> f.txt; _git add -A; _git commit -qm "c8 after (still bad)"
) >/dev/null 2>&1
B4=$(_git -C "$REPO4" rev-parse HEAD)                 # bad = c8
cd "$REPO4"
mkdir -p .rca/skip
bash "$WORKTREE" create skip --ref "$B4" >/dev/null
# --build-cmd fails (exit 1) whenever the BROKEN marker is present at that commit.
out=$(bash "$BISECT" run skip --good "$G4" --bad "$B4" \
        --build-cmd 'test ! -f BROKEN' --test-cmd 'sh check.sh')
assert_json "$out" '.ok == true' "bisect-with-skip still resolves"
assert_eq "$(jqf "$out" '.culprit_sha')" "$C7" "culprit is the flip commit despite a skip"
assert_json "$out" '.skipped >= 1' "at least one commit was skipped"
git -C "$REPO4/.claude/worktrees/rca/skip/worktree" bisect log >/dev/null 2>&1 && fail_test "bisect not reset after skip run"
bash "$WORKTREE" destroy skip >/dev/null 2>&1

finish
