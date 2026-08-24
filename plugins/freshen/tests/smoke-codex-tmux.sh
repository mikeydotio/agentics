#!/usr/bin/env bash
# Real Codex CLI + tmux Freshen transition. Kept outside make test because it
# requires a logged-in local Codex installation and launches a TUI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${FRESHEN_SMOKE_PLUGIN_ROOT:-$SCRIPT_DIR/..}" && pwd)"
AUTH_SOURCE="${CODEX_SMOKE_AUTH_FILE:-${CODEX_HOME:-$HOME/.codex}/auth.json}"
SMOKE_COMMAND="${FRESHEN_SMOKE_COMMAND:-/help}"
PRIME_COMMAND="${FRESHEN_SMOKE_PRIME_COMMAND:-}"

for command_name in codex tmux jq; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'SKIP: %s is not installed\n' "$command_name"
    exit 0
  }
done
[ -f "$AUTH_SOURCE" ] || {
  printf 'SKIP: no Codex auth file at %s\n' "$AUTH_SOURCE"
  exit 0
}

SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/freshen-codex-tmux.XXXXXX")"
# Codex canonicalizes macOS /var paths to /private/var before looking up the
# project trust entry, so use the physical path everywhere in this fixture.
SMOKE_ROOT="$(cd "$SMOKE_ROOT" && pwd -P)"
MARKET_ROOT="$SMOKE_ROOT/marketplace"
SMOKE_CODEX_HOME="$SMOKE_ROOT/codex-home"
SMOKE_BIN="$SMOKE_ROOT/bin"
WORKSPACE="$SMOKE_ROOT/workspace"
SOCKET_PATH="$SMOKE_ROOT/tmux.sock"
SESSION="freshen-age87-$$"
TMUX_REAL="$(command -v tmux)"
mkdir -p "$MARKET_ROOT/.agents/plugins" "$MARKET_ROOT/plugins" \
  "$SMOKE_CODEX_HOME" "$SMOKE_BIN" "$WORKSPACE"

cleanup() {
  if [ "${FRESHEN_SMOKE_KEEP:-0}" = "1" ]; then
    printf 'Freshen smoke fixture preserved at %s\n' "$SMOKE_ROOT" >&2
    return
  fi
  PATH="$SMOKE_BIN:$PATH" tmux kill-server >/dev/null 2>&1 || true
  rm -rf "$SMOKE_ROOT"
}
trap cleanup EXIT INT TERM

cp -R "$PLUGIN_DIR" "$MARKET_ROOT/plugins/freshen"
jq -n '
  {
    name: "age87-freshen",
    interface: {displayName: "Freshen Codex Smoke"},
    plugins: [
      {
        name: "freshen",
        source: {source: "local", path: "./plugins/freshen"},
        policy: {installation: "AVAILABLE", authentication: "ON_INSTALL"},
        category: "Productivity"
      }
    ]
  }
' > "$MARKET_ROOT/.agents/plugins/marketplace.json"

printf '#!/usr/bin/env bash\nexec "%s" -S "%s" "$@"\n' "$TMUX_REAL" "$SOCKET_PATH" > "$SMOKE_BIN/tmux"
chmod +x "$SMOKE_BIN/tmux"
cp "$AUTH_SOURCE" "$SMOKE_CODEX_HOME/auth.json"
printf '[projects."%s"]\ntrust_level = "trusted"\n\n[projects."%s"]\ntrust_level = "trusted"\n' \
  "$SMOKE_ROOT" "$WORKSPACE" > "$SMOKE_CODEX_HOME/config.toml"

CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin marketplace add "$MARKET_ROOT" --json >/dev/null
CODEX_HOME="$SMOKE_CODEX_HOME" codex plugin add freshen@age87-freshen --json >/dev/null
INSTALLED_MANIFEST="$(find "$SMOKE_CODEX_HOME" -path '*/.codex-plugin/plugin.json' -type f -print -quit)"
[ -n "$INSTALLED_MANIFEST" ]
INSTALLED_ROOT="$(cd "$(dirname "$INSTALLED_MANIFEST")/.." && pwd)"

LAUNCHER="$SMOKE_ROOT/launch-codex.sh"
printf '#!/usr/bin/env bash\nexec codex -C "%s" -s workspace-write -a never --dangerously-bypass-hook-trust\n' "$WORKSPACE" > "$LAUNCHER"
chmod +x "$LAUNCHER"

PATH="$SMOKE_BIN:$PATH" CODEX_HOME="$SMOKE_CODEX_HOME" \
  tmux new-session -d -s "$SESSION" -c "$WORKSPACE" "$LAUNCHER"
PANE="$(PATH="$SMOKE_BIN:$PATH" tmux list-panes -t "$SESSION" -F '#{pane_id}' | head -1)"

