"""Owner-independent bounded delivery transitions; no transport or filesystem effects."""
import uuid

from delivery_validation import body, digest, integer, text

TERMINAL = ("succeeded", "failed", "interrupted", "reconciled")


def note(s, now, event, task=None, reason=""):
    """Persist a visible decision with enough identity to audit it independently."""
    s["history"].append(dict(at=now, event=event, task_id=task["task_id"] if task else None,
                             attempt_id=task["attempt_id"] if task else None, reason=reason))


def terminal(s, now, outcome, reason):
    """Make an outcome durable before issuing bounded cleanup actions."""
    s["status"] = outcome
    s["reason"] = reason
    s["cleanup_deadline"] = now + 30
    for t in s["tasks"]:
        if t["status"] != "accepted":
            t["status"] = "interrupted" if outcome == "interrupted" else "failed"
    s["remaining"] = [t["agent_id"] for t in s["tasks"] if t["agent_id"] and not t["stopped"]]
    note(s, now, outcome, reason=reason)


def prepare_wave(s, now):
    """Start one fixed wave; earlier slow work cannot increase the batch ceiling."""
    for i in s["waves"][s["wave"]]:
        t = s["tasks"][i]
        t["status"] = "prepared"
        t["ceiling"] = min(s["deadline"], now + sum(t["budget"]))
        t["deadline"] = min(t["ceiling"], now + t["budget"][0])


def initialise(data, now, mono):
    """Validate and persist the entire roster before emitting a dispatch action."""
    owner = data.get("owner")
    host = data.get("host")
    if owner not in ("agents", "forge", "rca") or host not in ("claude", "codex"):
        raise ValueError("owner/host must name a supported protocol")
    capacity = integer(data.get("capacity"), "capacity", 1)
    roster = data.get("tasks")
    if not isinstance(roster, list) or not roster:
        raise ValueError("tasks must be a nonempty list")
    tasks = []
    waves = []
    for i, source in enumerate(roster):
        if not isinstance(source, dict) or type(source.get("writer")) is not bool:
            raise ValueError("each task must declare writer as a boolean")
        role = text(source.get("role"), "role")
        task = text(source.get("task"), "task")
        writer = source["writer"]
        budget = ([1800, 300, 0] if writer else [600, 120, 120]
                  if owner == "forge" and role in ("evaluator", "reviewer", "triager") else [900, 300, 300])
        tasks.append(dict(task_id=text(source.get("task_id"), "task_id"), task=task,
                          task_digest=digest(task), role=role, writer=writer, budget=budget,
                          status="queued", attempt=1, attempt_id=str(uuid.uuid4()), agent_id=None,
                          deadline=None, ceiling=None, probe_sent=False, extended=False,
                          stopped=False, integrity_ok=False, payload=None))
        if writer or not waves or len(waves[-1]) >= capacity or tasks[waves[-1][0]]["writer"]:
            waves.append([i])
        else:
            waves[-1].append(i)
    ceiling = sum(max(sum(tasks[i]["budget"]) for i in wave) for wave in waves)
    s = dict(schema=1, batch_id=str(uuid.uuid4()), owner=owner, host=host,
             session=text(data.get("session"), "session"), step=text(data.get("step"), "step"),
             capacity=capacity, tasks=tasks, waves=waves, wave=0, status="running", reason="",
             revision=0, created_at=now, created_mono=mono, last_mono=mono, last_wall=now,
             deadline=now + ceiling, history=[], remaining=[], cleanup_deadline=None, cleanup_mono=None)
    prepare_wave(s, now)
    note(s, now, "prepared", reason="Whole roster persisted before native dispatch")
    return s


def fail(s, t, now, reason, category="transport"):
    """Retry only a stopped, verified reader; every other failure halts the batch."""
    if t["writer"] or t["attempt"] >= 2 or category != "transport" or now >= t["ceiling"]:
        terminal(s, now, "failed", f"Task {t['task_id']}: {category}: {reason}")
        return
    t["status"] = "stopping"
    t["deadline"] = min(now + 30, t["ceiling"])
    note(s, now, "retry-pending", t, reason)


