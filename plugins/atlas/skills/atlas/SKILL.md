---
name: atlas
description: Use when the user wants a committed markdown map of the codebase for agentic tools, or to refresh one. Generates docs/atlas/ (token-budgeted INDEX + per-module type/relationship docs) and keeps it current via git-aware incremental updates. Commands are /atlas status, /atlas map, /atlas update, /atlas verify, /atlas repair, /atlas init, and /atlas remove.
argument-hint: [status | map | update | verify | repair | init | remove]
model: inherit
---

# Atlas: Codebase Mapping Orchestrator (v2 — Projection)

You orchestrate codebase mapping by delegating deterministic work to the CLI and
the only LLM step — *judgment* — to cartographer annotator agents. In v2 the map
is a deterministic projection: `extract` produces the structure, annotators emit
content-addressed *judgment cells*, and `project` renders the committed docs. You
never write a doc or a cell yourself.

**Router:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/atlas-router.sh <ARGUMENTS>`

## Hard Rules

1. Route ALL deterministic work through the router — scan, partition, extract,
   judge-plan, judgment (diff/ingest), project, ledger, index, lint, status,
   lock, commit, branch, init, remove. Never reimplement any of it inline, and
   never edit INDEX.md, atlas-ledger.json, the projected docs, or judgments.json
   by hand (all derived/CLI-owned; rebuild or re-ingest them).
2. `project` (the CLI) writes the map docs; cartographer **annotators** write the
   judgment cells that feed it. You assemble annotator prompts from the shared
   agent definition + atlas override + assignment (structure rows + the
   `missing_keys` to fill); you never compose doc content or cell content, and you
   pipe annotator output to `judgment ingest`.
3. Every user question is exactly one `AskUserQuestion` call with one
   question.
4. All agents run in the foreground. "In parallel" means multiple `Agent()`
   calls in a single message (max 8); never `run_in_background`.
5. Never `git add -A` or commit outside `atlas-cli commit` (pathspec-scoped,
   refuses mid-merge). `map`/`update` writes happen on an `atlas/*` branch
   created via `atlas-cli branch ensure`; never create or switch branches by
   hand, and leave the user on that branch at the end (atlas never merges).
6. When the router returns `ok: false`, surface its `message`/`display` and
   stop — after releasing the lock if this flow acquired it.
7. Locks: acquire before any flow that writes map files; release on EVERY
   exit path, including aborts.

## Dispatch

| Command | Flow |
|---|---|
| `/atlas` or `/atlas status` | Run `status` via the router; present tier, affected docs, and the suggested action (T0: nothing; T1/T2: `/atlas update`; T3: explain why the map is untrustworthy). |
| `/atlas covers <path>...` | Run `covers` via the router — a per-file analogue of `status`. For each path, report whether it is owned by a module doc, which doc, and whether that coverage is fresh (recorded blob == current blob). Use before exploring specific files: `mapped` + `fresh` means read the routed doc instead of re-deriving; `mapped` + not `fresh`, or unmapped, means the map won't fully answer for that file. Pure ledger read — no regeneration. |
| `/atlas map` | Full map. Read `references/mapping-protocol.md` and `references/map-format.md`, then follow the protocol exactly — step order is load-bearing. |
| `/atlas update` | Incremental update. Read `references/update-protocol.md` and `references/map-format.md`, then follow the protocol exactly. |
| `/atlas verify` | Lint + verification sweep without regeneration. Read `references/update-protocol.md` (Verify flow section). |
| `/atlas repair` | Verify-then-fix: correct the specific claims verification flagged, WITHOUT re-exploring. Reuses a prior `/atlas verify` when still valid; defers drift to `/atlas update`. Read `references/update-protocol.md` (Repair flow section). |
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

Cartographer annotators return a JSON array of judgment cells (never doc bytes
or markdown) — collect each wave's arrays and pipe them to `judgment ingest`.
The atlas override for the annotator role is
`plugins/atlas/agent-overrides/cartographer-context.md`; the v2 annotator does
not read `map-format.md` (it writes cells, not docs).

**Cartographer model.** Spawn every cartographer `Agent()` — the module
mappers, the overview cartographer, and every anchored/fresh regeneration — on
Sonnet's 1M-context model by setting the spawned agent's model to `sonnet[1m]`.
This is the single normative statement; the protocols only echo it. It applies
**only** to cartographer spawns from this skill: it does not modify the shared
`cartographer.md` definition (kept model-agnostic so forge/rca/council are
unaffected), and it does not change this skill's own `model: inherit` (a pinned
model on a long-running orchestrator overflows its window). Map-verifier spawns
are **not** pinned — they stay on the default model, where an independent model
is a feature for a cross-check, not a regression. Map-repairer spawns (the repair
flow) likewise stay on the default model and run foreground in waves ≤8: their
work is one doc plus targeted greps, not a 1M-context survey. (`[1m]` selects Sonnet's
1M-context window; if a build does not honor the suffix the agent still runs on
Sonnet, just at the default window.)

## References

- `references/mapping-protocol.md` — full-map orchestration (v2 Projection)
- `references/update-protocol.md` — incremental update + verify/repair (v2)
- `references/design-v2.md` — v2 Projection architecture (structure/judgment/
  projection, the judgment-key derivation) — read this first for v2
- `references/map-format.md` — normative doc format that `project` renders
- `references/claude-md-injection.md` — managed block mechanics
- `references/design-v2.md` — the design record (v2 Projection architecture + the folded-in v1 base)
