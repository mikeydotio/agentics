#!/usr/bin/env bash
# handle-issue.sh — deterministic helper for the /handle-issue skill.
#
# Two subcommands, each emitting exactly ONE JSON object on stdout with an `ok`
# boolean and a human-readable `display`. The SKILL is a thin router: it reads
# `ok`/`display` and halts (showing `display`) on `ok:false`.
#
#   list                 Preconditions + open-issue enumeration for the picker.
#                        Emits {ok, count, repo, issues:[{number,title,url,
#                        option:{label,description}}], display}. Side-effect free.
#
#   dispatch <n>         Open a new tmux window (named "<repo-prefix>-<n>", e.g.
#                        "age-42") in the current session — DETACHED by default so
#                        the caller's focus stays put — `cd` it to the repo
#                        root, launch `claude -w <n> --permission-mode plan` (the
#                        official --worktree switch creates a per-issue git
#                        worktree, so it must run from a git-tracked location;
#                        --permission-mode plan starts the session in plan mode
#                        deterministically, no keystrokes), gate on claude
#                        becoming ready, then type + submit the prompt.
#
# ok-vs-warning boundary (dispatch): steps 0–4 are HARD preconditions — a failure
# emits {ok:false} and exits before ANY side effect. From step 5 (the first
# `tmux new-window`) onward the window already exists, so a failure to confirm
# readiness or prompt submission degrades to {ok:true, warning, ...} rather than
# ok:false — reporting ok:false there would falsely imply nothing happened.
#
# All timing/behaviour is env-overridable (see the config block) so the flow is
# testable headlessly (HANDLE_ISSUE_DRY_RUN, HANDLE_ISSUE_GH_BIN) and the
# launch command / prompt are escape-hatchable without editing code.
#
# tmux send/confirm logic is modelled on plugins/freshen/lib/pane-confirm.sh
# (send-keys keys/literal modes + capture-pane read-back). It is INLINED here
# rather than sourced because freshen may not be installed alongside this plugin.
set -euo pipefail

# ---- config (all env-overridable) -------------------------------------------
GH="${HANDLE_ISSUE_GH_BIN:-gh}"
LIST_LIMIT="${HANDLE_ISSUE_LIST_LIMIT:-50}"
LAUNCH_TPL="${HANDLE_ISSUE_LAUNCH_CMD:-claude -w <n> --permission-mode plan}"
# The handoff prompt is the ONLY lever the dispatcher has over the child session,
# which is what actually plans, implements, and opens PRs. So it carries the
# GitHub self-reporting contract (issue #50): comment the finalized plan, word
# PRs to close the issue, comment PR links. Kept single-line + ASCII (no
# backticks) so `tmux send-keys -l` types it verbatim without key-interpretation.
PROMPT_TPL="${HANDLE_ISSUE_PROMPT:-Investigate and plan a fix for GitHub issue #<n> in this repo. When your plan is finalized and approved, post the full plan as a Markdown comment on issue #<n> using gh before you start implementing. Ensure every pull request you open closes the issue by including \"Closes #<n>\" in its body, and comment a link to each PR on issue #<n> after you push it.}"
# The "picked up" label applied to the issue at dispatch (issue #50). Set
# HANDLE_ISSUE_LABEL="" to disable labeling entirely. Color/description are used
# only when the label doesn't yet exist in the repo (create-if-missing). Uses
# `-` (not `:-`) so an explicit empty string opts out; only an unset var
# defaults to "in-progress".
LABEL="${HANDLE_ISSUE_LABEL-in-progress}"
LABEL_COLOR="${HANDLE_ISSUE_LABEL_COLOR:-fbca04}"
LABEL_DESC="${HANDLE_ISSUE_LABEL_DESC:-Actively being worked on}"
# New-window name. Default (computed in cmd_dispatch): first 3 alphanumerics of
# the repo name, lowercased, + "-<n>" (e.g. "age-42"). Set this to override in
# full; supports the <n> placeholder.
WINDOW_NAME_TPL="${HANDLE_ISSUE_WINDOW_NAME:-}"
# Focus policy: the new window is created DETACHED (-d) by default so the user's
# focus stays on their current window. Every follow-up send-keys/capture-pane
# targets the new pane by its captured id (not "the current window"), so the
# handoff still lands in the right window without stealing focus. Set
# HANDLE_ISSUE_FOREGROUND=1 to switch focus to the new window instead.
FOREGROUND="${HANDLE_ISSUE_FOREGROUND:-}"
# Readiness gate before typing the prompt. Claude's TUI text is a version-specific
# implementation detail, so READY_PATTERN is permissive and overridable; the
# fallback delay covers the case where the marker never matches.
READY_PATTERN="${HANDLE_ISSUE_READY_PATTERN:-for shortcuts}"
READY_ATTEMPTS="${HANDLE_ISSUE_READY_ATTEMPTS:-40}"
READY_DELAY="${HANDLE_ISSUE_READY_DELAY:-0.25}"
READY_FALLBACK_DELAY="${HANDLE_ISSUE_READY_FALLBACK_DELAY:-3}"
# Prompt-submission confirm/resend bounds (freshen semantics).
CONFIRM_ATTEMPTS="${HANDLE_ISSUE_CONFIRM_ATTEMPTS:-8}"
CONFIRM_DELAY="${HANDLE_ISSUE_CONFIRM_DELAY:-0.3}"
SEND_RETRIES="${HANDLE_ISSUE_SEND_RETRIES:-2}"
DRY_RUN="${HANDLE_ISSUE_DRY_RUN:-}"
ALLOW_CLOSED="${HANDLE_ISSUE_ALLOW_CLOSED:-}"

