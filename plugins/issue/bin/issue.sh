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
#   dispatch <n>         Fetch origin/<default> (best-effort — see the
#                        base-freshness tiers below, issue #107), create a NEW
#                        git worktree at .claude/worktrees/<name> on branch
#                        worktree-<name> based on that fresh tip, open a new tmux
#                        window (named "<repo-prefix>-<n>", e.g. "age-42") rooted
#                        IN that worktree — DETACHED by default so the caller's
#                        focus stays put — launch plain `claude --permission-mode
#                        plan --model opusplan` (no `-w`: dispatch already
#                        created the worktree itself, so new work always starts
#                        from the latest origin tip rather than the checkout's
#                        possibly-stale local HEAD; --permission-mode plan starts
#                        the session in plan mode deterministically, no
#                        keystrokes; --model opusplan runs Opus while planning
#                        and Sonnet once executing, issue #97), gate on claude
#                        becoming ready, then type + submit the prompt. The
#                        worktree is left UNLOCKED (unlike claude -w's own
#                        worktrees) so `complete` can reclaim it later.
#
# Base-freshness tiers (issue #107 — `do` must always build new work on the
# latest origin tip, never a stale local branch a daemon-managed repo never
# pulls): FRESH (the fetch above succeeded and origin/<default> resolves) →
# base_fresh:true, no warning. CACHED (the fetch failed but a PRIOR
# origin/<default> ref already exists) → base_fresh:false + a warning naming the
# cached OID — still based on origin, just possibly a poll behind. HEAD-FALLBACK
# (origin/<default> has never resolved at all — offline AND never fetched) →
# base_fresh:false + a loud warning that the freshness guarantee was NOT met;
# ISSUE_REQUIRE_FRESH_BASE=1 turns this tier into a hard {ok:false} instead of a
# warning, for callers that need the guarantee enforced rather than reported.
#
# ok-vs-warning boundary (dispatch): steps 0–4 are HARD preconditions — a failure
# emits {ok:false} and exits before ANY side effect. Step 5 (gitignore) is
# best-effort and never fails. Step 6 (fetch + resolve base) degrades through the
# three freshness tiers above rather than failing, UNLESS ISSUE_REQUIRE_FRESH_BASE
# is set (HEAD-fallback then hard-fails) or no base commit can be resolved at all
# (fully offline + unborn HEAD). Steps 7–8 (worktree creation, then the tmux
# window) are HARD FAILS — but unlike the pre-#107 flow, a window-open failure now
# rolls back the just-created worktree/branch (step 7 ran first this time), so a
# failed dispatch still leaves no litter. From step 9 (launch) onward the window
# already exists, so a failure to confirm readiness or prompt submission degrades
# to {ok:true, warning, ...} rather than ok:false — reporting ok:false there would
# falsely imply nothing happened.
#
# The `.gitignore` write for the per-issue worktree dir (issue #55) is a
# best-effort, idempotent hygiene write that runs BEFORE the worktree is created
# (moved earlier by issue #107 — it used to run after the window opened, back
# when `claude -w` created the worktree instead of dispatch itself) — the
# untracked worktree dir must never dirty `git status`, even transiently. It can
# never flip ok to false (a failure just reports gitignore:"add-failed").
#
# All timing/behaviour is env-overridable (see the config block) so the flow is
# testable headlessly (ISSUE_DRY_RUN, ISSUE_GH_BIN) and the
# launch command / prompt are escape-hatchable without editing code.
#
# tmux send/confirm logic is modelled on plugins/freshen/lib/pane-confirm.sh
# (literal paste + capture-pane read-back), hardened for issue #82 into a
# two-phase, input-row-scoped handoff: paste + settle, confirm RECEIPT (the box
# holds text), Enter, confirm SUBMISSION (the box cleared), re-sending Enter ALONE
# (never re-pasting) on the bracketed-paste Enter-absorption race. It is INLINED
# here rather than sourced because freshen may not be installed alongside this
# plugin.
set -euo pipefail

# Shared tmux/worktree/pane-readiness mechanics (window/worktree naming,
# git-safety helpers, the readiness gate, confirmed-send) live in
# lib/session.sh — provider-agnostic, and also used by the storyhook
# story.sh actuator. See that file's header for its external-variable
# contract with the config block immediately below.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/session.sh"

