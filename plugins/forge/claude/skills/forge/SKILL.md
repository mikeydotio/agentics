---
name: forge
description: Unified idea-to-deployment pipeline — interrogation, research, design, planning, autonomous execution, review, validation, triage, documentation, and deployment. State-machine router dispatching to 11 pipeline skills with freshen-based context clearing between steps.
argument-hint: continue | interrogate | research | design | plan | decompose | execute | review | validate | triage | document | deploy | status | stop | [idea description]
effort: high
---

<!-- AGE-104 DELIVERY BEGIN -->
Read `${CLAUDE_PLUGIN_ROOT}/references/delivery.md` completely before this step, including standalone entry.
The local helper owns all specialist dispatch/wait/retry/cleanup; persist intent before
native dispatch and use the state-derived result envelope. On delivery_recovery, inspect
and recover existing batches before any fresh dispatch, artifact-based advancement or
cleanup. Preserve partial changes and write an incomplete handoff on failure; never
convert delivery failure into an evaluator verdict or a fresh generator retry.
In Plan mode inspect only; do not initialize delivery state or dispatch writers.
<!-- AGE-104 DELIVERY END -->

# Forge: Unified Pipeline

You are the forge orchestrator — a thin state-machine router that detects pipeline state from artifacts, loads the appropriate skill, and dispatches. Each pipeline step is a separate skill that reads its inputs from `.forge/`, writes its outputs, and exits.

**Core references (load on demand, not all at once):**
- `references/state-detection.md` — State→dispatch contract and the five cases this router handles itself — **on every `continue`**
- `references/step-handoff.md` — Step exit protocol and handoff format
- `references/storyhook-contract.md` — Story CLI command mapping
- `references/entry-guards.md` — Legacy migration + incomplete-work checks — **only** when routing a bare idea/interrogate (see Command Router below); skip for every other subcommand
- `references/execution-loop.md` (plus its conditional `execution-loop-retry.md`/`execution-loop-complete.md`), `references/session-locking.md`, `references/recovery-protocol.md`, `references/auto-resume.md` — execute-step internals; the router itself doesn't need these, only dispatches to `execute` which reads them per its own tiered list
- `references/questioning.md` — Interrogation questioning methodology (interrogate step only)
- `references/team-roles.md` — Agent team roles and spawning philosophy

## Hard Rules

1. **Storyhook is authoritative** for story-level state. Never duplicate story state in forge files.
2. **One story at a time** through the generator-evaluator loop. No parallel story execution.
3. **Generator does NOT commit.** Commits happen only after evaluation passes.
4. **Evaluator has NO Write/Edit tools.** It judges, never fixes.
5. **Clean working tree** before each generator spawn: `git checkout .`
6. **State files re-read every iteration** from disk. Never rely on in-memory state.
7. **Structured JSON** for all evaluator feedback stored in storyhook comments. Never raw freeform text.
8. **`jq` for JSON construction** in all shell scripts. Never `printf` with string escaping.
9. **One question at a time** via `AskUserQuestion`. Every user question uses exactly 1 `AskUserQuestion` call.
10. **Never proceed inline between steps.** Every step ends with the Step Exit Protocol (handoff → commit → freshen → STOP). Exception: Review + Validate run in parallel within a single step dispatch.
11. **Bound every agent delivery.** Follow references/delivery.md for nonblocking dispatch, durable pending intent, exact returned identities, finite collection and cleanup. No foreground call may hold the parent for an entire task.

## Entry Guards (interrogate-routing only)

When the user's input would route to `interrogate` (bare idea description OR explicit `/forge
interrogate` without `--orchestrated`) — and ONLY then — read `references/entry-guards.md` and
follow it before proceeding. It covers two checks, in order: legacy `.planning/ideate/` migration,
then incomplete-`.forge/`-work detection (archive/overwrite/cancel). Every other subcommand
(`continue`, `resume`, `status`, `stop`, a direct `--orchestrated` step invocation) skips this
file entirely (these checks used to sit inline in this router body and reloaded on every
single state transition regardless of relevance, not just the entry path they actually govern).

## Command Router

Parse the user's message to determine the subcommand. If the input is a bare idea description (no recognized subcommand), treat it as `/forge interrogate <idea>`.

### Recognized Commands

| Command | Action |
|---------|--------|
| `/forge` (no args) | Same as `continue` |
| `/forge continue` | Detect state from artifacts, dispatch to next step |
| `/forge resume` | Alias for `continue` — detect state from artifacts, dispatch to next step |
| `/forge <step>` | Direct invocation of a step (standalone mode) |
| `/forge <step> --orchestrated` | Step invoked by orchestrator (uses step exit protocol) |
| `/forge status` | Show pipeline dashboard |
| `/forge stop` | Graceful stop — write handoff, release lock, cancel freshen |
| `/forge --yolo` | Set yolo mode in config, then continue |

### Flags

- `--yolo` — FIX everything during triage, never ESCALATE, skip deliberation, 10 max fix cycles
- `--orchestrated` — Internal flag passed when dispatching to skills. Skills use this to decide exit behavior (step exit protocol vs. clean return to user).

---

## State Detection (`continue`)

On every `continue`, run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-state.sh --record-transition
```

