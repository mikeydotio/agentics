#!/usr/bin/env bash
# When a conflict is resolved to exactly the base's tree, the replayed commit
# becomes empty. continue must SURFACE that (not silently drop it); continue
# --skip then finishes.
source "$(dirname "$0")/lib.sh"
PR=7
CO="$(reconcile_fixture conflict)"

out=$(rp "$CO" start "$PR")
assert_eq "$(jqf "$out" '.status')" "conflicts" "start → conflicts"
WT="$(wt_path "$CO" "$PR")"

# Resolve by taking MAIN's side exactly → the PR commit adds nothing.
printf 'MAIN value\nkeep-a\n' > "$WT/file.txt"
git -C "$WT" add file.txt

out=$(rp "$CO" continue "$PR")
assert_eq "$(jqf "$out" '.ok')" "true" "continue → ok:true"
assert_eq "$(jqf "$out" '.status')" "empty_after_resolution" "resolve-to-base → empty_after_resolution"
assert_contains "$(jqf "$out" '.display')" "--skip" "empty → suggests --skip"

# --skip drops the now-empty PR commit and finishes.
out=$(rp "$CO" continue "$PR" --skip)
assert_eq "$(jqf "$out" '.ok')" "true" "continue --skip → ok:true"
assert_eq "$(jqf "$out" '.status')" "clean" "continue --skip → clean"

finish
