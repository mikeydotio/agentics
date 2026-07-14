#!/usr/bin/env bash
# Shared tmux capture-pane confirm/retry helpers for freshen's on-stop.sh and
# on-clear.sh (F045, F041, F056 — see plugins/forge/references/auto-resume.md's
# "Capture-Pane Read-Back" section for the full design rationale).
#
# Both hooks used to blind-fire `tmux send-keys` with no confirmation the
# pane actually accepted the keystrokes — a busy, wedged, or dead pane
# silently stranded the pipeline (F045), and on-clear.sh additionally deleted
# its signal file on the strength of the FIRST of two send-keys calls
# succeeding, regardless of whether the second (the actual Enter submission)
# did (F041). These helpers turn "fire once and hope" into a bounded,
# verifiable, retryable send:
#
#   1. DELIVER the text ONCE, then a SEPARATE Enter to submit — with a short
#      settle (PANE_PASTE_SETTLE_DELAY) in between so a bracketed paste closes
#      and the Enter is read as "submit" rather than absorbed as a newline
#      into the still-settling paste (the issue #82 race). The text is pasted
#      via a single non-interpreted "keys" send for control sequences like
#      "/clear", or a `-l` literal send for arbitrary re-invocation command
#      strings that must not be key-interpreted.
#   2. poll `tmux capture-pane -p` for evidence the text we just sent no
#      longer sits, unsubmitted, on the last non-blank line of the pane —
#      i.e. it left the input box. This is deliberately agnostic to what
#      Claude Code's TUI actually renders once a command is accepted (that
#      is an implementation detail we cannot assume and which could change
#      across versions); "no longer sitting there unsubmitted" is the
#      weakest claim that still meaningfully distinguishes "the pane
#      reacted to our keystrokes" from "the pane never processed them at
#      all" (the classic busy/wedged-pane failure mode).
#   3. on failure to confirm within a bounded number of polls, re-send the
#      ENTER ALONE (bounded) — NEVER re-paste the text. Re-pasting on retry
#      would duplicate the command in the input box (issue #86, the sibling
#      of the #82 re-paste-on-retry bug); only a paste that never landed
#      (the send-keys call itself errored) is safe to repeat.
#
# WHY THE CONFIRM STAYS A LAST-LINE LIVENESS PROBE (and is NOT tightened to the
# "❯" input row the way plugins/issue/bin/issue.sh does for its #82 fix):
# freshen sends these keys to the SAME Claude Code session whose Stop /
# SessionStart hook is currently running. Per this repo's CLAUDE.md ("Hook
# ordering"), keystrokes sent by a hook are buffered and "aren't acted on until
# all of that turn's hooks finish" — so true SUBMISSION is causally gated on
# the hook batch returning and is UNOBSERVABLE from inside the hook (the confirm
# poll runs synchronously within it). The pipeline actually DEPENDS on this
# staying fast: on-stop.sh must set .clear-pending BEFORE /clear is processed,
# or on-clear.sh (which fires when /clear runs) sees no .clear-pending and skips
# the re-invoke. A receipt/submission confirm scoped to the input row would hang
# whenever the TUI echoes the typed text mid-hook, stranding the whole
# auto-resume cycle. The genuinely load-bearing branch here is the
# capture-pane-FAILURE path (a dead/unreachable pane -> resend); everything
# content-based is intentionally a weak liveness probe. (The input-row confirm
# only becomes correct if freshen ever sends to a SEPARATE live pane, as
# issue.sh does — it does not today. See plugins/forge/references/auto-resume.md,
# "Capture-Pane Read-Back".)
#
# Callers must source this file with $TMUX_PANE already validated present,
# and may override the bounds below via environment (tests do, to keep the
# poll and settle delays near-zero rather than sleeping for real).

# Attempts per confirm-poll loop (each ~PANE_CONFIRM_DELAY apart).
PANE_CONFIRM_ATTEMPTS="${PANE_CONFIRM_ATTEMPTS:-5}"
# Seconds between poll attempts. Fractional — both BSD (macOS) and GNU
# `sleep` accept fractional-second arguments.
PANE_CONFIRM_DELAY="${PANE_CONFIRM_DELAY:-0.3}"
# Total RESEND attempts if the first send is never confirmed (0 means: try
# once, poll for confirmation, then give up — no resend).
PANE_SEND_RETRIES="${PANE_SEND_RETRIES:-2}"
# Seconds to settle after delivering the text, BEFORE the Enter, so a bracketed
# paste closes and the Enter is read as "submit" rather than absorbed as a
# newline into the still-settling paste (the issue #82 race, adopted here
# defensively). Fractional — both BSD (macOS) and GNU `sleep` accept
# fractional-second arguments (the same guarantee PANE_CONFIRM_DELAY relies on);
# a value of 0 is also valid on both, which is what tests use.
PANE_PASTE_SETTLE_DELAY="${PANE_PASTE_SETTLE_DELAY:-0.2}"

