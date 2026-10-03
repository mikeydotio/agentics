"""Durable input evidence and non-destructive Council integrity failures."""
import copy
import hashlib
import os
from pathlib import Path

import council_model as model
from council_inventory import canonical, directory, read_evidence, repository, stable_inventory
from council_validation import loads, text

# Exact chair-owned names, never the whole sitting or .council tree.
ARTIFACTS = ("QUESTION.md", "PANEL.md", "STATE.json", ".state.lock", "LIVENESS.md",
             "BASELINE.json", "INTEGRITY.json", "ABORT.md", "DECISION.md",
             "proposals-round-1.md", "vote-round-1.md", "deliberation.md",
             "proposals-round-2.md", "vote-round-2.md")


def _containers(root, state):
    directory(root)
    directory(root / "scratch")
    scope = state.get("integrity_scope")
    if not isinstance(scope, dict) or not isinstance(scope.get("scratch"), list):
        raise ValueError("missing or invalid scratch ownership evidence")
    for name in scope["scratch"]:
        if not isinstance(name, str) or len(name) != 32 or any(c not in "0123456789abcdef" for c in name):
            raise ValueError("invalid owned scratch identity")
        directory(root / "scratch" / name)


def initialise(root, state, data, write):
    """Persist a baseline before any initial dispatch can become usable."""
    identity = repository(data.get("repository_root", os.getcwd()))
    if directory(root) == Path(identity["root"]):
        raise ValueError("Council sitting cannot be the repository root")
    state["repository"] = identity
    state["integrity_scope"] = {"scratch": []}
    reconciliation = data.get("reconciliation")
    if reconciliation is not None:
        if not isinstance(reconciliation, dict) or reconciliation.get("writers_stopped") is not True:
            raise ValueError("reconciliation requires writers_stopped:true")
        previous = directory(text(reconciliation.get("previous_directory"), "previous_directory"))
        reason = text(reconciliation.get("reason"), "reconciliation reason")
        if previous == directory(root):
            raise ValueError("reconciliation requires a new sitting")
        old = loads(read_evidence(previous / "STATE.json").decode("utf-8"))
        if old.get("status") != "aborted" or old.get("repository") != identity:
            raise ValueError("reconciliation requires an aborted sitting in this repository")
        state["reconciliation"] = {"previous_directory": str(previous), "reason": reason,
                                   "writers_stopped": True, "previous_council_id": old["council_id"]}
    _containers(root, state)
    (root / "scratch").mkdir(exist_ok=True, mode=0o700)
    snapshot = stable_inventory(identity, root, ARTIFACTS, [])
    manifest = {"schema_version": 1, "council_id": state["council_id"],
                "repository": identity, "sitting": str(directory(root)), "snapshot": snapshot}
    raw = canonical(manifest) + "\n"
    if (root / "BASELINE.json").exists() or (root / "BASELINE.json").is_symlink():
        raise ValueError("baseline already exists; preserve incomplete sitting")
    write(root / "BASELINE.json", raw)
    state["baseline"] = {"schema_version": 1, "sha256": hashlib.sha256(raw.encode()).hexdigest()}
    state["integrity"] = {"status": "clean", "baseline": state["baseline"],
                          "checkpoint": "init", "changed_paths": [], "details": [],
                          "excluded": snapshot["excluded"], "head_changed": False}


def verify(root, state, checkpoint):
    """Compare a stable current inventory with authenticated baseline bytes."""
    result = {"status": "unverified", "baseline": state.get("baseline"),
              "checkpoint": checkpoint, "changed_paths": [], "details": [],
              "excluded": [], "head_changed": False}
    try:
        _containers(root, state)
        baseline = state.get("baseline")
        if not isinstance(baseline, dict) or baseline.get("schema_version") != 1:
            raise ValueError("missing or unsupported baseline; legacy sitting cannot resume")
        path = root / "BASELINE.json"
        if path.is_symlink():
            raise ValueError("refusing symlink baseline")
        raw = read_evidence(path)
        if hashlib.sha256(raw).hexdigest() != baseline.get("sha256"):
            raise ValueError("baseline digest mismatch")
        manifest = loads(raw.decode("ascii"))
        if (manifest.get("schema_version") != 1 or manifest.get("council_id") != state["council_id"]
                or manifest.get("repository") != state.get("repository")
                or manifest.get("sitting") != str(directory(root))):
            raise ValueError("baseline identity mismatch")
        before = manifest["snapshot"]
        current = stable_inventory(state["repository"], root, ARTIFACTS,
                                   state["integrity_scope"]["scratch"], before.get("git_observation"))
        # A raw index cache refresh can change the discriminator, not the staged inputs.
        before.pop("git_observation", None)
        current.pop("git_observation", None)
        changed = set()
        for key in ("entries", "index"):
            changed.update(name for name in set(before[key]) | set(current[key])
                           if before[key].get(name) != current[key].get(name))
        result.update(status="clean" if before == current else "drift", changed_paths=sorted(changed),
                      head_changed=before["head"] != current["head"], excluded=current["excluded"])
        if result["status"] == "drift":
            result["details"] = ["Repository inputs changed; actor is not established."]
            result["head_before"], result["head_after"] = before["head"], current["head"]
    except (OSError, ValueError, KeyError, TypeError) as exc:
        result["details"] = [f"Cannot verify repository inputs: {exc}"]
    return result


def invalidate(state, result, data, now):
    """Preserve invalid findings, retire the usable slate, and stop the sitting."""
    state["integrity"] = result
    state["invalidated_findings"] = {"proposals": copy.deepcopy(state["proposals"]),
                                     "phases": copy.deepcopy(state["phases"]),
                                     "seats": copy.deepcopy(state["seats"]),
                                     "rejected_event": copy.deepcopy(data)}
    state["proposals"], state["phases"] = {}, {}
    for seat in state["seats"].values():
        if seat.get("status") == "accepted":
            seat.update(status="abstained", response=None, reason="inputs no longer verified")
    reason = f"integrity {result['status']} at {result['checkpoint']}: " + "; ".join(result["details"])
    reason += "; changed paths: " + canonical(result["changed_paths"])
    model.abort(state, now, reason)


def register_scratch(state):
    """Retain all owned attempts so late scratch output cannot alter source scope."""
    scope = state.get("integrity_scope")
    if state.get("integrity", {}).get("status") == "clean":
        scope["scratch"] = sorted(set(scope["scratch"]) |
                                  {s["attempt_id"] for s in state["seats"].values() if "attempt_id" in s})


def protect_outputs(root, state):
    """Never overwrite tracked evidence while trying to report an integrity failure."""
    from council_git import observation
    identity = state.get("repository")
    if not isinstance(identity, dict):
        return
    try:
        relative = directory(root).relative_to(Path(identity["root"])).as_posix()
    except ValueError:
        return
    observed = observation(identity)
    conflicts = sorted(f"{relative}/{name}" for name in ARTIFACTS
                       if f"{relative}/{name}" in observed["index"])
    if conflicts:
        raise ValueError("refusing to overwrite tracked Council artifacts: " + canonical(conflicts))
