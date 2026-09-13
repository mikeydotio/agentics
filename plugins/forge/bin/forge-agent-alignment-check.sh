#!/usr/bin/env bash
# forge-agent-alignment-check.sh — WS3 regression guard: keeps forge's docs/skills
# from silently drifting back to a nonexistent agent name, or back to spawning
# every pipeline agent as `general-purpose` with no registered-type/fallback path.
#
# This exists because forge once referenced three agents that don't exist in the
# shared library (`senior-engineer`, `devils-advocate`, bare `ux-designer`) and
# spawned every pipeline agent as `general-purpose` (making `tools:`/`read_only:`
# frontmatter purely cosmetic) — see the 2026-07-01 hardening audit's F057/F061/F083.
# Nothing detected either drift automatically. This script is the automated check:
# it never hardcodes the roster — it reads the real agent filenames off disk, the
# same way `forge-contract-check.sh` reads the real storyhook CLI instead of
# hardcoding a verb list.
#
# What it checks, for every references/*.md, skills/*/SKILL.md, and
# agent-overrides/*.md file under <docs-root>:
#   1. Roster cross-check: every agent name that appears in a roster-declaration
#      context (a backtick-quoted list bullet, a `| \`name\` |` table cell, or a
#      TEAM.md-template-style plain bullet) must be a real file in
#      <agents-root>/agents/*.md. This is what catches a reintroduced
#      `senior-engineer` / `devils-advocate` / bare `ux-designer`.
#   2. Spawn-site check: every `subagent_type: "..."` string must be either
#      `general-purpose` (only allowed in a file that also documents the
#      `agents:` preferred path alongside it — i.e. a real Preferred/Fallback
#      resolution, not a bare default) or `agents:<name>` where `<name>` is a
#      real roster entry. No other namespace is valid (there is no `forge:`
#      namespace — forge registers no agents of its own).
#
# Usage: forge-agent-alignment-check.sh [docs-root] [agents-root]
#   docs-root   defaults to the forge plugin root (one level up from bin/).
#   agents-root defaults to the sibling `agents` plugin root
#               ($(dirname docs-root)/agents) — same sibling-plugin resolution
#               forge uses at runtime (see references/team-roles.md).
#   Tests point these at throwaway fixture trees.
#
# Output (always exit 0 — callers branch on the JSON, not the exit code):
#   {ok, alignment_ok, unresolved_roster_tokens, spawn_site_violations,
#    real_roster, files_scanned, display}
#     ok                       - true if the check ran to completion (the
#                                agents-root resolved and had at least the
#                                concept of an agents/ dir, even if empty).
#     alignment_ok             - true if zero violations were found. Only
#                                meaningful when ok is true. THIS is the
#                                regression-guard pass/fail signal.
#     unresolved_roster_tokens - array of {file, line, name, text}.
#     spawn_site_violations    - array of {file, line, subagent_type, reason}.
#     display                  - human-readable summary.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"
AGENTS_ROOT="${2:-$(cd "$DOCS_ROOT/.." 2>/dev/null && pwd)/agents}"

if ! command -v python3 >/dev/null 2>&1; then
  jq -n '{ok: false, alignment_ok: false, unresolved_roster_tokens: [], spawn_site_violations: [],
          real_roster: [], files_scanned: [], error: "python3_missing",
          display: "[forge] agent-alignment check skipped: python3 not found"}'
  exit 0
fi

python3 - "$DOCS_ROOT" "$AGENTS_ROOT" <<'PYEOF'
import json
import os
import re
import sys

docs_root, agents_root = sys.argv[1], sys.argv[2]

def emit(obj):
    print(json.dumps(obj))

agents_dir = os.path.join(agents_root, "agents")
if not os.path.isdir(agents_dir):
    emit({
        "ok": False, "alignment_ok": False,
        "unresolved_roster_tokens": [], "spawn_site_violations": [],
        "real_roster": [], "files_scanned": [],
        "error": "agents_library_missing",
        "display": "[forge] agent-alignment check skipped: could not resolve the shared agents plugin root at " + agents_dir,
    })
    sys.exit(0)

real_roster = sorted(
    fn[:-3] for fn in os.listdir(agents_dir)
    if fn.endswith(".md") and not fn.startswith("_")
)
real_roster_set = set(real_roster)

