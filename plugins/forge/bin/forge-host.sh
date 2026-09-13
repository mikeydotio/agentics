#!/usr/bin/env bash
# Shared host boundary; callers source this without changing shell options.

# forge_resume_command <host> <command> — translate only a leading Forge invocation.
forge_resume_command() {
  local host="$1" command="$2"
  if [ "$host" = codex ]; then
    case "$command" in
      /forge) command='$forge:forge' ;;
      '/forge '*) command="\$forge:forge ${command#'/forge '}" ;;
    esac
  fi
  printf '%s\n' "$command"
}

# forge_freshen <root> <host> <args...> — call the selected native CLI.
forge_freshen() {
  local root="$1" host="$2" dependency
  shift 2
  if [ "$host" = codex ]; then
    dependency="$(bash "$root/bin/resolve-dependency.sh" freshen)" || return $?
    bash "$dependency/codex/bin/freshen.sh" "$@"
  else
    bash "$root/../freshen/bin/freshen.sh" "$@" 2>/dev/null
  fi
}
