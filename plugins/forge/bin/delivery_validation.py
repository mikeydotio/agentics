"""Strict JSON and persisted-state validation for the shared delivery protocol."""
import hashlib
import json
import math


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