# ── Locate every doc that declares a roster or spawns an agent ──
files = []
for tree in ("", "claude", "codex"):
    for directory in ("references", "skills", "agent-overrides"):
        base = os.path.join(docs_root, tree, directory)
        if not os.path.isdir(base):
            continue
        for folder, _, names in os.walk(base):
            for name in sorted(names):
                if name.endswith(".md") and (directory != "skills" or name == "SKILL.md"):
                    files.append(os.path.relpath(os.path.join(folder, name), docs_root))
files.sort()

KEBAB = r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*"
BULLET_BACKTICK_RE = re.compile(r"^- `(" + KEBAB + r")`")
TABLE_ROW_RE = re.compile(r"^\| `(" + KEBAB + r")` \|")
PLAIN_BULLET_RE = re.compile(r"^- (" + KEBAB + r")\s*$")
# Conditional-activation bullets, e.g. "- security-researcher: [YES/NO ...]" or
# the documented multi-variant shorthand "- ux-designer-{cli|web|mobile}: ...".
# The optional "-{...}" group is deliberately NOT flagged — it's the documented
# way to say "one of these three variants", not a literal single agent name.
CONDITIONAL_BULLET_RE = re.compile(r"^- (" + KEBAB + r")(-\{[^}]*\})?\s*:")

SUBAGENT_TYPE_RE = re.compile(r'(?:subagent_type|canonical role):\s*"([^"]+)"')
HEADING_RE = re.compile(r"^#{1,6}\s+(.*)")

# Only cross-check kebab tokens found under a heading that actually declares a
# roster/spawn list — every doc has plenty of unrelated "- `word`" bullets and
# "| `word` | ... |` table rows (state names, priority levels, dispatch
# values) that happen to be lowercase-kebab and would otherwise false-positive.
ALLOWED_SECTION_RE = re.compile(
    r"team|roster|spawn.*agent|active agents?|always active|conditionally activated",
    re.IGNORECASE,
)

unresolved = []
spawn_violations = []

for rel in files:
    path = os.path.join(docs_root, rel)
    try:
        with open(path, encoding="utf-8") as f:
            content = f.read()
    except OSError:
        continue
    lines = content.splitlines()

    has_general_purpose = False
    current_section = ""

    for i, raw in enumerate(lines, start=1):
        line = raw.rstrip("\n")

        hm = HEADING_RE.match(line)
        if hm:
            current_section = hm.group(1)

        if ALLOWED_SECTION_RE.search(current_section):
            candidates = []
            m = BULLET_BACKTICK_RE.match(line)
            if m:
                candidates.append(m.group(1))
            m = TABLE_ROW_RE.match(line)
            if m:
                candidates.append(m.group(1))
            m = PLAIN_BULLET_RE.match(line)
            if m:
                candidates.append(m.group(1))
            m = CONDITIONAL_BULLET_RE.match(line)
            if m and not m.group(2):
                candidates.append(m.group(1))

            for tok in candidates:
                if tok not in real_roster_set:
                    unresolved.append({"file": rel, "line": i, "name": tok, "text": line.strip()})

        m = SUBAGENT_TYPE_RE.search(line)
        if m:
            val = m.group(1)
            if "canonical role:" in line and ":" not in val:
                val = "agents:" + val
            if val == "general-purpose":
                has_general_purpose = True
            elif val.startswith("agents:"):
                name = val.split(":", 1)[1]
                # Skip documentation placeholders like "agents:<name>" — not a
                # literal spawn site, just prose explaining the convention.
                if "<" not in name and name not in real_roster_set:
                    spawn_violations.append({"file": rel, "line": i, "subagent_type": val, "reason": "unknown_agent"})
            else:
                spawn_violations.append({"file": rel, "line": i, "subagent_type": val, "reason": "unregistered_namespace"})

    if has_general_purpose and "agents:" not in content:
        spawn_violations.append({"file": rel, "line": 0, "subagent_type": "general-purpose", "reason": "undocumented_fallback_no_agents_namespace_mentioned"})

alignment_ok = (len(unresolved) == 0 and len(spawn_violations) == 0)

emit({
    "ok": True,
    "alignment_ok": alignment_ok,
    "unresolved_roster_tokens": unresolved,
    "spawn_site_violations": spawn_violations,
    "real_roster": real_roster,
    "files_scanned": files,
    "display": (
        "[forge] agent alignment: OK — {} files scanned against {} real agents".format(len(files), len(real_roster))
        if alignment_ok else
        "[forge] agent alignment: VIOLATIONS — {} unresolved roster token(s), {} spawn-site violation(s). See unresolved_roster_tokens / spawn_site_violations.".format(len(unresolved), len(spawn_violations))
    ),
})
PYEOF