# pane_text_still_pending <pane> <text> — true (exit 0) if <text> is still
# sitting, unsubmitted, as the trailing content of the pane's last non-blank
# line; false (exit 1) if it is not (confirmed: either genuinely accepted,
# or the pane is blank because it was accepted).
#
# A failed `capture-pane` call (dead pane, bad target, tmux server hiccup)
# is treated as "still pending", NOT as "confirmed" — we cannot observe the
# pane, so we must not assume success. This is deliberately the opposite
# default from "capture succeeded and shows nothing" (an entirely blank
# pane), which correctly means the text is confirmed gone.
pane_text_still_pending() {
  local pane="$1" text="$2" content last_line
  if ! content="$(tmux capture-pane -p -t "$pane" 2>/dev/null)"; then
    return 0
  fi
  last_line="$(printf '%s\n' "$content" | grep -v '^[[:space:]]*$' | tail -1)"
  case "$last_line" in
    *"$text") return 0 ;;
    *) return 1 ;;
  esac
}

# pane_wait_confirmed <pane> <text> — poll up to PANE_CONFIRM_ATTEMPTS times,
# PANE_CONFIRM_DELAY apart, for pane_text_still_pending to go false. Returns
# 0 the moment it's confirmed, 1 if it's still pending after every attempt.
pane_wait_confirmed() {
  local pane="$1" text="$2" attempt=0
  while [ "$attempt" -lt "$PANE_CONFIRM_ATTEMPTS" ]; do
    pane_text_still_pending "$pane" "$text" || return 0
    sleep "$PANE_CONFIRM_DELAY"
    attempt=$((attempt + 1))
  done
  return 1
}

# pane_paste <pane> <mode> <text> — DELIVER <text> to the pane's input box
# WITHOUT submitting, then settle (PANE_PASTE_SETTLE_DELAY). Never sends Enter.
# Returns non-zero if the send-keys call itself errored (nothing landed) so the
# caller may safely retry the PASTE; a paste that SUCCEEDED must never be
# repeated — repeating it duplicates the text in the input box (issue #86).
#
# <mode>:
#   keys    — `send-keys -t <pane> <text>` (key-name interpreted; for short
#             control sequences with no embedded whitespace/special tokens,
#             e.g. "/clear").
#   literal — `send-keys -t <pane> -l <text>` (literal bytes, never
#             key-interpreted; for arbitrary re-invocation command strings).
pane_paste() {
  local pane="$1" mode="$2" text="$3"
  if [ "$mode" = "literal" ]; then
    tmux send-keys -t "$pane" -l "$text" || return 1
  else
    tmux send-keys -t "$pane" "$text" || return 1
  fi
  sleep "$PANE_PASTE_SETTLE_DELAY"
}

# pane_send_and_confirm <pane> <mode> <text> — deliver <text> to <pane> and
# submit it, confirming via the capture-pane read-back. Returns 0 once
# confirmed, 1 if every bounded attempt fails.
#
# Two SEPARATE bounded phases so a swallowed submit never re-pastes the text:
#   A. DELIVER the text ONCE (pane_paste). Retry the paste only when the
#      send-keys call itself errored (nothing landed); a paste that returned
#      success is NEVER repeated.
#   B. SUBMIT with Enter and confirm. On a swallowed/failed submit, re-send
#      the ENTER ALONE (bounded) — never re-paste (issue #86).
#
# F041 is preserved: a "confirmed" (0) return still requires BOTH a delivered
# paste AND a submitted Enter that the read-back agrees left the input line; a
# paste that never lands, or an Enter that never confirms, both yield 1.
pane_send_and_confirm() {
  local pane="$1" mode="$2" text="$3" try pasted=false
  # Phase A — deliver once (retry only a paste that failed to send at all).
  try=0
  while [ "$try" -le "$PANE_SEND_RETRIES" ]; do
    if pane_paste "$pane" "$mode" "$text"; then
      pasted=true
      break
    fi
    try=$((try + 1))
  done
  [ "$pasted" = true ] || return 1
  # Phase B — submit + confirm; re-send ENTER ALONE on failure (never re-paste).
  try=0
  while [ "$try" -le "$PANE_SEND_RETRIES" ]; do
    if tmux send-keys -t "$pane" Enter; then
      pane_wait_confirmed "$pane" "$text" && return 0
    fi
    try=$((try + 1))
  done
  return 1
}
