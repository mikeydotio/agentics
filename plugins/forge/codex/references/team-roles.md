# Agent Team Roles

> **Note**: Agent definitions AND the roster (name, tools, description, "Used By") live in the
> shared library — `plugins/agents/references/agent-catalog.md` is the single source. This doc
> covers only what's genuinely forge-specific: which real filename to use for a role that's
> easy to misname, the project-type→team mapping, and how spawning actually works. For the
> per-step "who's used where" index, see `<plugin-root>/codex/skills/forge/SKILL.md`'s Agent Roster table — don't
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
both `VALIDATE-REPORT.md` and new test files directly. Each spawn site (`<plugin-root>/codex/skills/review/SKILL.md`,
`<plugin-root>/codex/skills/validate/SKILL.md`, `<plugin-root>/codex/skills/triage/SKILL.md`) states this at its own point of use; this is
just the one-line summary, not a third copy of the reasoning.

## Spawning Philosophy

Not every agent is needed for every project. The research step produces a `TEAM.md` recommending
which conditional agents to activate based on the project type (see `<plugin-root>/codex/skills/research/SKILL.md`'s
TEAM.md template for the full project-type list, which includes Mobile app for `ux-designer-mobile`):

- **CLI tool:** Engineer, Architect, QA, Security, Technical Writer, Skeptic
- **Web application:** All agents including UX (`ux-designer-web`) and Accessibility
- **Mobile app:** All agents including UX (`ux-designer-mobile`) and Accessibility
- **Library/SDK:** Engineer, Architect, QA, Technical Writer, Skeptic
- **Data pipeline:** Engineer, Architect, QA, Security, Technical Writer
- **Infrastructure:** Engineer, Architect, Security, Technical Writer

The Skeptic and Domain Researcher are always included regardless of project type.

## Resolving canonical role

Follow `<plugin-root>/codex/references/runtime.md` for native dispatch, role resolution,
permissions and result collection. All canonical roles come from the Agents resolver;
there is no registered Forge agent namespace. Use each role's full definition.

Append the Forge override for generator, evaluator, reviewer, triager and validator.
Append software-architect's override only for the execution-loop drift check.
Other roles have no Forge override. Conditional choices still come from TEAM.md.
