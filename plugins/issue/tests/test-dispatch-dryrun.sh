#!/usr/bin/env bash
# dispatch --dry-run runs the read-only checks for real, then emits the exact
# ordered tmux commands it WOULD run (with <n>/prompt substituted) and opens no
# window. Also covers closed-issue gating and the not-found path.
source "$(dirname "$0")/lib.sh"

repo=$(mk_repo)

# happy path: open issue, default launch/prompt
out=$(cd "$repo" && ISSUE_DRY_RUN=1 bash "$SCRIPT" dispatch 42 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "dryrun ok:true"
assert_eq "$(jqf "$out" .dry_run)" "true" "dryrun flag"
assert_eq "$(jqf "$out" .issue)" "42" "dryrun issue number"
cmds="$(jqf "$out" '.commands | join("\n")')"
assert_contains "$cmds" "claude -w rep-42 --permission-mode plan" "default launch names worktree like the window (<repo-prefix>-<n>), plan mode via flag"
assert_contains "$cmds" "issue #42 in this repo" "default prompt substituted"
# Plan mode is now the launch flag, not keystrokes: no Shift+Tab, and the prompt
# must NOT start with /plan (that routes to a /plan skill, e.g. forge's planner).
assert_not_contains "$cmds" "BTab" "no shift-tab keystrokes (plan mode via flag)"
assert_not_contains "$cmds" "/plan" "prompt no longer routes through the /plan skill"
# Window is named "<repo-prefix>-<n>": origin fake/repo -> "rep-42".
assert_eq "$(jqf "$out" .window_name)" "rep-42" "window_name is <repo-prefix>-<n>"
assert_contains "$cmds" "-n rep-42" "new-window carries the -n <name> flag"
# The core of issue #52: the worktree (claude -w <name>) arg IS the window name.
assert_contains "$cmds" "claude -w $(jqf "$out" .window_name)" "worktree arg equals window_name"
# The helper uses git's resolved toplevel (on macOS /tmp -> /private/tmp), which
# it also reports as .dir — assert the new-window targets exactly that.
reported_dir="$(jqf "$out" .dir)"
assert_contains "$cmds" "new-window -d -c $reported_dir" "new-window targets reported repo root (detached)"
# Default is DETACHED (-d) so the caller's focus stays on the current window (#54).
assert_contains "$cmds" "new-window -d" "default opens the window detached (keeps focus)"

# issue #50: dispatch marks the issue in-progress. The dry-run lists the two gh
# writes it WOULD run (create-if-missing label, then add it to the issue).
assert_eq "$(jqf "$out" .label)" "in-progress" "default label is in-progress"
assert_contains "$cmds" "gh label create in-progress --repo fake/repo" "dry-run lists label create"
assert_contains "$cmds" "gh issue edit 42 --repo fake/repo --add-label in-progress" "dry-run lists add-label to issue"
assert_contains "$(jqf "$out" .display)" "mark the issue in-progress" "display mentions the label"
# issue #50: the enriched handoff prompt carries the GitHub self-reporting
# contract for the child session (plan comment, closing keyword, PR link).
assert_contains "$cmds" "Closes #42" "prompt words PRs to close the issue"
assert_contains "$cmds" "post the full plan as a Markdown comment on issue #42" "prompt asks child to comment the plan"
assert_contains "$cmds" "comment a link to each PR on issue #42" "prompt asks child to comment PR links"

# issue #55: the dry-run previews the worktree gitignore decision. A fresh mk_repo
# has no .gitignore, so it reports "would-add" — and the write is NOT a tmux
# command, so it must not appear in the (asserted-verbatim) commands array.
assert_eq "$(jqf "$out" .gitignore)" "would-add" "fresh repo previews gitignore would-add"
assert_eq "$(jqf "$out" '[.commands[]|select(test("gitignore"))]|length')" "0" "gitignore write is not a tmux command"

# foreground opt-out (#54): ISSUE_FOREGROUND=1 drops -d so focus follows the window.
# Runs after the default-run assertions above, which rely on this run's $out/$cmds.
out=$(cd "$repo" && ISSUE_DRY_RUN=1 ISSUE_FOREGROUND=1 bash "$SCRIPT" dispatch 42 2>&1)
fg_cmds="$(jqf "$out" '.commands | join("\n")')"
assert_not_contains "$fg_cmds" "new-window -d" "foreground opt-out drops -d (focus follows)"
assert_contains "$fg_cmds" "new-window -c $reported_dir" "foreground opt-out uses plain new-window"

# custom launch/prompt templates substitute <n>
out=$(cd "$repo" && ISSUE_DRY_RUN=1 \
      ISSUE_LAUNCH_CMD="claude -w feature-<n>" \
      ISSUE_PROMPT="fix <n> now" \
      bash "$SCRIPT" dispatch 9 2>&1)
cmds="$(jqf "$out" '.commands | join("\n")')"
assert_contains "$cmds" "claude -w feature-9" "custom launch substituted"
assert_contains "$cmds" "fix 9 now" "custom prompt substituted"

# custom window name override substitutes <n>
out=$(cd "$repo" && ISSUE_DRY_RUN=1 \
      ISSUE_WINDOW_NAME="wip-<n>" \
      bash "$SCRIPT" dispatch 7 2>&1)
assert_eq "$(jqf "$out" .window_name)" "wip-7" "custom window name override"
ovr_cmds="$(jqf "$out" '.commands | join("\n")')"
assert_contains "$ovr_cmds" "-n wip-7" "custom window name in new-window"
# The window-name override flows into the default launch's <name>, renaming the
# worktree too — window and worktree stay in sync.
assert_contains "$ovr_cmds" "claude -w wip-7 --permission-mode plan" "window-name override renames the worktree too"

# closed issue -> ok:false (dry-run still validates state)
out=$(cd "$repo" && ISSUE_DRY_RUN=1 FAKE_GH_STATE=CLOSED bash "$SCRIPT" dispatch 42 2>&1)
assert_eq "$(jqf "$out" .ok)" "false" "closed ok:false"
assert_contains "$(jqf "$out" .display)" "closed" "closed display"

# closed + allow-closed override -> ok:true
out=$(cd "$repo" && ISSUE_DRY_RUN=1 FAKE_GH_STATE=CLOSED ISSUE_ALLOW_CLOSED=1 \
      bash "$SCRIPT" dispatch 42 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "allow-closed ok:true"

# nonexistent issue -> ok:false
out=$(cd "$repo" && ISSUE_DRY_RUN=1 FAKE_GH_VIEW_FAIL=1 bash "$SCRIPT" dispatch 999 2>&1)
assert_eq "$(jqf "$out" .ok)" "false" "nonexistent ok:false"
assert_contains "$(jqf "$out" .display)" "not found" "nonexistent display"

# issue #50: labeling opts out with an explicit empty ISSUE_LABEL (uses
# `-` not `:-`, so "" disables while unset defaults). No gh label commands appear.
out=$(cd "$repo" && ISSUE_DRY_RUN=1 ISSUE_LABEL="" bash "$SCRIPT" dispatch 42 2>&1)
assert_eq "$(jqf "$out" .label)" "" "empty label field when disabled"
assert_eq "$(jqf "$out" '[.commands[]|select(startswith("gh"))]|length')" "0" "no gh commands when label disabled"
assert_not_contains "$(jqf "$out" .display)" "mark the issue" "display omits label clause when disabled"

# issue #50: a custom label name flows through to both gh writes.
out=$(cd "$repo" && ISSUE_DRY_RUN=1 ISSUE_LABEL="wip" bash "$SCRIPT" dispatch 42 2>&1)
cmds="$(jqf "$out" '.commands | join("\n")')"
assert_eq "$(jqf "$out" .label)" "wip" "custom label field"
assert_contains "$cmds" "gh label create wip --repo fake/repo" "custom label in create"
assert_contains "$cmds" "--add-label wip" "custom label in add-label"

# issue #55: when the worktree dir is already ignored, the dry-run reports
# "already-ignored" and (in the real path) would write nothing. Use a fresh repo
# per case so a stray .gitignore can't leak between assertions.
ig_exact=$(mk_repo)
printf 'node_modules/\n.claude/worktrees/\n' > "$ig_exact/.gitignore"
out=$(cd "$ig_exact" && ISSUE_DRY_RUN=1 bash "$SCRIPT" dispatch 42 2>&1)
assert_eq "$(jqf "$out" .gitignore)" "already-ignored" "exact .claude/worktrees/ rule -> already-ignored"

ig_broad=$(mk_repo)
printf '.claude/\n' > "$ig_broad/.gitignore"
out=$(cd "$ig_broad" && ISSUE_DRY_RUN=1 bash "$SCRIPT" dispatch 42 2>&1)
assert_eq "$(jqf "$out" .gitignore)" "already-ignored" "broad .claude/ rule also counts as already-ignored"

finish
