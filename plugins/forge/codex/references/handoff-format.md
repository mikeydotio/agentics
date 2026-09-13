# Handoff Format

Specification for the execute step's own session-to-session handoff artifact —
`.forge/handoffs/handoff-execute.md` — that enables clean transitions between execution sessions
within the execute step (as distinct from `<plugin-root>/codex/references/step-handoff.md`, which specifies the
generic between-*steps* handoff format used by every pipeline step, including execute's own final
handoff to review_validate).

## Four Layers

Forge handoffs use four complementary persistence layers:

| Layer | File | Purpose | Tracked? |
|-------|------|---------|----------|
| Config + State | `.forge/config.json` + `.forge/state.json` | Machine-readable settings and runtime state | config: yes, state: no |
| Handoff | `.forge/handoffs/handoff-execute.md` | Human-readable session narrative | Yes (version-controlled, per `<plugin-root>/codex/references/step-handoff.md`) |
| Verdict Log | `.forge/verdicts.jsonl` | Structured evaluator history | No (ephemeral) |
| Storyhook | storyhook's own store, outside the repo | Story-level state and comments | No — see below |

**Storyhook is not a repo layer.** Story data lives in one SQLite store outside every repository
(`$STORYHOOK_DATA_DIR`, else `$XDG_DATA_HOME/storyhook`, else `~/.local/share/storyhook`); run
`story help storage` for the authoritative description. The only storyhook artifact a repository
carries is the committed pointer file `.storyhook.toml`, which names the project's uuid and prefix
so a fresh clone resolves the same project — it holds no story state. Nothing forge does can, or
should, commit story state: there is no repo path to add.

**Priority**: config.json + state.json + storyhook are required for mechanical recovery.
`handoff-execute.md` is the primary context source — if missing, pause and ask the user (see
"Recovery Without Handoff" below). `forge-state.sh`'s `expected_handoff`/`expected_handoff_present`
fields name this exact file when the detected state is `execute` and a resume (not a fresh start)
is in progress.

## handoff-execute.md Format

```markdown
# Work Handoff

## Session Summary
- **Session**: [session ID from lock]
- **Duration**: [time from lock acquired_at to now]
- **Stories completed**: [count]
- **Stories attempted**: [count]
- **Status**: [why we stopped — max_stories, blocked, error, user stop]

## What Happened
[Narrative of what was accomplished this session]

## Stories Completed This Session
- HP-5: [title] — [one-line summary]
- HP-6: [title] — [one-line summary]

## Current Blockers
- HP-7: [blocked reason and last evaluator feedback]

## Working Context
[This is the most valuable section for the next session]

### Patterns Established
- [Naming conventions decided during implementation]
- [Architecture patterns that emerged]

### Micro-Decisions
- [Small decisions not in DESIGN.md that future stories should follow]

### Known Gotchas
- [Things that tripped up the generator or evaluator]
- [Flaky tests and their names]

## What's Next
- [Next story to pick up]
- [Any decisions needed from user]
```

## Incremental Handoff Updates

After each story completes (Step 7 of the execution loop), update `handoff-execute.md` incrementally rather than rewriting from scratch. This ensures crash recovery has fresh context even without a clean pause.

**Before** (after HP-5 completes):
```markdown
## Stories Completed This Session
- HP-5: Create config module — loads YAML, returns typed config object

## Working Context
### Patterns Established
- Config uses strict zod schemas — all fields required, no defaults
```

**After** (HP-6 also completes — append to existing sections):
```markdown
## Stories Completed This Session
- HP-5: Create config module — loads YAML, returns typed config object
- HP-6: Create logger module — structured JSON to stdout, uses config for log level

## Working Context
### Patterns Established
- Config uses strict zod schemas — all fields required, no defaults
- Logger wraps pino, all modules import from src/logger.ts (not pino directly)
```

Only append — never remove prior entries. The handoff grows throughout the session.

## Writing the Handoff

The handoff is written at these triggers:
1. **`$forge:forge stop`** — User-initiated graceful stop
2. **Session stop hook** — Session ending (compaction, timeout)
3. **Loop pause** — `max_stories_per_session` reached, blocked, storyhook failure, runaway safeguard

The handoff MUST include a "working context" section that captures patterns, conventions, and micro-decisions from the session. This is what makes resumed sessions effective — without it, the next session starts cold.

## Cold-Start Essentials

When context is cleared between stories (`max_stories_per_session: 1`), the handoff is the ONLY source of session knowledge. These sections are mandatory in every handoff:

### Patterns Established (REQUIRED)

Every naming convention, architectural pattern, error handling approach, or code organization decision made during execution. Examples:
- "All handlers use the pattern: validate → transform → persist → respond"
- "Error types are defined in `src/errors.ts`, one per module"
- "Tests use the factory pattern from `tests/helpers/factory.ts`"

### Micro-Decisions (REQUIRED)

Decisions not in DESIGN.md that emerged during implementation:
- "Used zod instead of joi for validation (better TypeScript inference)"
- "Config paths are relative to project root, not CWD"

### Code Landmarks (REQUIRED)

Key files and their roles, so the next session knows where things are without exploring:
- "`src/config.ts` — central config, all modules import from here"
- "`src/middleware/auth.ts` — auth middleware, uses JWT with RS256"
- "`tests/helpers/factory.ts` — test data factories for all domain objects"

### Test State (REQUIRED)

- Which tests pass, which are flaky, which are skipped
- Test run command and any required environment setup
- Most recent test suite output summary

## Recovery Without Handoff

If `.forge/handoffs/handoff-execute.md` is missing (crash without clean shutdown), pause and ask the
user rather than continuing silently. The `the native question tool` for this case lives in
`<plugin-root>/codex/references/step-handoff.md` under **Missing Handoff on Resumption → Variant: the execute handoff
is missing after a crash** — that file owns the protocol for every missing-handoff case.

If the user chooses "Continue anyway", recovery falls back to:

| Source | What It Provides | What It Lacks |
|--------|-----------------|---------------|
| `state.json` | Metadata, retry counts | No working context |
| Storyhook | Story states, evaluator feedback | No cross-story patterns |
| `git log` | Recent commits | No micro-decisions or gotchas |
| `config.json` | User limits | No session narrative |
