#!/usr/bin/env bash
# reconcile-pr.sh — deterministic state machine for the /reconcile-pr skill.
#
# Rebases a GitHub PR's branch onto the latest tip of its base branch, drives an
# LLM through merge-conflict resolution, verifies with tests, force-pushes the
# reconciled branch under a leased safety guard, and comments on the PR. The
# SKILL is a thin router + judgment loop: the deterministic git/gh mechanics,
# every guard, and the JSON contract live HERE; only conflict resolution,
# behavior verification, and the comment prose are the LLM's.
#
# Every run emits exactly ONE JSON object on stdout with an `ok` boolean and a
# human-readable `display`. On `ok:false` the skill shows `display` and halts.
#
# Subcommands (each takes a positive-integer <pr>):
#   preflight <pr>          Read-only validation + plan. No side effects.
#   start <pr>              Fetch, create an isolated worktree, begin the rebase.
#                           Emits already_current | clean | conflicts.
#   status <pr>             Read-only re-orient (survives a context clear).
#   continue <pr> [--skip]  Advance the rebase after the LLM stages resolutions.
#                           Emits conflicts | clean | empty_after_resolution.
#   test <pr>               Run the suite in the worktree; record the result.
#   push <pr>               THE force-push safety gate (see below).
#   comment <pr> <file>     Post the LLM-authored summary as a PR comment.
#   abort <pr>              Give-up teardown (aborts an in-progress rebase).
#   cleanup <pr>            Success teardown (refuses mid-rebase without --force).
#
# Isolation: all rebase work happens in a dedicated git worktree under
# <repo>/.claude/worktrees/reconcile-pr/<pr>/worktree — the user's own checkout
# is never touched. That path is already gitignored (`.claude/worktrees/`).
# State (meta.json, conflicts.log) lives beside it.
#
# Rebase runs with `-c merge.conflictStyle=zdiff3` so every conflict hunk carries
# the common-ancestor block. During a rebase HEAD/ours = base and theirs = the PR
# commit (INVERTED vs. `git merge`), so this script NEVER speaks "ours/theirs":
# it relabels the two sides `base_side` (pre-existing base behavior to preserve)
# and `pr_side` (this PR's new work, anchored to the replayed commit SHA).
#
# The force-push safety gate (push): NEVER force-pushes a protected branch and
# NEVER uses a bare `git push --force`. It guards the DESTINATION ref (not the
# local branch), pushes `HEAD:refs/heads/<pr-branch>` with an explicit-OID
# `--force-with-lease=refs/heads/<dest>:<recorded-oid>`, and refuses (never
# falling back to --force) if the lease is stale.
#
# All behaviour is env-overridable (see the config block) so the whole flow is
# testable offline against a local bare-repo "origin" with a fake gh.
set -euo pipefail

# ---- config (all env-overridable) -------------------------------------------
GH="${RECONCILE_PR_GH_BIN:-gh}"
DRY_RUN="${RECONCILE_PR_DRY_RUN:-}"
SKIP_PUSH="${RECONCILE_PR_SKIP_PUSH:-}"
TEST_CMD="${RECONCILE_PR_TEST_CMD:-}"
ALLOW_UNTESTED="${RECONCILE_PR_ALLOW_UNTESTED:-}"
# Space-separated globs whose match on the PR head branch blocks a force-push.
PROTECTED_GLOBS="${RECONCILE_PR_PROTECTED_GLOBS:-main master develop staging prod production release/* gh-pages}"
DEFAULT_BRANCH_OVERRIDE="${RECONCILE_PR_DEFAULT_BRANCH:-}"

REPO_ROOT=""  # set by need_repo

# ---- JSON emitters ----------------------------------------------------------
# fail <message> — emit {ok:false, display} and exit non-zero. The skill halts
# and shows `display`.
fail() {
  jq -n --arg d "$1" '{ok:false, display:$d}'
  exit 1
}

# refuse <reason> <message> — a graceful {ok:false, reason, display}. Used for
# guard rejections (protected/untested/stale/…) the skill surfaces by reason.
refuse() {
  jq -n --arg r "$1" --arg d "$2" '{ok:false, reason:$r, display:$d}'
  exit 1
}

# ---- generic helpers --------------------------------------------------------
validate_pr() {  # validate_pr <n>
  [ -n "${1:-}" ] || fail "usage: reconcile-pr.sh <subcommand> <pr-number>"
  [[ "$1" =~ ^[0-9]+$ ]] || fail "PR number must be a positive integer (got: ${1})."
}

need_repo() {
  # Anchor REPO_ROOT to the MAIN worktree (parent of the shared git common dir),
  # independent of CWD. `--show-toplevel` is worktree-relative, so from inside the
  # reconcile worktree it mislocated state_dir and every subcommand reported the
  # reconcile as lost (#108). `--git-common-dir` resolves to <main>/.git from any
  # linked worktree; its dirname is the main repo root where `start` anchors state.
  local common
  common=$(git rev-parse --git-common-dir 2>/dev/null) \
    || fail "not inside a git repository."
  REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$common")" && pwd -P) \
    || fail "could not resolve repository root from git common dir ($common)."
}