# ---- JSON emitters ----------------------------------------------------------
# fail <message> — emit {ok:false, display} and exit non-zero. The skill halts
# and shows `display`.
fail() {
  jq -n --arg d "$1" '{ok:false, display:$d}'
  exit 1
}

# ---- helpers ----------------------------------------------------------------
render_template() {  # render_template <template-with-<n>> <number>
  local tpl="$1" n="$2"
  printf '%s' "${tpl//<n>/$n}"
}

require_gh() {
  command -v "$GH" >/dev/null 2>&1 \
    || fail "gh CLI not found — install GitHub CLI (https://cli.github.com)."
  "$GH" auth status >/dev/null 2>&1 \
    || fail "gh is not authenticated — run: gh auth login (or set GH_TOKEN)."
}

# origin_owner_repo — echo "<owner>/<repo>" derived from the origin remote, or
# return non-zero. Handles git@host:owner/repo(.git) and https://host/owner/repo(.git).
origin_owner_repo() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || return 1
  url="${url%.git}"
  url="${url%/}"
  if [[ "$url" =~ [:/]([^/:]+)/([^/]+)$ ]]; then
    printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

# apply_in_progress_label <repo> <n> — best-effort: ensure the $LABEL label
# exists in <repo> (create-if-missing; existing color/description untouched — no
# --force), then add it to issue <n>. Returns non-zero only if the add fails, so
# the caller can degrade to a warning. Never called when $LABEL is empty.
apply_in_progress_label() {
  local repo="$1" n="$2"
  # Create-if-missing. A failure here is fine: either the label already exists
  # (so add-label below still works) or we lack permission (add-label will then
  # surface the real failure). Deliberately no --force, to preserve any existing
  # styling the repo already gave this label.
  "$GH" label create "$LABEL" --repo "$repo" \
    --color "$LABEL_COLOR" --description "$LABEL_DESC" >/dev/null 2>&1 || true
  "$GH" issue edit "$n" --repo "$repo" --add-label "$LABEL" >/dev/null 2>&1
}

# text_still_pending <pane> <text> — true if <text> still sits, unsubmitted, as
# the trailing content of the pane's last non-blank line. A failed capture-pane
# counts as "still pending" (never a false confirmation).
text_still_pending() {
  local pane="$1" text="$2" content last_line
  content=$(tmux capture-pane -p -t "$pane" 2>/dev/null) || return 0
  last_line=$(printf '%s\n' "$content" | grep -v '^[[:space:]]*$' | tail -1 || true)
  case "$last_line" in
    *"$text") return 0 ;;
    *) return 1 ;;
  esac
}