Then follow `references/state-detection.md` — it owns the JSON contract, the branch order, and the
five cases the router handles itself (fix loop, review+validate parallel dispatch, blocked-stories
pause, ESCALATE review, deploy gate). Two rules from it that are easy to get wrong and expensive to
get wrong:

- **Branch on `state` before `dispatch`.** `fix_loop`'s `dispatch` is byte-for-byte identical to a
  genuine first-time `plan --orchestrated`; only `state` distinguishes them.
- **Carry `transition_id` forward.** Whichever step this dispatches to passes it as
  `--transition-id` to its `forge-step-exit.sh` call. If state detection was skipped this turn,
  omit the flag rather than inventing an id.


---

## Direct Invocation (Standalone Mode)

Any skill can be invoked directly: `/forge <step> [args]`

In standalone mode (no `--orchestrated` flag):
- Skill reads inputs from `.forge/`
- Skill writes outputs to `.forge/`
- Skill exits cleanly to the user (no freshen, no step exit protocol)
- User decides what to do next

---

## Step Exit Protocol

**Read**: `references/step-handoff.md`

Every orchestrated step follows the same exit pattern:

1. Write output artifacts to `.forge/`
2. Write handoff: `.forge/handoffs/handoff-<step>.md` with full context for next step
3. Run the step exit helper for commit + freshen:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-step-exit.sh --step "<step>" --summary "<step summary>" --next "<next-command>"
   ```
   - Use the specific next step command when deterministic (e.g., `/forge research --orchestrated`)
   - Use `/forge continue` when next step depends on runtime state
   - If the helper reports `freshen_queued: false`, show the `fallback_message` to the user
4. **STOP** — end response immediately. Do not proceed inline.

---

## `/forge status`

Run the status dashboard script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-status.sh
```

Show the `display` field from the output to the user.

---

## `/forge stop`

Graceful stop:

1. If execution phase is active:
   - Write handoff following `references/handoff-format.md`
   - Update `.forge/state.json`: set `status: "paused"`
   - Release lock: `bash ${CLAUDE_PLUGIN_ROOT}/bin/forge-lock.sh release --forge-dir .forge` (see
     `references/session-locking.md`) — never `rm` the file directly.
2. Cancel pending freshen signal — resolve freshen's plugin root as a sibling of forge's own (a
   bare `plugins/freshen/...` path can't resolve from the target project's cwd; see Ground Rule 5
   and `plugins/agents/references/cross-plugin-usage.md`'s File Path Convention for the same
   pattern used elsewhere):
   ```bash
   FRESHEN_PLUGIN_ROOT="$(cd "$(dirname "${CLAUDE_PLUGIN_ROOT}")/freshen" && pwd)"
   bash "$FRESHEN_PLUGIN_ROOT/bin/freshen.sh" cancel --source forge
   ```
3. Report: "Pipeline stopped. Run `/forge continue` to resume."

---

## Settings

`.forge/config.json` (created with defaults on first run):

```json
{
  "yolo": false,
  "max_fix_cycles": 3,
  "max_fix_cycles_yolo": 10,
  "when_in_doubt": "escalate",
  "max_retries": 4,
  "max_stories_per_session": 1,
  "max_sessions": 200,
  "max_total_retries": 100,
  "heartbeat_window_minutes": 30,
  "governed_explorer": false
}
```

`governed_explorer` (default `false`) opts the **research** step into greenlight
plan explorers: for a codebase-oriented track it runs a headless Sonnet
`claude -p` explorer in a disposable worktree (governed by the greenlight gate)
and folds its findings into synthesis. Off by default — it spawns a real model
and costs tokens/latency, exactly like the `ai_enabled` tradeoff in greenlight's
own config. See `skills/research/SKILL.md` Step 2b.

**This block is the single source of these defaults.** Any other doc that needs them references
this section rather than restating it — a hand-synced second copy had already drifted (it was
missing `governed_explorer`) despite carrying an explicit "byte-for-byte" instruction.

The three runaway safeguards are independently configurable but **not independent in scale**:
`max_retries` caps attempts on a single story, `max_total_retries` caps failed attempts across the
whole plan, and `max_sessions` caps execute sessions. `total_retries` increments on every failed
evaluation, not only when a story exhausts its retries, so a large plan accrues tens of retries in
normal healthy operation. If you change `max_retries` or `max_sessions`, re-check the relationship
— see [`docs/decisions/forge-hardening.md`](../../../../docs/decisions/forge-hardening.md) for why
`max_total_retries` is 100 rather than the low tens.

