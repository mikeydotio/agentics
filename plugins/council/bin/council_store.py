"""Durable command boundary for the Council protocol; only the chair writes state."""
import fcntl
import json
import os
from pathlib import Path
import tempfile
import time

import council_model as model
from council_validation import integer, loads, number, validate_state


def _system_clock():
    """Read clocks whose epochs remain stable across supported helper processes."""
    try:
        wall = time.time()
    except OSError as exc:
        raise ValueError(f"system wall clock unavailable: {exc}") from exc
    try:
        mono = time.clock_gettime(time.CLOCK_MONOTONIC)
    except (AttributeError, OSError, ValueError) as exc:
        raise ValueError(f"system monotonic clock unavailable: {exc}") from exc
    return wall, mono


def atomic_write(path, content):
    """Replace one artifact durably without exposing partially written JSON."""
    if path.is_symlink():
        raise ValueError(f"refusing symlink artifact: {path}")
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def render(root, s):
    """Regenerate chair-owned diagnostics after authoritative state is durable."""
    events = [h for h in s["history"] if h["event"] in
              ("retry", "probe", "extension", "abstain", "abort", "recovered", "cleanup")]
    lines = ["# Council Liveness", "", f"Council: {s['council_id']}",
             f"Status: {s['status']}; phase: {s['phase'] or 'not dispatched'}", "",
             "| Elapsed seconds | Phase | Seat | Event | Reason |", "|---:|---|---|---|---|"]
    for h in events:
        reason = h["reason"].replace("|", "\\|").replace("\n", " ")
        lines.append(f"| {h['at'] - s['created_at']:.1f} | {h['phase']} | {h['seat'] or '-'} | {h['event']} | {reason} |")
    atomic_write(root / "LIVENESS.md", "\n".join(lines) + "\n")
    abstentions = [h for h in events if h["event"] == "abstain"]
    if abstentions:
        panel = root / "PANEL.md"
        marker = "<!-- COUNCIL LIVENESS ABSTENTIONS -->"
        ending = "<!-- END COUNCIL LIVENESS ABSTENTIONS -->"
        existing = panel.read_text() if panel.exists() else "# Council Panel\n"
        section = "\n## Abstentions\n\n" + "\n".join(
            f"- Seat {h['seat']} abstained from {h['phase']}: {h['reason']}"
            for h in abstentions) + "\n"
        block = marker + section + ending
        if marker in existing:
            before, rest = existing.split(marker, 1)
            if ending not in rest:
                raise ValueError("PANEL.md has an incomplete generated abstention block")
            existing = before + block + rest.split(ending, 1)[1]
        else:
            existing += "\n" + block + "\n"
        atomic_write(panel, existing)
    if s["status"] == "aborted":
        seats = "\n".join(f"- Seat {x['seat']} ({x['archetype']}): {x.get('status', 'never dispatched')}; "
                           f"{x.get('reason', '')}; agent={x.get('agent_id')}"
                           for x in s["seats"].values())
        artifacts = ["QUESTION.md", "PANEL.md", "STATE.json", "LIVENESS.md"]
        phase_artifacts = {"research": ["proposals-round-1.md"], "vote": ["vote-round-1.md"],
                           "deliberation": ["deliberation.md", "proposals-round-2.md"],
                           "runoff": ["vote-round-2.md"]}
        for phase in s["phases"]:
            artifacts.extend(phase_artifacts[phase])
        atomic_write(root / "ABORT.md", f"# Council Aborted\n\nQuestion: {s['question']}\n\n"
                     f"Phase: {s['phase']}\n\nReason: {s['reason']}\n\n{seats}\n\n"
                     "## Salvageable evidence\n\nAccepted raw responses remain in STATE.json. "
                     "Phase Markdown may require regeneration after a crash.\n\n" +
                     "\n".join(f"- [{name}]({name})" for name in artifacts) + "\n")
    elif s["status"] == "decided":
        atomic_write(root / "DECISION.md", s["decision"] +
                     "\n\nLiveness and degraded participation: [LIVENESS.md](LIVENESS.md).\n")