# wait_ready <pane> <launch-cmd> — poll until the launch command has left the
# input line AND the readiness marker appears, bounded by READY_ATTEMPTS.
wait_ready() {
  local pane="$1" launch="$2" attempt=0 content last_line
  while [ "$attempt" -lt "$READY_ATTEMPTS" ]; do
    if content=$(tmux capture-pane -p -t "$pane" 2>/dev/null); then
      last_line=$(printf '%s\n' "$content" | grep -v '^[[:space:]]*$' | tail -1 || true)
      if [[ "$last_line" != *"$launch" ]] \
         && printf '%s' "$content" | grep -Eq -- "$READY_PATTERN"; then
        return 0
      fi
    fi
    sleep "$READY_DELAY"
    attempt=$((attempt + 1))
  done
  return 1
}

# send_prompt_confirmed <pane> <text> — literal-send <text> + Enter, then poll
# for it to leave the input line; resend up to SEND_RETRIES times.
send_prompt_confirmed() {
  local pane="$1" text="$2" resend=0 attempt
  while [ "$resend" -le "$SEND_RETRIES" ]; do
    if tmux send-keys -t "$pane" -l "$text" 2>/dev/null \
       && tmux send-keys -t "$pane" Enter 2>/dev/null; then
      attempt=0
      while [ "$attempt" -lt "$CONFIRM_ATTEMPTS" ]; do
        text_still_pending "$pane" "$text" || return 0
        sleep "$CONFIRM_DELAY"
        attempt=$((attempt + 1))
      done
    fi
    resend=$((resend + 1))
  done
  return 1
}