def advance(s, wall, mono):
    """Apply monotonic deadlines before every action and transport event."""
    now = s["created_at"] + mono - s["created_mono"]
    if s["status"] in TERMINAL:
        elapsed = mono - s["cleanup_mono"]
        return s["cleanup_deadline"] if elapsed < 0 else s["cleanup_deadline"] - 30 + elapsed
    if mono < s["last_mono"] or wall < s["last_wall"] or abs(wall - now) > 5:
        terminal(s, max(now, s["last_wall"]), "interrupted", "Clock discontinuity; no fresh deadline")
        return max(now, s["last_wall"])
    s["last_mono"], s["last_wall"] = mono, wall
    if now >= s["deadline"]:
        terminal(s, now, "failed", "Batch delivery ceiling reached")
        return now
    for t in s["tasks"]:
        if t["status"] in ("queued", "accepted"):
            continue
        if now >= t["ceiling"]:
            terminal(s, now, "failed", f"Task {t['task_id']}: delivery ceiling reached")
        elif now >= t["deadline"]:
            if t["status"] in ("prepared", "dispatch-attempted"):
                terminal(s, now, "interrupted", f"Task {t['task_id']}: dispatch unconfirmed")
            elif t["status"] == "stopping":
                terminal(s, now, "failed", f"Task {t['task_id']}: shutdown/integrity unconfirmed")
            elif t["status"] == "pending" and not t["extended"] and t["attempt"] == 1:
                t["status"] = "probing"
                t["extension_end"] = min(t["deadline"] + t["budget"][1], t["ceiling"])
                t["deadline"] = min(t["deadline"] + 30, t["extension_end"])
                note(s, now, "probe", t, "Initial deadline; inspect exact native identity")
                if now >= t["deadline"]:
                    fail(s, t, now, "No current progress at probe deadline")
            else:
                fail(s, t, now, "Delivery deadline reached")
        if s["status"] in TERMINAL:
            return now
    current = [s["tasks"][i] for i in s["waves"][s["wave"]]]
    if all(t["status"] == "accepted" for t in current):
        if s["wave"] + 1 == len(s["waves"]):
            s["status"] = "ready"
        elif all(t["stopped"] and t["integrity_ok"] for t in current):
            s["wave"] += 1
            prepare_wave(s, now)
    else:
        s["status"] = "running"
    return now


def delivery(s, t, data, now):
    """Accept only current identity and payload; never reinterpret a stale message."""
    if t["status"] not in ("pending", "probing") or data.get("sender") != t["agent_id"]:
        note(s, now, "rejected", t, "Non-pending or wrong native sender")
        return
    try:
        result = body(data.get("body"))
    except ValueError as exc:
        fail(s, t, now, f"Malformed delivery: {exc}")
        return
    identities = dict(batch_id=s["batch_id"], task_id=t["task_id"],
                      task_digest=t["task_digest"], attempt_id=t["attempt_id"])
    if any(result.get(k) != v for k, v in identities.items()):
        note(s, now, "rejected", t, "Stale/wrong batch, task, digest or attempt")
    elif result.get("kind") == "failure":
        try:
            reason = text(result.get("reason"), "failure reason")
            category = result.get("category", "transport")
            if category not in ("transport", "permission", "capability", "integrity"):
                raise ValueError("invalid failure category")
        except ValueError as exc:
            fail(s, t, now, f"Malformed failure envelope: {exc}")
        else:
            fail(s, t, now, reason, category)
    elif result.get("kind") != "result" or "payload" not in result or result["payload"] is None:
        fail(s, t, now, "Result has no valid payload/kind")
    else:
        t["payload"] = result["payload"]
        t["status"] = "accepted"
        note(s, now, "accepted", t, "Correlated delivery; owner must verify semantics/integrity")


def record(s, data, now):
    """Record one observed event, never substituting a requested name for an ID."""
    kind = data.get("kind")
    matches = [t for t in s["tasks"] if t["task_id"] == data.get("task_id")]
    if not matches:
        raise ValueError("unknown task_id")
    t = matches[0]
    if data.get("attempt_id") != t["attempt_id"]:
        note(s, now, "rejected", t, "Retired attempt event")
        return
    if kind == "stopped":
        if not t["agent_id"] or data.get("agent_id") != t["agent_id"]:
            raise ValueError("stopped must identify an owned native agent")
        if data.get("stopped") is not True:
            note(s, now, "cleanup", t, "Stop unconfirmed")
            return
        t["stopped"] = True
        t["integrity_ok"] = data.get("integrity_ok") is True
        s["remaining"] = [a for a in s["remaining"] if a != t["agent_id"]]
        note(s, now, "stopped", t, t["agent_id"])
        if s["status"] not in TERMINAL and t["status"] == "stopping":
            if not t["integrity_ok"]:
                terminal(s, now, "failed", "Retry refused: integrity check failed")
                return
            note(s, now, "retry", t, f"Stopped {t['agent_id']}; prior integrity verified")
            t.update(attempt=2, attempt_id=str(uuid.uuid4()), agent_id=None, stopped=False,
                     integrity_ok=False, status="prepared", probe_sent=False, extended=True, payload=None,
                     deadline=min(now + t["budget"][2], t["ceiling"]))
        return
    if s["status"] in TERMINAL:
        note(s, now, "rejected", t, "Terminal batch cannot accept transport")
        return
    if kind == "delivery":
        delivery(s, t, data, now)
    elif kind == "failure":
        fail(s, t, now, text(data.get("reason"), "reason"), data.get("category", "transport"))
    elif kind == "dispatch-attempted" and t["status"] == "prepared":
        t["status"] = "dispatch-attempted"
        note(s, now, kind, t)
    elif kind == "dispatched" and t["status"] == "dispatch-attempted":
        native = text(data.get("agent_id"), "agent_id")
        if any(other["agent_id"] == native for other in s["tasks"]):
            raise ValueError("native identity already owned by a task")
        t.update(agent_id=native, status="pending")
        note(s, now, kind, t, native)
    elif kind == "probe-attempted" and t["status"] == "probing" and not t["probe_sent"]:
        t["probe_sent"] = True
        note(s, now, kind, t)
    elif kind == "progress":
        if data.get("agent_id") != t["agent_id"]:
            note(s, now, "rejected", t, "Wrong native progress identity")
            return
        if t["status"] == "probing" and t["probe_sent"]:
            if data.get("working") is True and isinstance(data.get("evidence"), str) and data["evidence"].strip():
                t.update(status="pending", extended=True, deadline=t["extension_end"])
                note(s, now, "extension", t, data["evidence"])
            else:
                fail(s, t, now, "Idle/dead/unknown worker earns no extension")
        else:
            note(s, now, "rejected", t, "Progress outside the one probe")
    else:
        raise ValueError(f"invalid event {kind} for task state {t['status']}")


