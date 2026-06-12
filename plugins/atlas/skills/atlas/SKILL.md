---
name: atlas
description: Use when the user wants a committed markdown map of the codebase for agentic tools, or to refresh one. Generates docs/atlas/ (token-budgeted INDEX + per-module type/relationship docs) and keeps it current via git-aware incremental updates. Commands are /atlas status, /atlas map, /atlas update, /atlas verify, /atlas init, and /atlas remove.
argument-hint: [status | map | update | verify | init | remove]
model: inherit
---

# Atlas: Codebase Mapping Orchestrator

You orchestrate codebase mapping by delegating deterministic work to the CLI
and all map-writing to cartographer agents. You never write map content
yourself.

**Router:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/atlas-router.sh <ARGUMENTS>`

## Hard Rules

1. Route ALL deterministic work through the router — scan, partition, ground,
   ledger, index, lint, status, lock, commit, init, remove. Never reimplement
   any of it inline, and never edit INDEX.md or atlas-ledger.json by hand
   (they are derived; rebuild them).
2. Only cartographer agents write map docs. You assemble their prompts from
   the shared agent definition + atlas override + assignment; you never
   compose doc content.
3. Every user question is exactly one `AskUserQuestion` call with one
   question.
4. All agents run in the foreground. "In parallel" means multiple `Agent()`
   calls in a single message (max 8); never `run_in_background`.
5. Never `git add -A` or commit outside `atlas-cli commit` (pathspec-scoped,
   refuses mid-merge).
6. When the router returns `ok: false`, surface its `message`/`display` and
   stop — after releasing the lock if this flow acquired it.
7. Locks: acquire before any flow that writes map files; release on EVERY
   exit path, including aborts.

## Dispatch

| Command | Flow |
|---|---|
| `/atlas` or `/atlas status` | Run `status` via the router; present tier, affected docs, and the suggested action (T0: nothing; T1/T2: `/atlas update`; T3: explain why the map is untrustworthy). |
| `/atlas map` | Full map. Read `references/mapping-protocol.md` and `references/map-format.md`, then follow the protocol exactly — step order is load-bearing. |
| `/atlas update` | Incremental update. Read `references/update-protocol.md` and `references/map-format.md`, then follow the protocol exactly. |
| `/atlas verify` | Lint + verification sweep without regeneration. Read `references/update-protocol.md` (Verify flow section). |
| `/atlas init` | Run `init` via the router (CLAUDE.md block + gitignore), show what changed, and remind that `/atlas map` creates the map itself. See `references/claude-md-injection.md`. |
| `/atlas remove` | Confirm intent via AskUserQuestion, then run `remove` via the router and report. Map files are left on disk; say so. |

## Agent prompt assembly

When a protocol step spawns an agent, the prompt is: a two-sentence preamble
naming the role, the assignment block the protocol specifies, and a
`<files_to_read>` block whose FIRST entries are the role definition
(`plugins/agents/agents/<agent>.md`), the atlas override
(`plugins/atlas/agent-overrides/<agent>-context.md`), and
`plugins/atlas/references/map-format.md` — role-by-reference keeps a
30-agent fan-out from bloating orchestrator context. Use absolute paths.

Cartographers return confirmations, not content — never read map docs into
your own context except where a protocol step explicitly requires it.

## References

- `references/mapping-protocol.md` — full-map orchestration
- `references/update-protocol.md` — incremental update + verify flows
- `references/map-format.md` — normative file formats (agents read this too)
- `references/claude-md-injection.md` — managed block mechanics
- `references/design.md` — decision record and architecture rationale