require_gh() {
  command -v "$GH" >/dev/null 2>&1 \
    || fail "gh CLI not found — install GitHub CLI (https://cli.github.com)."
  "$GH" auth status >/dev/null 2>&1 \
    || fail "gh is not authenticated — run: gh auth login (or set GH_TOKEN)."
}

# origin_owner_repo — echo "<owner>/<repo>" from the origin remote, or non-zero.
origin_owner_repo() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || return 1
  url="${url%.git}"; url="${url%/}"
  if [[ "$url" =~ [:/]([^/:]+)/([^/]+)$ ]]; then
    printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

state_dir()    { printf '%s/.claude/worktrees/reconcile-pr/%s' "$REPO_ROOT" "$1"; }
worktree_dir() { printf '%s/worktree' "$(state_dir "$1")"; }
meta_path()    { printf '%s/meta.json' "$(state_dir "$1")"; }
conflicts_log(){ printf '%s/conflicts.log' "$(state_dir "$1")"; }
wt_branch()    { printf 'reconcile/%s' "$1"; }

read_meta() { jq -r "$2" "$(meta_path "$1")" 2>/dev/null; }  # read_meta <pr> <filter>

# default_branch — origin's default branch, offline-testable. Prefers the
# origin/HEAD symbolic ref (set by clone), then the env override, then main.
default_branch() {
  local d
  if d=$(git -C "$REPO_ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null); then
    printf '%s' "${d#origin/}"; return 0
  fi
  [ -n "$DEFAULT_BRANCH_OVERRIDE" ] && { printf '%s' "$DEFAULT_BRANCH_OVERRIDE"; return 0; }
  printf 'main'
}

# is_protected <dest> <base> — true if force-pushing <dest> must be refused.
is_protected() {
  local dest="$1" base="$2" defb g
  defb=$(default_branch)
  [ "$dest" = "$base" ] && return 0
  [ "$dest" = "$defb" ] && return 0
  for g in $PROTECTED_GLOBS; do
    # shellcheck disable=SC2254 — intentional glob match
    case "$dest" in $g) return 0 ;; esac
  done
  return 1
}

