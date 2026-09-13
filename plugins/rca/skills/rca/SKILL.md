---
name: rca
description: Use when a KNOWN bug, regression, or defect needs its true root cause found and fixed well — not for discovering whether bugs exist. Reproduction-gated scientific-debugging pipeline: Kepner-Tregoe intake, deterministic git forensics (bisect/blame/pickaxe/hotspots), competing-hypothesis falsification in disposable worktrees, ODC classification, surgical-vs-redesign verdicts, gated two-hats fixes, committed blameless postmortems. Resumable; latches to GitHub/storyhook issues.
argument-hint: "[bug description] | full|light <desc> | --issue <ref> <desc> | continue [slug] | status | abandon <slug>"
effort: high
---

<!-- HOST_DISPATCH_VERSION: 1 -->
# Host dispatcher

Select exactly one implementation before task work.

1. Determine the host from authoritative runtime identity first. If it is unavailable,
   use the native tool surface: Codex has `spawn_agent`/`followup_task`/`wait_agent`;
   Claude Code has `Agent`/`AskUserQuestion`. Environment compatibility aliases are not authoritative
   host signals. Conflicting or missing authoritative signals are ambiguous.
2. Resolve `<plugin-root>` two directories above this file's containing directory.
3. Read exactly one implementation completely:
   - Claude Code: `<plugin-root>/claude/skills/rca/SKILL.md`
   - Codex: `<plugin-root>/codex/skills/rca/SKILL.md`
4. If selection remains ambiguous, stop with `Ambiguous plugin host for rca:rca`.
5. Follow only the selected tree. Never combine hosts or fall back to the other host.
