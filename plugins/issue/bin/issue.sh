#!/usr/bin/env bash
# issue.sh — deterministic helper for the /issue skill.
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
#                        root, launch `claude -w <name> --permission-mode plan`
#                        (the official --worktree switch creates a per-issue git
#                        worktree named the SAME as the window, so it must run
#                        from a git-tracked location; --permission-mode plan
#                        starts the session in plan mode deterministically, no
#                        keystrokes), gate on claude becoming ready, then type +
#                        submit the prompt.
#
# ok-vs-warning boundary (dispatch): steps 0–4 are HARD preconditions — a failure
# emits {ok:false} and exits before ANY side effect. From step 5 (the first
# `tmux new-window`) onward the window already exists, so a failure to confirm
# readiness or prompt submission degrades to {ok:true, warning, ...} rather than
# ok:false — reporting ok:false there would falsely imply nothing happened.
#
# The step-5.5 `.gitignore` write for the per-issue worktree dir (issue #55) is a
# best-effort, idempotent hygiene write that runs AFTER the window opens; it can
# never flip ok to false (a failure just reports gitignore:"add-failed").
#
# All timing/behaviour is env-overridable (see the config block) so the flow is
# testable headlessly (ISSUE_DRY_RUN, ISSUE_GH_BIN) and the
# launch command / prompt are escape-hatchable without editing code.
#
# tmux send/confirm logic is modelled on plugins/freshen/lib/pane-confirm.sh
# (send-keys keys/literal modes + capture-pane read-back). It is INLINED here
# rather than sourced because freshen may not be installed alongside this plugin.
set -euo pipefail

# ---- config (all env-overridable) -------------------------------------------
GH="${ISSUE_GH_BIN:-gh}"
LIST_LIMIT="${ISSUE_LIST_LIMIT:-50}"
# Launch command. <name> renders to the resolved window/worktree name (see
# WINDOW_NAME_TPL below), so `claude -w <name>` names the worktree the SAME as
# the tmux window (e.g. "age-42") rather than the bare issue number. <n> (the
# issue number) is still substituted, so a custom override may use either.
LAUNCH_TPL="${ISSUE_LAUNCH_CMD:-claude -w <name> --permission-mode plan}"
# The handoff prompt is the ONLY lever the dispatcher has over the child session,
# which is what actually plans, implements, and opens PRs. So it carries the
# GitHub self-reporting contract (issue #50): comment the finalized plan, word
# PRs to close the issue, comment PR links. It also briefs the child NOT to bump
# the version or deploy from its worktree (those happen later from `main`), since
# this session always runs inside a per-issue worktree. Kept single-line + ASCII
# (no backticks) so `tmux send-keys -l` types it verbatim without key-interpretation.
PROMPT_TPL="${ISSUE_PROMPT:-Investigate and plan a fix for GitHub issue #<n> in this repo. When your plan is finalized and approved, post the full plan as a Markdown comment on issue #<n> using gh before you start implementing. Ensure every pull request you open closes the issue by including \"Closes #<n>\" in its body, and comment a link to each PR on issue #<n> after you push it. Do not bump the version or deploy from this worktree: do not run semver bump, deployit deploy, or any release/version step, and do not plan for them -- versioning and deployment happen later from the main branch, not here.}"
# The "picked up" label applied to the issue at dispatch (issue #50). Set
# ISSUE_LABEL="" to disable labeling entirely. Color/description are used
# only when the label doesn't yet exist in the repo (create-if-missing). Uses
# `-` (not `:-`) so an explicit empty string opts out; only an unset var
# defaults to "in-progress".
LABEL="${ISSUE_LABEL-in-progress}"
LABEL_COLOR="${ISSUE_LABEL_COLOR:-fbca04}"
LABEL_DESC="${ISSUE_LABEL_DESC:-Actively being worked on}"
# New-window (and worktree) name. Default (computed in cmd_dispatch): first 3
# alphanumerics of the repo name, lowercased, + "-<n>" (e.g. "age-42"). Set this
# to override in full; supports the <n> placeholder. Because the default launch
# command renders <name> from this value, overriding it renames the worktree too.
WINDOW_NAME_TPL="${ISSUE_WINDOW_NAME:-}"
# Focus policy: the new window is created DETACHED (-d) by default so the user's
# focus stays on their current window. Every follow-up send-keys/capture-pane
# targets the new pane by its captured id (not "the current window"), so the
# handoff still lands in the right window without stealing focus. Set
# ISSUE_FOREGROUND=1 to switch focus to the new window instead.
FOREGROUND="${ISSUE_FOREGROUND:-}"
# Per-issue git-worktree hygiene (issue #55). `claude -w <n>` (the launch flag)
# creates a worktree under this path; dispatch idempotently ensures the path is
# gitignored so it never dirties the parent repo's `git status`. The CONTAINER
# dir is ignored (not a per-issue `<n>` leaf), so the rule stays correct
# regardless of how the worktree leaf is named.
WORKTREE_IGNORE_PATH="${ISSUE_WORKTREE_IGNORE_PATH:-.claude/worktrees/}"
WORKTREE_IGNORE_COMMENT="# issue per-issue git worktrees (ephemeral — never commit)"
# Readiness gate before typing the prompt (issue #67). Two independent tiers, so
# a single Claude-Code footer-copy change can no longer false-negative readiness:
#
#   1. FAST PATH — a broadened, version-tolerant footer marker (READY_PATTERN).
#      An ALTERNATION of known idle-footer variants, matched with `grep -E`. Kept
#      deliberately metacharacter-free (an ERE `+`/`(`/`)` would silently mis-match
#      literal footer text like `shift+tab`) and mode-agnostic (`mode on` covers
#      both `plan mode on` — this dispatch runs in plan mode — and `auto mode on`).
#      `for shortcuts` is retained for back-compat with older builds. BUSY markers
#      (`esc to interrupt`) and the startup splash (`Welcome to Claude`) are
#      deliberately NOT here — they don't mean "idle and ready for input".
#   2. STRUCTURAL PATH — when NO footer variant matches (full future copy drift),
#      fall back to a copy-agnostic signal: the input-box frame rule (READY_FRAME_
#      GLYPH `─`) AND the idle prompt glyph (READY_PROMPT_GLYPH `❯`) are both
#      present AND the pane has STABILISED (byte-identical for READY_STABLE_POLLS
#      consecutive comparisons). The `❯` requirement stops a static framed *modal*
#      (e.g. the fresh-worktree "trust this folder?" dialog, which also draws `─`)
#      from being mistaken for the idle input box. Both glyphs are matched with
#      `grep -F` (literal bytes) so they're locale-independent and never touch the ERE.
#
# The blind READY_FALLBACK_DELAY remains ONLY as a last resort after both tiers
# exhaust the poll budget.
READY_PATTERN="${ISSUE_READY_PATTERN:-for shortcuts|for agents|mode on|to cycle}"
# ~15s ceiling (60 × 0.25s). The fast path short-circuits success immediately, so
# a larger ceiling only costs time in the genuine-failure case (better tolerating a
# fresh-worktree build + this repo's heavy SessionStart). Not doubled to 80: that
# would push worst-case FAILURE latency toward a ~20s silent hang.
READY_ATTEMPTS="${ISSUE_READY_ATTEMPTS:-60}"
READY_DELAY="${ISSUE_READY_DELAY:-0.25}"
READY_FALLBACK_DELAY="${ISSUE_READY_FALLBACK_DELAY:-3}"
# Structural-path knobs. READY_STABLE_POLLS is a count of consecutive EQUAL
# comparisons, so 3 == four identical captures in a row (N comparisons need N+1
# samples). READY_FRAME_GLYPH / READY_PROMPT_GLYPH are matched literally (grep -F).
READY_STABLE_POLLS="${ISSUE_READY_STABLE_POLLS:-3}"
READY_FRAME_GLYPH="${ISSUE_READY_FRAME_GLYPH:-─}"
READY_PROMPT_GLYPH="${ISSUE_READY_PROMPT_GLYPH:-❯}"
# Pane tail attached to a warning result as diagnostic evidence (issue #67): the
# last N non-blank lines of the pane, so the caller can triage without switching
# windows. Only ever emitted on the warning path — the success payload stays clean.
READY_TAIL_LINES="${ISSUE_READY_TAIL_LINES:-8}"
# Prompt-submission confirm/resend bounds (freshen semantics).
CONFIRM_ATTEMPTS="${ISSUE_CONFIRM_ATTEMPTS:-8}"
CONFIRM_DELAY="${ISSUE_CONFIRM_DELAY:-0.3}"
SEND_RETRIES="${ISSUE_SEND_RETRIES:-2}"
# Non-gating post-submit ACCEPTANCE marker (issue #67, direction #2). After the
# structural "text left the input line" confirmation, a bounded look for one of
# these tokens records whether a READY TUI actually consumed the prompt (vs. it
# scrolling off into, say, a modal). This is a version-specific string, so it only
# INFORMS (a `prompt_accepted` boolean) — it NEVER flips prompt_confirmed to false
# or triggers a resend (that would resurrect the very cry-wolf warning #67 fixes).
READY_ACCEPT_PATTERN="${ISSUE_READY_ACCEPT_PATTERN:-esc to interrupt|Thinking|Crunching|tokens|to interrupt}"
# `doctor` subcommand (issue #67, direction #5): a throwaway readiness self-test.
# Its launch OMITS `-w` (no worktree, no git side effect) — it only needs the TUI
# to render. Overridable so tests can point it at a harmless stand-in binary.
DOCTOR_LAUNCH_TPL="${ISSUE_DOCTOR_LAUNCH_CMD:-claude --permission-mode plan}"
DOCTOR_WINDOW_NAME="${ISSUE_DOCTOR_WINDOW_NAME:-hi-doctor}"
DRY_RUN="${ISSUE_DRY_RUN:-}"
ALLOW_CLOSED="${ISSUE_ALLOW_CLOSED:-}"

