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
#   1. send the keys (a single non-interpreted "keys" send for control
#      sequences like "/clear", or a literal-text send + separate Enter for
#      arbitrary re-invocation command strings that must not be
#      key-interpreted)
#   2. poll `tmux capture-pane -p` for evidence the text we just sent no
#      longer sits, unsubmitted, on the last non-blank line of the pane —
#      i.e. it left the input box. This is deliberately agnostic to what
#      Claude Code's TUI actually renders once a command is accepted (that
#      is an implementation detail we cannot assume and which could change
#      across versions); "no longer sitting there unsubmitted" is the
#      weakest claim that still meaningfully distinguishes "the pane
#      reacted to our keystrokes" from "the pane never processed them at
#      all" (the classic busy/wedged-pane failure mode).
#   3. on failure to confirm within a bounded number of polls, resend
#      (bounded) rather than giving up after one attempt (today's behavior)
#      or polling/resending forever.
#
# Callers must source this file with $TMUX_PANE already validated present,
# and may override the bounds below via environment (tests do, to keep the
# poll delay near-zero rather than sleeping for real).

# Attempts per confirm-poll loop (each ~PANE_CONFIRM_DELAY apart).
PANE_CONFIRM_ATTEMPTS="${PANE_CONFIRM_ATTEMPTS:-5}"
# Seconds between poll attempts. Fractional — both BSD (macOS) and GNU
# `sleep` accept fractional-second arguments.
PANE_CONFIRM_DELAY="${PANE_CONFIRM_DELAY:-0.3}"
# Total RESEND attempts if the first send is never confirmed (0 means: try
# once, poll for confirmation, then give up — no resend).
PANE_SEND_RETRIES="${PANE_SEND_RETRIES:-2}"

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

# pane_send_and_confirm <pane> <mode> <text> — send <text> to <pane> and poll
# for confirmation, resending up to PANE_SEND_RETRIES additional times if
# confirmation never lands. Returns 0 once confirmed, 1 if every attempt
# (original send + all resends) fails to confirm.
#
# <mode>:
#   keys    — one `send-keys -t <pane> <text> Enter` call. For short control
#             sequences with no embedded whitespace/special tokens (e.g.
#             "/clear").
#   literal — `send-keys -t <pane> -l <text>` then a SEPARATE `send-keys …
#             Enter` call. For arbitrary re-invocation command strings that
#             must not be key-interpreted. Both calls must succeed for this
#             attempt to count as "sent" (F041: the old on-clear.sh only
#             gated on the first of these two succeeding).
pane_send_and_confirm() {
  local pane="$1" mode="$2" text="$3" resend=0 sent
  while [ "$resend" -le "$PANE_SEND_RETRIES" ]; do
    sent=false
    if [ "$mode" = "literal" ]; then
      if tmux send-keys -t "$pane" -l "$text" && tmux send-keys -t "$pane" Enter; then
        sent=true
      fi
    else
      if tmux send-keys -t "$pane" "$text" Enter; then
        sent=true
      fi
    fi
    if [ "$sent" = true ] && pane_wait_confirmed "$pane" "$text"; then
      return 0
    fi
    resend=$((resend + 1))
  done
  return 1
}
