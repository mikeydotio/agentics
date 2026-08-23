---
name: agents
description: Browse and validate the shared agent library
---

<!-- HOST_DISPATCH_VERSION: 1 -->
# Host dispatcher

Select exactly one host implementation before doing any task work.

1. Determine the host from the authoritative runtime identity and native tool surface:
   - Codex: the system identifies Codex, or native tools such as `spawn_agent` and `wait_agent` are available.
   - Claude Code: the system identifies Claude Code, or Claude tools such as `AskUserQuestion` and `Agent` are available.
   - Environment compatibility aliases are not authoritative host signals.
2. Resolve `<plugin-root>` as three directories above this file.
3. Load exactly one implementation completely:
   - Codex: `<plugin-root>/codex/skills/agents/SKILL.md`
   - Claude Code: `<plugin-root>/claude/skills/agents/SKILL.md`
4. If both signals or neither signal are present, stop with: `Ambiguous plugin host for agents:agents; refusing to combine host instruction trees.`
5. Follow only the selected implementation. Never merge or fall back across host trees.
