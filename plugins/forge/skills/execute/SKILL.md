---
name: execute
description: Generator-evaluator execution loop with retry and session persistence. Implements stories autonomously through isolated subagent spawning.
argument-hint: "[--dry-run [--dry-run-mode all-pass|all-fail|mixed]]"
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
   - Claude Code: `<plugin-root>/claude/skills/execute/SKILL.md`
   - Codex: `<plugin-root>/codex/skills/execute/SKILL.md`
4. If selection remains ambiguous, stop with `Ambiguous plugin host for forge:execute`.
5. Follow only the selected tree. Never combine hosts or fall back to the other host.
