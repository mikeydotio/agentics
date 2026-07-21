#!/usr/bin/env bash
# story.sh — deterministic helper for storyhook-based dispatch (conductor's
# storyhook-dispatch migration, Phase 1 Task A2 — see
# docs/plans/2026-07-20-storyhook-dispatch-migration.md in the conductor
# repo). Sibling to plugins/issue/bin/issue.sh: same tmux/worktree mechanics,
# but claims and reports against storyhook `story` stories instead of GitHub
# issues.
#
# HARD RUNTIME DEPENDENCY (deliberate, not accidental): this script sources
# plugins/issue/lib/session.sh, which lives inside the SEPARATE `issue`
# plugin. `issue` and `storywork` are independently `/plugin install`-able
# marketplace entries, and the plugin.json manifest schema has no
# dependency-declaration field — a user who installs `storywork@agentics`
# WITHOUT also installing `issue` gets a story.sh that fails at the `source`
# line below. This is a known, accepted limitation (not a bug to silently
# route around): session.sh's own header says it is meant to stay at that
# path and be sourced in place by exactly this kind of sibling actuator, and
# conductor's own usage is unaffected (its `story_sh`/`issue_sh` config point
# at a full local agentics checkout by path, never a marketplace subset).
#
# Two subcommands, each emitting exactly ONE JSON object on stdout with an
# `ok` boolean and a human-readable `display`, mirroring issue.sh's contract
# exactly (conductor's dispatch.py parses `ok`/`display`/`window_name`/`pane`
# and must keep working unmodified across the migration):
#
#   dispatch <id>   Fetch origin/<default> (best-effort), create a NEW git
#                    worktree at .claude/worktrees/<name> on branch
#                    worktree-<name>, open a new tmux window named
#                    "<repo-prefix>-<id>" (e.g. "con-SH-12") rooted in that
#                    worktree, gate on claude becoming ready, then type +
#                    submit the prompt. Emits the SAME {ok, window_name,
#                    pane} shape issue.sh dispatch does today.
#
#                    CLAIM SEMANTICS — the load-bearing difference from
#                    issue.sh: storyhook's `state` IS the claim marker (there
#                    is no separate assignee/label concept), and `story move`
#                    has NO self-transition guard of its own — moving a story
#                    to the state it is already in still appends a new
#                    StoryStateChanged event and fires the state_change hook.
#                    So unlike issue.sh's best-effort, TRAILING label apply,
#                    the claim here is a HARD PRECONDITION, checked BEFORE any
#                    worktree/window side effect:
#                      1. Read current state via `story show <id> --json`.
#                      2. If it already equals "in-progress" (a caller —
#                         conductor's storyx.claim_ready — pre-claimed it),
#                         skip the move ENTIRELY: no redundant transition, no
#                         spurious hook fire.
#                      3. Otherwise attempt `story move <id> in-progress
#                         --if-state <state>`. A `conflict` result (another
#                         dispatch won the race between our read and our
#                         move) REFUSES before any worktree/window is
#                         created — never a redundant/silent no-op.
#
#   complete <id>    Worktree/branch cleanup ONLY — never touches story
#                    state. Mirrors issue.sh's `complete execute <n>
#                    --no-close` split: conductor's own --if-state-guarded
#                    `story move <id> done` (Phase 2) performs the actual
#                    state transition, exactly as conductor removes the
#                    in-progress label itself today rather than delegating
#                    that to issue.sh. The scan is a purpose-built,
#                    single-target lookup — only the ONE worktree +
#                    worktree-<name> branch this dispatch itself would have
#                    created — NOT a port of issue.sh's collect_targets,
#                    which also discovers a GitHub PR's merged head branch.
#                    storyhook has no such lookup: the worktree directory
#                    name is the sole PR<->story linkage.
#
# ENV VAR NAMESPACE — a deliberate choice, not inherited: session.sh's own
# header flags the daemon-caller seam (target-session / prompt-extra) as
# "left open" by the session-lib extraction. This script introduces its OWN
# STORY_* namespace (STORY_TARGET_SESSION, STORY_PROMPT_EXTRA, etc.) rather
# than reusing issue.sh's ISSUE_* names verbatim, keeping the two actuators'
# configuration surfaces independent. The ONE exception is
# ISSUE_PROTECTED_BRANCHES: is_protected_branch() in session.sh reads that
# literal env var name directly (not a caller-supplied local), and
# session.sh is out of this task's scope to change — so protected-branch
# overrides for story.sh are configured via ISSUE_PROTECTED_BRANCHES too,
# by construction of the shared library, not by choice made here.
set -euo pipefail

