---
name: fix
description: RCA step 6 — gated fix implementation. RED (repro still fails) → software-engineer implements the behavior fix → GREEN → full suite → fix: commit → sibling-pattern sweep → optional separate refactor: commit. Two hats, feature branch, push/PR left to the user.
argument-hint: "[slug]"
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
   - Claude Code: `<plugin-root>/claude/skills/fix/SKILL.md`
   - Codex: `<plugin-root>/codex/skills/fix/SKILL.md`
4. If selection remains ambiguous, stop with `Ambiguous plugin host for rca:fix`.
5. Follow only the selected tree. Never combine hosts or fall back to the other host.
