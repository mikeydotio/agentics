#!/usr/bin/env bash
# rca-forensics.sh: pickaxe finds the planted term, blame attributes a line
# range, intro candidates include the introducing commit (with parent), and
# timeline is chronological (oldest first).
source "$(dirname "$0")/lib.sh"

REPO="$(make_fixture_repo)"
cd "$REPO"
printf 'alpha\nbeta\ngamma\n' > f.txt; _git add -A; _git commit -qm "c1 add f.txt"
C1=$(_git rev-parse HEAD)
printf 'alpha\nBEACON_TOKEN\ngamma\ndelta\n' > f.txt; echo x > g.txt; _git add -A; _git commit -qm "c2 introduce BEACON_TOKEN"
C2=$(_git rev-parse HEAD)
printf 'alpha\nBEACON_TOKEN\ngamma\ndelta\nepsilon\n' > f.txt; _git add -A; _git commit -qm "c3 extend"
C3=$(_git rev-parse HEAD)

# ---- pickaxe: finds the commit that introduced the term ----------------------
out=$(bash "$FORENSICS" pickaxe --term BEACON_TOKEN)
assert_json "$out" '.ok == true and .mode == "pickaxe"' "pickaxe ok"
assert_json "$out" '[.commits[].sha] | index("'"$C2"'") != null' "pickaxe includes the introducing commit"
assert_json "$out" '.commits[0].files_touched | index("f.txt") != null' "pickaxe reports files_touched"

# --regex form works too
out=$(bash "$FORENSICS" pickaxe --term 'BEACON_[A-Z]+' --regex)
assert_json "$out" '[.commits[].sha] | index("'"$C2"'") != null' "pickaxe --regex finds it"

# ---- blame: attributes line 2 (BEACON_TOKEN) to c2, with a line range --------
out=$(bash "$FORENSICS" blame --file f.txt --lines 2,4)
assert_json "$out" '.ok == true and .mode == "blame"' "blame ok"
assert_json "$out" '[.commits[].sha] | index("'"$C2"'") != null' "blame attributes lines to c2"
assert_json "$out" '.commits[] | select(.sha=="'"$C2"'") | .lines | length > 0' "blame reports implicated line range"

# blame at an explicit rev
out=$(bash "$FORENSICS" blame --file f.txt --lines 1,1 --rev "$C1")
assert_json "$out" '[.commits[].sha] | index("'"$C1"'") != null' "blame --rev attributes to c1"

# ---- intro: candidates include the introducing commit, newest first, w/ parent
out=$(bash "$FORENSICS" intro --file f.txt --lines 2,2)
assert_json "$out" '.ok == true and .mode == "intro"' "intro ok"
assert_json "$out" '[.candidates[].sha] | index("'"$C2"'") != null' "intro candidates include c2"
assert_json "$out" '.candidates[] | select(.sha=="'"$C2"'") | .parent == "'"$C1"'"' "intro reports the parent for context"

# ---- timeline: chronological (oldest first) ----------------------------------
out=$(bash "$FORENSICS" timeline --paths f.txt)
assert_json "$out" '.ok == true and .mode == "timeline"' "timeline ok"
assert_eq "$(jqf "$out" '.commits[0].sha')" "$C1" "timeline starts oldest (c1)"
assert_eq "$(jqf "$out" '.commits[-1].sha')" "$C3" "timeline ends newest (c3)"

# timeline --limit caps the count
out=$(bash "$FORENSICS" timeline --paths f.txt --limit 1)
assert_json "$out" '(.commits|length) == 1' "timeline --limit caps output"

finish