# ---- JSON emitters ----------------------------------------------------------
# fail <message> — emit {ok:false, display} and exit non-zero. The skill halts
# and shows `display`.
fail() {
  jq -n --arg d "$1" '{ok:false, display:$d}'
  exit 1
}

# refuse <reason> <message> — a GUARD rejection: {ok:false, reason, display} +
# non-zero exit. Distinct from fail() so callers can tell a guard veto (e.g. a
# protected branch) from an ordinary error. Modelled on reconcile-pr.sh.
refuse() {
  jq -n --arg r "$1" --arg d "$2" '{ok:false, reason:$r, display:$d}'
  exit 1
}

# ---- helpers ----------------------------------------------------------------
render_template() {  # render_template <template> <number> [<name>]
  # <n>    -> the issue number
  # <name> -> the resolved window/worktree name (wname); empty when not passed.
  local tpl="$1" n="$2" name="${3:-}"
  tpl="${tpl//<name>/$name}"
  printf '%s' "${tpl//<n>/$n}"
}

# repo_prefix <owner/repo> — the first 3 alphanumerics of the repo name,
# lowercased (e.g. "agentics" -> "age"). The window/worktree naming stem.
repo_prefix() {
  printf '%s' "${1##*/}" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:upper:]' '[:lower:]'
}

# resolve_wname <n> <owner/repo> — the window/worktree name for issue <n>:
# the ISSUE_WINDOW_NAME override if set, else "<repo-prefix>-<n>" (e.g. age-42).
# Shared by dispatch (to name the window/worktree it creates) and complete (to
# find the worktree/branch to clean up), so both agree on the name.
resolve_wname() {
  local n="$1" repo="$2"
  if [ -n "$WINDOW_NAME_TPL" ]; then
    render_template "$WINDOW_NAME_TPL" "$n"
  else
    printf '%s-%s' "$(repo_prefix "$repo")" "$n"
  fi
}

# ---- git-safety helpers (used by `complete`) --------------------------------
# default_branch — the repo's default branch NAME (no "origin/"), from
# origin/HEAD, falling back to "main". NEVER a valid delete target.
default_branch() {
  local ref
  ref=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) || ref=""
  if [ -n "$ref" ]; then printf '%s' "${ref##*/}"; else printf 'main'; fi
}

# is_protected_branch <branch> — true for the default branch, main/master, or any
# glob in ISSUE_PROTECTED_BRANCHES (space-separated). These are never deleted.
is_protected_branch() {
  local b="$1" d extra g
  d=$(default_branch)
  case "$b" in "$d"|main|master) return 0 ;; esac
  for g in ${ISSUE_PROTECTED_BRANCHES:-}; do
    case "$b" in $g) return 0 ;; esac
  done
  return 1
}

# local_branch_exists <branch>
local_branch_exists() { git show-ref --verify --quiet "refs/heads/$1"; }

# remote_branch_exists <branch>
remote_branch_exists() { [ -n "$(git ls-remote --heads origin "$1" 2>/dev/null)" ]; }