def _load(root):
    path = root / "STATE.json"
    if path.is_symlink():
        raise ValueError("refusing symlink STATE.json")
    try:
        state = loads(path.read_text())
        validate_state(state)
    except (ValueError, TypeError) as exc:
        raise ValueError(f"cannot read state {path}: {exc}") from exc
    for seat in state["seats"].values():
        if "scratch" in seat and Path(seat["scratch"]) != root / "scratch" / seat["attempt_id"]:
            raise ValueError("invalid state: scratch path does not match attempt identity")
    return state


def _response(root, s, now, since):
    notices = [h for h in s["history"][since:] if h["event"] in
               ("retry", "probe", "extension", "abstain", "abort", "recovered", "cleanup")]
    return {"ok": True, "state": s, "actions": model.actions(s, now), "notices": notices,
            "display": f"Council {s['council_id']}: {s['status']} ({s['phase'] or 'not dispatched'}); "
                       f"elapsed {now - s['created_at']:.1f}s; audit {root / 'LIVENESS.md'}"}


def execute(root, command, data, clock=None):
    """Execute one revision-checked command against a council directory."""
    if command not in ("init", "begin-phase", "record", "advance", "status", "recover", "finish"):
        raise ValueError(f"unknown command: {command}")
    if not isinstance(data, dict):
        raise ValueError("command input must be a JSON object")
    root = Path(root).absolute()
    if root.is_symlink():
        raise ValueError("refusing symlink council directory")
    now, mono = (clock or _system_clock)()
    number(now, "wall clock")
    number(mono, "monotonic clock")
    if command == "init":
        root.mkdir(parents=True, exist_ok=True)
    if command == "status":
        state = _load(root)
        return _response(root, state, model.observed_time(state, now, mono), 0)
    lock = root / ".state.lock"
    fd = os.open(lock, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ValueError(f"council state busy: {root}") from exc
        if command == "init":
            if any((root / name).exists() for name in ("STATE.json", "DECISION.md", "ABORT.md")):
                raise ValueError("council already exists; use status/recover, never overwrite")
            state = model.initialise(data, now, mono)
            since = 0
        else:
            state = _load(root)
            if integer(data.get("revision"), "revision") != state["revision"]:
                raise ValueError(f"revision conflict: current revision is {state['revision']}")
            since = len(state["history"])
            was_terminal = state["status"] in model.TERMINAL
            now = model.advance(state, now, mono, root)
            newly_terminal = not was_terminal and state["status"] in model.TERMINAL
            if not newly_terminal:
                if command == "begin-phase":
                    model.begin_phase(state, data, now, root)
                elif command == "record":
                    if data.get("kind") == "cleanup" and was_terminal:
                        remaining = data.get("remaining")
                        if not isinstance(remaining, list) or any(not isinstance(x, str) for x in remaining):
                            raise ValueError("cleanup remaining must list agent IDs")
                        model.note(state, now, "cleanup", reason=f"agents not stopped: {remaining}")
                    else:
                        model.record(state, data, now, root)
                elif command == "recover":
                    model.recover(state, data, now)
                elif command == "finish":
                    model.finish(state, data, now)
            state["revision"] += 1
        validate_state(state)
        # State precedes every external side effect, including scratch creation.
        atomic_write(root / "STATE.json", json.dumps(state, indent=2, allow_nan=False) + "\n")
        for seat in state["seats"].values():
            if seat.get("status") == "prepared":
                scratch = Path(seat["scratch"])
                if scratch.is_symlink() or scratch.parent.is_symlink():
                    raise ValueError(f"refusing symlink scratch directory: {scratch}")
                scratch.mkdir(parents=True, exist_ok=True, mode=0o700)
        render(root, state)
        return _response(root, state, now, since)
    finally:
        os.close(fd)
