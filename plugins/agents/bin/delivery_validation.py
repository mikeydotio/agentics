"""Strict JSON and persisted-state validation for the shared delivery protocol."""
import hashlib
import json
import math
import re


def text(value, name):
    """Require a nonempty string without silently coercing identity fields."""
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{name} must be a nonempty string")
    return value


def number(value, name):
    """Require a finite non-boolean clock value."""
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{name} must be finite")
    return value


def integer(value, name, minimum=0):
    """Require an actual integer, not a boolean or rounded number."""
    if type(value) is not int or value < minimum:
        raise ValueError(f"{name} must be an integer >= {minimum}")
    return value


def digest(task):
    """Bind the envelope to the exact original task text."""
    return hashlib.sha256(task.encode("utf-8")).hexdigest()


def loads(raw):
    """Reject duplicate fields and non-finite JSON rather than resolving ambiguity."""
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError(f"duplicate JSON field: {key}")
            result[key] = value
        return result

    def constant(value):
        raise ValueError(f"invalid JSON constant: {value}")

    return json.loads(raw, object_pairs_hook=pairs, parse_constant=constant)


def body(raw):
    """Accept raw JSON or one complete JSON fence on either host."""
    raw = text(raw, "body").strip()
    if raw.startswith("```json\n") and raw.endswith("\n```"):
        raw = raw[8:-4]
    result = loads(raw)
    if not isinstance(result, dict):
        raise ValueError("delivery must be a JSON object")
    return result


def no_send_evidence(s, t, data, prior):
    """Validate an owner's reviewed no-send attestation, not transport absence itself."""
    identity = dict(batch_id=s["batch_id"], task_id=t["task_id"],
                    attempt_id=t["attempt_id"], task_digest=t["task_digest"], session=s["session"])
    if any(data.get(key) != value for key, value in identity.items()):
        raise ValueError("no-send evidence must identify the exact original session and current attempt")
    if s["status"] not in ("failed", "interrupted", "reconciled") or t["status"] not in ("failed", "interrupted"):
        raise ValueError("no-send evidence requires terminal failure")
    if t["agent_id"] is not None or t["payload"] is not None:
        raise ValueError("no-send evidence conflicts with known native identity or payload")
    if t["stopped"] or t["integrity_ok"]:
        raise ValueError("no-send evidence cannot claim native shutdown or task integrity")
    if any(e["event"] == "dispatched" and e["attempt_id"] == t["attempt_id"] for e in s["history"]):
        raise ValueError("no-send evidence conflicts with confirmed dispatch")
    if not any(e["event"] == "dispatch-attempted" and e["task_id"] == t["task_id"] and
               e["attempt_id"] == t["attempt_id"] for e in prior):
        raise ValueError("no-send evidence requires a prior current dispatch-attempted event")
    if not any(e["event"] in ("failed", "interrupted") for e in prior):
        raise ValueError("no-send evidence requires prior terminal failure history")
    if data.get("no_transport") is not True:
        raise ValueError("no-send evidence requires explicit no_transport:true attestation")
    evidence = dict(identity, no_transport=True)
    for key in ("reason", "evidence", "evidence_sha256", "reviewer"):
        evidence[key] = text(data.get(key), key)
    if not re.fullmatch(r"[0-9a-fA-F]{64}", evidence["evidence_sha256"]):
        raise ValueError("evidence_sha256 must be a 64-character hexadecimal SHA256")
    if data.keys() - evidence.keys() - {"revision", "kind", "at", "event"}:
        raise ValueError("unexpected no-send evidence fields")
    return evidence


def no_send_attempts(s):
    """Revalidate stored attestations before letting them resolve an uncertain send."""
    attempts = set()
    for index, event in enumerate(s["history"]):
        if event["event"] != "dispatch-not-sent":
            continue
        matches = [t for t in s["tasks"] if t["task_id"] == event.get("task_id")]
        if len(matches) != 1:
            raise ValueError("no-send evidence has an unknown task")
        no_send_evidence(s, matches[0], event, s["history"][:index])
        number(event.get("at"), "no-send evidence time")
        attempt = event["attempt_id"]
        if attempt in attempts:
            raise ValueError("duplicate stored no-send evidence")
        attempts.add(attempt)
    return attempts


def unresolved_dispatches(s):
    """Resolve each attempted send only by dispatch confirmation or validated no-send evidence."""
    attempted = {e["attempt_id"] for e in s["history"] if e["event"] == "dispatch-attempted"}
    confirmed = {e["attempt_id"] for e in s["history"] if e["event"] == "dispatched"}
    return attempted - confirmed - no_send_attempts(s)