# Shared tmux/worktree/pane-readiness mechanics (window/worktree naming,
# git-safety helpers, the readiness gate, confirmed-send) live in
# plugins/issue/lib/session.sh — see this file's header above for the cross-
# plugin dependency this creates.
source "$(dirname "${BASH_SOURCE[0]}")/../../issue/lib/session.sh"

# ---- config (all env-overridable) -------------------------------------------
STORY="${STORY_BIN:-story}"
# Launch command, run INSIDE the worktree dispatch already created — must NOT
# include `-w`/`--worktree` (would try to create a second worktree at the
# same path). <name> renders to the resolved window/worktree name, <n> to the
# story id, for a custom override that wants either.
LAUNCH_TPL="${STORY_LAUNCH_CMD:-claude --permission-mode plan --model opusplan}"
# The handoff prompt — the only lever the dispatcher has over the child
# session. Single-line + ASCII (no backticks) by default; delivery is via a
# bracketed paste (paste_prompt), so a multi-line STORY_PROMPT override is
# safe.
PROMPT_TPL="${STORY_PROMPT:-Investigate and plan a fix for story <n> in this repo. Begin by reading it with \`story show <n> --json\` (its comments carry the discussion history). When your plan is finalized and approved, post it as a comment on <n> via \`story comment <n> \"<plan>\"\` before you start implementing. Ensure every pull request you open references story <n> in its body, and comment a link to each PR on <n> after you push it. Do not bump the version or deploy from this worktree: do not run semver bump, deployit deploy, or any release/version step, and do not plan for them -- versioning and deployment happen later from the main branch, not here.}"
# Extra clause a caller appends to the handoff prompt (daemon-caller seam —
# see this file's ENV VAR NAMESPACE header note). Appended VERBATIM with a
# single space separator, AFTER <n>/<name> templating.
PROMPT_EXTRA="${STORY_PROMPT_EXTRA:-}"
# New-window (and worktree) name override; supports the <n> placeholder.
WINDOW_NAME_TPL="${STORY_WINDOW_NAME:-}"
# Focus policy: the new window is created DETACHED (-d) by default.
FOREGROUND="${STORY_FOREGROUND:-}"
# Target tmux session for the dispatch window (daemon-caller seam — see the
# ENV VAR NAMESPACE header note).
TARGET_SESSION="${STORY_TARGET_SESSION:-}"
# Per-story git-worktree hygiene AND the worktree container itself.
WORKTREE_IGNORE_PATH="${STORY_WORKTREE_IGNORE_PATH:-.claude/worktrees/}"
WORKTREE_IGNORE_COMMENT="# storywork per-story git worktrees (ephemeral — never commit)"
# Readiness gate before typing the prompt — see issue.sh's own config block
# for the full two-tier rationale (this is the same gate, same defaults).
READY_PATTERN="${STORY_READY_PATTERN:-for shortcuts|for agents|mode on|to cycle}"
READY_ATTEMPTS="${STORY_READY_ATTEMPTS:-60}"
READY_DELAY="${STORY_READY_DELAY:-0.25}"
READY_FALLBACK_DELAY="${STORY_READY_FALLBACK_DELAY:-3}"
READY_STABLE_POLLS="${STORY_READY_STABLE_POLLS:-3}"
READY_FRAME_GLYPH="${STORY_READY_FRAME_GLYPH:-─}"
READY_PROMPT_GLYPH="${STORY_READY_PROMPT_GLYPH:-❯}"
READY_TAIL_LINES="${STORY_READY_TAIL_LINES:-8}"
CONFIRM_ATTEMPTS="${STORY_CONFIRM_ATTEMPTS:-8}"
CONFIRM_DELAY="${STORY_CONFIRM_DELAY:-0.3}"
SEND_RETRIES="${STORY_SEND_RETRIES:-2}"
PASTE_SETTLE_DELAY="${STORY_PASTE_SETTLE_DELAY:-0.2}"
READY_ACCEPT_PATTERN="${STORY_READY_ACCEPT_PATTERN:-esc to interrupt|Thinking|Crunching|tokens|to interrupt}"
CAPTURE_LINES="${STORY_CAPTURE_LINES:-200}"
DRY_RUN="${STORY_DRY_RUN:-}"
ALLOW_CLOSED="${STORY_ALLOW_CLOSED:-}"

