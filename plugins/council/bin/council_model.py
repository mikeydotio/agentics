"""Council liveness policy, independent of host agent tools and filesystem I/O."""
import copy
import hashlib
import uuid

from council_validation import envelope, integer, payload, text

# A probe's 30 seconds is part of the extension, never an additional budget.
BUDGETS = {"research": (900, 300, 300), "vote": (120, 60, 120),
           "deliberation": (120, 60, 120), "runoff": (120, 60, 120)}
TERMINAL = ("aborted", "decided")
RESOLVED = ("accepted", "abstained", "excluded")


def note(s, now, event, seat=None, reason=""):
    """Append an audit event suitable for user-visible diagnostics."""
    current = s["seats"].get(str(seat), {})
    s["history"].append({"at": now, "phase": s["phase"], "event": event,
                         "seat": seat, "reason": reason, "attempt_id": current.get("attempt_id"),
                         "agent_id": current.get("agent_id"), "scratch": current.get("scratch")})


def initialise(data, now, mono):
    """Create an undispatched sitting with a unique question identity."""
    question = text(data.get("question"), "question")
    chair = text(data.get("chair"), "chair")
    host = data.get("host")
    if host not in ("claude", "codex"):
        raise ValueError("host must be claude or codex")
    roles = data.get("archetypes")
    if not isinstance(roles, list) or len(roles) != 3:
        raise ValueError("exactly three archetypes required")
    for role in roles:
        text(role, "archetype")
    if len(set(roles)) != 3:
        raise ValueError("three distinct archetypes required")
    return {"schema_version": 1, "revision": 0, "council_id": uuid.uuid4().hex,
            "question": question, "question_digest": hashlib.sha256(question.encode()).hexdigest(),
            "chair": chair, "host": host, "created_at": now, "created_mono": mono,
            "clock_wall": now, "clock_mono": mono,
            "status": "ready", "phase": None, "participants": [], "proposals": {}, "phases": {},
            "history": [], "seats": {str(i): {"seat": i, "archetype": role, "agent_id": None,
                                             "proposal_label": None}
                                      for i, role in enumerate(roles, 1)}}


def abort(s, now, reason):
    """End without a winner and start a separate, bounded cleanup window."""
    s.update(status="aborted", reason=reason, cleanup_deadline=now + 30)
    note(s, now, "abort", reason=reason)


def new_attempt(s, seat, root):
    """Mint an unguessable routing token and a private scratch namespace."""
    seat["attempt_id"] = uuid.uuid4().hex
    seat["name"] = f"council_{s['council_id']}_seat_{seat['seat']}_{seat['attempt_id'][:8]}"
    seat["scratch"] = str(root / "scratch" / seat["attempt_id"])
    seat["probe_attempted"] = False


def begin_phase(s, data, now, root):
    """Prepare every phase's dispatch before any native agent call occurs."""
    phase = data.get("phase")
    if not isinstance(phase, str) or phase not in BUDGETS:
        raise ValueError("phase must be research, vote, deliberation, or runoff")
    expected = {None: "research", "research": "vote", "vote": "deliberation",
                "deliberation": "runoff"}.get(s["phase"])
    if phase != expected or s["status"] not in ("ready", "phase-complete"):
        raise ValueError("phase order violation or previous phase not complete")
    if s["phase"] == "vote" and unanimous(s):
        raise ValueError("unanimous vote must finish without deliberation")
    initial, extension, retry = BUDGETS[phase]
    s.update(phase=phase, status="running", phase_started=now, initial_deadline=now + initial,
             hard_deadline=now + initial + extension + retry)
    s["participants"] = []
    for seat in s["seats"].values():
        excluded = phase == "deliberation" and seat["proposal_label"] is None
        needs_stop = (seat.get("status") == "abstained" or seat.get("old_agent_id") is not None) \
            and seat.get("agent_id") is not None
        seat.update(status="excluded" if excluded else "stopping" if needs_stop else "prepared", retry_count=0,
                    deadline=now + initial, extended=False, response=None, reason="",
                    old_agent_id=seat["agent_id"] if needs_stop else None)
        new_attempt(s, seat, root)
        if not excluded:
            s["participants"].append(seat["seat"])
    note(s, now, "begin-phase")


def fail(s, seat, now, reason, root):
    """Route every delivery failure through one retry, then phase abstention."""
    seat["reason"] = reason
    note(s, now, "attempt-failed", seat["seat"], reason)
    if seat["retry_count"] == 0 and now < s["hard_deadline"]:
        seat["retry_count"] = 1
        seat["old_agent_id"] = seat["agent_id"]
        seat["status"] = "stopping" if seat["agent_id"] else "prepared"
        seat["deadline"] = min(now + BUDGETS[s["phase"]][2], s["hard_deadline"])
        new_attempt(s, seat, root)
        note(s, now, "retry", seat["seat"], reason)
    else:
        seat["status"] = "abstained"
        note(s, now, "abstain", seat["seat"], reason)