# worktree_gitdir <wt> — absolute path to the worktree's per-worktree git dir.
worktree_gitdir() {
  local wt="$1" gd
  gd=$(git -C "$wt" rev-parse --git-dir 2>/dev/null) || return 1
  case "$gd" in /*) printf '%s' "$gd" ;; *) printf '%s/%s' "$wt" "$gd" ;; esac
}

# is_mid_rebase <wt> — true while a rebase is in progress in the worktree.
is_mid_rebase() {
  local wt="$1" gd
  gd=$(worktree_gitdir "$wt") || return 1
  [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]
}

# has_unmerged <wt> — true if any path is still in an unmerged (conflicted) state.
has_unmerged() {
  local wt="$1"
  [ -n "$(git -C "$wt" ls-files -u 2>/dev/null)" ]
}

# fetch_pr_json <pr> <repo> [fields] — echo gh pr view JSON or non-zero.
fetch_pr_json() {
  local n="$1" repo="$2" fields="${3:-state,baseRefName,headRefName,isCrossRepository,mergeable,commits,url}"
  "$GH" pr view "$n" --repo "$repo" --json "$fields" 2>/dev/null
}

# conflicted_files_json <wt> — JSON array of the worktree's unmerged files, each
# tagged with a base/pr-relative conflict_type and index blob refs.
conflicted_files_json() {
  local wt="$1" entry xy path ctype
  local items=()
  while IFS= read -r -d '' entry; do
    xy="${entry:0:2}"; path="${entry:3}"
    case "$xy" in
      UU) ctype="both_modified" ;;
      AA) ctype="added_by_both" ;;
      DU) ctype="deleted_by_base" ;;   # base(ours) deleted, PR(theirs) modified
      UD) ctype="deleted_by_pr" ;;     # base modified, PR deleted
      AU) ctype="added_by_base" ;;
      UA) ctype="added_by_pr" ;;
      DD) ctype="both_deleted" ;;
      *)  continue ;;
    esac
    items+=("$(jq -n --arg p "$wt/$path" --arg rel "$path" --arg t "$ctype" \
      '{path:$p, rel:$rel, conflict_type:$t,
        base_blob:(":2:"+$rel), pr_blob:(":3:"+$rel), ancestor_blob:(":1:"+$rel)}')")
  done < <(git -C "$wt" -c core.quotepath=false status --porcelain=v1 -z 2>/dev/null || true)
  if [ "${#items[@]}" -eq 0 ]; then printf '[]'; else printf '%s\n' "${items[@]}" | jq -s '.'; fi
}

# stopped_commit <pr> <wt> — echo "<sha>\t<subject>" for the commit the rebase
# stopped on (tab-separated; both empty if unknown).
stopped_commit() {
  local wt="$1" gd sha="" subj=""
  gd=$(worktree_gitdir "$wt") || { printf '\t'; return; }
  [ -f "$gd/rebase-merge/stopped-sha" ] && sha=$(cat "$gd/rebase-merge/stopped-sha" 2>/dev/null || true)
  [ -n "$sha" ] && subj=$(git -C "$wt" log -1 --format=%s "$sha" 2>/dev/null || true)
  printf '%s\t%s' "$sha" "$subj"
}

# ---- state rendering --------------------------------------------------------
# emit_conflicts <pr> <wt> <do_log> — render {status:"conflicts"}, optionally
# appending the conflict facts to conflicts.log (do_log=1 for start/continue,
# 0 for the read-only status re-orient).
emit_conflicts() {
  local pr="$1" wt="$2" do_log="$3"
  local base head files sc sha subj
  base=$(read_meta "$pr" '.base'); head=$(read_meta "$pr" '.head')
  files=$(conflicted_files_json "$wt")
  sc=$(stopped_commit "$pr" "$wt"); sha="${sc%%$'\t'*}"; subj="${sc#*$'\t'}"
  if [ "$do_log" = "1" ]; then
    jq -cn --arg sha "$sha" --arg subj "$subj" --argjson files "$files" --arg ts "$(now_utc)" \
      '{ts:$ts, commit:{sha:$sha, subject:$subj},
        files:[$files[] | {rel, conflict_type}]}' >> "$(conflicts_log "$pr")"
  fi
  jq -n --arg pr "$pr" --arg sha "$sha" --arg subj "$subj" \
     --argjson files "$files" --arg base "$base" --arg head "$head" '
     ($files | length) as $n |
     {ok:true, status:"conflicts", pr:($pr|tonumber),
      current_commit:{sha:$sha, subject:$subj},
      conflicted_files:$files,
      labels:{
        base_side:("latest " + $base + " — pre-existing behavior to preserve (the <<<<<<< / base side)"),
        pr_side:("this PR’s new work" + (if $sha=="" then "" else " (commit " + ($sha[0:8]) + ")" end) + " — the >>>>>>> side")
      },
      display:("[reconcile-pr] #" + $pr + ": " + ($n|tostring) + " conflicted file(s) replaying "
               + (if $subj=="" then "a commit" else ("“"+$subj+"”") end)
               + ". Resolve preserving BOTH sides, `git add` them in the worktree, then run continue.")}'
}

emit_clean() {
  local pr="$1" wt="$2" head_oid
  head_oid=$(git -C "$wt" rev-parse HEAD 2>/dev/null || echo "")
  jq -n --arg pr "$pr" --arg oid "$head_oid" '
    {ok:true, status:"clean", pr:($pr|tonumber), head_oid:$oid,
     display:("[reconcile-pr] #" + $pr + ": rebase complete, no (more) conflicts. Run test, then push.")}'
}

# post_rebase_state <pr> <wt> <rc> <cap> — after a rebase / --continue / --skip,
# render the resulting state (conflicts | clean | fail).
post_rebase_state() {
  local pr="$1" wt="$2" rc="$3" cap="$4"
  if is_mid_rebase "$wt"; then
    if has_unmerged "$wt"; then
      emit_conflicts "$pr" "$wt" 1
    else
      fail "rebase paused with nothing to resolve (git rc=$rc). Inspect with \`status $pr\`, then continue/continue --skip or abort. Detail: $(printf '%s' "$cap" | tail -n 3)"
    fi
  elif [ "$rc" -eq 0 ]; then
    emit_clean "$pr" "$wt"
  else
    # Not mid-rebase and non-zero: the rebase failed/aborted itself.
    fail "rebase failed (git rc=$rc): $(printf '%s' "$cap" | tail -n 5)"
  fi
}

# teardown <pr> — remove the worktree, its branch, and the state dir. All git
# chatter is silenced (stdout too — `git branch -D` prints "Deleted branch …"
# to stdout, which would otherwise corrupt the caller's JSON).
teardown() {
  local pr="$1" wt; wt=$(worktree_dir "$pr")
  [ -d "$wt" ] && git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" branch -D "$(wt_branch "$pr")" >/dev/null 2>&1 || true
  rm -rf "$(state_dir "$pr")"
}

# ---- subcommand: preflight --------------------------------------------------
cmd_preflight() {
  local n="${1:-}"; validate_pr "$n"; need_repo; require_gh
  local repo pr_json state base head cross url commits
  repo=$(origin_owner_repo) || fail "no GitHub origin remote found (git remote get-url origin)."
  pr_json=$(fetch_pr_json "$n" "$repo") || fail "PR #$n not found on $repo."
  state=$(printf '%s' "$pr_json" | jq -r '.state // ""')
  base=$(printf '%s' "$pr_json" | jq -r '.baseRefName // ""')
  head=$(printf '%s' "$pr_json" | jq -r '.headRefName // ""')
  cross=$(printf '%s' "$pr_json" | jq -r '.isCrossRepository // false')
  url=$(printf '%s' "$pr_json" | jq -r '.url // ""')
  commits=$(printf '%s' "$pr_json" | jq -r '((.commits // []) | length)')

  [ "$state" = "OPEN" ] || fail "PR #$n is $state on $repo — reconcile only operates on OPEN PRs."
  [ "$cross" = "true" ] && fail "PR #$n is from a fork (cross-repository). reconcile-pr does not support fork PRs yet."
  [ -n "$base" ] && [ -n "$head" ] || fail "could not read base/head branch for PR #$n."
  [ "$head" != "$base" ] && ! is_protected "$head" "$base" \
    || fail "PR #$n's head branch '$head' is protected (base/default/protected-glob) — refusing to reconcile a branch we could never safely force-push."

  jq -n --arg pr "$n" --arg repo "$repo" --arg state "$state" --arg base "$base" \
     --arg head "$head" --arg url "$url" --arg commits "$commits" \
     --arg wt "$(worktree_dir "$n")" '
     {ok:true, pr:($pr|tonumber), repo:$repo, state:$state, base:$base, head:$head,
      is_cross_repo:false, commit_count:($commits|tonumber), url:$url,
      plan:{worktree_path:$wt, base_ref:("origin/"+$base), head_ref:("origin/"+$head)},
      display:("[reconcile-pr] #" + $pr + " (" + $repo + "): would rebase '" + $head
               + "' onto origin/" + $base + " (" + $commits + " commit(s)) in an isolated worktree. Run start to begin.")}'
}

# ---- subcommand: start ------------------------------------------------------
cmd_start() {
  local n="${1:-}"; validate_pr "$n"; need_repo; require_gh
  local repo pr_json state base head cross url
  repo=$(origin_owner_repo) || fail "no GitHub origin remote found (git remote get-url origin)."

  # Fail fast on an in-progress reconcile for this PR.
  [ -e "$(state_dir "$n")" ] && fail "a reconcile for #$n is already in progress ($(state_dir "$n")). Use \`status $n\`, or \`abort $n\` to discard it."

  pr_json=$(fetch_pr_json "$n" "$repo") || fail "PR #$n not found on $repo."
  state=$(printf '%s' "$pr_json" | jq -r '.state // ""')
  base=$(printf '%s' "$pr_json" | jq -r '.baseRefName // ""')
  head=$(printf '%s' "$pr_json" | jq -r '.headRefName // ""')
  cross=$(printf '%s' "$pr_json" | jq -r '.isCrossRepository // false')
  url=$(printf '%s' "$pr_json" | jq -r '.url // ""')

  [ "$state" = "OPEN" ] || fail "PR #$n is $state on $repo — reconcile only operates on OPEN PRs."
  [ "$cross" = "true" ] && fail "PR #$n is from a fork (cross-repository). reconcile-pr does not support fork PRs yet."
  [ -n "$base" ] && [ -n "$head" ] || fail "could not read base/head branch for PR #$n."
  { [ "$head" != "$base" ] && ! is_protected "$head" "$base"; } \
    || fail "PR #$n's head branch '$head' is protected — refusing."

  # Dry-run: read-only checks ran for real; emit the plan and stop before side effects.
  if [ -n "$DRY_RUN" ]; then
    jq -n --arg pr "$n" --arg repo "$repo" --arg base "$base" --arg head "$head" \
       --arg wt "$(worktree_dir "$n")" '
       {ok:true, dry_run:true, pr:($pr|tonumber), repo:$repo, base:$base, head:$head,
        commands:[
          ("git fetch origin +refs/heads/" + $base + ":refs/remotes/origin/" + $base
             + " +refs/heads/" + $head + ":refs/remotes/origin/" + $head),
          ("git worktree add " + $wt + " -B reconcile/" + $pr + " --no-track origin/" + $head),
          ("git -c merge.conflictStyle=zdiff3 rebase --empty=drop --no-reapply-cherry-picks origin/" + $base)
        ],
        display:("[reconcile-pr] DRY RUN #" + $pr + ": would rebase " + $head + " onto origin/" + $base + " in " + $wt + ".")}'
    return 0
  fi

  # Fetch base + head into remote-tracking refs (fail before any worktree exists).
  local cap rc=0
  cap=$(git -C "$REPO_ROOT" fetch origin \
          "+refs/heads/$base:refs/remotes/origin/$base" \
          "+refs/heads/$head:refs/remotes/origin/$head" 2>&1) || rc=$?
  [ "$rc" -eq 0 ] || fail "git fetch of origin/$base and origin/$head failed: $(printf '%s' "$cap" | tail -n 3)"

  local remote_oid base_oid
  remote_oid=$(git -C "$REPO_ROOT" rev-parse "refs/remotes/origin/$head" 2>/dev/null) \
    || fail "could not resolve origin/$head after fetch."
  base_oid=$(git -C "$REPO_ROOT" rev-parse "refs/remotes/origin/$base" 2>/dev/null) \
    || fail "could not resolve origin/$base after fetch."

  # Already current: the PR head already contains the latest base ⇒ no rebase,
  # no worktree, nothing to push.
  if git -C "$REPO_ROOT" merge-base --is-ancestor "$base_oid" "$remote_oid" 2>/dev/null; then
    jq -n --arg pr "$n" --arg base "$base" --arg head "$head" '
      {ok:true, status:"already_current", pr:($pr|tonumber), base:$base, head:$head,
       display:("[reconcile-pr] #" + $pr + ": '\''" + $head + "'\'' already contains the latest origin/" + $base + " — nothing to reconcile.")}'
    return 0
  fi

  # Create the isolated worktree + state.
  mkdir -p "$(state_dir "$n")"
  git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" branch -D "$(wt_branch "$n")" >/dev/null 2>&1 || true
  local wt; wt=$(worktree_dir "$n")
  cap=$(git -C "$REPO_ROOT" worktree add "$wt" -B "$(wt_branch "$n")" --no-track "refs/remotes/origin/$head" 2>&1) || {
    rm -rf "$(state_dir "$n")"
    fail "git worktree add failed: $(printf '%s' "$cap" | tail -n 3)"
  }

  jq -n --arg pr "$n" --arg repo "$repo" --arg base "$base" --arg head "$head" \
     --arg url "$url" --arg roid "$remote_oid" --arg boid "$base_oid" \
     --arg wt "$wt" --arg br "$(wt_branch "$n")" --arg ts "$(now_utc)" '
     {pr:($pr|tonumber), repo:$repo, base:$base, head:$head, url:$url,
      remote_oid:$roid, base_oid:$boid, worktree:$wt, branch:$br,
      started:$ts, last_test:null}' > "$(meta_path "$n")"
  : > "$(conflicts_log "$n")"

  # Begin the rebase (non-interactive editor; zdiff3; drop becoming-empty picks).
  rc=0
  cap=$(cd "$wt" && GIT_EDITOR=: GIT_SEQUENCE_EDITOR=: \
        git -c merge.conflictStyle=zdiff3 \
            rebase --empty=drop --no-reapply-cherry-picks "refs/remotes/origin/$base" 2>&1) || rc=$?
  post_rebase_state "$n" "$wt" "$rc" "$cap"
}

# ---- subcommand: status -----------------------------------------------------
cmd_status() {
  local n="${1:-}"; validate_pr "$n"; need_repo
  if [ ! -e "$(state_dir "$n")" ]; then
    jq -n --arg pr "$n" '{ok:true, phase:"idle", pr:($pr|tonumber),
      display:("[reconcile-pr] #" + $pr + ": no active reconcile.")}'
    return 0
  fi
  local wt last_test; wt=$(worktree_dir "$n")
  last_test=$(read_meta "$n" '.last_test'); [ -n "$last_test" ] || last_test="null"
  if is_mid_rebase "$wt"; then
    local files sc sha subj; sc=$(stopped_commit "$n" "$wt"); sha="${sc%%$'\t'*}"; subj="${sc#*$'\t'}"
    if has_unmerged "$wt"; then files=$(conflicted_files_json "$wt"); else files='[]'; fi
    jq -n --arg pr "$n" --argjson files "$files" --arg sha "$sha" --arg subj "$subj" \
       --argjson lt "$last_test" '
       {ok:true, phase:"mid_rebase", pr:($pr|tonumber),
        current_commit:{sha:$sha, subject:$subj}, conflicted_files:$files, last_test:$lt,
        display:("[reconcile-pr] #" + $pr + ": mid-rebase, " + (($files|length)|tostring)
                 + " unresolved file(s)" + (if ($files|length)==0 then " (all staged — run continue)" else "" end) + ".")}'
  else
    local head_oid; head_oid=$(git -C "$wt" rev-parse HEAD 2>/dev/null || echo "")
    jq -n --arg pr "$n" --arg oid "$head_oid" --argjson lt "$last_test" '
       {ok:true, phase:"clean", pr:($pr|tonumber), head_oid:$oid, last_test:$lt,
        display:("[reconcile-pr] #" + $pr + ": rebase finished (HEAD " + ($oid[0:8]) + "). Run test, then push.")}'
  fi
}

# ---- subcommand: continue ---------------------------------------------------
cmd_continue() {
  local n="" skip=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --skip) skip=1 ;;
      *) [ -z "$n" ] && n="$1" || fail "unexpected argument: $1" ;;
    esac
    shift
  done
  validate_pr "$n"; need_repo
  [ -e "$(state_dir "$n")" ] || fail "no active reconcile for #$n — run \`start $n\` first."
  local wt; wt=$(worktree_dir "$n")
  is_mid_rebase "$wt" || fail "reconcile #$n is not mid-rebase (nothing to continue). Check \`status $n\`."

  local cap rc=0
  if [ -n "$skip" ]; then
    cap=$(cd "$wt" && GIT_EDITOR=: GIT_SEQUENCE_EDITOR=: \
          git -c merge.conflictStyle=zdiff3 rebase --skip 2>&1) || rc=$?
    post_rebase_state "$n" "$wt" "$rc" "$cap"
    return 0
  fi

  # Refuse until every conflict is staged.
  if has_unmerged "$wt"; then
    fail "unmerged paths remain in the worktree — resolve every conflict and \`git -C $wt add\` them (or run \`continue $n --skip\` to drop this commit), then continue."
  fi
  # Empty-after-resolution: the staged tree matches HEAD ⇒ the replayed commit is
  # now empty. Dropping the PR's commit is a judgment call — surface, don't skip.
  if git -C "$wt" diff --cached --quiet 2>/dev/null; then
    local sc sha subj; sc=$(stopped_commit "$n" "$wt"); sha="${sc%%$'\t'*}"; subj="${sc#*$'\t'}"
    jq -n --arg pr "$n" --arg sha "$sha" --arg subj "$subj" '
      {ok:true, status:"empty_after_resolution", pr:($pr|tonumber),
       commit:{sha:$sha, subject:$subj},
       display:("[reconcile-pr] #" + $pr + ": commit “" + $subj + "” is empty after resolution — origin/base already has these changes. If that is correct, run `continue " + $pr + " --skip` to drop it; otherwise re-resolve to keep the PR'\''s intent.")}'
    return 0
  fi

  cap=$(cd "$wt" && GIT_EDITOR=: GIT_SEQUENCE_EDITOR=: \
        git -c merge.conflictStyle=zdiff3 rebase --continue 2>&1) || rc=$?
  post_rebase_state "$n" "$wt" "$rc" "$cap"
}

# ---- subcommand: test -------------------------------------------------------
cmd_test() {
  local n="${1:-}"; validate_pr "$n"; need_repo
  [ -e "$(state_dir "$n")" ] || fail "no active reconcile for #$n — run \`start $n\` first."
  local wt; wt=$(worktree_dir "$n")
  is_mid_rebase "$wt" && fail "reconcile #$n is still mid-rebase — finish resolving before testing."

  local tested_oid cmd="" out rc=0 status tail_out
  tested_oid=$(git -C "$wt" rev-parse HEAD 2>/dev/null || echo "")

  if [ -n "$TEST_CMD" ]; then
    cmd="$TEST_CMD"
  elif [ -f "$wt/Makefile" ] && grep -qE '^test:' "$wt/Makefile"; then
    cmd="make test"
  elif [ -f "$wt/GNUmakefile" ] && grep -qE '^test:' "$wt/GNUmakefile"; then
    cmd="make test"
  elif [ -f "$wt/package.json" ] && jq -e '.scripts.test' "$wt/package.json" >/dev/null 2>&1; then
    cmd="npm test"
  else
    jq --arg s "no_test_command" --arg o "$tested_oid" --arg c "" --arg t "$(now_utc)" \
       '.last_test = {status:$s, oid:$o, cmd:$c, ts:$t}' "$(meta_path "$n")" > "$(meta_path "$n").tmp" \
       && mv "$(meta_path "$n").tmp" "$(meta_path "$n")"
    jq -n --arg pr "$n" --arg oid "$tested_oid" '
      {ok:true, status:"no_test_command", pr:($pr|tonumber), tested_oid:$oid,
       display:("[reconcile-pr] #" + $pr + ": no test command detected (set RECONCILE_PR_TEST_CMD, or add a Makefile `test:` / package.json test script). push will WARN-but-allow.")}'
    return 0
  fi

  out=$(cd "$wt" && eval "$cmd" 2>&1) && rc=0 || rc=$?
  [ "$rc" -eq 0 ] && status="pass" || status="fail"
  tail_out=$(printf '%s\n' "$out" | tail -n 40)
  jq --arg s "$status" --arg o "$tested_oid" --arg c "$cmd" --arg t "$(now_utc)" \
     '.last_test = {status:$s, oid:$o, cmd:$c, ts:$t}' "$(meta_path "$n")" > "$(meta_path "$n").tmp" \
     && mv "$(meta_path "$n").tmp" "$(meta_path "$n")"
  jq -n --arg pr "$n" --arg s "$status" --arg c "$cmd" --arg tail "$tail_out" --arg oid "$tested_oid" '
     {ok:true, status:$s, pr:($pr|tonumber), cmd:$c, tested_oid:$oid, tail:$tail,
      display:("[reconcile-pr] #" + $pr + ": `" + $c + "` " + (if $s=="pass" then "PASSED." else "FAILED — fix the resolution and re-test, or abort." end))}'
}

# ---- subcommand: push (the safety gate) -------------------------------------
cmd_push() {
  local n="${1:-}"; validate_pr "$n"; need_repo
  [ -e "$(state_dir "$n")" ] || fail "no active reconcile for #$n — run \`start $n\` first."
  local wt; wt=$(worktree_dir "$n")
  is_mid_rebase "$wt" && fail "reconcile #$n is still mid-rebase — finish resolving (continue) before push."

  local repo base dest remote_oid head_oid
  repo=$(read_meta "$n" '.repo'); base=$(read_meta "$n" '.base'); dest=$(read_meta "$n" '.head')
  remote_oid=$(read_meta "$n" '.remote_oid')
  head_oid=$(git -C "$wt" rev-parse HEAD 2>/dev/null) || fail "could not resolve worktree HEAD for #$n."

  # Best-effort live re-check of head/base/cross (defends against drift since start).
  local pr_json live_head live_cross
  if pr_json=$(fetch_pr_json "$n" "$repo" "state,baseRefName,headRefName,isCrossRepository" 2>/dev/null); then
    live_cross=$(printf '%s' "$pr_json" | jq -r '.isCrossRepository // false')
    live_head=$(printf '%s' "$pr_json" | jq -r '.headRefName // ""')
    [ "$live_cross" = "true" ] && refuse "cross_repo" "PR #$n is now a fork PR — refusing to push."
    [ -n "$live_head" ] && [ "$live_head" != "$dest" ] \
      && refuse "head_changed" "PR #$n's head branch changed to '$live_head' since start — abort and restart."
  fi

  # DESTINATION guard — never force-push a protected branch.
  is_protected "$dest" "$base" \
    && refuse "protected" "refusing to force-push '$dest': it is the base/default/a protected branch. reconcile-pr only ever force-pushes a PR's own head branch."

  # Test gate.
  local lt_status lt_oid warn=""
  lt_status=$(read_meta "$n" '.last_test.status // ""')
  lt_oid=$(read_meta "$n" '.last_test.oid // ""')
  case "$lt_status" in
    pass)
      if [ "$lt_oid" != "$head_oid" ]; then
        [ -n "$ALLOW_UNTESTED" ] || refuse "untested" "the recorded passing test was for a different tree (HEAD moved since \`test $n\`). Re-run test, or set RECONCILE_PR_ALLOW_UNTESTED=1."
        warn="tests were last green on an earlier tree; pushed with RECONCILE_PR_ALLOW_UNTESTED."
      fi ;;
    fail)
      [ -n "$ALLOW_UNTESTED" ] || refuse "tests_failing" "tests FAILED for #$n — refusing to force-push. Fix the resolution and re-test, or set RECONCILE_PR_ALLOW_UNTESTED=1 to override."
      warn="tests were FAILING; pushed with RECONCILE_PR_ALLOW_UNTESTED." ;;
    no_test_command)
      warn="no test command was detected — pushed without a verified suite." ;;
    *)
      [ -n "$ALLOW_UNTESTED" ] || refuse "untested" "no test run recorded for #$n — run \`test $n\` first, or set RECONCILE_PR_ALLOW_UNTESTED=1."
      warn="no test run was recorded; pushed with RECONCILE_PR_ALLOW_UNTESTED." ;;
  esac

  local planned="git -c url.\"https://github.com/\".insteadOf=\"git@github.com:\" push --force-with-lease=refs/heads/$dest:$remote_oid origin HEAD:refs/heads/$dest"
  if [ -n "$SKIP_PUSH" ] || [ -n "$DRY_RUN" ]; then
    jq -n --arg pr "$n" --arg dest "$dest" --arg cmd "$planned" --arg warn "$warn" '
      {ok:true, pushed:false, dry_run:true, pr:($pr|tonumber), dest:$dest, planned_command:$cmd}
      + (if $warn=="" then {} else {warning:$warn} end)
      + {display:("[reconcile-pr] #" + $pr + " SKIP-PUSH: would run → " + $cmd)}'
    return 0
  fi

  # The push — explicit-OID lease, HTTPS override, HEAD:refs/heads/<dest>. NEVER --force.
  local cap rc=0
  cap=$(git -C "$wt" -c url."https://github.com/".insteadOf="git@github.com:" \
          push --force-with-lease="refs/heads/$dest:$remote_oid" \
          origin "HEAD:refs/heads/$dest" 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    jq -n --arg pr "$n" --arg dest "$dest" --arg oid "$head_oid" --arg warn "$warn" '
      {ok:true, pushed:true, pr:($pr|tonumber), dest:$dest, new_oid:$oid}
      + (if $warn=="" then {} else {warning:$warn} end)
      + {display:("[reconcile-pr] #" + $pr + ": force-pushed reconciled '\''" + $dest + "'\'' (" + ($oid[0:8]) + ") with a leased guard."
                  + (if $warn=="" then "" else " ⚠ " + $warn end))}'
    return 0
  fi
  # Stale lease vs. other failure.
  if printf '%s' "$cap" | grep -qiE 'stale info|force-with-lease|\[rejected\]|non-fast-forward'; then
    local remote_now=""
    remote_now=$(git -C "$wt" ls-remote origin "refs/heads/$dest" 2>/dev/null | awk '{print $1}' || true)
    jq -n --arg pr "$n" --arg dest "$dest" --arg rn "$remote_now" --arg exp "$remote_oid" '
      {ok:false, reason:"stale", pr:($pr|tonumber), dest:$dest, remote_oid:$rn, expected_oid:$exp,
       display:("[reconcile-pr] #" + $pr + ": force-push REFUSED — origin/'\''" + $dest + "'\'' moved since start (lease stale). Someone pushed to the branch. Abort and restart the reconcile; reconcile-pr will NOT fall back to --force.")}'
    exit 1
  fi
  fail "force-push failed for #$n: $(printf '%s' "$cap" | tail -n 5)"
}

# ---- subcommand: comment ----------------------------------------------------
cmd_comment() {
  local n="${1:-}" body="${2:-}"; validate_pr "$n"; need_repo
  [ -n "$body" ] || fail "usage: reconcile-pr.sh comment <pr> <body-file>"
  [ -f "$body" ] || fail "comment body file not found: $body"
  local repo
  if [ -e "$(state_dir "$n")" ]; then repo=$(read_meta "$n" '.repo'); fi
  [ -n "${repo:-}" ] || repo=$(origin_owner_repo) || fail "no GitHub origin remote found."
  require_gh

  if [ -n "$DRY_RUN" ]; then
    jq -n --arg pr "$n" --arg repo "$repo" --arg body "$body" '
      {ok:true, dry_run:true, pr:($pr|tonumber),
       planned_command:("gh pr comment " + $pr + " --repo " + $repo + " --body-file " + $body),
       display:("[reconcile-pr] #" + $pr + " DRY RUN: would post the summary comment.")}'
    return 0
  fi
  local cap rc=0
  cap=$("$GH" pr comment "$n" --repo "$repo" --body-file "$body" 2>&1) || rc=$?
  [ "$rc" -eq 0 ] || fail "gh pr comment failed for #$n: $(printf '%s' "$cap" | tail -n 3)"
  local url; url=$(printf '%s' "$cap" | grep -Eo 'https://[^ ]+' | tail -n1 || true)
  jq -n --arg pr "$n" --arg url "$url" '
    {ok:true, pr:($pr|tonumber), url:$url,
     display:("[reconcile-pr] #" + $pr + ": posted resolution summary" + (if $url=="" then "." else " → " + $url end))}'
}

# ---- subcommand: abort ------------------------------------------------------
cmd_abort() {
  local n="${1:-}"; validate_pr "$n"; need_repo
  if [ ! -e "$(state_dir "$n")" ]; then
    jq -n --arg pr "$n" '{ok:true, pr:($pr|tonumber),
      display:("[reconcile-pr] #" + $pr + ": no active reconcile to abort.")}'
    return 0
  fi
  local wt; wt=$(worktree_dir "$n")
  is_mid_rebase "$wt" && { (cd "$wt" && GIT_EDITOR=: git rebase --abort >/dev/null 2>&1) || true; }
  teardown "$n"
  jq -n --arg pr "$n" '{ok:true, pr:($pr|tonumber),
    display:("[reconcile-pr] #" + $pr + ": aborted — worktree removed. The PR branch on origin is untouched.")}'
}

# ---- subcommand: cleanup ----------------------------------------------------
cmd_cleanup() {
  local n="" force=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=1 ;;
      *) [ -z "$n" ] && n="$1" || fail "unexpected argument: $1" ;;
    esac
    shift
  done
  validate_pr "$n"; need_repo
  if [ ! -e "$(state_dir "$n")" ]; then
    jq -n --arg pr "$n" '{ok:true, pr:($pr|tonumber),
      display:("[reconcile-pr] #" + $pr + ": already clean (no state).")}'
    return 0
  fi
  local wt; wt=$(worktree_dir "$n")
  if is_mid_rebase "$wt"; then
    [ -n "$force" ] || fail "reconcile #$n is still mid-rebase — finish it, use \`abort $n\`, or \`cleanup $n --force\`."
    (cd "$wt" && GIT_EDITOR=: git rebase --abort >/dev/null 2>&1) || true
  fi
  teardown "$n"
  jq -n --arg pr "$n" '{ok:true, pr:($pr|tonumber),
    display:("[reconcile-pr] #" + $pr + ": cleaned up — worktree and state removed.")}'
}

# ---- router -----------------------------------------------------------------
case "${1:-}" in
  preflight) shift; cmd_preflight "$@" ;;
  start)     shift; cmd_start "$@" ;;
  status)    shift; cmd_status "$@" ;;
  continue)  shift; cmd_continue "$@" ;;
  test)      shift; cmd_test "$@" ;;
  push)      shift; cmd_push "$@" ;;
  comment)   shift; cmd_comment "$@" ;;
  abort)     shift; cmd_abort "$@" ;;
  cleanup)   shift; cmd_cleanup "$@" ;;
  *)         fail "usage: reconcile-pr.sh <preflight|start|status|continue|test|push|comment|abort|cleanup> <pr-number>" ;;
esac
