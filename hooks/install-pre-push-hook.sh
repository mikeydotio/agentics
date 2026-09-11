#!/usr/bin/env bash
# Install/check the standalone pre-push bundle for Claude, Codex, or both.
# Updates preserve unique backups and replace regular files atomically.
# Registrations and plugin caches are never rewritten. The legacy default is
# Claude; PREPUSH_HOOK_DEST retains the custom-path/fixture contract.
set -uo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
operation="${1:-}"
provider=claude
explicit_provider=false

usage() {
    echo "usage: install-pre-push-hook.sh {install|check} [--provider claude|codex|all]" >&2
    exit 2
}
case "$operation" in install|check) ;; *) usage ;; esac
shift
if [ "$#" -gt 0 ]; then
    [ "$#" -eq 2 ] && [ "$1" = --provider ] || usage
    provider="$2"
    explicit_provider=true
fi
case "$provider" in claude|codex|all) ;; *) usage ;; esac
if [ -n "${PREPUSH_HOOK_DEST:-}" ] && [ "$explicit_provider" = true ]; then
    echo "install-pre-push-hook: PREPUSH_HOOK_DEST and --provider are mutually exclusive" >&2
    exit 2
fi

# Missing source cannot silently produce a partial bundle.
for name in pre-push-delegation.py pre-push-tests.sh; do
    [ -f "$source_dir/$name" ] || {
        echo "install-pre-push-hook: missing source $source_dir/$name" >&2
        exit 1
    }
done
digest() { shasum -a 256 "$1" | awk '{print $1}'; }

# Byte equality alone is insufficient for an executable entry point.
current() {
    local source="$1" destination="$2" mode="$3"
    [ -f "$destination" ] && [ ! -L "$destination" ] && [ -r "$destination" ] \
        && cmp -s "$source" "$destination" \
        && { [ "$mode" != 755 ] || [ -x "$destination" ]; }
}

# Install the companion first. A missing companion retains global enforcement.
# Unique backup names preserve repeated repairs within the same second.
install_file() (
    local source="$1" destination="$2" mode="$3" temporary="" backup
    trap '[ -z "$temporary" ] || rm -f "$temporary"' EXIT
    if current "$source" "$destination" "$mode"; then
        echo "install-pre-push-hook: already current at $destination"
        return 0
    fi
    if [ -e "$destination" ]; then
        backup="$(mktemp "${destination}.bak.XXXXXXXX")" || return 1
        cp -p "$destination" "$backup" || return 1
        echo "install-pre-push-hook: backed up the previous gate: $backup"
    fi
    temporary="$(mktemp "${destination}.tmp.XXXXXXXX")" || return 1
    cp "$source" "$temporary" && chmod "$mode" "$temporary" \
        && mv -f "$temporary" "$destination" || return 1
    temporary=""
    echo "install-pre-push-hook: installed $destination (sha256 $(digest "$destination"))"
)

# Verify a literal PreToolUse registration without executing shell text.
registration() {
    python3 - "$1" "$2" <<'PY'
import json
import math
import os
import re
import shlex
import sys

settings, destination = sys.argv[1:]
try:
    with open(settings) as stream:
        data = json.load(stream)
    for entry in data.get("hooks", {}).get("PreToolUse", []):
        matcher = entry.get("matcher", "")
        if matcher not in ("", "*") and not re.search(matcher, "Bash"):
            continue
        for hook in entry.get("hooks", []):
            command = shlex.split(hook.get("command", ""))
            command = [os.path.expanduser(os.path.expandvars(word)) for word in command]
            seconds = hook.get("timeout")
            valid_timeout = (isinstance(seconds, (int, float)) and not isinstance(seconds, bool)
                             and math.isfinite(seconds) and seconds > 0)
            if (hook.get("type") == "command" and valid_timeout
                    and command in (["bash", destination], ["bash", "--", destination], [destination])):
                print(f"install-pre-push-hook: registration verified in {settings}")
                sys.exit(0)
except (OSError, ValueError, AttributeError, TypeError, re.error) as error:
    print(f"install-pre-push-hook: registration unreadable in {settings}: {error}", file=sys.stderr)
    sys.exit(1)
print(f"install-pre-push-hook: registration missing or unsupported in {settings}: {destination}", file=sys.stderr)
sys.exit(1)
PY
}

# A healthy first provider cannot hide a later provider's drift.
process_provider() {
    local selected="$1" destination="$2" settings="$3" directory name source target mode status=0
    directory="$(dirname "$destination")"
    echo "install-pre-push-hook: $operation $selected at $directory"
    if [ "$operation" = install ]; then
        for target in "$destination" "$directory/pre-push-delegation.py"; do
            if [ -L "$target" ] || { [ -e "$target" ] && [ ! -f "$target" ]; }; then
                echo "install-pre-push-hook: refusing non-regular destination $target" >&2
                return 1
            fi
        done
        mkdir -p "$directory" || return 1
    fi
    for name in pre-push-delegation.py pre-push-tests.sh; do
        source="$source_dir/$name"
        target="$directory/$name"
        mode=644
        if [ "$name" = pre-push-tests.sh ]; then target="$destination"; mode=755; fi
        if [ "$operation" = install ]; then
            install_file "$source" "$target" "$mode" || return 1
        elif current "$source" "$target" "$mode"; then
            echo "install-pre-push-hook: current $target"
        else
            echo "install-pre-push-hook: DRIFT — missing, changed, linked, or non-executable: $target" >&2
            status=1
        fi
    done
    if [ -n "$settings" ] && ! registration "$settings" "$destination"; then
        echo "install-pre-push-hook: registration unchanged; repair the named provider registration" >&2
        [ "$operation" = install ] || status=1
    fi
    return "$status"
}

if [ -n "${PREPUSH_HOOK_DEST:-}" ]; then
    process_provider custom "$PREPUSH_HOOK_DEST" ""
    exit "$?"
fi
status=0
for selected in claude codex; do
    [ "$provider" = all ] || [ "$provider" = "$selected" ] || continue
    settings="$HOME/.$selected/settings.json"
    [ "$selected" != codex ] || settings="$HOME/.codex/hooks.json"
    process_provider "$selected" "$HOME/.$selected/hooks/pre-push-tests.sh" "$settings" || status=1
done
exit "$status"