require_story() {
  command -v "$STORY" >/dev/null 2>&1 \
    || fail "story CLI not found — build/install it from mikeydotio/storyhook (see story --help)."
}

# valid_story_id <id> — a story id is interpolated verbatim into worktree
# paths and branch names (via resolve_wname), so it is validated at this
# boundary: non-empty, alphanumeric plus hyphen/underscore only (storyhook's
# own ids look like "SH-12"; this also rejects path-traversal/whitespace).
valid_story_id() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]
}

# ---- subcommand: dispatch ---------------------------------------------------
cmd_dispatch() {
  local id="${1:-}"
  [ -n "$id" ] || fail "usage: story.sh dispatch <story-id>"
  valid_story_id "$id" || fail "story id must be alphanumeric (hyphens/underscores allowed) (got: $id)."

  # Step 1: tmux precondition (relaxed under dry-run and under
  # STORY_TARGET_SESSION — a daemon caller outside tmux dispatches into a
  # NAMED session, so its own tmux context is irrelevant).
  if [ -z "$DRY_RUN" ] && [ -z "$TARGET_SESSION" ]; then
    [ -n "${TMUX:-}" ] || fail "story requires tmux — run Claude inside a tmux session."
    [ -n "${TMUX_PANE:-}" ] || fail "story requires \$TMUX_PANE — run Claude inside a tmux pane."
  fi

  # Step 2: repo dir (worktree creation below needs a git-tracked location).
  local dir
  dir=$(git rev-parse --show-toplevel 2>/dev/null) || fail "not inside a git repository."

  # Step 3: story CLI present.
  require_story

  # Step 4: story exists, not closed, and CLAIMABLE — the hard precondition.
  # Every read here is REAL, even under dry-run (issue.sh's own asymmetry:
  # reads always run for real, only writes are symbolic under dry-run).
  local show_json result title state superstate
  show_json=$("$STORY" show "$id" --json 2>/dev/null) || true
  result=$(printf '%s' "$show_json" | jq -r '.result // ""' 2>/dev/null || printf '')
  if [ "$result" != "ok" ]; then
    fail "story \`$id\` not found ($(printf '%s' "$show_json" | jq -r '.error // "story show failed"' 2>/dev/null))."
  fi
  title=$(printf '%s' "$show_json" | jq -r '.story.story.title // ""')
  state=$(printf '%s' "$show_json" | jq -r '.story.story.state // ""')
  superstate=$(printf '%s' "$show_json" | jq -r '.story.story.superstate // ""')
  if [ "$superstate" = "CLOSED" ] && [ -z "$ALLOW_CLOSED" ]; then
    fail "story $id is closed (superstate CLOSED) (set STORY_ALLOW_CLOSED=1 to dispatch anyway)."
  fi

  # claim_needed: false when the story is ALREADY in-progress (a caller —
  # conductor's storyx.claim_ready — pre-claimed it): the move is then
  # skipped ENTIRELY, never repeated. Only a REAL transition attempts the CAS
  # move, and only outside dry-run (a write, not a read).
  local claim_needed=false
  [ "$state" = "in-progress" ] || claim_needed=true

  if [ -z "$DRY_RUN" ] && [ "$claim_needed" = true ]; then
    local move_json move_result
    move_json=$("$STORY" move "$id" in-progress --if-state "$state" --json 2>/dev/null) || true
    move_result=$(printf '%s' "$move_json" | jq -r '.result // ""' 2>/dev/null || printf '')
    case "$move_result" in
      ok)
        state="in-progress" ;;
      conflict)
        refuse "claim-conflict" "story $id changed state before it could be claimed (expected \`$state\`, now \`$(printf '%s' "$move_json" | jq -r '.actual // "?"' 2>/dev/null)\`) — another dispatch likely won the race." ;;
      *)
        fail "story move $id in-progress failed: $(printf '%s' "$move_json" | jq -r '.error // "story move emitted no result"' 2>/dev/null)." ;;
    esac
  fi

  # Compute the name used for the tmux window, the worktree dir leaf, AND the
  # worktree branch: "<repo-prefix>-<id>" (e.g. "con-SH-12"), or the
  # STORY_WINDOW_NAME override. repo_prefix's input need not be an
  # "owner/repo" string (storyhook has no GitHub-owner concept) — the git
  # toplevel directory's own basename is enough to derive a stable, repo-
  # scoped prefix, and repo_prefix already tolerates a no-slash input
  # unchanged.
  local repo_name wname wt_container worktree_path worktree_branch
  repo_name="$(basename "$dir")"
  wname=$(resolve_wname "$id" "$repo_name")
  wt_container="${WORKTREE_IGNORE_PATH%/}"
  worktree_path="$dir/$wt_container/$wname"
  worktree_branch="worktree-$wname"

  local launch_cmd prompt
  launch_cmd=$(render_template "$LAUNCH_TPL" "$id" "$wname")
  prompt=$(render_template "$PROMPT_TPL" "$id" "$wname")
  [ -n "$PROMPT_EXTRA" ] && prompt="$prompt $PROMPT_EXTRA"

  local ignore_status
  ignore_status=$(worktree_ignore_status "$dir")

  local detach="-d "
  [ -n "$FOREGROUND" ] && detach=""
  local target=""
  [ -n "$TARGET_SESSION" ] && target="-t $TARGET_SESSION: "

  local claim_cmd=""
  if [ "$claim_needed" = true ]; then
    claim_cmd="story move $id in-progress --if-state $state"
  fi

  # Dry-run: all read-only checks above ran for real; emit the planned
  # commands SYMBOLICALLY and stop before any side effect.
  if [ -n "$DRY_RUN" ]; then
    jq -n \
      --arg id "$id" --arg title "$title" --arg dir "$dir" \
      --arg wname "$wname" --arg launch "$launch_cmd" --arg prompt "$prompt" \
      --arg state "$state" --argjson claim_needed "$claim_needed" \
      --arg ignore_status "$ignore_status" \
      --arg detach "$detach" --arg target "$target" \
      --arg wtpath "$worktree_path" --arg wtbranch "$worktree_branch" \
      --arg claimcmd "$claim_cmd" '
      {
        ok: true, dry_run: true,
        id: $id, title: $title, dir: $dir,
        window_name: $wname, prompt: $prompt, state: $state,
        worktree_branch: $wtbranch, worktree_path: $wtpath,
        gitignore: (if $ignore_status == "already-ignored" then "already-ignored" else "would-add" end),
        commands: ((if $claimcmd == "" then [] else [$claimcmd] end) + [
          ("git worktree add --no-track -b " + $wtbranch + " " + $wtpath + " <base-oid>"),
          ("tmux new-window " + $target + $detach + "-c " + $wtpath + " -n " + $wname + " -P -F #{pane_id}"),
          ("tmux send-keys -t <pane> -l " + $launch),
          "tmux send-keys -t <pane> Enter",
          ("printf %s " + $prompt + " | tmux load-buffer -b story-" + $id + " -"),
          ("tmux paste-buffer -p -d -b story-" + $id + " -t <pane>"),
          "tmux send-keys -t <pane> Enter"
        ]),
        display: ("[story] DRY RUN for " + $id + " (" + $title
                  + "): would create worktree " + $wtpath + " (branch " + $wtbranch
                  + "), open a new tmux window named " + $wname
                  + (if $claimcmd == "" then " (already in-progress)" else ", claiming it via `" + $claimcmd + "`" end)
                  + " and run the listed commands.")
      }'
    return 0
  fi

  # Step 5: idempotently gitignore the per-story worktree CONTAINER dir,
  # BEFORE the worktree materializes. Best-effort — never flips ok to false.
  local gitignore_result="already-ignored"
  if [ "$ignore_status" = "not-ignored" ]; then
    gitignore_result=$(append_worktree_ignore "$dir")
  fi

  # Step 6: fetch origin/<default> (best-effort, quiet) and resolve the
  # commit the new worktree will be based on. Two tiers: FRESH (the ref
  # resolves after freshening) or HEAD-FALLBACK (origin/<default> has never
  # resolved at all — offline and never fetched); either way dispatch never
  # blocks on network.
  local default base_oid="" base_fresh=false base_note=""
  default=$(default_branch)
  freshen_base_ref "$default"
  if base_oid=$(git rev-parse --verify --quiet "refs/remotes/origin/$default^{commit}" 2>/dev/null) \
     && [ -n "$base_oid" ]; then
    base_fresh=true
  elif base_oid=$(git rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null) && [ -n "$base_oid" ]; then
    base_note="could not determine origin/$default; new work is based on the local checkout, NOT the latest origin tip"
  else
    fail "cannot resolve a base commit for the new worktree (no origin/$default and HEAD has no commits)."
  fi

  # Step 7: create the worktree off the resolved base commit.
  if git show-ref --verify --quiet "refs/heads/$worktree_branch" || [ -e "$worktree_path" ]; then
    fail "a worktree or branch for \`$wname\` already exists — already dispatched? Clean it up first with \`story.sh complete $id\`."
  fi
  local wt_err
  if ! wt_err=$(git worktree add --no-track -b "$worktree_branch" "$worktree_path" "$base_oid" 2>&1); then
    fail "failed to create worktree at $worktree_path: $(printf '%s' "$wt_err" | tail -n 2)"
  fi

  # Step 8: open the window (rooted IN the new worktree). A failure here
  # rolls back the just-created worktree/branch so a failed dispatch leaves
  # no litter.
  local new_window_args pane window
  new_window_args=(-c "$worktree_path" -n "$wname" -P -F '#{pane_id}')
  [ -z "$FOREGROUND" ] && new_window_args=(-d "${new_window_args[@]}")
  [ -n "$TARGET_SESSION" ] && new_window_args=(-t "$TARGET_SESSION:" "${new_window_args[@]}")
  if ! pane=$(tmux new-window "${new_window_args[@]}" 2>/dev/null) || [ -z "$pane" ]; then
    git worktree remove --force "$worktree_path" >/dev/null 2>&1 || true
    git worktree prune >/dev/null 2>&1 || true
    git branch -D "$worktree_branch" >/dev/null 2>&1 || true
    fail "failed to open a new tmux window."
  fi
  window=$(tmux display-message -p -t "$pane" '#{window_id}' 2>/dev/null || printf '')

  # Pin the name before launching claude, so an early title escape can't win
  # the race.
  if [ -n "$window" ]; then
    tmux set-window-option -t "$window" automatic-rename off 2>/dev/null || true
    tmux set-window-option -t "$window" allow-rename off 2>/dev/null || true
  fi

  # Step 9: launch claude (literal mode). The worktree already exists (Step
  # 7), so the default launch omits `-w` entirely.
  paste_text "$pane" "$launch_cmd" || true
  tmux send-keys -t "$pane" Enter 2>/dev/null || true

  # Step 10: readiness gate before typing the prompt.
  local readiness_confirmed=false
  if wait_ready "$pane" "$launch_cmd"; then
    readiness_confirmed=true
  else
    sleep "$READY_FALLBACK_DELAY"
  fi

  # Step 11: type + submit the prompt, confirmed.
  local prompt_confirmed=false prompt_accepted_flag=false
  if send_prompt_confirmed "$pane" "$prompt" "story-$id"; then
    prompt_confirmed=true
    if prompt_accepted "$pane"; then
      prompt_accepted_flag=true
    fi
  fi

  # Result. ok:true from here on (the claim already succeeded in Step 4, or
  # was never needed) — warn on any unconfirmed step or a non-fresh base.
  local claim_note=""
  [ "$claim_needed" = true ] && claim_note=" and claimed it (now \`in-progress\`)"

  local warning="" display base
  if [ "$readiness_confirmed" = true ] && [ "$prompt_confirmed" = true ]; then
    base="[story] $id ($title) → opened tmux window \`$wname\` on a worktree based on \`origin/$default\` @ \`${base_oid:0:8}\`, launched \`$launch_cmd\` (plan mode), submitted the prompt${claim_note}."
  else
    if [ "$readiness_confirmed" = false ] && [ "$prompt_confirmed" = false ]; then
      warning="Couldn't confirm claude finished starting, nor that the prompt submitted — check window \`$wname\`."
    elif [ "$readiness_confirmed" = false ]; then
      warning="Couldn't confirm claude finished starting before the prompt was sent, but the prompt did submit — glance at window \`$wname\`."
    else
      warning="claude started, but couldn't confirm the prompt submitted — check window \`$wname\`."
    fi
    base="[story] $id ($title) → window \`$wname\` opened on a worktree based on \`origin/$default\` @ \`${base_oid:0:8}\`, but I couldn't fully confirm the handoff."
  fi
  if [ -n "$base_note" ]; then
    warning="${warning:+$warning }${base_note}."
  fi

  local tail_evidence=""
  if [ -n "$warning" ]; then
    display="$base $warning"
    tail_evidence=$(pane_tail "$pane")
  else
    display="$base"
  fi

  jq -n \
    --arg id "$id" --arg title "$title" --arg window "$window" --arg wname "$wname" \
    --arg pane "$pane" --arg state "$state" \
    --arg gitignore "$gitignore_result" \
    --argjson ready "$readiness_confirmed" --argjson pconf "$prompt_confirmed" \
    --argjson paccept "$prompt_accepted_flag" \
    --argjson claimed "$claim_needed" \
    --arg warning "$warning" --arg tail "$tail_evidence" --arg display "$display" \
    --arg default "$default" --arg base_oid "$base_oid" --argjson base_fresh "$base_fresh" \
    --arg wtbranch "$worktree_branch" --arg wtpath "$worktree_path" '
    {
      ok: true,
      id: $id, title: $title,
      window: $window, window_name: $wname, pane: $pane,
      state: $state,
      readiness_confirmed: $ready, prompt_confirmed: $pconf, prompt_accepted: $paccept,
      claimed: $claimed, gitignore: $gitignore,
      base_branch: $default, base_ref: ("origin/" + $default),
      base_oid: $base_oid, base_fresh: $base_fresh,
      worktree_branch: $wtbranch, worktree_path: $wtpath
    }
    + (if $warning == "" then {} else {warning: $warning} end)
    + (if $tail == "" then {} else {pane_tail: $tail} end)
    + {display: $display}'
}

