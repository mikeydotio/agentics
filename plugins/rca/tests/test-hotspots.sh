#!/usr/bin/env bash
# rca-hotspots.sh: churn/commit counts on a skewed history, a co-change coupling
# (a pair that changes together >=3 times), and the --since window filter.
source "$(dirname "$0")/lib.sh"

REPO="$(make_fixture_repo)"
cd "$REPO"

# hot.txt churns a lot (5 commits); cold.txt changes once.
for i in 1 2 3 4 5; do echo "line $i" >> hot.txt; _git add -A; _git commit -qm "hot $i"; done >/dev/null 2>&1
echo "once" >> cold.txt; _git add -A; _git commit -qm "cold once" >/dev/null 2>&1

out=$(bash "$HOTSPOTS" --since "10.years" --top 10)
assert_json "$out" '.ok == true' "hotspots ok"
assert_eq "$(jqf "$out" '.hotspots[0].file')" "hot.txt" "hot.txt is the top hotspot"
assert_json "$out" '.hotspots[] | select(.file=="hot.txt") | .commits == 5' "hot.txt commit count = 5"
assert_json "$out" '.hotspots[] | select(.file=="hot.txt") | .churn >= 5' "hot.txt churn accumulated"
assert_json "$out" '.hotspots[] | select(.file=="hot.txt") | .loc == 5' "hot.txt loc via wc -l"
assert_json "$out" '.hotspots[] | select(.file=="hot.txt") | .score > 0' "hot.txt has a positive score"
# score ordering: hot.txt outscores cold.txt
assert_json "$out" '(.hotspots[] | select(.file=="hot.txt") | .score) > (.hotspots[] | select(.file=="cold.txt") | .score)' \
  "hot outscores cold"

# ---- co-change coupling: a.txt & b.txt change together 3 times ---------------
REPO2="$(make_fixture_repo)"
cd "$REPO2"
for i in 1 2 3; do echo "$i" >> a.txt; echo "$i" >> b.txt; _git add -A; _git commit -qm "pair $i"; done >/dev/null 2>&1
echo solo >> c.txt; _git add -A; _git commit -qm "solo c" >/dev/null 2>&1
out=$(bash "$HOTSPOTS" --since "10.years")
assert_json "$out" '.couplings | length >= 1' "a coupling was detected"
assert_json "$out" '.couplings[] | select((.a=="a.txt" and .b=="b.txt") or (.a=="b.txt" and .b=="a.txt")) | .co_changes == 3' \
  "a.txt/b.txt co-changed 3 times"
assert_json "$out" '.couplings[] | select(.a=="a.txt" or .b=="a.txt") | .confidence == 1' \
  "confidence = co_changes / min(commits_a,commits_b) = 1.0"
# c.txt changed alone → never coupled
assert_json "$out" '[.couplings[] | select(.a=="c.txt" or .b=="c.txt")] | length == 0' "solo file has no coupling"

# ---- --since window excludes old commits -------------------------------------
REPO3="$(make_fixture_repo)"
cd "$REPO3"
# An "old" commit dated well in the past; a recent one now.
GIT_AUTHOR_DATE="2000-01-01T00:00:00" GIT_COMMITTER_DATE="2000-01-01T00:00:00" \
  bash -c 'echo old >> ancient.txt; git -c user.email=t@t -c user.name=test add -A; git -c user.email=t@t -c user.name=test commit -qm "ancient"' >/dev/null 2>&1
echo new >> recent.txt; _git add -A; _git commit -qm "recent" >/dev/null 2>&1
out=$(bash "$HOTSPOTS" --since "1.year")
assert_json "$out" '[.hotspots[].file] | index("recent.txt") != null' "--since keeps recent.txt"
assert_json "$out" '[.hotspots[].file] | index("ancient.txt") == null' "--since excludes the 2000 commit"

finish
