---
name: intake
description: RCA step 1 — latch an existing GitHub/storyhook issue, scaffold the investigation, and build the Kepner-Tregoe IS/IS-NOT differential grid from the bug description, issue, and light recon; ask only about genuine gaps.
argument-hint: "[bug description] [--issue <gh#|url|storyhook-id>]"
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
   - Claude Code: `<plugin-root>/claude/skills/intake/SKILL.md`
   - Codex: `<plugin-root>/codex/skills/intake/SKILL.md`
4. If selection remains ambiguous, stop with `Ambiguous plugin host for rca:intake`.
5. Follow only the selected tree. Never combine hosts or fall back to the other host.
