#!/usr/bin/env bash
# dispatch --dry-run runs the read-only checks for real, then emits the exact
# ordered tmux commands it WOULD run (with <n>/prompt substituted) and opens no
# window. Also covers closed-issue gating and the not-found path.
source "$(dirname "$0")/lib.sh"

repo=$(mk_repo)

# happy path: open issue, default launch/prompt
out=$(cd "$repo" && HANDLE_ISSUE_DRY_RUN=1 bash "$SCRIPT" dispatch 42 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "dryrun ok:true"
assert_eq "$(jqf "$out" .dry_run)" "true" "dryrun flag"
assert_eq "$(jqf "$out" .issue)" "42" "dryrun issue number"
cmds="$(jqf "$out" '.commands | join("\n")')"
assert_contains "$cmds" "claude -w 42 --permission-mode plan" "default launch forces plan mode via flag"
assert_contains "$cmds" "issue #42 in this repo" "default prompt substituted"
# Plan mode is now the launch flag, not keystrokes: no Shift+Tab, and the prompt
# must NOT start with /plan (that routes to a /plan skill, e.g. forge's planner).
assert_not_contains "$cmds" "BTab" "no shift-tab keystrokes (plan mode via flag)"
assert_not_contains "$cmds" "/plan" "prompt no longer routes through the /plan skill"
# Window is named "<repo-prefix>-<n>": origin fake/repo -> "rep-42".
assert_eq "$(jqf "$out" .window_name)" "rep-42" "window_name is <repo-prefix>-<n>"
assert_contains "$cmds" "-n rep-42" "new-window carries the -n <name> flag"
# The helper uses git's resolved toplevel (on macOS /tmp -> /private/tmp), which
# it also reports as .dir — assert the new-window targets exactly that.
reported_dir="$(jqf "$out" .dir)"
assert_contains "$cmds" "new-window -d -c $reported_dir" "new-window targets reported repo root (detached)"
# Default is DETACHED (-d) so the caller's focus stays on the current window (#54).
assert_contains "$cmds" "new-window -d" "default opens the window detached (keeps focus)"

# foreground opt-out: HANDLE_ISSUE_FOREGROUND=1 drops -d so focus follows the window.
out=$(cd "$repo" && HANDLE_ISSUE_DRY_RUN=1 HANDLE_ISSUE_FOREGROUND=1 bash "$SCRIPT" dispatch 42 2>&1)
fg_cmds="$(jqf "$out" '.commands | join("\n")')"
assert_not_contains "$fg_cmds" "new-window -d" "foreground opt-out drops -d (focus follows)"
assert_contains "$fg_cmds" "new-window -c $reported_dir" "foreground opt-out uses plain new-window"

# custom launch/prompt templates substitute <n>
out=$(cd "$repo" && HANDLE_ISSUE_DRY_RUN=1 \
      HANDLE_ISSUE_LAUNCH_CMD="claude -w feature-<n>" \
      HANDLE_ISSUE_PROMPT="fix <n> now" \
      bash "$SCRIPT" dispatch 9 2>&1)
cmds="$(jqf "$out" '.commands | join("\n")')"
assert_contains "$cmds" "claude -w feature-9" "custom launch substituted"
assert_contains "$cmds" "fix 9 now" "custom prompt substituted"

# custom window name override substitutes <n>
out=$(cd "$repo" && HANDLE_ISSUE_DRY_RUN=1 \
      HANDLE_ISSUE_WINDOW_NAME="wip-<n>" \
      bash "$SCRIPT" dispatch 7 2>&1)
assert_eq "$(jqf "$out" .window_name)" "wip-7" "custom window name override"
assert_contains "$(jqf "$out" '.commands | join("\n")')" "-n wip-7" "custom window name in new-window"

# closed issue -> ok:false (dry-run still validates state)
out=$(cd "$repo" && HANDLE_ISSUE_DRY_RUN=1 FAKE_GH_STATE=CLOSED bash "$SCRIPT" dispatch 42 2>&1)
assert_eq "$(jqf "$out" .ok)" "false" "closed ok:false"
assert_contains "$(jqf "$out" .display)" "closed" "closed display"

# closed + allow-closed override -> ok:true
out=$(cd "$repo" && HANDLE_ISSUE_DRY_RUN=1 FAKE_GH_STATE=CLOSED HANDLE_ISSUE_ALLOW_CLOSED=1 \
      bash "$SCRIPT" dispatch 42 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "allow-closed ok:true"

# nonexistent issue -> ok:false
out=$(cd "$repo" && HANDLE_ISSUE_DRY_RUN=1 FAKE_GH_VIEW_FAIL=1 bash "$SCRIPT" dispatch 999 2>&1)
assert_eq "$(jqf "$out" .ok)" "false" "nonexistent ok:false"
assert_contains "$(jqf "$out" .display)" "not found" "nonexistent display"

finish
