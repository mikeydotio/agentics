#!/usr/bin/env bash
# rca-bisect.sh — drive `git bisect run` inside an investigation's worktree to
# find the commit that introduced a regression.
#
# Usage:
#   rca-bisect.sh run <slug> --good <rev> --bad <rev> --test-cmd "<cmd>"
#                            [--build-cmd "<cmd>"] [--timeout-per-step SEC=600]
#
# Requires the slug's worktree (rca-worktree.sh create <slug>) to exist. Runs an
# automated bisect between --good and --bad. A per-step wrapper maps outcomes to
# git-bisect semantics: pass→good(0), test failure→bad(1), and build/setup
# failure (--build-cmd fails, or test-cmd exits 126/127) or a per-step timeout
# →skip(125). `git bisect reset` ALWAYS runs on exit (trap).
#
# Output on success (exit 0):
#   {ok:true, culprit_sha, culprit_short, culprit_subject, culprit_author,
#    culprit_date, steps, skipped, log_tail}
# Errors (exit 1): no_jq, no_git, missing_slug, bad_args, not_a_git_repo,
#   no_worktree, bad_rev, good_is_bad, bisect_inconclusive, bad_subcommand.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"ok":false,"error":"no_jq","detail":"jq is required"}\n'; exit 1; }
emit_err() { jq -n --arg e "$1" --arg d "${2:-}" '{ok:false, error:$e, detail:$d}'; exit 1; }
command -v git >/dev/null 2>&1 || emit_err no_git "git is required"

ROOT=""
need_root() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || emit_err not_a_git_repo "not inside a git repository"
  ROOT=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10); exit}')
  [ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || emit_err not_a_git_repo "not inside a git repository"
}
wt_dir() { printf '%s/.claude/worktrees/rca/%s/worktree' "$ROOT" "$1"; }

# write_wrapper <path> — emit the per-step bisect wrapper. It reads TEST_CMD,
# BUILD_CMD and STEP_TIMEOUT from the environment and exits 0/1/125.
write_wrapper() {
  cat > "$1" <<'WRAP'
#!/usr/bin/env bash
set -u
_timeout="${STEP_TIMEOUT:-600}"
run_bounded() {
  local cmd="$1" pid elapsed=0
  bash -c "$cmd" >/dev/null 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$_timeout" ]; then
      kill -TERM "$pid" 2>/dev/null || true; sleep 1; kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1; elapsed=$((elapsed + 1))
  done
  wait "$pid"
}
if [ -n "${BUILD_CMD:-}" ]; then
  run_bounded "$BUILD_CMD" || exit 125   # build failure / timeout → skip
fi
run_bounded "${TEST_CMD:?}"; code=$?
case "$code" in
  0)           exit 0 ;;    # pass → good
  124)         exit 125 ;;  # timeout → skip
  125|126|127) exit 125 ;;  # cannot build/run this commit → skip
  *)           exit 1 ;;    # test failed → bad
esac
WRAP
}