# ---- config (all env-overridable) -------------------------------------------
GH="${ISSUE_GH_BIN:-gh}"
LIST_LIMIT="${ISSUE_LIST_LIMIT:-50}"
# Launch command, run INSIDE the worktree dispatch already created (see
# cmd_dispatch) — so it must NOT include `-w`/`--worktree`: that flag would try
# to create ANOTHER worktree at the path <name> names, colliding with the one
# dispatch just made (issue #107). <name> still renders to the resolved
# window/worktree name and <n> to the issue number, for a custom override that
# wants either (e.g. folding the name into a system prompt).
LAUNCH_TPL="${ISSUE_LAUNCH_CMD:-claude --permission-mode plan --model opusplan}"
# The handoff prompt is the ONLY lever the dispatcher has over the child session,
# which is what actually plans, implements, and opens PRs. So it carries the
# briefs the child can't get any other way: read the issue AND all its comments
# for the full history, treat a reopen as a signal a previous fix fell short
# (issue #78), the GitHub self-reporting contract (issue #50) — comment the
# finalized plan, word PRs to close the issue, comment PR links — and a directive
# NOT to bump the version or deploy from its worktree (those happen later from
# `main`), since this session always runs inside a per-issue worktree. The default
# is single-line + ASCII (no backticks) for readability, but delivery is via a
# bracketed paste (paste_prompt), so a multi-line ISSUE_PROMPT override is safe —
# an embedded newline stays text and the whole prompt submits as one message
# (issue #87), not at the first line.
PROMPT_TPL="${ISSUE_PROMPT:-Investigate and plan a fix for GitHub issue #<n> in this repo. Begin by reading the issue and ALL of its comments (e.g. gh issue view <n> --comments) so you have the full discussion history. If the issue has been reopened, treat that as a signal that a previous fix was insufficient: review the earlier attempts and any linked PRs, understand why they fell short, and make sure your plan resolves the underlying problem rather than repeating them. When your plan is finalized and approved, post the full plan as a Markdown comment on issue #<n> using gh before you start implementing. Ensure every pull request you open closes the issue by including \"Closes #<n>\" in its body, and comment a link to each PR on issue #<n> after you push it. Do not bump the version or deploy from this worktree: do not run semver bump, deployit deploy, or any release/version step, and do not plan for them -- versioning and deployment happen later from the main branch, not here.}"
# Extra clause a caller appends to the handoff prompt (daemon-caller seam).
# Appended VERBATIM with a single space separator, AFTER <n>/<name> templating
# of the base prompt — the extra itself undergoes NO substitution. Like
# PROMPT_TPL, keep it single-line + ASCII (no backticks): tmux send-keys -l
# types it into the child session literally. Empty/unset leaves the prompt
# byte-identical to the PROMPT_TPL rendering.
PROMPT_EXTRA="${ISSUE_PROMPT_EXTRA:-}"
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
# to override in full; supports the <n> placeholder. cmd_dispatch derives BOTH
# the worktree path (.claude/worktrees/<wname>) and branch (worktree-<wname>)
# from this resolved name, so overriding it renames the worktree too.
WINDOW_NAME_TPL="${ISSUE_WINDOW_NAME:-}"
# Focus policy: the new window is created DETACHED (-d) by default so the user's
# focus stays on their current window. Every follow-up send-keys/capture-pane
# targets the new pane by its captured id (not "the current window"), so the
# handoff still lands in the right window without stealing focus. Set
# ISSUE_FOREGROUND=1 to switch focus to the new window instead.
FOREGROUND="${ISSUE_FOREGROUND:-}"
# Target tmux session for the dispatch window (daemon-caller seam). Default
# (empty) opens the window in the CALLER'S current session, which is why the
# $TMUX/$TMUX_PANE hard preconditions exist. When set (e.g. "moshtail"),
# `tmux new-window` gains `-t "<session>:"` (trailing colon = the session as a
# whole, so tmux picks the next free window index) and those preconditions are
# SKIPPED — the caller may be a daemon outside tmux entirely. Safe because
# every follow-up send-keys/capture-pane already targets the new pane by its
# captured id, which is server-global, never "the current window".
TARGET_SESSION="${ISSUE_TARGET_SESSION:-}"
# Per-issue git-worktree hygiene (issue #55) AND the worktree container itself
# (issue #107: dispatch now creates each worktree directly under this path via
# `git worktree add`, rather than delegating to `claude -w`). Dispatch
# idempotently ensures the path is gitignored — BEFORE creating the worktree —
# so it never dirties the parent repo's `git status`. The CONTAINER dir is
# ignored (not a per-issue `<n>` leaf), so the rule stays correct regardless of
# how the worktree leaf is named.
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
# Both tiers above are gated by a THIRD, independent check before either can
# succeed (AGE-83, porting storyhook's SH-226): the pane's foreground command
# — a fact from the process table, not from rendered characters — must match
# READY_PROCESS_PATTERN. A shell prompt can supply a frame rule and an idle
# glyph for free; it cannot supply a process table entry named `claude`. On a
# miss, dispatch now REFUSES outright rather than typing the prompt anyway —
# see cmd_dispatch's own Step 10 comment for why "warn and proceed" stopped
# being a safe default.
READY_PATTERN="${ISSUE_READY_PATTERN:-for shortcuts|for agents|mode on|to cycle}"
# ~15s ceiling (60 × 0.25s). The fast path short-circuits success immediately, so
# a larger ceiling only costs time in the genuine-failure case (better tolerating a
# fresh-worktree build + this repo's heavy SessionStart). Not doubled to 80: that
# would push worst-case FAILURE latency toward a ~20s silent hang.
READY_ATTEMPTS="${ISSUE_READY_ATTEMPTS:-60}"
READY_DELAY="${ISSUE_READY_DELAY:-0.25}"
# Structural-path knobs. READY_STABLE_POLLS is a count of consecutive EQUAL
# comparisons, so 3 == four identical captures in a row (N comparisons need N+1
# samples). READY_FRAME_GLYPH / READY_PROMPT_GLYPH are matched literally (grep -F).
READY_STABLE_POLLS="${ISSUE_READY_STABLE_POLLS:-3}"
READY_FRAME_GLYPH="${ISSUE_READY_FRAME_GLYPH:-─}"
READY_PROMPT_GLYPH="${ISSUE_READY_PROMPT_GLYPH:-❯}"
# The pane's foreground command must be the launch binary before ANY text is
# delivered to it (AGE-83, porting storyhook's SH-226). `node` is here because
# Claude Code installs as a Node wrapper on some paths and tmux reports the
# foreground process; excluding it would refuse real sessions. It still
# excludes every shell, which is the discrimination the failure needs.
# Heuristic, and deliberately overridable: setting this to `.` matches
# anything and restores the pre-fix behaviour with no code change — the
# escape hatch for an environment where Claude reports an unexpected name.
READY_PROCESS_PATTERN="${ISSUE_READY_PROCESS_PATTERN:-^(claude|node)$}"
# Pane tail attached to a warning result as diagnostic evidence (issue #67): the
# last N non-blank lines of the pane, so the caller can triage without switching
# windows. Only ever emitted on the warning path — the success payload stays clean.
READY_TAIL_LINES="${ISSUE_READY_TAIL_LINES:-8}"
# Prompt-submission confirm/resend bounds. CONFIRM_ATTEMPTS/_DELAY bound BOTH the
# receipt poll (the paste landed in the input box) and the submit poll (the box
# cleared); SEND_RETRIES bounds BOTH the receipt re-paste AND the submit re-Enter
# (issue #82). Reusing CONFIRM_DELAY means a test that zeroes it also zeroes the
# receipt poll with no extra plumbing.
CONFIRM_ATTEMPTS="${ISSUE_CONFIRM_ATTEMPTS:-8}"
CONFIRM_DELAY="${ISSUE_CONFIRM_DELAY:-0.3}"
SEND_RETRIES="${ISSUE_SEND_RETRIES:-2}"
# Settle after each literal paste, BEFORE Enter, so a bracketed paste closes and
# the Enter is read as "submit" rather than absorbed as a newline into the still-
# settling paste buffer (issue #82 — the primary cure). Fractional; BSD + GNU
# sleep compatible. Tests zero it.
PASTE_SETTLE_DELAY="${ISSUE_PASTE_SETTLE_DELAY:-0.2}"
# Non-gating post-submit ACCEPTANCE marker (issue #67, direction #2). After the
# structural "text left the input line" confirmation, a bounded look for one of
# these tokens records whether a READY TUI actually consumed the prompt (vs. it
# scrolling off into, say, a modal). This is a version-specific string, so it only
# INFORMS (a `prompt_accepted` boolean) — it NEVER flips prompt_confirmed to false
# or triggers a resend (that would resurrect the very cry-wolf warning #67 fixes).
READY_ACCEPT_PATTERN="${ISSUE_READY_ACCEPT_PATTERN:-esc to interrupt|Thinking|Crunching|tokens|to interrupt}"
# `doctor` subcommand (issue #67, direction #5): a throwaway readiness self-test.
# Its launch creates NO worktree/git side effect (dispatch now creates the
# worktree itself via `git worktree add` before launching claude, issue #107) —
# doctor just needs the TUI to render in the current directory — but otherwise
# mirrors the dispatch launch flags, so a flag a future claude rejects at
# startup fails here first, not in a real dispatch (issue #97). Overridable so
# tests can point it at a harmless stand-in binary.
DOCTOR_LAUNCH_TPL="${ISSUE_DOCTOR_LAUNCH_CMD:-claude --permission-mode plan --model opusplan}"
DOCTOR_WINDOW_NAME="${ISSUE_DOCTOR_WINDOW_NAME:-hi-doctor}"
# `capture` subcommand (issue #87 live-verification aid): how many rendered rows of
# a worktree window's scrollback to dump. Enough to show the recent exchange
# without unbounded output.
CAPTURE_LINES="${ISSUE_CAPTURE_LINES:-200}"
DRY_RUN="${ISSUE_DRY_RUN:-}"
ALLOW_CLOSED="${ISSUE_ALLOW_CLOSED:-}"
# issue #107: when set, a HEAD-fallback base (origin/<default> never resolvable —
# offline AND never fetched) hard-fails dispatch instead of warning-and-proceeding
# — for callers that must enforce the "always built on the latest origin tip"
# guarantee rather than merely have it reported.
REQUIRE_FRESH_BASE="${ISSUE_REQUIRE_FRESH_BASE:-}"

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

