#!/usr/bin/env bash
# Shared lightweight append-only transition audit log (F047).
#
# NOT a new subsystem and NOT `tmux pipe-pane` (which mirrors a pane's raw
# output continuously and needs its own enable/disable lifecycle plus
# size/rotation management to stay bounded — real scope for comparatively
# little extra diagnostic value here). Instead: one short, timestamped line
# per pipeline transition point (what sent, when), written directly by the
# scripts that already know the semantically interesting moment — enough to
# reconstruct a stalled auto-resume cycle's timeline post-hoc with a plain
# `cat`/`tail`.
#
# Used by freshen's own hooks (on-stop.sh, on-clear.sh) via same-plugin
# sourcing, and by forge's forge-step-exit.sh via the same resolved
# sibling-plugin path it already uses to invoke freshen.sh (ground rule 5 —
# never a bare `plugins/freshen/...` path).
#
# The log lives at .freshen/transitions.log — inside the already-gitignored
# .freshen/ directory, so no separate ignore rule is needed. Path is
# relative to cwd, matching every other freshen state file (hooks and
# forge-step-exit.sh alike always run with cwd = the target project root).

FRESHEN_LOG_DIR="${FRESHEN_LOG_DIR:-.freshen}"
FRESHEN_LOG_MAX_LINES="${FRESHEN_LOG_MAX_LINES:-500}"

# freshen_log_transition <message> — append one timestamped line.
#
# Best-effort only, by design: a logging failure (read-only filesystem, a
# file sitting where the directory should be, etc.) must never fail or
# block the caller — every failure path here is swallowed. This is pure
# diagnostics, not correctness-load-bearing state.
freshen_log_transition() {
  local msg="$1" log="${FRESHEN_LOG_DIR}/transitions.log"
  mkdir -p "$FRESHEN_LOG_DIR" 2>/dev/null || return 0
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" >> "$log" 2>/dev/null || return 0
  _freshen_trim_log "$log" "$FRESHEN_LOG_MAX_LINES"
}

# _freshen_trim_log <log> <max_lines> — keep the log genuinely lightweight
# across a long-running pipeline by capping it to the most recent
# <max_lines> lines rather than letting it grow unbounded.
_freshen_trim_log() {
  local log="$1" max_lines="$2" line_count
  line_count="$(wc -l < "$log" 2>/dev/null | tr -d ' ')" || return 0
  [ -n "$line_count" ] || return 0
  if [ "$line_count" -gt "$max_lines" ] 2>/dev/null; then
    tail -n "$max_lines" "$log" > "${log}.tmp" 2>/dev/null && mv "${log}.tmp" "$log" 2>/dev/null || true
  fi
}
