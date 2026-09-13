---
name: reproduce
description: RCA step 2 — the firm reproduction gate. Detect the test stack, have qa-engineer build an automated failing repro test, quantify flakiness, minimize (FULL tier), and set the investigation tier. No hypothesis work happens until this gate is passed or explicitly overridden.
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
   - Claude Code: `<plugin-root>/claude/skills/reproduce/SKILL.md`
   - Codex: `<plugin-root>/codex/skills/reproduce/SKILL.md`
4. If selection remains ambiguous, stop with `Ambiguous plugin host for rca:reproduce`.
5. Follow only the selected tree. Never combine hosts or fall back to the other host.