def validate(s):
    """Fail closed on malformed or incompatible stored delivery records."""
    if not isinstance(s, dict) or s.get("schema") != 1:
        raise ValueError("invalid delivery state schema")
    required = {"batch_id", "owner", "host", "session", "step", "status", "tasks", "waves",
                "wave", "capacity", "created_at", "created_mono", "last_mono", "last_wall",
                "deadline", "revision", "history", "remaining", "cleanup_deadline", "cleanup_mono", "reason"}
    if not required <= s.keys():
        raise ValueError("invalid delivery state: missing fields")
    for key in ("batch_id", "session", "step"):
        text(s[key], key)
    if s["owner"] not in ("agents", "forge", "rca") or s["host"] not in ("claude", "codex"):
        raise ValueError("invalid delivery owner/host")
    if s["status"] not in ("running", "ready", "succeeded", "failed", "interrupted", "reconciled"):
        raise ValueError("invalid delivery status")
    integer(s["revision"], "revision")
    integer(s["capacity"], "capacity", 1)
    integer(s["wave"], "wave")
    for key in ("created_at", "created_mono", "last_mono", "last_wall", "deadline"):
        number(s[key], key)
    if s["cleanup_deadline"] is not None:
        number(s["cleanup_deadline"], "cleanup_deadline")
        number(s["cleanup_mono"], "cleanup_mono")
    if not isinstance(s["tasks"], list) or not s["tasks"]:
        raise ValueError("invalid delivery tasks")
    ids = set()
    agent_ids = set()
    for t in s["tasks"]:
        keys = {"task_id", "task", "task_digest", "role", "writer", "status", "attempt",
                "attempt_id", "agent_id", "deadline", "ceiling", "probe_sent", "stopped",
                "integrity_ok", "extended", "budget", "payload"}
        if not isinstance(t, dict) or not keys <= t.keys():
            raise ValueError("invalid delivery task fields")
        for key in ("task_id", "task", "role", "attempt_id"):
            text(t[key], key)
        if t["task_id"] in ids or digest(t["task"]) != t["task_digest"]:
            raise ValueError("invalid task identity/digest")
        ids.add(t["task_id"])
        if t["status"] not in ("queued", "prepared", "dispatch-attempted", "pending", "probing",
                                "stopping", "accepted", "failed", "interrupted"):
            raise ValueError("invalid task status")
        for key in ("writer", "probe_sent", "stopped", "integrity_ok", "extended"):
            if type(t[key]) is not bool:
                raise ValueError(f"invalid task boolean: {key}")
        integer(t["attempt"], "attempt", 1)
        if t["attempt"] > 2 or (t["writer"] and t["attempt"] > 1):
            raise ValueError("invalid retry count")
        for key in ("deadline", "ceiling"):
            if t[key] is not None:
                number(t[key], key)
        if t["agent_id"] is not None:
            text(t["agent_id"], "agent_id")
            if t["agent_id"] in agent_ids:
                raise ValueError("native identity reused across tasks")
            agent_ids.add(t["agent_id"])
        expected = ([1800, 300, 0] if t["writer"] else
                    [600, 120, 120] if s["owner"] == "forge" and t["role"] in
                    ("evaluator", "reviewer", "triager") else [900, 300, 300])
        if t["budget"] != expected:
            raise ValueError("invalid task budget")
    if not isinstance(s["waves"], list) or not all(isinstance(w, list) and w for w in s["waves"]):
        raise ValueError("invalid waves")
    if sorted(i for w in s["waves"] for i in w) != list(range(len(s["tasks"]))):
        raise ValueError("invalid wave task membership")
    if s["wave"] >= len(s["waves"]):
        raise ValueError("invalid current wave")
    for wave in s["waves"]:
        if len(wave) > s["capacity"] or (len(wave) > 1 and any(s["tasks"][i]["writer"] for i in wave)):
            raise ValueError("invalid wave concurrency")
    if not isinstance(s["history"], list) or not isinstance(s["remaining"], list):
        raise ValueError("invalid history/cleanup")
    if len(set(s["remaining"])) != len(s["remaining"]) or not set(s["remaining"]) <= agent_ids:
        raise ValueError("invalid cleanup ownership")
    if s["status"] == "succeeded" and not all(t["status"] == "accepted" and t["integrity_ok"] for t in s["tasks"]):
        raise ValueError("invalid successful outcome")
    unresolved = unresolved_dispatches(s)
    if s["status"] == "reconciled" and unresolved:
        raise ValueError("invalid reconciled outcome: uncertain native dispatch")
