"""Durable, revision-checked delivery storage and read-only pipeline guards."""
import fcntl
import json
import os
from pathlib import Path
import tempfile
import time

import delivery_model as model
from delivery_validation import integer, loads, number, validate


def atomic_write(path, value):
    """Persist before replacement and sync the directory before allowing transport."""
    if path.is_symlink():
        raise ValueError(f"refusing symlink artifact: {path}")
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read(root):
    """Validate an existing batch without changing it."""
    if root.is_symlink() or (root / "STATE.json").is_symlink():
        raise ValueError(f"refusing symlink delivery state: {root}")
    s = loads((root / "STATE.json").read_text(encoding="utf-8"))
    try:
        validate(s)
    except (KeyError, TypeError, IndexError) as exc:
        raise ValueError(f"invalid delivery state: {root}: {exc}") from exc
    return s


def inspect_runs(directory):
    """Fail closed on unfinished, legacy, corrupt, or unclean delivery batches."""
    directory = Path(directory).absolute()
    records = []
    try:
        if directory.is_symlink():
            raise ValueError("delivery root is a symlink")
        children = sorted(directory.iterdir()) if directory.exists() else []
        for root in children:
            if root.name == ".gitignore":
                continue
            try:
                s = read(root)
                blocked = s["status"] not in ("succeeded", "reconciled") or bool(s["remaining"])
                records.append(dict(path=str(root), batch_id=s["batch_id"], step=s["step"],
                                    status=s["status"], blocked=blocked, reason=s["reason"],
                                    remaining=s["remaining"]))
            except (OSError, ValueError) as exc:
                records.append(dict(path=str(root), status="unknown", blocked=True, reason=str(exc)))
    except (OSError, ValueError) as exc:
        records.append(dict(path=str(directory), status="unknown", blocked=True, reason=str(exc)))
    blocked = any(r["blocked"] for r in records)
    return dict(ok=True, blocked=blocked, legacy=not records, runs=records,
                display=(f"Delivery recovery required: {directory}; preserve artifacts and inspect runs"
                         if blocked else f"No unresolved recorded deliveries: {directory}; legacy dispatch is unknown"))


def render(root, s):
    """Regenerate human-readable diagnostics from authoritative state."""
    lines = ["# Agent delivery", "", f"Batch: {s['batch_id']}",
             f"Owner: {s['owner']}; step: {s['step']}; status: {s['status']}",
             f"Reason: {s['reason']}", f"Cleanup survivors: {s['remaining']}", "",
             "| Elapsed seconds | Task | Event | Reason |", "|---:|---|---|---|"]
    for event in s["history"]:
        reason = str(event["reason"]).replace("|", "\\|").replace("\n", " ")
        lines.append(f"| {event['at'] - s['created_at']:.1f} | {event['task_id'] or '-'} | {event['event']} | {reason} |")
    atomic_write(root / "LIVENESS.md", "\n".join(lines) + "\n")


def response(root, s, now, since):
    """Return the exact next obligations and newly persisted visible notices."""
    return dict(ok=True, state=s, actions=model.actions(s, now), notices=s["history"][since:],
                display=f"{s['owner']} {s['step']}: {s['status']}; elapsed {now - s['created_at']:.1f}s; "
                        f"reason {s['reason'] or 'collecting'}; audit {root / 'LIVENESS.md'}")


def execute(directory, command, data, clock=None):
    """Run one durable state transition; caller must stop transport on any error."""
    if command not in ("init", "record", "advance", "status", "recover", "finish"):
        raise ValueError(f"unknown command: {command}")
    if not isinstance(data, dict):
        raise ValueError("command input must be a JSON object")
    root = Path(directory).absolute()
    if root.is_symlink() or root.parent.is_symlink():
        raise ValueError(f"refusing symlink delivery directory: {root}")
    wall, mono = (clock or (lambda: (time.time(), time.monotonic())))()
    number(wall, "wall clock")
    number(mono, "monotonic clock")
    if command == "status":
        s = read(root)
        return response(root, s, max(wall, s["created_at"] + mono - s["created_mono"]), 0)
    if command == "init":
        s = model.initialise(data, wall, mono)
        validate(s)
        if root.exists():
            raise ValueError(f"delivery directory already exists: {root}; inspect/recover, never overwrite")
        root.mkdir(parents=True)
        # A local ignore file prevents runtime IDs entering owner commits without
        # rewriting the target project's root ignore policy.
        ignore = root.parent / ".gitignore"
        if not ignore.exists():
            with ignore.open("x", encoding="utf-8") as stream:
                stream.write("*\n")
    fd = os.open(root / ".lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ValueError(f"delivery state busy: {root}") from exc
        since = 0
        now = wall
        if command != "init":
            s = read(root)
            if integer(data.get("revision"), "revision") != s["revision"]:
                raise ValueError(f"revision conflict: current revision is {s['revision']}")
            since = len(s["history"])
            was_terminal = s["status"] in model.TERMINAL
            now = model.advance(s, wall, mono)
            newly_terminal = not was_terminal and s["status"] in model.TERMINAL
            if not newly_terminal:
                if command == "record":
                    model.record(s, data, now)
                elif command == "recover":
                    model.recover(s, data, now)
                elif command == "finish":
                    model.finish(s, data, now)
            if s["status"] not in model.TERMINAL:
                model.advance(s, wall, mono)
            s["revision"] += 1
        validate(s)
        atomic_write(root / "STATE.json", json.dumps(s, indent=2, allow_nan=False) + "\n")
        render(root, s)
        return response(root, s, now, since)
    finally:
        os.close(fd)