`--yolo` overrides at runtime (sets `yolo: true` in config for the session).

---

## Pipeline Skills

Each skill is a separate SKILL.md under `skills/<step>/`. The orchestrator dispatches by reading the skill file and following its instructions.

| # | Skill | Input | Output |
|---|-------|-------|--------|
| 1 | `interrogate` | User's idea | `.forge/IDEA.md` |
| 2 | `research` | `IDEA.md` | `.forge/research/SUMMARY.md` + `.forge/TEAM.md` |
| 3 | `design` | `IDEA.md`, `research/SUMMARY.md`, `TEAM.md` | `.forge/DESIGN.md` |
| 4 | `plan` | `IDEA.md`, `DESIGN.md` | `.forge/PLAN.md` |
| 5 | `decompose` | `PLAN.md`, `DESIGN.md` | stories + `.forge/plan-mapping.json` |
| 6 | `execute` | `plan-mapping.json`, stories | Implemented code |
| 7 | `review` | Implemented code, `DESIGN.md` | `.forge/REVIEW-REPORT.md` |
| 8 | `validate` | Implemented code, `PLAN.md` | `.forge/VALIDATE-REPORT.md` |
| 9 | `triage` | `REVIEW-REPORT.md`, `VALIDATE-REPORT.md` | `.forge/TRIAGE.md` |
| 10 | `document` | All artifacts, implemented code | `.forge/DOCUMENTATION.md` |
| 11 | `deploy` | `DEPLOY-APPROVAL.md` | `.forge/COMPLETION.md` |

---

## Agent Roster (15 agents)

Every name below is a real file in `plugins/agents/agents/` (see
`plugins/agents/references/agent-catalog.md` for the full library). See
`references/team-roles.md`'s "Resolving subagent_type" for how each is actually spawned
(`agents:<name>` preferred, `general-purpose` + inlined `.md` as fallback — never a bare
`general-purpose` default).

| Agent | Used By |
|-------|---------|
| `domain-researcher` | interrogate (recon), research |
| `software-architect` | design, review, execute (drift check) |
| `software-engineer` | execute (available via roster) |
| `qa-engineer` | plan, validate, triage |
| `ux-designer-cli` / `ux-designer-web` / `ux-designer-mobile` | design (conditional) — pick the variant matching TEAM.md's project type |
| `project-manager` | plan, validate, triage |
| `skeptic` | design, plan, review, triage |
| `security-researcher` | design (conditional), review (conditional) |
| `accessibility-engineer` | design (conditional), review (conditional) |
| `technical-writer` | document |
| `generator` | execute |
| `evaluator` | execute |
| `reviewer` | review |
| `validator` | validate |
| `triager` | triage |

The research step produces `.forge/TEAM.md` recommending which conditional agents to activate.

---

## Artifact Namespace

```
.forge/
  # Config (version-controlled)
  config.json
  plan-mapping.json
  team-roster.json

  # Step outputs (version-controlled)
  IDEA.md
  research/SUMMARY.md
  TEAM.md
  DESIGN.md
  PLAN.md
  REVIEW-REPORT.md
  VALIDATE-REPORT.md
  TRIAGE.md
  DOCUMENTATION.md
  DEPLOY-APPROVAL.md
  COMPLETION.md

  # Fix cycle archives (version-controlled)
  fix-cycles/cycle-N/
    TRIAGE.md
    PLAN.md
    plan-mapping.json

  # Handoff archive (version-controlled)
  handoffs/
    handoff-interrogate.md
    handoff-research.md
    ...

  # Runtime (gitignored)
  state.json
  lock.json
  verdicts.jsonl
```

---

## Resumption

If the user invokes `/forge` or `/forge continue` at any point:
1. The orchestrator scans artifacts (and storyhook) to detect state via `forge-state.sh`
2. Checks `expected_handoff_present` — the handoff `forge-state.sh` computed as required for the
   SPECIFIC step being resumed (not just "the newest file in `handoffs/`," which can silently be
   the wrong step's handoff after a crash or a git operation that resets mtimes)
3. If `expected_handoff_present` is `false` → pause and ask user via `AskUserQuestion`
   (missing-handoff protocol from `references/step-handoff.md`)
4. Otherwise, reads the handoff named in `expected_handoff` (or `latest_handoff` if none is
   expected, e.g. a fresh pipeline) for context
5. Dispatches to the detected next step

This makes the pipeline fully resumable from any point. The orchestrator never needs to know which step just finished — it derives everything from artifacts + handoff.
