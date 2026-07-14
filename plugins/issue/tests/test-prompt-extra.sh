#!/usr/bin/env bash
# ISSUE_PROMPT_EXTRA (daemon-caller seam): when set, dispatch appends its value
# to the rendered handoff prompt — verbatim, AFTER <n>/<name> templating of the
# base prompt (the extra itself is never templated), joined by a single space.
# The dry-run payload surfaces the final prompt as a top-level .prompt field
# (also embedded in commands[3], the load-buffer delivery line — the two must
# stay in sync; #87 moved delivery from send-keys -l to a bracketed
# printf | tmux load-buffer paste). Unset/empty, the prompt is byte-identical
# to today's PROMPT_TPL rendering.
source "$(dirname "$0")/lib.sh"

# --- Case 1: default (var unset) — prompt unchanged, surfaced as .prompt ------
repo=$(mk_repo)
out=$(cd "$repo" && ISSUE_DRY_RUN=1 bash "$SCRIPT" dispatch 7 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "default dry-run: ok:true"
base_prompt="$(jqf "$out" .prompt)"
assert_eq "$(jqf "$out" '.prompt | startswith("Investigate and plan")')" "true" \
  "default: .prompt starts with the base prompt text"
assert_not_contains "$base_prompt" "council-vote" \
  "default: .prompt carries no extra clause"
# The base prompt's own tail is the worktree directive — locks that the extra
# (when present) lands strictly AFTER today's full rendering, not inside it.
assert_eq "$(jqf "$out" '.prompt | endswith("not here.")')" "true" \
  "default: .prompt ends with the base prompt tail"
# .prompt and the delivery command must agree byte-for-byte.
assert_eq "$(jqf "$out" '.commands[3] == ("printf %s " + .prompt + " | tmux load-buffer -b issue-7 -")')" \
  "true" "default: commands[3] embeds exactly .prompt"

# --- Case 2: extra appended verbatim with a single space separator ------------
out=$(cd "$repo" && ISSUE_DRY_RUN=1 ISSUE_PROMPT_EXTRA="Use council-vote." \
      bash "$SCRIPT" dispatch 7 2>&1)
assert_eq "$(jqf "$out" .ok)" "true" "extra dry-run: ok:true"
assert_eq "$(jqf "$out" '.prompt | endswith("Use council-vote.")')" "true" \
  "extra: .prompt ends with the extra clause"
assert_eq "$(jqf "$out" '.prompt | startswith("Investigate and plan")')" "true" \
  "extra: base prompt text still precedes the extra"
# Exact-equality against Case 1's baseline proves BOTH the verbatim append and
# the single-space separator in one assertion.
assert_eq "$(jqf "$out" .prompt)" "$base_prompt Use council-vote." \
  "extra: .prompt is base + single space + extra, byte-exact"
# The delivery command carries the appended prompt too (what tmux actually
# pastes): the clause sits at the prompt's tail, immediately before the pipe.
assert_eq "$(jqf "$out" '.commands[3] | contains("Use council-vote. | tmux load-buffer")')" "true" \
  "extra: commands[3] carries the appended clause"

# --- Case 3: the extra is NEVER templated — <n>/<name> stay literal -----------
out=$(cd "$repo" && ISSUE_DRY_RUN=1 ISSUE_PROMPT_EXTRA='Report on <n> as <name>.' \
      bash "$SCRIPT" dispatch 7 2>&1)
assert_eq "$(jqf "$out" '.prompt | endswith("Report on <n> as <name>.")')" "true" \
  "no-templating: <n>/<name> in the extra survive literally"

finish