# branch_is_merged <branch> <base> — true iff <branch> is fully merged into
# <base> (a local branch or, failing that, origin/<base>). If neither base ref
# exists, returns FALSE — the safe default: an un-comparable branch is NOT
# considered merged, so it is never auto-deleted.
branch_is_merged() {
  local branch="$1" base="$2" baseref=""
  if   git show-ref --verify --quiet "refs/heads/$base";          then baseref="$base"
  elif git show-ref --verify --quiet "refs/remotes/origin/$base"; then baseref="origin/$base"
  else return 1
  fi
  git branch --merged "$baseref" 2>/dev/null | sed 's/^[*+ ]*//' | grep -qxF "$branch"
}

# collect_targets <n> <repo> — READ-ONLY. Emit TSV describing every cleanup
# candidate for issue <n>, one per line, so both `complete plan` (display) and
# `complete execute` (act) work from the same scan:
#   WT<TAB>removable|current|locked|dirty<TAB><path><TAB><branch>
#   BR<TAB>local|remote<TAB>deletable|unmerged|protected<TAB><branch>
# Worktrees are matched by basename == the resolved wname OR the legacy bare <n>.
# Branch candidates: the worktree branches (worktree-<wname>, worktree-<n>) and
# the head branch of every MERGED PR that closed the issue. Identical rows are
# de-duplicated (a worktree branch that is also a closing PR's head would appear
# via both paths); branch_is_merged is deterministic, so any dup is an exact line.
collect_targets() {
  _collect_targets_raw "$@" | awk '!seen[$0]++'
}
_collect_targets_raw() {
  local n="$1" repo="$2" wname default cur
  wname=$(resolve_wname "$n" "$repo")
  default=$(default_branch)
  cur=$(git rev-parse --show-toplevel 2>/dev/null || printf '')

  # --- worktrees (awk flattens the porcelain blocks to path<TAB>branch<TAB>locked) ---
  # awk emits path<TAB>branch<TAB>locked. `branch` is "-" when a worktree is
  # detached (empty) — a placeholder, NOT an empty field: `read` with IFS=$'\t'
  # collapses adjacent tabs (tab is whitespace to `read`), which would otherwise
  # merge an empty branch into its neighbours and lose the `locked` flag.
  local wt_path wt_branch wt_locked base status
  while IFS=$'\t' read -r wt_path wt_branch wt_locked; do
    [ -n "$wt_path" ] || continue
    [ "$wt_branch" = "-" ] && wt_branch=""
    base="${wt_path##*/}"
    [ "$base" = "$wname" ] || [ "$base" = "$n" ] || continue
    if   [ "$wt_path" = "$cur" ];                                            then status=current
    elif [ "$wt_locked" = "1" ];                                            then status=locked
    elif [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ];      then status=dirty
    else                                                                         status=removable
    fi
    printf 'WT\t%s\t%s\t%s\n' "$status" "$wt_path" "$wt_branch"
  done < <(git worktree list --porcelain 2>/dev/null | awk '
    function flush() { if (p!="") print p"\t"(b==""?"-":b)"\t"l }
    /^worktree /  { flush(); p=substr($0,10); b=""; l=0 }
    /^branch /    { b=$0; sub(/^branch refs\/heads\//,"",b) }
    /^locked/     { l=1 }
    END           { flush() }')

  # --- worktree branches (local only; these are never pushed as PR heads) ---
  local b
  for b in "worktree-$wname" "worktree-$n"; do
    local_branch_exists "$b" || continue
    if branch_is_merged "$b" "$default"; then
      printf 'BR\tlocal\tdeletable\t%s\n' "$b"
    else
      printf 'BR\tlocal\tunmerged\t%s\n' "$b"
    fi
  done

  # --- head branches of MERGED PRs that closed the issue ---
  local prs pr head prj st
  prs=$("$GH" issue view "$n" --repo "$repo" --json closedByPullRequestsReferences 2>/dev/null \
          | jq -r '.closedByPullRequestsReferences[]?.number' 2>/dev/null || printf '')
  for pr in $prs; do
    prj=$("$GH" pr view "$pr" --repo "$repo" --json state,headRefName 2>/dev/null) || continue
    st=$(printf '%s' "$prj" | jq -r '.state // ""')
    head=$(printf '%s' "$prj" | jq -r '.headRefName // ""')
    [ "$st" = "MERGED" ] && [ -n "$head" ] || continue
    if local_branch_exists "$head"; then
      if branch_is_merged "$head" "$default"; then
        printf 'BR\tlocal\tdeletable\t%s\n' "$head"
      else
        printf 'BR\tlocal\tunmerged\t%s\n' "$head"
      fi
    fi
    if remote_branch_exists "$head"; then
      if is_protected_branch "$head"; then
        printf 'BR\tremote\tprotected\t%s\n' "$head"
      else
        printf 'BR\tremote\tdeletable\t%s\n' "$head"
      fi
    fi
  done
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

# wait_ready <pane> <launch-cmd> — poll until Claude's TUI is ready, bounded by
# READY_ATTEMPTS. Two tiers (see the config block for the full rationale):
#   FAST:       launch_gone AND content matches the READY_PATTERN footer marker.
#   STRUCTURAL: launch_gone AND content has BOTH the frame rule and the idle
#               prompt glyph AND has stabilised (byte-identical for
#               READY_STABLE_POLLS consecutive comparisons).
# Either tier satisfied → success. On success, WAIT_READY_TIER is set to the tier
# that matched ("marker" | "structural") for callers (doctor) that want it; a
# timeout leaves it "none".
#
# launch_gone = "the pane's last non-blank line no longer ends with the launch
# command", i.e. the typed launch command has left the input line (claude started).
WAIT_READY_TIER="none"
wait_ready() {
  local pane="$1" launch="$2" attempt=0 content last_line
  local prev='' stable=0 launch_gone
  WAIT_READY_TIER="none"
  while [ "$attempt" -lt "$READY_ATTEMPTS" ]; do
    if content=$(tmux capture-pane -p -t "$pane" 2>/dev/null); then
      last_line=$(printf '%s\n' "$content" | grep -v '^[[:space:]]*$' | tail -1 || true)
      launch_gone=false
      if [[ "$last_line" != *"$launch" ]]; then launch_gone=true; fi

      # Tier 1 — broadened footer marker (returns immediately; no stabilise wait).
      if [ "$launch_gone" = true ] \
         && printf '%s' "$content" | grep -Eq -- "$READY_PATTERN"; then
        WAIT_READY_TIER="marker"
        return 0
      fi

      # Tier 2 — structural frame + idle glyph + stabilisation. Increment the
      # stable counter ONLY when all structural preconditions hold AND this
      # capture is byte-identical to the previous one; any change (or a missing
      # precondition) resets it. `prev` starts empty, so the first identical pair
      # is the first comparison that can count.
      if [ "$launch_gone" = true ] \
         && printf '%s' "$content" | grep -qF -- "$READY_FRAME_GLYPH" \
         && printf '%s' "$content" | grep -qF -- "$READY_PROMPT_GLYPH" \
         && [ -n "$content" ] && [ "$content" = "$prev" ]; then
        stable=$((stable + 1))
        if [ "$stable" -ge "$READY_STABLE_POLLS" ]; then
          WAIT_READY_TIER="structural"
          return 0
        fi
      else
        stable=0
      fi
      prev="$content"
    else
      # Couldn't observe the pane — don't let a stale `prev` fake a stable streak.
      stable=0
      prev=''
    fi
    sleep "$READY_DELAY"
    attempt=$((attempt + 1))
  done
  return 1
}

# pane_tail <pane> — READ-ONLY. Echo the last READY_TAIL_LINES non-blank lines of
# the pane, for attaching to a warning result as diagnostic evidence (issue #67).
# A failed capture echoes nothing (an empty tail is an acceptable degrade).
pane_tail() {
  local pane="$1" content
  content=$(tmux capture-pane -p -t "$pane" 2>/dev/null) || return 0
  printf '%s\n' "$content" | grep -v '^[[:space:]]*$' | tail -n "$READY_TAIL_LINES" || true
}

# prompt_accepted <pane> — READ-ONLY, NON-GATING. Best-effort check that a READY
# TUI consumed the just-submitted prompt: either a working/thinking indicator
# rendered (READY_ACCEPT_PATTERN) or the idle prompt glyph sits on an otherwise
# cleared input row. Returns 0 (accepted) / 1 (unconfirmed). Callers record the
# result as signal only — it must NEVER flip prompt_confirmed or trigger a resend.
prompt_accepted() {
  local pane="$1" content last_line
  content=$(tmux capture-pane -p -t "$pane" 2>/dev/null) || return 1
  if printf '%s' "$content" | grep -Eq -- "$READY_ACCEPT_PATTERN"; then
    return 0
  fi
  # Idle input row: the last non-blank line is just the prompt glyph (no trailing
  # user text), i.e. the input box cleared and re-rendered its empty prompt.
  last_line=$(printf '%s\n' "$content" | grep -v '^[[:space:]]*$' | tail -1 || true)
  case "$last_line" in
    *"$READY_PROMPT_GLYPH") return 0 ;;
    *) return 1 ;;
  esac
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

# worktree_ignore_status <dir> — READ-ONLY. Echo "already-ignored" when a git
# ignore rule already covers the worktree dir — the exact rule OR a broader one
# such as `.claude/` — else "not-ignored". `git check-ignore -q` returns 0 when a
# path is ignored and 1 when it is not; 1 is a legitimate answer here, NOT an
# error, so the call MUST be wrapped in `if` (a bare invocation would trip the
# `set -e` at the top of this script). check-ignore reads ignore files only
# (independent of HEAD/index), so it works in a fresh repo with no commits and no
# .gitignore. Probe a child path so a directory rule (trailing `/`) matches.
worktree_ignore_status() {
  local dir="$1" base
  base="${WORKTREE_IGNORE_PATH%/}"
  if git -C "$dir" check-ignore -q "$base/probe" 2>/dev/null; then
    printf 'already-ignored'
  else
    printf 'not-ignored'
  fi
}

# append_worktree_ignore <dir> — idempotent, BEST-EFFORT write of the worktree
# ignore rule to <dir>/.gitignore. Mirrors the canonical pattern in
# plugins/atlas/bin/atlas-cli (trailing-newline fix, blank separator, comment,
# rule). Echoes "added" on success, "already-ignored" if the exact rule is
# already present, or "add-failed" on any write error — and NEVER aborts the
# caller (a failure degrades the dispatch to the pre-fix status quo, an untracked
# worktree dir, not a hard failure).
append_worktree_ignore() {
  local dir="$1" gi base rule lead=""
  gi="$dir/.gitignore"
  base="${WORKTREE_IGNORE_PATH%/}"
  rule="$base/"
  # Self-idempotent exact-line guard. The caller already gates on check-ignore
  # (which also honors a broader rule); this keeps the writer safe on its own.
  if [ -f "$gi" ] && grep -qxF "$rule" "$gi" 2>/dev/null; then
    printf 'already-ignored'
    return 0
  fi
  if [ -s "$gi" ]; then
    # Terminate an unterminated final line first ($(...) strips the trailing
    # newline, so a non-empty last byte means the file does NOT end in one)...
    [ -n "$(tail -c1 "$gi" 2>/dev/null)" ] && lead=$'\n'
    # ...then add a blank separator only when the last line is non-blank.
    [ -n "$(tail -n1 "$gi" 2>/dev/null)" ] && lead="${lead}"$'\n'
  fi
  { printf '%s%s\n%s\n' "$lead" "$WORKTREE_IGNORE_COMMENT" "$rule" >>"$gi"; } 2>/dev/null \
    && printf 'added' || printf 'add-failed'
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
        else ("[issue] " + (length | tostring) + " open issue(s) on " + $repo)
        end
      )
    }'
}

# ---- subcommand: view -------------------------------------------------------
# view <n> — READ-ONLY. Render issue <n>'s full content (gh's native plaintext,
# including comments) into `display` and stop. Also emits structured
# {ok, issue, title, state, url} for callers that want the fields. No side
# effects; the skill simply prints `display`.
cmd_view() {
  local n="${1:-}"
  [ -n "$n" ] || fail "usage: issue.sh view <issue-number>"
  [[ "$n" =~ ^[0-9]+$ ]] || fail "issue number must be a positive integer (got: $n)."
  require_gh
  local repo meta title state url body
  repo=$(origin_owner_repo) || fail "no GitHub origin remote found (git remote get-url origin)."
  # Structured metadata first, so a missing issue fails cleanly with ok:false.
  if ! meta=$("$GH" issue view "$n" --repo "$repo" \
                --json number,title,state,url 2>/dev/null); then
    fail "issue #$n not found on $repo."
  fi
  title=$(printf '%s' "$meta" | jq -r '.title // ""')
  state=$(printf '%s' "$meta" | jq -r '.state // ""')
  url=$(printf '%s' "$meta" | jq -r '.url // ""')
  # Human-readable body via gh's native rendering (plaintext in a non-TTY),
  # including comments. Best-effort: if it fails after metadata succeeded, fall
  # back to a minimal one-liner rather than a hard fail.
  body=$("$GH" issue view "$n" --repo "$repo" --comments 2>/dev/null || printf '')
  [ -n "$body" ] || body="#$n — $title [$state]"$'\n'"$url"
  jq -n --arg issue "$n" --arg title "$title" --arg state "$state" \
        --arg url "$url" --arg display "$body" '
    {ok:true, issue:($issue|tonumber), title:$title, state:$state, url:$url, display:$display}'
}

# ---- subcommand: create -----------------------------------------------------
# create --title <t> [--body-file <path> | --body <text>] [--label <csv>]
#   Files a NEW issue via `gh issue create`, parses the assigned number from the
#   printed URL, and emits {ok, number, url, title, display}. The body is passed
#   by FILE by default (the `new` flow writes drafted markdown to a temp file) so
#   multi-line content never has to survive shell/tmux escaping. ISSUE_DRY_RUN=1
#   prints the planned command and files nothing.
cmd_create() {
  local title="" body_file="" body="" labels="" have_body=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --title)     title="${2:-}"; shift 2 ;;
      --body-file) body_file="${2:-}"; have_body=1; shift 2 ;;
      --body)      body="${2:-}"; have_body=1; shift 2 ;;
      --label)     labels="${2:-}"; shift 2 ;;
      *) fail "create: unknown argument '$1' (usage: create --title <t> [--body-file <p>|--body <t>] [--label <csv>])" ;;
    esac
  done
  [ -n "$title" ] || fail "create: --title is required."
  if [ -n "$body_file" ] && [ ! -f "$body_file" ]; then
    fail "create: --body-file '$body_file' does not exist."
  fi
  require_gh
  local repo
  repo=$(origin_owner_repo) || fail "no GitHub origin remote found (git remote get-url origin)."

  # Assemble gh args. --body-file wins over --body; an omitted body still passes
  # an explicit empty --body so gh never opens an interactive editor.
  local args=(issue create --repo "$repo" --title "$title")
  if [ -n "$body_file" ]; then
    args+=(--body-file "$body_file")
  elif [ -n "$have_body" ]; then
    args+=(--body "$body")
  else
    args+=(--body "")
  fi
  [ -n "$labels" ] && args+=(--label "$labels")

  if [ -n "$DRY_RUN" ]; then
    jq -n --arg repo "$repo" --arg title "$title" \
          --arg bf "$body_file" --arg labels "$labels" '
      {ok:true, dry_run:true, repo:$repo, title:$title,
       command:("gh issue create --repo " + $repo + " --title " + $title
                + (if $bf == "" then " --body <inline>" else " --body-file " + $bf end)
                + (if $labels == "" then "" else " --label " + $labels end)),
       display:("[issue] DRY RUN: would file \"" + $title + "\" on " + $repo + ".")}'
    return 0
  fi

  local out url num
  if ! out=$("$GH" "${args[@]}" 2>&1); then
    fail "gh issue create failed: $(printf '%s' "$out" | tail -n 2)"
  fi
  # gh prints the new issue's URL; recover the number from its trailing segment.
  url=$(printf '%s\n' "$out" | grep -Eo 'https?://[^ ]*/issues/[0-9]+' | tail -n1)
  [ -n "$url" ] || fail "gh issue create returned no issue URL (got: $(printf '%s' "$out" | tail -n1))."
  num="${url##*/}"
  jq -n --arg num "$num" --arg url "$url" --arg title "$title" '
    {ok:true, number:($num|tonumber), url:$url, title:$title,
     display:("[issue] Filed #" + $num + " — " + $title + "\n" + $url)}'
}

