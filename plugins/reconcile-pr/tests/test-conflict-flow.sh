#!/usr/bin/env bash
# The conflict happy path: start → conflicts (with NON-INVERTED base/pr labeling)
# → resolve preserving both → continue → clean. Also proves conflicts.log logging.
source "$(dirname "$0")/lib.sh"
PR=7
CO="$(reconcile_fixture conflict)"

out=$(rp "$CO" start "$PR")
assert_eq "$(jqf "$out" '.ok')" "true" "start → ok:true"
assert_eq "$(jqf "$out" '.status')" "conflicts" "start → status conflicts"
assert_eq "$(jqf "$out" '.conflicted_files[0].rel')" "file.txt" "conflict on file.txt"
assert_eq "$(jqf "$out" '.conflicted_files[0].conflict_type')" "both_modified" "type both_modified"
assert_contains "$(jqf "$out" '.labels.base_side')" "main" "base_side names the base branch"
assert_contains "$(jqf "$out" '.labels.pr_side')" "PR" "pr_side names the PR"

WT="$(wt_path "$CO" "$PR")"

# NON-INVERSION proof: index stage 2 (base/ours) is main's value; stage 3
# (pr/theirs) is the PR's value. If these were swapped the LLM would resolve
# backwards — this is the single most important correctness assertion.
base_blob=$(git -C "$WT" show ":2:file.txt" 2>/dev/null)
pr_blob=$(git -C "$WT" show ":3:file.txt" 2>/dev/null)
assert_contains "$base_blob" "MAIN value" "stage 2 == base (main) value"
assert_contains "$pr_blob"   "PR value"   "stage 3 == pr value"

# conflicts.log recorded the stop.
assert_contains "$(cat "$CO/.claude/worktrees/reconcile-pr/$PR/conflicts.log" 2>/dev/null)" "file.txt" "conflicts.log records file.txt"

# Resolve preserving BOTH sides, stage, continue → clean.
printf 'MAIN value\nPR value\nkeep-a\n' > "$WT/file.txt"
git -C "$WT" add file.txt
out=$(rp "$CO" continue "$PR")
assert_eq "$(jqf "$out" '.ok')" "true" "continue → ok:true"
assert_eq "$(jqf "$out" '.status')" "clean" "continue → status clean"
# The merged content survives into the rebased tree.
assert_contains "$(cat "$WT/file.txt" 2>/dev/null)" "PR value" "resolved tree kept PR value"
assert_contains "$(cat "$WT/file.txt" 2>/dev/null)" "MAIN value" "resolved tree kept MAIN value"

# continue when not mid-rebase → ok:false.
out=$(rp "$CO" continue "$PR")
assert_eq "$(jqf "$out" '.ok')" "false" "continue after clean → ok:false"

finish
