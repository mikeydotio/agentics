#!/usr/bin/env bash
# Install / verify the repo's copy of the pre-push test gate.
#
# The gate is a PreToolUse hook that Claude Code loads from an absolute path
# under $HOME. It cannot be loaded from a plugin (that would ride the
# version-keyed plugin install cache, which is stale by 1.5 majors on this
# machine — AGE-72) and it cannot source a repo file (it must work from any
# checkout, including none). So the installed file is necessarily a COPY, and
# the only honest way to run a copy is to make the drift visible:
#
#   install   back the current installed file up, copy this repo's, print digests
#   check     report whether the installed file matches this repo's
#
# ⚠ Neither verb touches ~/.claude/settings.json. The registration — same path,
# same declared timeout — is deliberately left alone, so the gate's derived
# budget and tests/gate-deadline.sh's keep resolving exactly as before.
#
# ⚠ NOT part of `make test`. Both verbs read, and `install` writes, outside the
# repository; a gate that mutates $HOME as a side effect of running the suite
# would be a far worse defect than the one this fixes. PREPUSH_HOOK_DEST exists
# so tests/prepush-gate.sh can exercise both verbs against a fixture directory
# instead — which is why this file has coverage at all despite never being run
# against a real $HOME by the suite.

set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pre-push-tests.sh"
DEST="${PREPUSH_HOOK_DEST:-$HOME/.claude/hooks/pre-push-tests.sh}"

digest() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

usage() { echo "usage: install-pre-push-hook.sh {install|check}" >&2; exit 2; }

[ -f "$SRC" ] || { echo "install-pre-push-hook: missing source $SRC" >&2; exit 1; }

case "${1:-}" in
    install)
        mkdir -p "$(dirname "$DEST")" || exit 1
        if [ -f "$DEST" ]; then
            if [ "$(digest "$SRC")" = "$(digest "$DEST")" ]; then
                echo "install-pre-push-hook: already current at $DEST"
                echo "  sha256 $(digest "$SRC")"
                exit 0
            fi
            backup="${DEST}.bak.$(date -u '+%Y%m%dT%H%M%SZ')"
            cp -p "$DEST" "$backup" || exit 1
            echo "install-pre-push-hook: backed up the previous gate"
            echo "  $backup"
        fi
        cp "$SRC" "$DEST" || exit 1
        chmod +x "$DEST" || exit 1
        echo "install-pre-push-hook: installed $SRC -> $DEST"
        echo "  sha256 $(digest "$DEST")"
        ;;
    check)
        if [ ! -f "$DEST" ]; then
            echo "install-pre-push-hook: NOT INSTALLED — no file at $DEST" >&2
            echo "  run: make install-hooks" >&2
            exit 1
        fi
        if [ "$(digest "$SRC")" = "$(digest "$DEST")" ]; then
            echo "install-pre-push-hook: installed gate matches this repo"
            echo "  sha256 $(digest "$SRC")  $DEST"
            exit 0
        fi
        echo "install-pre-push-hook: DRIFT — the installed gate differs from this repo" >&2
        echo "  repo      $(digest "$SRC")  $SRC" >&2
        echo "  installed $(digest "$DEST")  $DEST" >&2
        echo "  run: make install-hooks   (the previous file is backed up first)" >&2
        exit 1
        ;;
    *) usage ;;
esac