# ---- subcommand: dispatch ---------------------------------------------------
cmd_dispatch() {
  local n="${1:-}"
  [ -n "$n" ] || fail "usage: issue.sh dispatch <issue-number>"
  [[ "$n" =~ ^[0-9]+$ ]] || fail "issue number must be a positive integer (got: $n)."

  # launch_cmd/prompt are rendered AFTER wname is resolved (below), since the
  # default launch command interpolates <name> = wname.
  local launch_cmd prompt

  # Step 1: tmux precondition (relaxed under dry-run so it runs headlessly).
  if [ -z "$DRY_RUN" ]; then
    [ -n "${TMUX:-}" ] || fail "issue requires tmux — run Claude inside a tmux session."
    [ -n "${TMUX_PANE:-}" ] || fail "issue requires \$TMUX_PANE — run Claude inside a tmux pane."
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
    fail "issue #$n is closed on $repo (set ISSUE_ALLOW_CLOSED=1 to dispatch anyway)."
  fi

  # Compute the name used for BOTH the tmux window and the git worktree:
  # "<repo-prefix>-<n>" (e.g. "age-42"), or the ISSUE_WINDOW_NAME override. Shared
  # with `complete`, which resolves the same name to find what to clean up.
  local wname
  wname=$(resolve_wname "$n" "$repo")

  # Render launch/prompt now that wname is known. The default launch command
  # resolves <name> -> wname, so `claude -w <name>` names the worktree the same
  # as the window. (A pathological override yielding an empty prefix would make
  # wname start with "-", producing a leading-dash launch arg — see WINDOW_NAME_TPL.)
  launch_cmd=$(render_template "$LAUNCH_TPL" "$n" "$wname")
  prompt=$(render_template "$PROMPT_TPL" "$n" "$wname")

  # Read-only: is the per-issue worktree dir already gitignored (issue #55)?
  # Computed here so both the dry-run preview and the real write can report it.
  local ignore_status
  ignore_status=$(worktree_ignore_status "$dir")

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
      --arg ignore_status "$ignore_status" \
      --arg detach "$detach" '
      {
        ok: true, dry_run: true,
        issue: ($issue | tonumber), title: $title, repo: $repo, dir: $dir,
        window_name: $wname, label: $label,
        gitignore: (if $ignore_status == "already-ignored" then "already-ignored" else "would-add" end),
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
        display: ("[issue] DRY RUN for #" + $issue + " (" + $title
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
  # with ISSUE_FOREGROUND=1. Keystrokes below target $pane by id regardless.
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

  # Step 5.5: idempotently gitignore the per-issue worktree dir (issue #55) so
  # `claude -w` (Step 6, which actually creates .claude/worktrees/<n>) doesn't
  # dirty the parent repo's `git status`. Best-effort — a write failure NEVER
  # flips dispatch to ok:false (worst case is the pre-fix status quo). Runs AFTER
  # the window opens (so `tmux new-window` stays the "first side effect") but
  # before the worktree materializes.
  local gitignore_result="already-ignored"
  if [ "$ignore_status" = "not-ignored" ]; then
    gitignore_result=$(append_worktree_ignore "$dir")
  fi

  # Step 6: launch claude (literal mode — the space/flag must not be key-interpreted).
  tmux send-keys -t "$pane" -l "$launch_cmd" 2>/dev/null || true
  tmux send-keys -t "$pane" Enter 2>/dev/null || true

  # Step 7: readiness gate before typing the prompt (claude -w also builds the
  # worktree before its TUI renders, so this wait matters). Two-tier (marker or
  # structural — see wait_ready); on total miss we settle a fixed amount and
  # proceed best-effort. Plan mode itself needs no gate: it's set by the
  # --permission-mode plan launch flag.
  local readiness_confirmed=false
  if wait_ready "$pane" "$launch_cmd"; then
    readiness_confirmed=true
  else
    sleep "$READY_FALLBACK_DELAY"
  fi

  # Step 8: type + submit the prompt, confirmed (structural: the text left the
  # input line). Then a NON-GATING acceptance observation — did a ready TUI
  # actually consume it (working indicator / cleared input row)? This only informs
  # `prompt_accepted`; it never changes prompt_confirmed or re-sends (issue #67).
  local prompt_confirmed=false prompt_accepted=false
  if send_prompt_confirmed "$pane" "$prompt"; then
    prompt_confirmed=true
    if prompt_accepted "$pane"; then
      prompt_accepted=true
    fi
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
    base="[issue] #$n ($title) → opened tmux window \`$wname\`, launched \`$launch_cmd\` (plan mode), submitted the prompt${label_ok_note}."
  else
    if [ "$readiness_confirmed" = false ] && [ "$prompt_confirmed" = false ]; then
      warning="Couldn't confirm claude finished starting, nor that the prompt submitted — check window \`$wname\`."
    elif [ "$readiness_confirmed" = false ]; then
      warning="Couldn't confirm claude finished starting before the prompt was sent, but the prompt did submit — glance at window \`$wname\`."
    else
      warning="claude started, but couldn't confirm the prompt submitted — check window \`$wname\`."
    fi
    base="[issue] #$n ($title) → window \`$wname\` opened, but I couldn't fully confirm the handoff."
  fi

  # Fold a label failure into the warning (best-effort — never ok:false).
  if [ -n "$label_note" ]; then
    warning="${warning:+$warning }$label_note."
  fi

  # On the warning path only, capture a pane tail as diagnostic evidence (issue
  # #67, direction #4). Captured AFTER the send attempts, so it reflects whether
  # the prompt landed. Kept off the success payload so that stays byte-stable.
  local tail_evidence=""
  if [ -n "$warning" ]; then
    display="$base $warning"
    tail_evidence=$(pane_tail "$pane")
  else
    display="$base"
  fi

  jq -n \
    --arg issue "$n" --arg title "$title" --arg window "$window" --arg wname "$wname" \
    --arg pane "$pane" --arg label "$LABEL" --arg gitignore "$gitignore_result" \
    --argjson ready "$readiness_confirmed" --argjson pconf "$prompt_confirmed" \
    --argjson paccept "$prompt_accepted" \
    --argjson lapplied "$label_applied" \
    --arg warning "$warning" --arg tail "$tail_evidence" --arg display "$display" '
    {
      ok: true,
      issue: ($issue | tonumber), title: $title,
      window: $window, window_name: $wname, pane: $pane,
      readiness_confirmed: $ready, prompt_confirmed: $pconf, prompt_accepted: $paccept,
      label: $label, label_applied: $lapplied, gitignore: $gitignore
    }
    + (if $warning == "" then {} else {warning: $warning} end)
    + (if $tail == "" then {} else {pane_tail: $tail} end)
    + {display: $display}'
}

# ---- subcommand: doctor -----------------------------------------------------
# doctor — drift self-test for the readiness gate (issue #67, direction #5).
# Spins a throwaway claude in a scratch DETACHED tmux window, waits via
# wait_ready, reports which tier matched (marker | structural | none), then tears
# the window down. Purely diagnostic: no GitHub calls, no labeling, no worktree
# (the scratch launch omits `-w`). Deliberately NOT part of `make test` — it needs
# a live claude, and the pre-push gate must stay deterministic/offline. Run it by
# hand after a Claude Code upgrade to confirm the default READY_PATTERN still matches.
cmd_doctor() {
  # tmux precondition (relaxed under dry-run so it runs headlessly).
  if [ -z "$DRY_RUN" ]; then
    [ -n "${TMUX:-}" ] || fail "issue doctor requires tmux — run Claude inside a tmux session."
    [ -n "${TMUX_PANE:-}" ] || fail "issue doctor requires \$TMUX_PANE — run Claude inside a tmux pane."
  fi

  # The launch binary (first word of the launch template) must be on PATH.
  local doctor_bin="${DOCTOR_LAUNCH_TPL%% *}"
  command -v "$doctor_bin" >/dev/null 2>&1 \
    || fail "launch binary '$doctor_bin' not found on PATH (set ISSUE_DOCTOR_LAUNCH_CMD)."

  # Dry-run: emit the planned commands and stop before any side effect.
  if [ -n "$DRY_RUN" ]; then
    jq -n --arg launch "$DOCTOR_LAUNCH_TPL" --arg wname "$DOCTOR_WINDOW_NAME" '
      {
        ok: true, dry_run: true, window_name: $wname,
        commands: [
          ("tmux new-window -d -n " + $wname + " -P -F #{pane_id}"),
          ("tmux send-keys -t <pane> -l " + $launch),
          "tmux send-keys -t <pane> Enter",
          "tmux kill-window -t <window>"
        ],
        display: ("[issue] DRY RUN doctor: would spin a throwaway `" + $launch
                  + "` in window " + $wname + ", check readiness, and tear it down.")
      }'
    return 0
  fi

  # Open a scratch DETACHED window (never steals focus).
  local pane window
  if ! pane=$(tmux new-window -d -n "$DOCTOR_WINDOW_NAME" -P -F '#{pane_id}' 2>/dev/null) || [ -z "$pane" ]; then
    fail "failed to open a scratch tmux window for the readiness self-test."
  fi
  window=$(tmux display-message -p -t "$pane" '#{window_id}' 2>/dev/null || printf '')

  # Launch (literal mode) and gate on readiness.
  tmux send-keys -t "$pane" -l "$DOCTOR_LAUNCH_TPL" 2>/dev/null || true
  tmux send-keys -t "$pane" Enter 2>/dev/null || true

  local readiness_confirmed=false tier="none" tail_evidence
  if wait_ready "$pane" "$DOCTOR_LAUNCH_TPL"; then
    readiness_confirmed=true
  fi
  tier="$WAIT_READY_TIER"
  tail_evidence=$(pane_tail "$pane")

  # Tear down the scratch window (best-effort — a failure never flips ok).
  if [ -n "$window" ]; then
    tmux kill-window -t "$window" 2>/dev/null || true
  else
    tmux kill-window -t "$pane" 2>/dev/null || true
  fi

  local display
  if [ "$readiness_confirmed" = true ]; then
    display="[issue] doctor: readiness OK via the '$tier' tier — the installed Claude build is recognised."
  else
    display="[issue] doctor: readiness NOT confirmed within the poll budget — the readiness marker may have drifted. See pane_tail."
  fi

  jq -n \
    --argjson ready "$readiness_confirmed" --arg tier "$tier" \
    --arg tail "$tail_evidence" --arg display "$display" '
    {
      ok: true,
      readiness_confirmed: $ready,
      matched_tier: $tier
    }
    + (if $tail == "" then {} else {pane_tail: $tail} end)
    + {display: $display}'
}

# ---- subcommand: complete ---------------------------------------------------
# complete <plan|execute> <n> — close issue <n> as completed and clean up its
# artifacts. Two-phase (like `semver bump`): `plan` is READ-ONLY and previews
# exactly what `execute` would do; the skill shows the preview, asks ONE
# confirmation, then runs `execute`. Guard rails live entirely here (never the
# LLM): only removable worktrees and fully-merged branches are ever touched;
# current/locked/dirty worktrees and unmerged/protected branches are skipped and
# reported.

# complete_issue_state <n> <repo> — echo the issue's state (OPEN/CLOSED) or fail
# if the issue doesn't exist. Sets the caller's REPO_STATE via stdout.
complete_issue_state() {
  local n="$1" repo="$2" meta
  if ! meta=$("$GH" issue view "$n" --repo "$repo" --json number,state 2>/dev/null); then
    fail "issue #$n not found on $repo."
  fi
  printf '%s' "$meta" | jq -r '.state // "OPEN"'
}

# cmd_complete_plan <n> — READ-ONLY preview. Emits the structured plan + a
# human-readable `display`. Deletes nothing.
cmd_complete_plan() {
  local n="${1:-}"
  [ -n "$n" ] || fail "usage: issue.sh complete plan <issue-number>"
  [[ "$n" =~ ^[0-9]+$ ]] || fail "issue number must be a positive integer (got: $n)."
  require_gh
  git rev-parse --show-toplevel >/dev/null 2>&1 || fail "not inside a git repository."
  local repo state default targets rows_json
  repo=$(origin_owner_repo) || fail "no GitHub origin remote found (git remote get-url origin)."
  state=$(complete_issue_state "$n" "$repo")
  default=$(default_branch)
  targets=$(collect_targets "$n" "$repo")
  rows_json=$(printf '%s' "$targets" | jq -R -s 'split("\n") | map(select(length>0) | split("\t"))')

  jq -n --argjson rows "$rows_json" --arg n "$n" --arg state "$state" --arg default "$default" '
    ($rows | map(select(.[0]=="WT"))) as $wt |
    ($rows | map(select(.[0]=="BR"))) as $br |
    {
      ok: true, issue: ($n|tonumber), state: $state, default_branch: $default,
      plan: {
        close: ($state=="OPEN"),
        worktrees: {
          removable: [ $wt[] | select(.[1]=="removable") | {path:.[2], branch:.[3]} ],
          skipped:   [ $wt[] | select(.[1]!="removable") | {path:.[2], branch:.[3], reason:.[1]} ]
        },
        branches: {
          local_deletable:  [ $br[] | select(.[1]=="local"  and .[2]=="deletable") | .[3] ],
          remote_deletable: [ $br[] | select(.[1]=="remote" and .[2]=="deletable") | .[3] ],
          skipped:          [ $br[] | select(.[2]!="deletable") | {scope:.[1], branch:.[3], reason:.[2]} ]
        }
      }
    }
    | .actions_count = ((.plan.worktrees.removable|length)
                        + (.plan.branches.local_deletable|length)
                        + (.plan.branches.remote_deletable|length)
                        + (if .plan.close then 1 else 0 end))
    | .display = (
        "[issue] complete #\($n)"
        + (if .plan.close then " — will CLOSE as completed." else " — already \($state|ascii_downcase)." end)
        + "\n"
        + ( [ (.plan.worktrees.removable[]  | "  remove worktree  \(.path)")
            , (.plan.branches.local_deletable[]  | "  delete branch    \(.) (local, merged)")
            , (.plan.branches.remote_deletable[] | "  delete branch    \(.) (remote, merged PR)")
            ] as $do
            | if ($do|length) > 0 then "Will:\n" + ($do|join("\n")) + "\n" else "Nothing to remove.\n" end )
        + ( [ (.plan.worktrees.skipped[] | "  keep worktree    \(.path) (\(.reason))")
            , (.plan.branches.skipped[]  | "  keep branch      \(.branch) (\(.scope), \(.reason))")
            ] as $skip
            | if ($skip|length) > 0 then "Skipped (preserved):\n" + ($skip|join("\n")) else "" end )
      )'
}

# cmd_complete_execute <n> [--no-close] — DESTRUCTIVE. Closes the issue (unless
# --no-close / already closed) and removes exactly the removable worktrees and
# merged branches the plan identified. ISSUE_DRY_RUN=1 records the commands and
# performs no side effect.
cmd_complete_execute() {
  local n="" no_close=""
  local no_clean=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-close) no_close=1; shift ;;
      --no-clean) no_clean=1; shift ;;   # close only: skip all deletions
      *) [ -z "$n" ] && n="$1" && shift || fail "complete execute: unexpected argument '$1'." ;;
    esac
  done
  [ -n "$n" ] || fail "usage: issue.sh complete execute <issue-number> [--no-close] [--no-clean]"
  [[ "$n" =~ ^[0-9]+$ ]] || fail "issue number must be a positive integer (got: $n)."
  require_gh
  git rev-parse --show-toplevel >/dev/null 2>&1 || fail "not inside a git repository."
  local repo state default targets
  repo=$(origin_owner_repo) || fail "no GitHub origin remote found (git remote get-url origin)."
  state=$(complete_issue_state "$n" "$repo")
  default=$(default_branch)
  targets=$(collect_targets "$n" "$repo")

  local -a commands=() removed_wt=() removed_bl=() removed_br=() failed=()
  local closed=false close_note=""

  # 1) Close the issue as completed (unless opted out or already closed).
  if [ -z "$no_close" ] && [ "$state" = "OPEN" ]; then
    if [ -n "$DRY_RUN" ]; then
      commands+=("gh issue close $n --repo $repo --reason completed")
      closed=true
    elif "$GH" issue close "$n" --repo "$repo" --reason completed >/dev/null 2>&1; then
      closed=true
    else
      close_note="couldn't close #$n (check gh permissions)"
    fi
  fi

  # 2) Act on the scanned targets (skipped entirely under --no-clean / "close
  #    only"). Every deletion has a git-native backstop: `worktree remove` (no
  #    --force) refuses dirty/current; `branch -d` refuses unmerged. A
  #    protected/default branch can never reach here (filtered out).
  local kind a b c
  if [ -z "$no_clean" ]; then
  while IFS=$'\t' read -r kind a b c; do
    case "$kind" in
      WT)  # a=status b=path c=branch
        [ "$a" = "removable" ] || continue
        if [ -n "$DRY_RUN" ]; then
          commands+=("git worktree remove $b" "git worktree prune")
          removed_wt+=("$b")
        elif git worktree remove "$b" >/dev/null 2>&1; then
          git worktree prune >/dev/null 2>&1 || true
          removed_wt+=("$b")
        else
          failed+=("worktree:$b")
        fi ;;
      BR)  # a=scope b=status c=branch
        [ "$b" = "deletable" ] || continue
        # Belt-and-suspenders: never delete a protected/default branch even if a
        # future scan bug mislabels it.
        if is_protected_branch "$c"; then failed+=("branch:$c(protected)"); continue; fi
        if [ "$a" = "local" ]; then
          if [ -n "$DRY_RUN" ]; then
            commands+=("git branch -d $c"); removed_bl+=("$c")
          elif git branch -d "$c" >/dev/null 2>&1; then
            removed_bl+=("$c")
          else
            failed+=("branch:$c(local)")
          fi
        else  # remote
          if [ -n "$DRY_RUN" ]; then
            commands+=("git push origin --delete $c"); removed_br+=("$c")
          elif git -c url."https://github.com/".insteadOf="git@github.com:" \
                 push origin --delete "$c" >/dev/null 2>&1; then
            removed_br+=("$c")
          else
            failed+=("branch:$c(remote)")
          fi
        fi ;;
    esac
  done <<EOF