def recover(s, data, now):
    """Preserve only confirmed same-session work; never resend uncertain attempts."""
    if s["status"] in TERMINAL:
        return
    reachable = data.get("reachable")
    if not isinstance(reachable, list) or any(not isinstance(a, str) for a in reachable):
        raise ValueError("reachable must list observed native IDs")
    uncertain = any(t["status"] == "dispatch-attempted" or
                    (t["agent_id"] and not t["stopped"] and t["agent_id"] not in reachable)
                    for t in s["tasks"])
    if data.get("session") != s["session"] or uncertain:
        terminal(s, now, "interrupted", "Owner changed, uncertain send or unreachable owned agent")
    else:
        note(s, now, "recovered", reason="Original owner, identities and deadlines retained")


def finish(s, data, now):
    """Owner acknowledgement cannot manufacture successful worker results."""
    outcome = data.get("outcome")
    if outcome == "reconciled":
        if s["status"] not in ("failed", "interrupted") or s["remaining"]:
            raise ValueError("reconciliation requires terminal failure and confirmed shutdown")
        attempted = {e["attempt_id"] for e in s["history"] if e["event"] == "dispatch-attempted"}
        confirmed = {e["attempt_id"] for e in s["history"] if e["event"] == "dispatched"}
        if attempted - confirmed:
            raise ValueError("uncertain native dispatch requires external identity reconciliation")
        if data.get("integrity_ok") is not True or data.get("artifacts_reconciled") is not True:
            raise ValueError("reconciliation requires integrity and artifact review")
        s["status"] = "reconciled"
        note(s, now, "reconciled", reason=text(data.get("reason"), "reason"))
    elif s["status"] in TERMINAL:
        raise ValueError("batch is already terminal")
    elif outcome == "succeeded":
        if s["status"] != "ready" or data.get("integrity_ok") is not True:
            raise ValueError("success requires all deliveries and verified integrity")
        for t in s["tasks"]:
            t["integrity_ok"] = True
        terminal(s, now, "succeeded", "All required results and owner checks complete")
    elif outcome in ("failed", "interrupted"):
        terminal(s, now, outcome, text(data.get("reason"), "reason"))
    else:
        raise ValueError("invalid finish outcome")


def actions(s, now):
    """Return bounded transport obligations; expired cleanup never blocks return."""
    result = []
    if s["status"] in TERMINAL:
        if now < s["cleanup_deadline"]:
            result = [dict(kind="stop", agent_id=a, wait_seconds=min(30, s["cleanup_deadline"] - now))
                      for a in s["remaining"]]
        return result
    for t in s["tasks"]:
        identity = dict(task_id=t["task_id"], attempt_id=t["attempt_id"], agent_id=t["agent_id"])
        status = t["status"]
        if status == "prepared":
            result.append(dict(identity, kind="dispatch"))
        elif status == "probing" and not t["probe_sent"]:
            result.append(dict(identity, kind="probe"))
        elif status == "stopping" or (status == "accepted" and not t["stopped"]):
            result.append(dict(identity, kind="stop"))
    deadlines = [t["deadline"] for t in s["tasks"] if t["status"] not in ("queued", "accepted")]
    result.append(dict(kind="finish" if s["status"] == "ready" else "wait",
                       wait_seconds=max(0, min([30, s["deadline"] - now] + [d - now for d in deadlines]))))
    return result