# ---- subcommand: complete ---------------------------------------------------
# complete <id> — worktree/branch cleanup ONLY (see this file's header for
# why this never touches story state). Guard rails live entirely here (never
# the LLM): only a removable worktree and a fully-merged local branch are
# ever touched; current/locked/dirty worktrees and unmerged/protected
# branches are skipped and reported.

# _story_worktree_status <path> — READ-ONLY. Echo missing|current|locked|
# dirty|removable for the worktree registered at EXACTLY <path>. A purpose-
# built, single-target scan: unlike issue.sh's collect_targets, story.sh has
# no legacy bare-<n> alias to also match and discovers no GitHub PR head
# branch — it only ever looks at the ONE worktree its own dispatch would
# have created.
_story_worktree_status() {
  local target="$1" cur locked
  cur=$(git rev-parse --show-toplevel 2>/dev/null || printf '')
  locked=$(git worktree list --porcelain 2>/dev/null | awk -v want="$target" '
    function flush() { if (p==want) print (l?"1":"0") }
    /^worktree / { flush(); p=substr($0,10); l=0 }
    /^locked/    { l=1 }
    END          { flush() }')
  [ -n "$locked" ] || { printf 'missing'; return 0; }
  if [ "$target" = "$cur" ]; then printf 'current'; return 0; fi
  if [ "$locked" = "1" ]; then printf 'locked'; return 0; fi
  if [ -n "$(git -C "$target" status --porcelain 2>/dev/null)" ]; then printf 'dirty'; return 0; fi
  printf 'removable'
}

cmd_complete() {
  local id="${1:-}"
  [ -n "$id" ] || fail "usage: story.sh complete <story-id>"
  valid_story_id "$id" || fail "story id must be alphanumeric (hyphens/underscores allowed) (got: $id)."
  git rev-parse --show-toplevel >/dev/null 2>&1 || fail "not inside a git repository."

  local dir repo_name wname default
  dir=$(git rev-parse --show-toplevel)
  repo_name="$(basename "$dir")"
  wname=$(resolve_wname "$id" "$repo_name")
  default=$(default_branch)
  # Freshen origin/<default> once so merged-ness is judged against ground
  # truth, not a local <default> a daemon-managed repo never pulls.
  freshen_base_ref "$default"

  local wt_container worktree_path worktree_branch
  wt_container="${WORKTREE_IGNORE_PATH%/}"
  worktree_path="$dir/$wt_container/$wname"
  worktree_branch="worktree-$wname"

  local -a removed_wt=() removed_bl=() failed=() skipped=()

  local wt_status
  wt_status=$(_story_worktree_status "$worktree_path")
  case "$wt_status" in
    removable)
      if git worktree remove "$worktree_path" >/dev/null 2>&1; then
        git worktree prune >/dev/null 2>&1 || true
        removed_wt+=("$worktree_path")
      else
        failed+=("worktree:$worktree_path")
      fi ;;
    missing) : ;;  # nothing to remove — may already be cleaned up; not an error.
    *) skipped+=("worktree:$worktree_path($wt_status)") ;;
  esac

  if local_branch_exists "$worktree_branch"; then
    if is_protected_branch "$worktree_branch"; then
      failed+=("branch:$worktree_branch(protected)")
    elif branch_is_merged "$worktree_branch" "$default"; then
      if delete_merged_local_branch "$worktree_branch" "$default"; then
        removed_bl+=("$worktree_branch")
      else
        failed+=("branch:$worktree_branch(local)")
      fi
    else
      skipped+=("branch:$worktree_branch(unmerged)")
    fi
  fi

  local rwt rbl fail_json skip_json
  rwt=$(printf '%s\n' "${removed_wt[@]:-}" | jq -R -s 'split("\n")|map(select(length>0))')
  rbl=$(printf '%s\n' "${removed_bl[@]:-}" | jq -R -s 'split("\n")|map(select(length>0))')
  fail_json=$(printf '%s\n' "${failed[@]:-}" | jq -R -s 'split("\n")|map(select(length>0))')
  skip_json=$(printf '%s\n' "${skipped[@]:-}" | jq -R -s 'split("\n")|map(select(length>0))')

  jq -n --arg id "$id" --argjson rwt "$rwt" --argjson rbl "$rbl" \
        --argjson failed "$fail_json" --argjson skipped "$skip_json" '
    {
      ok: true, id: $id,
      removed: { worktrees: $rwt, branches: $rbl }
    }
    + (if ($failed|length) > 0 then {failed:$failed} else {} end)
    + (if ($skipped|length) > 0 then {skipped:$skipped} else {} end)
    + { display: (
        "[story] complete " + $id + ": removed "
        + ($rwt|length|tostring) + " worktree(s), "
        + ($rbl|length|tostring) + " branch(es)."
        + (if ($failed|length) > 0 then " Could not: " + ($failed|join(", ")) + "." else "" end)
        + (if ($skipped|length) > 0 then " Preserved: " + ($skipped|join(", ")) + "." else "" end)
      ) }'
}

# ---- router -----------------------------------------------------------------
case "${1:-}" in
  dispatch) shift; cmd_dispatch "$@" ;;
  complete) shift; cmd_complete "$@" ;;
  *)        fail "usage: story.sh <dispatch <story-id> | complete <story-id>>" ;;
esac