cmd_run() {
  local slug="" good="" bad="" test_cmd="" build_cmd="" step_timeout=600
  slug="${1:-}"; shift || true
  [ -n "$slug" ] && [ "${slug#--}" = "$slug" ] || emit_err missing_slug "run requires a <slug>"
  while [ $# -gt 0 ]; do
    case "$1" in
      --good)             good="${2:-}"; shift 2 ;;
      --bad)              bad="${2:-}"; shift 2 ;;
      --test-cmd)         test_cmd="${2:-}"; shift 2 ;;
      --build-cmd)        build_cmd="${2:-}"; shift 2 ;;
      --timeout-per-step) step_timeout="${2:-600}"; shift 2 ;;
      *)                  emit_err bad_args "unexpected argument: $1" ;;
    esac
  done
  [ -n "$good" ] || emit_err bad_args "run requires --good"
  [ -n "$bad" ] || emit_err bad_args "run requires --bad"
  [ -n "$test_cmd" ] || emit_err bad_args "run requires --test-cmd"

  need_root
  local wt; wt=$(wt_dir "$slug")
  { [ -d "$wt" ] && git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1; } \
    || emit_err no_worktree "no worktree for $slug — run: rca-worktree.sh create $slug"

  local good_oid bad_oid
  good_oid=$(git -C "$wt" rev-parse --verify "${good}^{commit}" 2>/dev/null) || emit_err bad_rev "cannot resolve --good: $good"
  bad_oid=$(git -C "$wt" rev-parse --verify "${bad}^{commit}" 2>/dev/null) || emit_err bad_rev "cannot resolve --bad: $bad"

  local wrapper; wrapper=$(mktemp "${TMPDIR:-/tmp}/rca-bisect.XXXXXX")
  write_wrapper "$wrapper"
  chmod +x "$wrapper"
  # shellcheck disable=SC2064
  trap "git -C '$wt' bisect reset >/dev/null 2>&1 || true; rm -f '$wrapper'" EXIT

  export TEST_CMD="$test_cmd" BUILD_CMD="$build_cmd" STEP_TIMEOUT="$step_timeout"

  # good_is_bad: the good rev must actually pass. Run the wrapper there once.
  git -C "$wt" checkout -q "$good_oid" 2>/dev/null || emit_err bad_rev "cannot checkout --good: $good"
  local gcode=0
  ( cd "$wt" && bash "$wrapper" ) || gcode=$?
  [ "$gcode" -eq 1 ] && emit_err good_is_bad "--good ($good) already fails the test — it is not a good baseline"

  git -C "$wt" bisect start "$bad_oid" "$good_oid" >/dev/null 2>&1 \
    || emit_err bisect_inconclusive "git bisect start failed"

  local run_out run_rc=0
  run_out=$( cd "$wt" && git bisect run bash "$wrapper" 2>&1 ) || run_rc=$?

  local culprit
  culprit=$(printf '%s\n' "$run_out" | grep -Eo '^[0-9a-f]{40} is the first bad commit' | head -1 | awk '{print $1}' || true)

  local log_all; log_all=$(git -C "$wt" bisect log 2>/dev/null || true)
  local steps skipped
  steps=$(printf '%s\n' "$run_out" | grep -c 'Bisecting:' || true)
  skipped=$(printf '%s\n' "$log_all" | grep -c '^git bisect skip' || true)
  local log_tail; log_tail=$(printf '%s\n' "$run_out" | tail -n 30)

  if [ -z "$culprit" ]; then
    emit_err bisect_inconclusive "no single culprit (rc=$run_rc); $(printf '%s' "$run_out" | tail -n 3)"
  fi

  local cshort csubj cauthor cdate
  cshort=$(git -C "$wt" rev-parse --short "$culprit" 2>/dev/null || true)
  csubj=$(git -C "$wt" log -1 --format=%s "$culprit" 2>/dev/null || true)
  cauthor=$(git -C "$wt" log -1 --format=%an "$culprit" 2>/dev/null || true)
  cdate=$(git -C "$wt" log -1 --format=%aI "$culprit" 2>/dev/null || true)

  jq -n --arg sha "$culprit" --arg short "$cshort" --arg subj "$csubj" \
        --arg author "$cauthor" --arg date "$cdate" \
        --argjson steps "${steps:-0}" --argjson skipped "${skipped:-0}" --arg log "$log_tail" '
    {ok:true, culprit_sha:$sha, culprit_short:$short, culprit_subject:$subj,
     culprit_author:$author, culprit_date:$date, steps:$steps, skipped:$skipped, log_tail:$log,
     display:("[rca] culprit " + $short + " — " + $subj + " (" + ($steps|tostring) + " steps, " + ($skipped|tostring) + " skipped)")}'
}

case "${1:-}" in
  run) shift; cmd_run "$@" ;;
  *)   emit_err bad_subcommand "usage: rca-bisect.sh run <slug> --good <rev> --bad <rev> --test-cmd \"<cmd>\" [--build-cmd \"<cmd>\"] [--timeout-per-step SEC]" ;;
esac