def complete_phase(s, now):
    """Archive terminal seat outcomes and maintain the surviving proposal slate."""
    if s["status"] != "running":
        return
    seats = [s["seats"][str(n)] for n in s["participants"]]
    if sum(seat["status"] == "abstained" for seat in seats) >= 2:
        abort(s, now, f"two or more abstentions in {s['phase']}")
        return
    if not all(seat["status"] in RESOLVED for seat in seats):
        return
    if s["phase"] == "research":
        accepted = [seat for seat in seats if seat["status"] == "accepted"]
        if len(accepted) == 2:
            order = [h["seat"] for h in s["history"] if h["event"] == "accepted"]
            accepted.sort(key=lambda seat: order.index(seat["seat"]))
        # Stable seat order matches the original A/B/C mapping when all seats deliver.
        for label, seat in zip("ABC", accepted):
            seat["proposal_label"] = label
            s["proposals"][label] = seat["response"]
    elif s["phase"] == "deliberation":
        for seat in seats:
            if seat["status"] == "accepted":
                s["proposals"][seat["proposal_label"]] = seat["response"]["revised_proposal"]
    s["phases"][s["phase"]] = copy.deepcopy(s["seats"])
    s["status"] = "phase-complete"
    note(s, now, "phase-complete")


def advance(s, now, mono, root):
    """Apply elapsed deadlines before accepting any new transport event."""
    if s["status"] in TERMINAL:
        return
    wall_delta, mono_delta = now - s["clock_wall"], mono - s["clock_mono"]
    logical_now = s["created_at"] + mono - s["created_mono"]
    if wall_delta < 0 or mono_delta < 0 or abs(now - logical_now) > 5:
        abort(s, now, "interrupted council: clock discontinuity; original deadlines preserved")
        return
    s.update(clock_wall=now, clock_mono=mono)
    now = logical_now
    if s["status"] != "running":
        return
    for n in s["participants"]:
        seat = s["seats"][str(n)]
        if seat["status"] in RESOLVED or now < seat["deadline"]:
            continue
        if now >= s["hard_deadline"]:
            fail(s, seat, now, "hard phase deadline exhausted", root)
        elif seat["retry_count"] == 0 and not seat["extended"] and seat["status"] == "pending":
            seat.update(status="probing", deadline=min(s["initial_deadline"] + 30,
                                                       s["hard_deadline"]))
            note(s, now, "probe", n, "no validated delivery at initial deadline")
            if now >= seat["deadline"]:
                fail(s, seat, now, "liveness probe deadline exhausted", root)
        else:
            fail(s, seat, now, "response deadline exhausted", root)
    complete_phase(s, now)


def delivery(s, seat, data, now, root):
    """Authenticate routing metadata before classifying substantive payloads."""
    if data.get("sender") != seat["agent_id"] or not seat["agent_id"]:
        note(s, now, "ignored", seat["seat"], "sender mismatch")
        return
    try:
        message = envelope(data.get("body"))
    except ValueError as exc:
        fail(s, seat, now, f"malformed delivery: {exc}", root)
        return
    identity = {"council_id": s["council_id"], "question_digest": s["question_digest"],
                "phase": s["phase"], "seat": seat["seat"], "attempt_id": seat["attempt_id"]}
    if any(message.get(key) != value or type(message.get(key)) is not type(value)
           for key, value in identity.items()):
        note(s, now, "ignored", seat["seat"], "envelope identity mismatch")
        return
    try:
        if message.get("kind") == "failure":
            fail(s, seat, now, text(message.get("reason"), "reason"), root)
            return
        if message.get("kind") != "result":
            raise ValueError("expected result or failure message kind")
        payload(message.get("payload"), s["phase"], seat["seat"], s["proposals"], seat["proposal_label"])
    except ValueError as exc:
        fail(s, seat, now, f"invalid payload: {exc}", root)
        return
    seat.update(status="accepted", response=message["payload"], reason="")
    note(s, now, "accepted", seat["seat"])


