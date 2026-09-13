"""Strict validation of untrusted Council wire payloads and persisted JSON."""
import json
import math
import hashlib


def text(value, name):
    """Require a nonempty string, without coercing arbitrary JSON values."""
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{name}: expected nonempty string")
    return value


def integer(value, name):
    """Require an integer rather than JSON's distinct boolean type."""
    if type(value) is not int:
        raise ValueError(f"{name}: expected integer")
    return value


def loads(raw):
    """Parse JSON without duplicate keys or nonfinite numeric constants."""
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    def constant(value):
        raise ValueError(f"invalid JSON constant: {value}")

    return json.loads(raw, object_pairs_hook=pairs, parse_constant=constant)


def envelope(raw):
    """Accept bare JSON or exactly one fence, never surrounding prose."""
    raw = text(raw, "body").strip()
    if raw.startswith("```"):
        lines = raw.splitlines()
        if len(lines) < 3 or lines[0] not in ("```", "```json") or lines[-1] != "```":
            raise ValueError("invalid JSON fence")
        raw = "\n".join(lines[1:-1])
    value = loads(raw)
    if not isinstance(value, dict):
        raise ValueError("envelope must be an object")
    return value


def proposal(value):
    """Validate a research proposal's existing four required fields."""
    if not isinstance(value, dict):
        raise ValueError("proposal must be an object")
    for key in ("summary", "rationale", "risks", "confidence"):
        text(value.get(key), key)
    if value["confidence"] not in ("low", "medium", "high"):
        raise ValueError("invalid confidence")


def payload(value, phase, seat, proposals, own_label):
    """Validate the phase's payload against the actual surviving slate."""
    if not isinstance(value, dict):
        raise ValueError("payload must be an object")
    if phase == "research":
        proposal(value)
        return
    if phase == "deliberation":
        if integer(value.get("seat"), "seat") != seat:
            raise ValueError("deliberation seat mismatch")
        if value.get("action") not in ("stand", "revise"):
            raise ValueError("invalid deliberation action")
        proposal(value.get("revised_proposal"))
        text(value.get("delta"), "delta")
        if value["action"] == "stand" and value["revised_proposal"] != proposals[own_label]:
            raise ValueError("stand must repeat the original proposal")
        return
    text(value.get("reason"), "reason")
    if phase == "vote":
        if not isinstance(value.get("choice"), str) or value["choice"] not in proposals:
            raise ValueError("choice is not in the proposal slate")
    else:
        keys = ("first", "second", "third")[:len(proposals)]
        choices = [value.get(key) for key in keys]
        if (any(not isinstance(x, str) for x in choices)
                or len(set(choices)) != len(choices) or set(choices) != set(proposals)
                or (len(proposals) == 2 and "third" in value)):
            raise ValueError("ranking must cover the surviving slate exactly once")


def validate_state(s):
    """Reject damaged state before computing actions or overwriting evidence."""
    try:
        if not isinstance(s, dict):
            raise ValueError("expected state object")
        if s["schema_version"] != 1 or type(s["schema_version"]) is not int:
            raise ValueError("unsupported schema version")
        integer(s["revision"], "revision")
        for key in ("council_id", "question", "question_digest", "chair", "host"):
            text(s[key], key)
        if s["host"] not in ("codex", "claude"):
            raise ValueError("invalid host")
        if s["status"] not in ("ready", "running", "phase-complete", "aborted", "decided"):
            raise ValueError("invalid council status")
        if s["phase"] not in (None, "research", "vote", "deliberation", "runoff"):
            raise ValueError("invalid phase")
        if s["question_digest"] != hashlib.sha256(s["question"].encode()).hexdigest():
            raise ValueError("question digest mismatch")
        for key in ("clock_wall", "clock_mono", "created_at", "created_mono"):
            if type(s[key]) not in (int, float) or not math.isfinite(s[key]):
                raise ValueError(f"invalid {key}")
        if not isinstance(s["seats"], dict) or set(s["seats"]) != {"1", "2", "3"}:
            raise ValueError("expected three seats")
        for key in ("history", "participants"):
            if not isinstance(s[key], list):
                raise ValueError(f"invalid {key}")
        for key in ("phases", "proposals"):
            if not isinstance(s[key], dict):
                raise ValueError(f"invalid {key}")
        if any(type(n) is not int or n not in (1, 2, 3) for n in s["participants"]):
            raise ValueError("invalid participant identity")
        if len(set(s["participants"])) != len(s["participants"]):
            raise ValueError("duplicate participants")
        for event in s["history"]:
            if (not isinstance(event, dict) or type(event.get("at")) not in (int, float)
                    or not math.isfinite(event["at"]) or not isinstance(event.get("reason"), str)
                    or not isinstance(event.get("event"), str) or "seat" not in event or "phase" not in event):
                raise ValueError("invalid history event")
        for n, seat in s["seats"].items():
            if not isinstance(seat, dict):
                raise ValueError("seat must be an object")
            text(seat["archetype"], "archetype")
            if seat["seat"] != int(n) or type(seat["seat"]) is not int:
                raise ValueError("invalid seat identity")
            if s["phase"] is not None:
                for key in ("attempt_id", "name", "scratch"):
                    text(seat[key], key)
                if seat["status"] not in ("prepared", "dispatch-attempted", "pending", "probing",
                                          "stopping", "accepted", "abstained", "excluded"):
                    raise ValueError("invalid seat status")
                if type(seat["retry_count"]) is not int or seat["retry_count"] not in (0, 1):
                    raise ValueError("invalid retry count")
                if type(seat["deadline"]) not in (int, float) or not math.isfinite(seat["deadline"]):
                    raise ValueError("invalid deadline")
                for key in ("response", "reason", "agent_id", "old_agent_id", "extended", "proposal_label"):
                    if key not in seat:
                        raise ValueError(f"missing seat {key}")
                if type(seat["extended"]) is not bool or type(seat["probe_attempted"]) is not bool:
                    raise ValueError("invalid extension/probe flags")
                if not isinstance(seat["reason"], str):
                    raise ValueError("invalid failure reason")
                for key in ("agent_id", "old_agent_id"):
                    if seat[key] is not None:
                        text(seat[key], key)
                if seat["status"] in ("pending", "probing", "accepted") and not seat["agent_id"]:
                    raise ValueError("pending/accepted seat missing agent ID")
                if seat["status"] == "accepted" and not isinstance(seat["response"], dict):
                    raise ValueError("accepted seat missing response")
        if s["phase"] is not None:
            for key in ("phase_started", "hard_deadline", "initial_deadline"):
                if type(s[key]) not in (int, float) or not math.isfinite(s[key]):
                    raise ValueError(f"invalid {key}")
            # Kept local to avoid a validation/model import cycle.
            initial, total = (900, 1500) if s["phase"] == "research" else (120, 300)
            if (s["initial_deadline"] != s["phase_started"] + initial
                    or s["hard_deadline"] != s["phase_started"] + total):
                raise ValueError("phase budget mismatch")
            expected = [x["seat"] for x in s["seats"].values() if x["status"] != "excluded"]
            if s["participants"] != expected:
                raise ValueError("participant set mismatch")
            if any(not s["phase_started"] <= x["deadline"] <= s["hard_deadline"] for x in s["seats"].values()):
                raise ValueError("seat deadline outside phase budget")
        if s["status"] == "decided":
            text(s["decision"], "decision")
        if s["status"] in ("aborted", "decided"):
            text(s["reason"], "terminal reason")
            if type(s["cleanup_deadline"]) not in (int, float):
                raise ValueError("invalid cleanup deadline")
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError(f"invalid council state: {exc}") from exc