# ---- subcommand: list -------------------------------------------------------
cmd_list() {
  require_gh
  git rev-parse --show-toplevel >/dev/null 2>&1 || fail "not inside a git repository."
  local repo issues_json
  repo=$(origin_owner_repo) || fail "no GitHub origin remote found (git remote get-url origin)."
  if ! issues_json=$("$GH" issue list --repo "$repo" --state open --limit "$LIST_LIMIT" \
                       --json number,title,url 2>/dev/null); then
    fail "failed to list open issues for $repo (gh issue list)."
  fi
  printf '%s' "$issues_json" | jq --arg repo "$repo" '
    {
      ok: true,
      count: length,
      repo: $repo,
      issues: [ .[] | {
        number, title, url,
        option: {
          label: ("#" + (.number | tostring)),
          description: (.title // "(no title)")
        }
      } ],
      display: (
        if length == 0
        then ("No open issues on " + $repo + ".")
        else ("[handle-issue] " + (length | tostring) + " open issue(s) on " + $repo)
        end
      )
    }'
}

# ---- subcommand: dispatch ---------------------------------------------------
cmd_dispatch() {
  local n="${1:-}"
  [ -n "$n" ] || fail "usage: handle-issue.sh dispatch <issue-number>"
  [[ "$n" =~ ^[0-9]+$ ]] || fail "issue number must be a positive integer (got: $n)."

  local launch_cmd prompt
  launch_cmd=$(render_template "$LAUNCH_TPL" "$n")
  prompt=$(render_template "$PROMPT_TPL" "$n")

  # Step 1: tmux precondition (relaxed under dry-run so it runs headlessly).
  if [ -z "$DRY_RUN" ]; then
    [ -n "${TMUX:-}" ] || fail "handle-issue requires tmux — run Claude inside a tmux session."
    [ -n "${TMUX_PANE:-}" ] || fail "handle-issue requires \$TMUX_PANE — run Claude inside a tmux pane."
  fi

  # Step 2: repo dir (also satisfies claude -w's git-tracked-location requirement).
  local dir
  dir=$(git rev-parse --show-toplevel 2>/dev/null) || fail "not inside a git repository."

  # Step 3: gh present + authed.
  require_gh

  # Step 4: issue exists and is open.
  local repo issue_json title state
  repo=$(origin_owner_repo) || fail "no GitHub origin remote found (git remote get-url origin)."
  if ! issue_json=$("$GH" issue view "$n" --repo "$repo" \
                      --json number,title,state,url 2>/dev/null); then
    fail "issue #$n not found on $repo."
  fi
  title=$(printf '%s' "$issue_json" | jq -r '.title // ""')
  state=$(printf '%s' "$issue_json" | jq -r '.state // ""')
  if [ "$state" = "CLOSED" ] && [ -z "$ALLOW_CLOSED" ]; then
    fail "issue #$n is closed on $repo (set HANDLE_ISSUE_ALLOW_CLOSED=1 to dispatch anyway)."
  fi

  # Compute the new-window name: "<repo-prefix>-<n>" (e.g. "age-42"), where the
  # prefix is the first 3 alphanumerics of the repo name, lowercased. Fully
  # overridable via HANDLE_ISSUE_WINDOW_NAME (supports the <n> placeholder).
  local wname
  if [ -n "$WINDOW_NAME_TPL" ]; then
    wname=$(render_template "$WINDOW_NAME_TPL" "$n")
  else
    local repo_name pfx
    repo_name="${repo##*/}"
    pfx=$(printf '%s' "$repo_name" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:upper:]' '[:lower:]')
    wname="${pfx}-${n}"
  fi

  # Detached by default (keeps the caller's focus); "-d " unless FOREGROUND is set.
  # Kept in sync with the real new-window invocation in Step 5 below.
  local detach="-d "
  [ -n "$FOREGROUND" ] && detach=""

  # Dry-run: all read-only checks above ran for real; emit the planned commands
  # and stop before any side effect.
  if [ -n "$DRY_RUN" ]; then
    jq -n \
      --arg issue "$n" --arg title "$title" --arg repo "$repo" --arg dir "$dir" \
      --arg wname "$wname" --arg launch "$launch_cmd" --arg prompt "$prompt" \
      --arg label "$LABEL" --arg color "$LABEL_COLOR" --arg desc "$LABEL_DESC" \
      --arg detach "$detach" '
      {
        ok: true, dry_run: true,
        issue: ($issue | tonumber), title: $title, repo: $repo, dir: $dir,
        window_name: $wname, label: $label,
        commands: ([
          ("tmux new-window " + $detach + "-c " + $dir + " -n " + $wname + " -P -F #{pane_id}"),
          ("tmux send-keys -t <pane> -l " + $launch),
          "tmux send-keys -t <pane> Enter",
          ("tmux send-keys -t <pane> -l " + $prompt),
          "tmux send-keys -t <pane> Enter"
        ] + (if $label == "" then [] else [
          ("gh label create " + $label + " --repo " + $repo + " --color " + $color
           + " --description " + $desc),
          ("gh issue edit " + $issue + " --repo " + $repo + " --add-label " + $label)
        ] end)),
        display: ("[handle-issue] DRY RUN for #" + $issue + " (" + $title
                  + "): would open a new tmux window named " + $wname + " in " + $dir
                  + (if $label == "" then "" else ", mark the issue " + $label end)
                  + " and run the listed commands.")
      }'
    return 0
  fi

  # Step 5: open the window (first side effect). Hard-fail is still safe here —
  # window creation is atomic; a failure leaves nothing to clean up.
  local new_window_args pane window
  new_window_args=(-c "$dir" -n "$wname" -P -F '#{pane_id}')
  # Detached by default so the caller's focus stays put; opt in to focus-follow
  # with HANDLE_ISSUE_FOREGROUND=1. Keystrokes below target $pane by id regardless.
  [ -z "$FOREGROUND" ] && new_window_args=(-d "${new_window_args[@]}")
  if ! pane=$(tmux new-window "${new_window_args[@]}" 2>/dev/null) || [ -z "$pane" ]; then
    fail "failed to open a new tmux window."
  fi
  window=$(tmux display-message -p -t "$pane" '#{window_id}' 2>/dev/null || printf '')

  # Pin the name: disable tmux's automatic-rename AND program-driven renames so
  # "<repo-prefix>-<n>" survives claude setting its own terminal title. Do this
  # before launching claude, so an early title escape can't win the race.
  if [ -n "$window" ]; then
    tmux set-window-option -t "$window" automatic-rename off 2>/dev/null || true
    tmux set-window-option -t "$window" allow-rename off 2>/dev/null || true
  fi

  # Step 6: launch claude (literal mode — the space/flag must not be key-interpreted).
  tmux send-keys -t "$pane" -l "$launch_cmd" 2>/dev/null || true
  tmux send-keys -t "$pane" Enter 2>/dev/null || true

  # Step 7: readiness gate before typing the prompt (claude -w also builds the
  # worktree before its TUI renders, so this wait matters). One-shot — no retry
  # cycle, so on miss we settle a fixed amount and proceed best-effort. Plan mode
  # itself needs no gate: it's set by the --permission-mode plan launch flag.
  local readiness_confirmed=false
  if wait_ready "$pane" "$launch_cmd"; then
    readiness_confirmed=true
  else
    sleep "$READY_FALLBACK_DELAY"
  fi

  # Step 8: type + submit the prompt, confirmed.
  local prompt_confirmed=false
  if send_prompt_confirmed "$pane" "$prompt"; then
    prompt_confirmed=true
  fi

  # Step 9: mark the issue in-progress on GitHub (issue #50). Done last so the
  # two gh round-trips don't delay the interactive handoff above. Best-effort —
  # a failure here only adds a warning, never flips dispatch to ok:false — and
  # skipped entirely when labeling is disabled ($LABEL empty).
  local label_applied=false label_note="" label_ok_note=""
  if [ -n "$LABEL" ]; then
    if apply_in_progress_label "$repo" "$n"; then
      label_applied=true
      label_ok_note=" and marked it \`$LABEL\`"
    else
      label_note="couldn't apply the \`$LABEL\` label to #$n (check gh permissions/repo access)"
    fi
  fi

  # Result. ok:true from here on; warn on any unconfirmed step.
  local warning="" display base
  if [ "$readiness_confirmed" = true ] && [ "$prompt_confirmed" = true ]; then
    base="[handle-issue] #$n ($title) → opened tmux window \`$wname\`, launched \`$launch_cmd\` (plan mode), submitted the prompt${label_ok_note}."
  else
    if [ "$readiness_confirmed" = false ] && [ "$prompt_confirmed" = false ]; then
      warning="Couldn't confirm claude finished starting, nor that the prompt submitted — check window \`$wname\`."
    elif [ "$readiness_confirmed" = false ]; then
      warning="Couldn't confirm claude finished starting before the prompt was sent, but the prompt did submit — glance at window \`$wname\`."
    else
      warning="claude started, but couldn't confirm the prompt submitted — check window \`$wname\`."
    fi
    base="[handle-issue] #$n ($title) → window \`$wname\` opened, but I couldn't fully confirm the handoff."
  fi

  # Fold a label failure into the warning (best-effort — never ok:false).
  if [ -n "$label_note" ]; then
    warning="${warning:+$warning }$label_note."
  fi

  if [ -n "$warning" ]; then
    display="$base $warning"
  else
    display="$base"
  fi

  jq -n \
    --arg issue "$n" --arg title "$title" --arg window "$window" --arg wname "$wname" \
    --arg pane "$pane" --arg label "$LABEL" \
    --argjson ready "$readiness_confirmed" --argjson pconf "$prompt_confirmed" \
    --argjson lapplied "$label_applied" \
    --arg warning "$warning" --arg display "$display" '
    {
      ok: true,
      issue: ($issue | tonumber), title: $title,
      window: $window, window_name: $wname, pane: $pane,
      readiness_confirmed: $ready, prompt_confirmed: $pconf,
      label: $label, label_applied: $lapplied
    }
    + (if $warning == "" then {} else {warning: $warning} end)
    + {display: $display}'
}

# ---- router -----------------------------------------------------------------
case "${1:-}" in
  list)     shift; cmd_list "$@" ;;
  dispatch) shift; cmd_dispatch "$@" ;;
  *)        fail "usage: handle-issue.sh <list | dispatch <issue-number>>" ;;
esac
