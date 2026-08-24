#!/usr/bin/env bash
# Codex-specific parser: only the actual input row is readiness evidence.
codex_pane_capture() { tmux capture-pane -p -J -t "$1" 2>/dev/null; }

codex_input_row_from_content() {
  local content="$1" encoded text
  encoded="$(printf '%s\n' "$content" | awk '
    function flush_prompt() {
      if (active) { last = text; found = 1 }
      active = 0
      text = ""
    }
    /^[[:space:]]*(›|❯)/ {
      flush_prompt()
      line = $0
      sub(/^[[:space:]]*(›|❯)[[:space:]]*/, "", line)
      text = line
      active = 1
      next
    }
    active && /^[[:space:]]*$/ { flush_prompt(); next }
    active && /^[[:space:]]*(gpt-|[0-9]+% context|[0-9]+% tokens|[?] for shortcuts)/ {
      flush_prompt()
      next
    }
    active {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      text = text " " line
    }
    END {
      flush_prompt()
      if (found) printf "__FRESHEN_INPUT__%s\n", last
    }
  ')"
  case "$encoded" in
    __FRESHEN_INPUT__*) text="${encoded#__FRESHEN_INPUT__}" ;;
    *) return 1 ;;
  esac
  text="$(printf '%s\n' "$text" | sed -E 's/[[:space:]]+$//')"
  # Codex renders this placeholder on an empty new-session input row.  It is
  # UI chrome, not pending user input.
  [ "$text" = "Ask Codex to do anything" ] && text=""
  printf '%s\n' "$text"
}

codex_pane_input_text() {
  local content
  content="$(codex_pane_capture "$1")" || return 1
  codex_input_row_from_content "$content"
}

codex_pane_input_equals() {
  local actual
  actual="$(codex_pane_input_text "$1")" || return 1
  [ "$actual" = "$2" ]
}

codex_content_is_interactive_prompt() {
  local content="$1"
  ! printf '%s\n' "$content" | grep -Eq 'esc to interrupt|Working\.\.\.|Thinking\.\.\.' || return 1
  ! printf '%s\n' "$content" | grep -Eq 'Do you trust the contents|Press enter to continue|hooks need review|Review .*hooks' || return 1
  [ "$(codex_input_row_from_content "$content" 2>/dev/null || printf __missing__)" = "" ]
}

codex_pane_wait_stable_empty() {
  local pane="$1" attempts="${FRESHEN_CODEX_READY_ATTEMPTS:-${FRESHEN_CODEX_DEFERRED_ATTEMPTS:-80}}"
  local delay="${FRESHEN_CODEX_READY_DELAY:-0.25}" required="${FRESHEN_CODEX_STABLE_OBSERVATIONS:-2}"
  local content i=0 stable=0
  while [ "$i" -lt "$attempts" ]; do
    content="$(codex_pane_capture "$pane" 2>/dev/null || true)"
    if [ -n "$content" ] && codex_content_is_interactive_prompt "$content"; then
      stable=$((stable + 1))
      [ "$stable" -ge "$required" ] && return 0
    else
      stable=0
    fi
    i=$((i + 1))
    [ "$i" -lt "$attempts" ] && sleep "$delay"
  done
  return 1
}

codex_pane_wait_ready() { codex_pane_wait_stable_empty "$1"; }
