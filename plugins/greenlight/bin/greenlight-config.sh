#!/usr/bin/env bash
# Manage sparse Greenlight overrides. Exit 0=success, 1=operation, 2=usage.

set -o pipefail
PLUGIN_ROOT="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}}"
# shellcheck source=../lib/config.sh
source "$PLUGIN_ROOT/lib/config.sh" || exit 1

# Reject invalid requests before any directory, lock, backup, or edit is created.
usage_error() {
  printf 'greenlight config: %s\nUsage: greenlight-config.sh status | get KEY | set KEY VALUE | unset KEY... | add/remove LIST TOKEN | reset\n' "$*" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || { gl_config_error 'jq is required'; exit 1; }
VERB="${1:-status}"
[[ $# == 0 ]] || shift
GL_EDIT_KEYS=(); GL_EDIT_VALUE=""
case "$VERB" in
  status|reset) [[ $# == 0 ]] || usage_error "$VERB takes no arguments" ;;
  get) [[ $# == 1 ]] && gl_config_index "$1" || usage_error 'get requires a recognized key' ;;
  set|add|remove)
    [[ $# == 2 ]] && gl_config_index "$1" || usage_error "$VERB requires a recognized key and value"
    gl_config_valid_value "$1" "$2" || usage_error "invalid value for $1"
    if [[ "$VERB" != set ]]; then
      case "$1" in disabled_modes|custom_allow|custom_pass) ;; *) usage_error "$1 is not a list" ;; esac
      [[ -n "$2" && "$2" != *[[:space:]]* ]] || usage_error 'list token must be nonempty and contain no whitespace'
    fi
    GL_EDIT_KEYS=("$1"); GL_EDIT_VALUE="$2" ;;
  unset)
    [[ $# -gt 0 ]] || usage_error 'unset requires at least one key'
    for key in "$@"; do gl_config_index "$key" || usage_error "unknown key: $key"; done
    GL_EDIT_KEYS=("$@") ;;
  *) usage_error "unknown command: $VERB" ;;
esac

gl_config_load "$PLUGIN_ROOT" || exit 1
case "$VERB" in
  get)
    gl_config_index "$1" || exit 1
    printf '%s\n' "${GL_VALUES[GL_INDEX]}" ;;
  status)
    # One jq process; NUL separators preserve tabs, quotes and empty values.
    for n in "${!GL_KEYS[@]}"; do
      printf '%s\0%s\0%s\0%s\0%s\0' "${GL_KEYS[n]}" "${GL_VALUES[n]}" "${GL_DEFAULTS[n]}" "${GL_SOURCES[n]}" "${GL_PINNED[n]}"
    done | jq -Rs 'split("\u0000") | .[:-1] | . as $a |
      {ok:true,settings:(reduce range(0; length; 5) as $i ({};
        .[$a[$i]]={value:$a[$i+1],default:$a[$i+2],source:$a[$i+3],pinned:($a[$i+4]=="true")}))}' ;;
  *)
    # shellcheck source=../lib/config-write.sh
    source "$PLUGIN_ROOT/lib/config-write.sh" || exit 1
    gl_config_write "$VERB" || exit 1 ;;
esac