. "$INSTALLED_ROOT/hooks/codex/pane-ready.sh"
if ! PATH="$SMOKE_BIN:$PATH" FRESHEN_CODEX_READY_ATTEMPTS=80 FRESHEN_CODEX_READY_DELAY=0.25 \
  codex_pane_wait_ready "$PANE"; then
  PATH="$SMOKE_BIN:$PATH" tmux capture-pane -p -t "$PANE" >&2 || true
  printf 'Freshen smoke: Codex TUI never became ready\n' >&2
  exit 1
fi

if [ -n "$PRIME_COMMAND" ]; then
  PATH="$SMOKE_BIN:$PATH" tmux send-keys -t "$PANE" -l "$PRIME_COMMAND"
  sleep 0.3
  PATH="$SMOKE_BIN:$PATH" tmux send-keys -t "$PANE" Enter

  primed=false
  for _ in $(seq 1 240); do
    while IFS= read -r rollout; do
      if jq -s -e --arg expected "$PRIME_COMMAND" '
        any(.[];
          (.type == "response_item"
           and .payload.type == "message"
           and .payload.role == "user"
           and any(.payload.content[]?;
             .type == "input_text" and .text == $expected))
          or (.type == "event_msg"
              and .payload.type == "user_message"
              and (.payload.message // .payload.text // "") == $expected)
        )
        and any(.[]; .type == "event_msg" and .payload.type == "task_complete")
      ' "$rollout" >/dev/null 2>&1; then
        primed=true
        break 2
      fi
    done < <(find "$SMOKE_CODEX_HOME/sessions" -type f -name 'rollout-*.jsonl' \
      -print 2>/dev/null || true)
    sleep 0.25
  done

  if [ "$primed" != true ]; then
    PATH="$SMOKE_BIN:$PATH" tmux capture-pane -p -t "$PANE" >&2 || true
    printf 'Freshen smoke: Codex did not complete the priming turn\n' >&2
    exit 1
  fi
fi

(
  cd "$WORKSPACE"
  PATH="$SMOKE_BIN:$PATH" TMUX="$SOCKET_PATH" TMUX_PANE="$PANE" \
    bash "$INSTALLED_ROOT/codex/bin/freshen.sh" \
    queue "$SMOKE_COMMAND" --source smoke --summary 'real Codex tmux transition' >/dev/null
  printf '{"hook_event_name":"Stop"}\n' \
    | PATH="$SMOKE_BIN:$PATH" PLUGIN_ROOT="$INSTALLED_ROOT" \
      TMUX="$SOCKET_PATH" TMUX_PANE="$PANE" \
      PANE_CONFIRM_DELAY=0.1 PANE_PASTE_SETTLE_DELAY=0.1 \
      bash "$INSTALLED_ROOT/hooks/host-dispatch.sh" on-stop.sh >/dev/null
)

consumed=false
for _ in $(seq 1 480); do
  if [ ! -f "$WORKSPACE/.freshen/smoke.signal" ] \
    && find "$WORKSPACE/.freshen/.codex-reset" -maxdepth 1 -type d \
      -name 'completed-*' -print -quit 2>/dev/null | grep -q . \
    && grep -q 'phase session-start-ack' "$WORKSPACE/.freshen/transitions.log" 2>/dev/null \
    && grep -q 'phase continuation-stop' "$WORKSPACE/.freshen/transitions.log" 2>/dev/null; then
    consumed=true
    break
  fi
  if PATH="$SMOKE_BIN:$PATH" tmux list-panes -t "$SESSION" -F '#{pane_dead}' 2>/dev/null | grep -q '^1$'; then
    break
  fi
  sleep 0.25
done

if [ "$consumed" != true ]; then
  PATH="$SMOKE_BIN:$PATH" tmux capture-pane -p -t "$PANE" >&2 || true
  [ -f "$WORKSPACE/.freshen/codex-deferred-stop.log" ] \
    && cat "$WORKSPACE/.freshen/codex-deferred-stop.log" >&2
  [ -f "$WORKSPACE/.freshen/transitions.log" ] \
    && cat "$WORKSPACE/.freshen/transitions.log" >&2
  printf 'Freshen smoke: Codex did not consume the continuation signal\n' >&2
  exit 1
fi

find "$WORKSPACE/.freshen/.codex-reset" -maxdepth 1 -type d \
  -name 'completed-*' -print -quit | grep -q .
grep -q 'phase session-start-ack' "$WORKSPACE/.freshen/transitions.log"
grep -q 'phase continuation-stop' "$WORKSPACE/.freshen/transitions.log"

printf 'PASS: real Codex CLI completed Freshen /new and resumed queued command\n'