# dispatch_ready_note — one clause naming WHY the readiness check gave up, from
# the globals wait_ready sets. A timeout and "a shell is sitting in that pane"
# are different situations with different remedies, and the operator needs to
# be told which. Added AGE-83, porting storyhook's SH-226.
dispatch_ready_note() {
  case "$WAIT_READY_REASON" in
    wrong-process)
      printf 'that pane is running `%s`, not a process matching `%s` — the launch never started. Set ISSUE_READY_PROCESS_PATTERN if your claude reports a different name; `.` matches anything' \
        "${WAIT_READY_COMMAND:-?}" "$READY_PROCESS_PATTERN"
      ;;
    *)
      if [ -n "$WAIT_READY_COMMAND" ]; then
        printf 'timed out waiting for it to render; the pane is running `%s`' "$WAIT_READY_COMMAND"
      else
        printf 'timed out waiting for it to render, and the pane occupant could not be observed'
      fi
      ;;
  esac
}

# ---- subcommand: dispatch ---------------------------------------------------
cmd_dispatch() {
  local n="${1:-}"
  [ -n "$n" ] || fail "usage: issue.sh dispatch <issue-number>"
  [[ "$n" =~ ^[0-9]+$ ]] || fail "issue number must be a positive integer (got: $n)."

  # launch_cmd/prompt are rendered AFTER wname is resolved (below), since the
  # default launch command interpolates <name> = wname.
  local launch_cmd prompt

  # Step 1: tmux precondition (relaxed under dry-run so it runs headlessly, and
  # under ISSUE_TARGET_SESSION — a daemon caller outside tmux dispatches into a
  # NAMED session, so its own tmux context is irrelevant).
  if [ -z "$DRY_RUN" ] && [ -z "$TARGET_SESSION" ]; then
    [ -n "${TMUX:-}" ] || fail "issue requires tmux — run Claude inside a tmux session."
    [ -n "${TMUX_PANE:-}" ] || fail "issue requires \$TMUX_PANE — run Claude inside a tmux pane."
  fi

  # Step 2: repo dir (worktree creation below needs a git-tracked location).
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

  # Compute the name used for the tmux window, the worktree dir leaf, AND the
  # worktree branch: "<repo-prefix>-<n>" (e.g. "age-42"), or the
  # ISSUE_WINDOW_NAME override. Shared with `complete`, which resolves the same
  # name to find what to clean up.
  local wname default wt_container worktree_path worktree_branch
  wname=$(resolve_wname "$n" "$repo")
  default=$(default_branch)
  wt_container="${WORKTREE_IGNORE_PATH%/}"
  worktree_path="$dir/$wt_container/$wname"
  worktree_branch="worktree-$wname"

  # Render launch/prompt now that wname is known (issue #107: the default launch
  # no longer takes <name> — see LAUNCH_TPL — but a custom override may still).
  launch_cmd=$(render_template "$LAUNCH_TPL" "$n" "$wname")
  prompt=$(render_template "$PROMPT_TPL" "$n" "$wname")
  # Caller clause (PROMPT_EXTRA): appended verbatim after templating, so the
  # extra never undergoes <n>/<name> substitution. Single-space separator.
  [ -n "$PROMPT_EXTRA" ] && prompt="$prompt $PROMPT_EXTRA"

  # Read-only: is the per-issue worktree dir already gitignored (issue #55)?
  # Computed here so both the dry-run preview and the real write can report it.
  local ignore_status
  ignore_status=$(worktree_ignore_status "$dir")

  # Detached by default (keeps the caller's focus); "-d " unless FOREGROUND is set.
  # Kept in sync with the real new-window invocation in Step 8 below.
  local detach="-d "
  [ -n "$FOREGROUND" ] && detach=""

  # Session target: "-t <session>: " when ISSUE_TARGET_SESSION is set, else "".
  # Kept in sync with the real new-window invocation in Step 8 below.
  local target=""
  [ -n "$TARGET_SESSION" ] && target="-t $TARGET_SESSION: "

  # Dry-run: all read-only checks above ran for real; emit the planned commands
  # SYMBOLICALLY (no fetch, no OID resolution, no HEAD touch — a dry-run repo may
  # have an unborn HEAD or an unfetched origin) and stop before any side effect.
  if [ -n "$DRY_RUN" ]; then
    jq -n \
      --arg issue "$n" --arg title "$title" --arg repo "$repo" --arg dir "$dir" \
      --arg wname "$wname" --arg launch "$launch_cmd" --arg prompt "$prompt" \
      --arg label "$LABEL" --arg color "$LABEL_COLOR" --arg desc "$LABEL_DESC" \
      --arg ignore_status "$ignore_status" \
      --arg detach "$detach" --arg target "$target" \
      --arg default "$default" --arg wtpath "$worktree_path" --arg wtbranch "$worktree_branch" '
      {
        ok: true, dry_run: true,
        issue: ($issue | tonumber), title: $title, repo: $repo, dir: $dir,
        window_name: $wname, label: $label, prompt: $prompt,
        base_branch: $default, base_ref: ("origin/" + $default),
        worktree_branch: $wtbranch, worktree_path: $wtpath,
        gitignore: (if $ignore_status == "already-ignored" then "already-ignored" else "would-add" end),
        commands: ([
          ("git fetch --quiet origin +refs/heads/" + $default + ":refs/remotes/origin/" + $default),
          ("git worktree add --no-track -b " + $wtbranch + " " + $wtpath + " origin/" + $default),
          ("tmux new-window " + $target + $detach + "-c " + $wtpath + " -n " + $wname + " -P -F #{pane_id}"),
          ("tmux send-keys -t <pane> -l " + $launch),
          "tmux send-keys -t <pane> Enter",
          ("printf %s " + $prompt + " | tmux load-buffer -b issue-" + $issue + " -"),
          ("tmux paste-buffer -p -d -b issue-" + $issue + " -t <pane>"),
          "tmux send-keys -t <pane> Enter"
        ] + (if $label == "" then [] else [
          ("gh label create " + $label + " --repo " + $repo + " --color " + $color
           + " --description " + $desc),
          ("gh issue edit " + $issue + " --repo " + $repo + " --add-label " + $label)
        ] end)),
        display: ("[issue] DRY RUN for #" + $issue + " (" + $title
                  + "): would fetch " + ("origin/" + $default) + ", create worktree "
                  + $wtpath + " (branch " + $wtbranch + "), open a new tmux window named "
                  + $wname
                  + (if $label == "" then "" else ", mark the issue " + $label end)
                  + " and run the listed commands.")
      }'
    return 0
  fi

  # Step 5: idempotently gitignore the per-issue worktree CONTAINER dir (issue
  # #55), BEFORE the worktree materializes (issue #107 moved this earlier — it
  # used to run after the window opened, back when `claude -w` created the
  # worktree; now dispatch creates it directly, so the untracked dir must never
  # dirty `git status` even transiently). Best-effort — a write failure NEVER
  # flips dispatch to ok:false (worst case is the pre-#55 status quo) and is
  # never rolled back (idempotent/harmless either way).
  local gitignore_result="already-ignored"
  if [ "$ignore_status" = "not-ignored" ]; then
    gitignore_result=$(append_worktree_ignore "$dir")
  fi

  # Step 6: fetch origin/<default> (best-effort, quiet — the freshen_base_ref
  # idiom used by `complete`, rc-checked here) and resolve the commit the new
  # worktree will be based on. Three tiers (issue #107 — see the header comment
  # for the full rationale): FRESH (fetch ok + ref resolves), CACHED (fetch
  # failed but a prior origin/<default> ref exists), HEAD-FALLBACK (origin/
  # <default> has never resolved — offline and never fetched). All git calls are
  # fully quieted so stray output can't corrupt the final JSON payload.
  local fetch_rc=0
  git fetch --quiet origin "+refs/heads/$default:refs/remotes/origin/$default" \
    >/dev/null 2>&1 || fetch_rc=$?

  local base_oid="" base_fresh=false base_note=""
  if base_oid=$(git rev-parse --verify --quiet "refs/remotes/origin/$default^{commit}" 2>/dev/null) \
     && [ -n "$base_oid" ]; then
    if [ "$fetch_rc" -eq 0 ]; then
      base_fresh=true
    else
      base_note="couldn't refresh origin/$default (offline?); based on last-known origin/$default @ ${base_oid:0:8}"
    fi
  elif base_oid=$(git rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null) && [ -n "$base_oid" ]; then
    base_note="could not determine origin/$default; new work is based on the local checkout, NOT the latest origin tip"
    if [ -n "$REQUIRE_FRESH_BASE" ]; then
      fail "could not determine a fresh origin/$default and ISSUE_REQUIRE_FRESH_BASE is set — refusing to dispatch on a possibly-stale base."
    fi
  else
    fail "cannot resolve a base commit for the new worktree (no origin/$default and HEAD has no commits)."
  fi

  # Step 7: create the worktree off the resolved base commit — the first
  # genuinely irreversible side effect, so a precise pre-check first. Left
  # UNLOCKED, deliberately DIVERGING from claude -w's own (locked) worktrees:
  # `complete`'s collect_targets skips locked worktrees with no unlock step, so a
  # locked worktree here would never be reclaimed once the session ends —
  # unlocked lets `complete` reap it via its existing `removable` path.
  if git show-ref --verify --quiet "refs/heads/$worktree_branch" || [ -e "$worktree_path" ]; then
    fail "a worktree or branch for \`$wname\` already exists — already dispatched? Clean it up first with \`/issue complete $n\`."
  fi
  local wt_err
  if ! wt_err=$(git worktree add --no-track -b "$worktree_branch" "$worktree_path" "$base_oid" 2>&1); then
    fail "failed to create worktree at $worktree_path: $(printf '%s' "$wt_err" | tail -n 2)"
  fi

  # Step 8: open the window (rooted IN the new worktree, not the repo root).
  # Unlike the pre-#107 flow, the worktree now exists BEFORE this step — a
  # failure here rolls back the worktree/branch so a failed dispatch still
  # leaves no litter.
  local new_window_args pane window
  new_window_args=(-c "$worktree_path" -n "$wname" -P -F '#{pane_id}')
  # Detached by default so the caller's focus stays put; opt in to focus-follow
  # with ISSUE_FOREGROUND=1. Keystrokes below target $pane by id regardless.
  [ -z "$FOREGROUND" ] && new_window_args=(-d "${new_window_args[@]}")
  # Open in the named target session when set (daemon-caller seam). Prepended so
  # the flag order matches the dry-run command string above.
  [ -n "$TARGET_SESSION" ] && new_window_args=(-t "$TARGET_SESSION:" "${new_window_args[@]}")
  if ! pane=$(tmux new-window "${new_window_args[@]}" 2>/dev/null) || [ -z "$pane" ]; then
    git worktree remove --force "$worktree_path" >/dev/null 2>&1 || true
    git worktree prune >/dev/null 2>&1 || true
    git branch -D "$worktree_branch" >/dev/null 2>&1 || true
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

  # Step 9: launch claude (literal mode — the space/flag must not be
  # key-interpreted). The worktree already exists (Step 7), so the default
  # launch omits `-w` entirely (issue #107) — an override MUST NOT reintroduce it
  # (see LAUNCH_TPL above). Route through paste_text so the same settle guards
  # the launch's own Enter against the bracketed-paste race (issue #82).
  paste_text "$pane" "$launch_cmd" || true
  tmux send-keys -t "$pane" Enter 2>/dev/null || true

  # Step 10: readiness GATE before typing the prompt (AGE-83, porting
  # storyhook's SH-226). This GATES — it used to only warn-and-proceed on a
  # miss. An unconfirmed pane gets no text at all: even this plugin's
  # ATTENDED prompt is a substantial block of instructions, and typing it
  # into whatever a mis-detected pane actually holds is not a safe default.
  # The window is deliberately left standing — it is the only place the
  # launch failure's own words survive — while the worktree and branch are
  # rolled back so an immediate retry is not answered with "already
  # dispatched?" (the worktree/branch collision check keys on this same path).
  if ! wait_ready "$pane" "$launch_cmd"; then
    local ready_tail
    ready_tail=$(pane_tail "$pane")
    git worktree remove --force "$worktree_path" >/dev/null 2>&1 || true
    git worktree prune >/dev/null 2>&1 || true
    git branch -D "$worktree_branch" >/dev/null 2>&1 || true
    refuse_with pane-not-ready \
      "[issue] #$n → could not confirm claude is running in window \`$wname\` ($(dispatch_ready_note)). Nothing was typed into that pane. The window is left open so you can look at it; the worktree and branch were rolled back." \
      "$(jq -n --arg issue "$n" --arg window "$window" --arg wname "$wname" \
            --arg pane "$pane" --arg cmd "$WAIT_READY_COMMAND" \
            --arg wreason "$WAIT_READY_REASON" --arg tail "$ready_tail" \
            --arg pattern "$READY_PROCESS_PATTERN" \
            '{issue:($issue|tonumber), window:$window, window_name:$wname, pane:$pane,
              readiness_confirmed:false, pane_command:$cmd,
              wait_ready_reason:$wreason, ready_process_pattern:$pattern,
              pane_tail:$tail}')"
  fi
  local readiness_confirmed=true

  # Step 11: type + submit the prompt, confirmed (structural: the text left the
  # input line). Then a NON-GATING acceptance observation — did a ready TUI
  # actually consume it (working indicator / cleared input row)? This only informs
  # `prompt_accepted`; it never changes prompt_confirmed or re-sends (issue #67).
  local prompt_confirmed=false prompt_accepted=false
  if send_prompt_confirmed "$pane" "$prompt" "issue-$n"; then
    prompt_confirmed=true
    if prompt_accepted "$pane"; then
      prompt_accepted=true
    fi
  fi

  # Step 12: mark the issue in-progress on GitHub (issue #50). Done last so the
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

  # Result. ok:true from here on — readiness is always confirmed by this point
  # (Step 10 refuses otherwise); warn only on an unconfirmed prompt submission
  # (or a base that isn't fresh, issue #107).
  local warning="" display base
  if [ "$prompt_confirmed" = true ]; then
    base="[issue] #$n ($title) → opened tmux window \`$wname\` on a worktree based on \`origin/$default\` @ \`${base_oid:0:8}\`, launched \`$launch_cmd\` (plan mode), submitted the prompt${label_ok_note}."
  else
    warning="claude started, but couldn't confirm the prompt submitted — check window \`$wname\`."
    base="[issue] #$n ($title) → window \`$wname\` opened on a worktree based on \`origin/$default\` @ \`${base_oid:0:8}\`, but I couldn't fully confirm the handoff."
  fi

  # Fold a non-fresh base (issue #107) and a label failure into the warning
  # (both best-effort — never ok:false).
  if [ -n "$base_note" ]; then
    warning="${warning:+$warning }${base_note}."
  fi
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
    --arg warning "$warning" --arg tail "$tail_evidence" --arg display "$display" \
    --arg default "$default" --arg base_oid "$base_oid" --argjson base_fresh "$base_fresh" \
    --arg wtbranch "$worktree_branch" --arg wtpath "$worktree_path" '
    {
      ok: true,
      issue: ($issue | tonumber), title: $title,
      window: $window, window_name: $wname, pane: $pane,
      readiness_confirmed: $ready, prompt_confirmed: $pconf, prompt_accepted: $paccept,
      label: $label, label_applied: $lapplied, gitignore: $gitignore,
      base_branch: $default, base_ref: ("origin/" + $default),
      base_oid: $base_oid, base_fresh: $base_fresh,
      worktree_branch: $wtbranch, worktree_path: $wtpath
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
          "printf %s <multi-line probe> | tmux load-buffer -b issue-doctor -",
          "tmux paste-buffer -p -d -b issue-doctor -t <pane>",
          "tmux capture-pane -p -t <pane>",
          "tmux kill-window -t <window>"
        ],
        display: ("[issue] DRY RUN doctor: would spin a throwaway `" + $launch
                  + "` in window " + $wname + ", check readiness, paste a multi-line probe "
                  + "to verify bracketed-paste delivery, and tear it down.")
      }'
    return 0
  fi

  # Open a scratch DETACHED window (never steals focus).
  local pane window
  if ! pane=$(tmux new-window -d -n "$DOCTOR_WINDOW_NAME" -P -F '#{pane_id}' 2>/dev/null) || [ -z "$pane" ]; then
    fail "failed to open a scratch tmux window for the readiness self-test."
  fi
  window=$(tmux display-message -p -t "$pane" '#{window_id}' 2>/dev/null || printf '')

  # Launch (literal mode) and gate on readiness. paste_text adds the settle
  # before Enter (issue #82).
  paste_text "$pane" "$DOCTOR_LAUNCH_TPL" || true
  tmux send-keys -t "$pane" Enter 2>/dev/null || true

  local readiness_confirmed=false tier="none" tail_evidence
  if wait_ready "$pane" "$DOCTOR_LAUNCH_TPL"; then
    readiness_confirmed=true
  fi
  tier="$WAIT_READY_TIER"
  tail_evidence=$(pane_tail "$pane")

  # Live multi-line paste probe (issue #87): paste a 3-line marker into the REAL
  # TUI via the bracketed-paste path — WITHOUT submitting — then read the input box
  # back. When the build's bracketed paste works, all three lines land as ONE block
  # and the FIRST line sits on the `❯` input row; had delivery split at a newline,
  # the first line would have submitted and only the last would remain in the box.
  # Purely diagnostic and model-free (never presses Enter); only meaningful once the
  # TUI is ready, so it's skipped otherwise.
  local probe_ran=false probe_first_held=false probe_seen=0 probe_total=3
  if [ "$readiness_confirmed" = true ]; then
    local probe capture box_row marker
    probe=$(printf 'issue87-probe-alpha\nissue87-probe-bravo\nissue87-probe-charlie')
    if paste_prompt "$pane" "$probe" "issue-doctor"; then
      probe_ran=true
      capture=$(tmux capture-pane -p -t "$pane" 2>/dev/null || printf '')
      box_row=$(input_box_text "$capture")
      for marker in issue87-probe-alpha issue87-probe-bravo issue87-probe-charlie; do
        case "$capture" in *"$marker"*) probe_seen=$((probe_seen + 1)) ;; esac
      done
      case "$box_row" in *issue87-probe-alpha*) probe_first_held=true ;; esac
    fi
  fi

  # Tear down the scratch window (best-effort — a failure never flips ok). The
  # probe text is discarded unsubmitted with the window.
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
  if [ "$probe_ran" = true ]; then
    if [ "$probe_first_held" = true ] && [ "$probe_seen" -eq "$probe_total" ]; then
      display="$display Multi-line paste probe: OK — all $probe_total lines held as one un-submitted block."
    else
      display="$display Multi-line paste probe: SUSPECT (first-line-held=$probe_first_held, $probe_seen/$probe_total lines seen) — bracketed paste may not be landing."
    fi
  fi

  jq -n \
    --argjson ready "$readiness_confirmed" --arg tier "$tier" \
    --arg tail "$tail_evidence" --arg display "$display" \
    --argjson probe_ran "$probe_ran" --argjson probe_first "$probe_first_held" \
    --argjson probe_seen "$probe_seen" --argjson probe_total "$probe_total" '
    {
      ok: true,
      readiness_confirmed: $ready,
      matched_tier: $tier
    }
    + (if $probe_ran then {multiline_probe: {first_line_held: $probe_first, lines_seen: $probe_seen, lines_total: $probe_total}} else {} end)
    + (if $tail == "" then {} else {pane_tail: $tail} end)
    + {display: $display}'
}

