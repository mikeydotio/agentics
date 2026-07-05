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
assert_contains "$cmds" "claude -w 42" "default launch substituted"
assert_contains "$cmds" "issue #42 in this repo" "default prompt substituted"
assert_contains "$cmds" "BTab BTab" "shift-tab keys present"
# The helper uses git's resolved toplevel (on macOS /tmp -> /private/tmp), which
# it also reports as .dir — assert the new-window targets exactly that.
reported_dir="$(jqf "$out" .dir)"
assert_contains "$cmds" "new-window -c $reported_dir" "new-window targets reported repo root"

# custom launch/prompt templates substitute <n>
out=$(cd "$repo" && HANDLE_ISSUE_DRY_RUN=1 \
      HANDLE_ISSUE_LAUNCH_CMD="claude -w feature-<n>" \
      HANDLE_ISSUE_PROMPT="fix <n> now" \
      bash "$SCRIPT" dispatch 9 2>&1)
cmds="$(jqf "$out" '.commands | join("\n")')"
assert_contains "$cmds" "claude -w feature-9" "custom launch substituted"
assert_contains "$cmds" "fix 9 now" "custom prompt substituted"

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