$targets
EOF
  fi

  # Skipped (preserved) items, re-derived from the scan for the report.
  local skipped_json
  skipped_json=$(printf '%s' "$targets" | jq -R -s '
    split("\n") | map(select(length>0) | split("\t"))
    | [ (.[] | select(.[0]=="WT" and .[1]!="removable") | {kind:"worktree", ref:.[2], reason:.[1]})
      , (.[] | select(.[0]=="BR" and .[2]!="deletable") | {kind:"branch", ref:.[3], reason:(.[1]+", "+.[2])}) ]')

  # Assemble JSON arrays from the bash arrays.
  local rwt rbl rbr fail_json
  rwt=$(printf '%s\n' "${removed_wt[@]:-}" | jq -R -s 'split("\n")|map(select(length>0))')
  rbl=$(printf '%s\n' "${removed_bl[@]:-}" | jq -R -s 'split("\n")|map(select(length>0))')
  rbr=$(printf '%s\n' "${removed_br[@]:-}" | jq -R -s 'split("\n")|map(select(length>0))')
  fail_json=$(printf '%s\n' "${failed[@]:-}" | jq -R -s 'split("\n")|map(select(length>0))')
  local cmds_json='[]'
  if [ -n "$DRY_RUN" ]; then
    cmds_json=$(printf '%s\n' "${commands[@]:-}" | jq -R -s 'split("\n")|map(select(length>0))')
  fi

  jq -n --arg n "$n" --arg repo "$repo" --argjson closed "$closed" \
        --arg close_note "$close_note" \
        --argjson rwt "$rwt" --argjson rbl "$rbl" --argjson rbr "$rbr" \
        --argjson failed "$fail_json" --argjson skipped "$skipped_json" \
        --argjson cmds "$cmds_json" --argjson dry "$([ -n "$DRY_RUN" ] && echo true || echo false)" \
        --argjson no_clean "$([ -n "$no_clean" ] && echo true || echo false)" '
    {
      ok: true, issue: ($n|tonumber), closed: $closed,
      removed: { worktrees: $rwt, branches_local: $rbl, branches_remote: $rbr },
      skipped: $skipped
    }
    + (if $no_clean then {cleanup:"skipped"} else {} end)
    + (if ($failed|length) > 0 then {failed:$failed} else {} end)
    + (if $dry then {dry_run:true, commands:$cmds} else {} end)
    + { display: (
        "[issue] complete #\($n): "
        + (if $dry then "DRY RUN — " else "" end)
        + (if $closed then "closed as completed" else "left open" end)
        + (if $no_clean then "; cleanup skipped (close only)."
           else "; removed "
                + (($rwt|length)|tostring) + " worktree(s), "
                + ((($rbl|length)+($rbr|length))|tostring) + " branch(es)." end)
        + (if $close_note != "" then "\n" + $close_note + "." else "" end)
        + (if ($failed|length) > 0 then "\nCould not: " + ($failed|join(", ")) + "." else "" end)
        + (if ($skipped|length) > 0 then "\nPreserved: "
             + ([$skipped[] | "\(.ref) (\(.reason))"]|join("; ")) + "." else "" end)
      ) }'
}

cmd_complete() {
  local sub="${1:-}"
  shift 2>/dev/null || true
  case "$sub" in
    plan)    cmd_complete_plan "$@" ;;
    execute) cmd_complete_execute "$@" ;;
    *)       fail "usage: issue.sh complete <plan|execute> <issue-number>" ;;
  esac
}

# ---- router -----------------------------------------------------------------
case "${1:-}" in
  list)     shift; cmd_list "$@" ;;
  dispatch) shift; cmd_dispatch "$@" ;;
  view)     shift; cmd_view "$@" ;;
  create)   shift; cmd_create "$@" ;;
  complete) shift; cmd_complete "$@" ;;
  doctor)   shift; cmd_doctor "$@" ;;
  *)        fail "usage: issue.sh <list | dispatch <n> | view <n> | create --title <t> [--body-file <p>] | complete <plan|execute> <n> | doctor>" ;;
esac