def record(s, data, now, root):
    """Apply one chair-observed event for the current seat attempt."""
    if s["phase"] is None:
        raise ValueError("record requires a dispatched phase")
    n = integer(data.get("seat"), "seat")
    if str(n) not in s["seats"]:
        raise ValueError("unknown seat")
    seat = s["seats"][str(n)]
    if data.get("attempt_id") != seat.get("attempt_id"):
        note(s, now, "ignored", n, "stale attempt event")
        return
    kind = data.get("kind")
    if s["status"] in TERMINAL or seat.get("status") in RESOLVED:
        note(s, now, "ignored", n, "terminal or duplicate event")
        return
    status = seat.get("status")
    if kind == "dispatch-attempted" and status == "prepared":
        seat["status"] = "dispatch-attempted"
    elif kind == "probe-attempted" and status == "probing" and not seat["probe_attempted"]:
        seat["probe_attempted"] = True
    elif kind == "dispatched" and status == "dispatch-attempted":
        agent = text(data.get("agent_id"), "agent_id")
        if any(other["seat"] != n and other.get("agent_id") == agent for other in s["seats"].values()):
            raise ValueError("agent identity already belongs to another seat")
        seat.update(agent_id=agent, status="pending")
    elif kind == "stopped" and status == "stopping":
        if data.get("agent_id") != seat["old_agent_id"] or data.get("stopped") is not True:
            fail(s, seat, now, "could not confirm old attempt stopped", root)
        else:
            seat.update(status="prepared", old_agent_id=None)
    elif kind == "failure":
        fail(s, seat, now, text(data.get("reason"), "reason"), root)
    elif kind == "delivery" and status in ("pending", "probing"):
        delivery(s, seat, data, now, root)
    elif kind == "liveness" and status in ("pending", "probing"):
        if data.get("agent_id") != seat["agent_id"]:
            note(s, now, "ignored", n, "liveness identity mismatch")
            return
        if status == "probing":
            if data.get("working") is True and isinstance(data.get("evidence"), str) and data["evidence"].strip():
                seat.update(status="pending", extended=True,
                            deadline=s["initial_deadline"] + BUDGETS[s["phase"]][1])
                note(s, now, "extension", n, data["evidence"])
            else:
                fail(s, seat, now, "seat idle, dead, blocked, or liveness unavailable", root)
    elif kind == "delivery":
        note(s, now, "ignored", n, "delivery outside a confirmed pending attempt")
    else:
        raise ValueError(f"invalid event {kind!r} for seat {n} in {status}")
    note(s, now, kind, n)
    complete_phase(s, now)


def unanimous(s):
    """Use the existing unanimity rule over the ballots actually returned."""
    choices = [x["response"]["choice"] for x in s["seats"].values() if x["status"] == "accepted"]
    return len(choices) >= 2 and len(set(choices)) == 1


def finish(s, data, now):
    """Persist a chair-rendered decision only after the required voting path."""
    if s["status"] in TERMINAL:
        raise ValueError("council already terminal")
    if data.get("outcome") == "abort":
        abort(s, now, text(data.get("reason"), "reason"))
    elif data.get("outcome") == "decision":
        if s["status"] != "phase-complete" or s["phase"] not in ("vote", "runoff"):
            raise ValueError("decision requires a completed vote or runoff")
        if s["phase"] == "vote" and not unanimous(s):
            raise ValueError("split vote requires deliberation and runoff")
        s.update(status="decided", reason="chair recorded decision after completed ballots",
                 decision=text(data.get("markdown"), "markdown"), cleanup_deadline=now + 30)
        note(s, now, "decision")
    else:
        raise ValueError("outcome must be abort or decision")


def recover(s, data, now):
    """Require the same chair and reconcilable native identities to resume."""
    if s["status"] in TERMINAL:
        return
    reachable = data.get("reachable")
    if not isinstance(reachable, list) or any(not isinstance(x, str) for x in reachable):
        raise ValueError("reachable must list observed native agent IDs")
    uncertain = any(x.get("status") == "dispatch-attempted" for x in s["seats"].values())
    pending = [x for x in s["seats"].values() if x.get("status") not in RESOLVED]
    missing = [x["agent_id"] for x in pending if x.get("agent_id") and x["agent_id"] not in reachable]
    if data.get("chair") != s["chair"] or uncertain or missing:
        abort(s, now, f"interrupted council: chair changed, uncertain dispatch, or lost agent IDs {missing}")
    else:
        note(s, now, "recovered", reason="original deadlines and accepted results preserved")


def actions(s, now):
    """Describe the next bounded transport steps without performing host I/O."""
    result = []
    if s["status"] in TERMINAL:
        if now < s["cleanup_deadline"]:
            result.append({"kind": "cleanup", "deadline": s["cleanup_deadline"],
                           "agent_ids": list(dict.fromkeys(x["agent_id"] for x in s["seats"].values()
                                                          if x.get("agent_id")))})
        return result
    if s["status"] == "running":
        for n in s["participants"]:
            seat = s["seats"][str(n)]
            if seat["status"] in RESOLVED:
                continue
            kind = {"prepared": "dispatch", "dispatch-attempted": "reconcile-dispatch",
                    "pending": "wait", "probing": "probe", "stopping": "stop"}[seat["status"]]
            if kind == "probe" and seat["probe_attempted"]:
                kind = "wait"
            result.append({"kind": kind, "seat": n, "attempt_id": seat["attempt_id"],
                           "agent_id": seat["agent_id"], "name": seat["name"], "scratch": seat["scratch"],
                           "deadline": seat["deadline"], "wait_seconds": max(0, min(30, seat["deadline"] - now))})
    return result
