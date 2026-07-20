#!/usr/bin/env bash
# Regression for #108: subcommands must anchor to the MAIN worktree root, not the
# ambient CWD. When CWD is INSIDE the reconcile worktree — where the model edits and
# stages conflicts, per SKILL.md — status/continue/test must still find the active
# state. Pre-fix, `--show-toplevel` returned the worktree root, so state_dir pointed
# at a nonexistent nested path (phase:"idle" / "no active reconcile"). Fixed by
# anchoring REPO_ROOT via `--git-common-dir` instead.
source "$(dirname "$0")/lib.sh"
PR=7
CO="$(reconcile_fixture conflict)"

out=$(rp "$CO" start "$PR")
assert_eq "$(jqf "$out" '.ok')"     "true"      "start → ok:true"
assert_eq "$(jqf "$out" '.status')" "conflicts" "start → status conflicts"

WT="$(wt_path "$CO" "$PR")"

# Read path FROM INSIDE the worktree → mid_rebase (was idle pre-fix).
out=$(rp "$WT" status "$PR")
assert_eq "$(jqf "$out" '.ok')"    "true"       "status(in-wt) → ok:true"
assert_eq "$(jqf "$out" '.phase')" "mid_rebase" "status(in-wt) → phase mid_rebase, not idle"

# Resolve preserving BOTH sides, stage in the worktree, then continue FROM INSIDE
# the worktree → clean (was ok:false "no active reconcile" pre-fix).
printf 'MAIN value\nPR value\nkeep-a\n' > "$WT/file.txt"
git -C "$WT" add file.txt
out=$(rp "$WT" continue "$PR")
assert_eq "$(jqf "$out" '.ok')"     "true"  "continue(in-wt) → ok:true"
assert_eq "$(jqf "$out" '.status')" "clean" "continue(in-wt) → status clean"

# Read path stays anchored after continue.
out=$(rp "$WT" status "$PR")
assert_eq "$(jqf "$out" '.phase')" "clean" "status(in-wt) after continue → phase clean"

# Write path also anchors (meta.json lives under the MAIN root, not the worktree):
# test FROM INSIDE the worktree records last_test there too.
out=$(rp "$WT" test "$PR")
assert_eq "$(jqf "$out" '.ok')"     "true"            "test(in-wt) → ok:true"
assert_eq "$(jqf "$out" '.status')" "no_test_command" "test(in-wt) → no_test_command"

finish
