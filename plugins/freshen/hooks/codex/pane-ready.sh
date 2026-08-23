#!/usr/bin/env bash
# Advisory Codex TUI readiness probe. The shared bounded capture-pane read-back
# remains the final delivery check, so UI copy changes cannot mark a send done.

codex_pane_wait_ready() {
  local pane="$1" attempts="${FRESHEN_CODEX_READY_ATTEMPTS:-12}"
  local delay="${FRESHEN_CODEX_READY_DELAY:-0.25}" content i=0
  local marker="${FRESHEN_CODEX_READY_PATTERN:-OpenAI Codex|context left|tokens left|for shortcuts}"
  local glyph="${FRESHEN_CODEX_PROMPT_PATTERN:-›|❯}"

  while [[ "$i" -lt "$attempts" ]]; do
    content="$(tmux capture-pane -p -t "$pane" 2>/dev/null || true)"
    if [[ -n "$content" ]] \
      && ! printf '%s' "$content" | grep -Eq 'esc to interrupt|Working\.\.\.|Thinking\.\.\.' \
      && ! printf '%s' "$content" | grep -Eq 'Do you trust the contents|Press enter to continue|hooks need review|Review .*hooks' \
      && { printf '%s' "$content" | grep -Eq -- "$marker" \
           || printf '%s' "$content" | grep -Eq -- "$glyph"; }; then
      return 0
    fi
    i=$((i + 1))
    [[ "$i" -lt "$attempts" ]] && sleep "$delay"
  done
  return 1
}
