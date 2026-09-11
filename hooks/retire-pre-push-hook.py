#!/usr/bin/env python3
"""Retire Agentics' global test hook without changing repository test policy."""

import argparse
import copy
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shlex
import stat
import sys
import tempfile


def read_regular(path, home):
    """Snapshot a regular file, refusing redirected paths and special files."""
    for component in (path, *path.parents):
        if component == home:
            break
        if component.is_symlink():
            raise ValueError(f"refusing symlink: {component}")
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None
    with os.fdopen(descriptor, "rb") as handle:
        metadata = os.fstat(handle.fileno())
        if not stat.S_ISREG(metadata.st_mode):
            raise ValueError(f"not a regular file: {path}")
        return handle.read(), stat.S_IMODE(metadata.st_mode)


def unique_object(pairs):
    """Refuse duplicate JSON keys rather than silently discard user settings."""
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def is_retired_command(command, home, target):
    """Recognize only the installed hook's direct shell invocation."""
    if not isinstance(command, str):
        raise ValueError("hook command must be a string")
    spellings = (str(target), str(target).replace(str(home), "$HOME", 1),
                 str(target).replace(str(home), "${HOME}", 1),
                 str(target).replace(str(home), "~", 1))
    try:
        words = shlex.split(command)
    except ValueError:
        if "pre-push-tests.sh" in command:
            raise ValueError(f"unrecognized retired-hook invocation: {command}")
        return False
    if words[:1] in (["bash"], ["/bin/bash"], ["/usr/bin/bash"]):
        words = words[1:]
    if len(words) == 1 and words[0] in spellings:
        return True
    if any(spelling in command for spelling in spellings):
        raise ValueError(f"unrecognized retired-hook invocation: {command}")
    return False


def without_hook(encoded, home, target):
    """Remove matching registrations while retaining every unrelated JSON value."""
    data = json.loads(encoded, object_pairs_hook=unique_object)
    if not isinstance(data, dict):
        raise ValueError("settings must be a JSON object")
    updated = copy.deepcopy(data)
    events = updated.get("hooks", {})
    if not isinstance(events, dict):
        raise ValueError("hooks must be a JSON object")
    for event, entries in events.items():
        if not isinstance(entries, list):
            raise ValueError(f"hooks.{event} must be an array")
        remaining = []
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("hooks"), list):
                raise ValueError(f"hooks.{event} entry must contain a hooks array")
            kept = []
            removed = False
            for hook in entry["hooks"]:
                if not isinstance(hook, dict):
                    raise ValueError(f"hooks.{event} hook must be an object")
                if hook.get("type") == "command" and is_retired_command(
                    hook.get("command"), home, target
                ):
                    removed = True
                else:
                    kept.append(hook)
            if not removed or kept:
                entry["hooks"] = kept
                remaining.append(entry)
        events[event] = remaining
    return None if updated == data else (json.dumps(updated, indent=2) + "\n").encode()


def changes_for(home):
    """Validate both host installations completely before planning any write."""
    changes = []
    for host, settings in (("claude", "settings.json"), ("codex", "hooks.json")):
        directory = home / f".{host}"
        target = directory / "hooks/pre-push-tests.sh"
        path = directory / settings
        snapshot = read_regular(path, home)
        if snapshot is not None:
            try:
                updated = without_hook(snapshot[0], home, target)
            except ValueError as error:
                raise ValueError(f"{path}: {error}") from error
            if updated is not None:
                changes.append((path, snapshot, updated))
        snapshot = read_regular(target, home)
        if snapshot is not None:
            changes.append((target, snapshot, None))
    # All registrations leave before either executable, including on partial failure.
    return sorted(changes, key=lambda change: change[2] is None)


def apply_changes(home, changes):
    """Back up exact inputs before atomic settings replacement and hook removal."""
    if not changes:
        return None
    parent = home / ".local/state/agentics/retired-pre-push"
    for component in (parent, *parent.parents):
        if component == home:
            break
        if component.is_symlink():
            raise ValueError(f"refusing symlink backup directory: {component}")
    parent.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-")
    backup = Path(tempfile.mkdtemp(prefix=stamp, dir=parent))
    try:
        for path, (encoded, mode), _ in changes:
            saved = backup / path.relative_to(home)
            saved.parent.mkdir(parents=True, exist_ok=True)
            with saved.open("xb") as handle:
                os.fchmod(handle.fileno(), mode)
                handle.write(encoded)
                handle.flush()
                os.fsync(handle.fileno())
        for path, snapshot, updated in changes:
            if read_regular(path, home) != snapshot:
                raise ValueError(f"file changed during retirement: {path}")
            if updated is None:
                path.unlink()
                continue
            descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
            try:
                with os.fdopen(descriptor, "wb") as handle:
                    os.fchmod(handle.fileno(), snapshot[1])
                    handle.write(updated)
                    handle.flush()
                    os.fsync(handle.fileno())
                os.replace(temporary, path)
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)
    except (OSError, ValueError) as error:
        raise ValueError(f"retirement incomplete; backups: {backup}; {error}") from error
    return str(backup)


def main():
    """Check retirement by default; mutate only on an explicit --apply request."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--apply", action="store_true", help="back up and retire both host copies")
    args = parser.parse_args()
    home = args.home.expanduser().resolve()
    try:
        changes = changes_for(home)
        backup = apply_changes(home, changes) if args.apply else None
        print(json.dumps({"status": "retired" if args.apply or not changes else "pending",
                          "paths": [str(change[0]) for change in changes], "backup": backup}))
        return 0 if args.apply or not changes else 1
    except (OSError, ValueError) as error:
        print(f"retire-pre-push-hook: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
