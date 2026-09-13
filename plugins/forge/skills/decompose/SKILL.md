---
name: decompose
description: Decompose PLAN.md into storyhook stories with dependencies, priorities, and design context. Produces plan-mapping.json. Maps waves to stories with embedded DESIGN.md sections.
argument-hint: ""
model: sonnet
effort: medium
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
   - Claude Code: `<plugin-root>/claude/skills/decompose/SKILL.md`
   - Codex: `<plugin-root>/codex/skills/decompose/SKILL.md`
4. If selection remains ambiguous, stop with `Ambiguous plugin host for forge:decompose`.
5. Follow only the selected tree. Never combine hosts or fall back to the other host.
