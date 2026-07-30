# Agent Team Roles

> **Note**: Agent definitions AND the roster (name, tools, description, "Used By") live in the
> shared library — `plugins/agents/references/agent-catalog.md` is the single source. This doc
> covers only what's genuinely forge-specific: which real filename to use for a role that's
> easy to misname, the project-type→team mapping, and how spawning actually works. For the
> per-step "who's used where" index, see `skills/forge/SKILL.md`'s Agent Roster table — don't
> restate it here.

## Naming gotchas

These three roles get misnamed often enough to call out explicitly — the name on the left does
**not** exist in `plugins/agents/agents/`:

| Wrong | Real agent file |
|---|---|
| `senior-engineer` | `software-engineer.md` |
| `devils-advocate` (or "devil's advocate") | `skeptic.md` — "devil's advocate" is this role's description, not its filename |
| `ux-designer` (bare) | one of `ux-designer-cli.md` / `ux-designer-web.md` / `ux-designer-mobile.md` — pick the variant matching `TEAM.md`'s recorded project type; if ambiguous or cross-platform, default to `ux-designer-web` and say so explicitly in the handoff |

**Read/write ownership** for the three `read_only: true` pipeline agents (`reviewer`, `triager`)
vs. the one that legitimately isn't (`validator`): `reviewer` and `triager` return findings/
decisions as their response — the orchestrating skill (review/triage) synthesizes the report file
from that response, the agent never writes it itself. `validator` is the exception — it writes
both `VALIDATE-REPORT.md` and new test files directly. Each spawn site (`skills/review/SKILL.md`,
`skills/validate/SKILL.md`, `skills/triage/SKILL.md`) states this at its own point of use; this is
just the one-line summary, not a third copy of the reasoning.

## Spawning Philosophy

Not every agent is needed for every project. The research step produces a `TEAM.md` recommending
which conditional agents to activate based on the project type (see `skills/research/SKILL.md`'s
TEAM.md template for the full project-type list, which includes Mobile app for `ux-designer-mobile`):

- **CLI tool:** Engineer, Architect, QA, Security, Technical Writer, Skeptic
- **Web application:** All agents including UX (`ux-designer-web`) and Accessibility
- **Mobile app:** All agents including UX (`ux-designer-mobile`) and Accessibility
- **Library/SDK:** Engineer, Architect, QA, Technical Writer, Skeptic
- **Data pipeline:** Engineer, Architect, QA, Security, Technical Writer
- **Infrastructure:** Engineer, Architect, Security, Technical Writer

The Skeptic and Domain Researcher are always included regardless of project type.

## Spawning Mechanics

All agent spawns are **foreground**. Never set `run_in_background` on any Agent() call.

To spawn agents in parallel: make multiple Agent() calls in a single message. The orchestrator blocks until all agents return their results, then synthesizes.

This ensures every step completes all its agent work before writing artifacts and exiting.

### Resolving `subagent_type`
Every spawn — not just generator/evaluator — must resolve a real `subagent_type` instead of
defaulting to `general-purpose`, and must wire in the pipeline-specific override when one exists.
The full resolution mechanism and the reason it exists (tool restrictions are cosmetic under
`general-purpose`) live in the `agents` plugin's cross-plugin usage reference — resolve its path
the same way as any other sibling-plugin file (never a bare `plugins/agents/references/...` path,
per that same doc's own File Path Convention):
`Read "$(cd "$(dirname "${CLAUDE_PLUGIN_ROOT}")/agents" && pwd)/references/cross-plugin-usage.md"`.
Read it in full; this section only adds forge-specific specifics.

**Which forge agents have an override** (`${CLAUDE_PLUGIN_ROOT}/agent-overrides/<name>-context.md`)
to concatenate in when spawning them: `generator`, `evaluator`, `reviewer`, `triager`, `validator`,
`software-architect` (the execution-loop drift check only — see `agent-overrides/software-architect-context.md`).
Every other agent forge uses (domain-researcher, qa-engineer, ux-designer-*, project-manager,
skeptic, security-researcher, accessibility-engineer, technical-writer — see
`plugins/agents/references/agent-catalog.md` for the full library) has no forge override — skip
that step for them and inline only the shared definition (or use the registered `agents:<name>`
type directly).

**Quick reference for every spawn:**
1. Try `subagent_type: "agents:<name>"`. If it's in your available subagent types, use it — done
   (override + dynamic context still get appended to the prompt if an override file exists).
2. Otherwise resolve `AGENTS_PLUGIN_ROOT="$(cd "$(dirname "${CLAUDE_PLUGIN_ROOT}")/agents" && pwd)"`,
   read `"$AGENTS_PLUGIN_ROOT/agents/<name>.md"`, read
   `"${CLAUDE_PLUGIN_ROOT}/agent-overrides/<name>-context.md"` if it exists, concatenate both plus
   the dynamic context, and spawn `subagent_type: "general-purpose"`.
3. Never spawn a namespace that isn't `agents:` or `general-purpose` — there is no `forge:`
   namespace (forge registers no agents of its own; every agent it uses lives in the `agents`
   plugin).