# ---- subcommand: capture ----------------------------------------------------
# capture <n> — READ-ONLY. Dump the recent rendered transcript of the live tmux
# window for issue <n> (the `<repo-prefix>-<n>` window `do` opened), so you can
# peek at what that worktree session received/did without switching windows — and,
# after dispatching a multi-line prompt, confirm every line landed in the ONE
# submitted message (issue #87 live check). Fragile by nature (the TUI render
# wraps/box-draws), but distinctive per-line markers survive it. No GitHub calls;
# opens/kills nothing.
cmd_capture() {
  if [ -z "$DRY_RUN" ]; then
    [ -n "${TMUX:-}" ] || fail "issue capture requires tmux — run Claude inside a tmux session."
  fi
  local n="${1:-}"
  case "$n" in
    ''|*[!0-9]*) fail "usage: issue.sh capture <issue-number>" ;;
  esac
  local repo wname
  repo=$(origin_owner_repo) || fail "no GitHub origin remote found (git remote get-url origin)."
  wname=$(resolve_wname "$n" "$repo")

  # Dry-run: report the single read-only command it would run and stop.
  if [ -n "$DRY_RUN" ]; then
    jq -n --arg wname "$wname" --arg lines "$CAPTURE_LINES" '
      {
        ok: true, dry_run: true, window_name: $wname,
        commands: [ ("tmux capture-pane -p -t <pane-of " + $wname + "> -S -" + $lines) ],
        display: ("[issue] DRY RUN capture: would dump the last " + $lines
                  + " rendered rows of the window " + $wname + ".")
      }'
    return 0
  fi

  local pane transcript
  pane=$(pane_for_window "$wname")
  [ -n "$pane" ] || fail "no live tmux window named \`$wname\` — dispatch it first with \`/issue do $n\`."
  transcript=$(capture_pane_transcript "$pane") \
    || fail "failed to capture pane \`$pane\` (window \`$wname\`)."

  jq -n --arg wname "$wname" --arg pane "$pane" --arg tx "$transcript" '
    {
      ok: true, window_name: $wname, pane: $pane, transcript: $tx,
      display: ("[issue] capture " + $wname + " (" + $pane + ") — recent rendered rows:\n\n" + $tx)
    }'
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
  # Freshen origin/<default> once so merged-ness is judged against ground truth,
  # not a local <default> that daemon-managed repos never pull (issue #99).
  freshen_base_ref "$default"
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
  # Freshen origin/<default> once so merged-ness (and the -d→-D delete escalation)
  # is judged against ground truth, not a stale local <default> (issue #99).
  freshen_base_ref "$default"
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
          elif delete_merged_local_branch "$c" "$default"; then
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
  capture)  shift; cmd_capture "$@" ;;
  *)        fail "usage: issue.sh <list | dispatch <n> | view <n> | create --title <t> [--body-file <p>] | complete <plan|execute> <n> | doctor | capture <n>>" ;;
esac
