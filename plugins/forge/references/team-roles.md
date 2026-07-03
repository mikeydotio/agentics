# Agent Team Roles

> **Note**: Agent definitions have moved to the shared library at `plugins/agents/agents/`. See `plugins/agents/references/agent-catalog.md` for the full roster.

The forge pipeline uses a cross-functional team of specialized agents. Each agent has a distinct perspective, toolset, and responsibility. The orchestrator spawns them at the appropriate step.

## Role Catalog

### Domain Researcher
**Perspective:** "What already exists? What are the established patterns?"
**When spawned:** During interrogation (to check existing solutions) and research step (to research best practices)
**Output:** Research findings with confidence levels, existing solution analysis, best practice recommendations

### Software Architect
**Perspective:** "Does this design hold together? Are the abstractions right?"
**When spawned:** During design step, review step, and execution drift checks
**Output:** Architecture review, component diagram descriptions, interface definitions, integration concerns

### Software Engineer
**Agent file:** `software-engineer.md` (not `senior-engineer` — that name doesn't exist in the library)
**Perspective:** "How do I build this correctly and maintainably?"
**When spawned:** During execution (available via team roster)
**Output:** Working code, implementation notes, technical debt flags

### QA Engineer
**Perspective:** "How do I break this? What hasn't been tested?"
**When spawned:** During plan step, validate step, and triage step
**Output:** Test plan, test cases (unit/integration/e2e), edge case catalog, test coverage analysis

### UX Designer (platform-specific)
**Agent file:** one of `ux-designer-cli.md` / `ux-designer-web.md` / `ux-designer-mobile.md` — there
is no bare `ux-designer.md`. Pick the variant matching the project type recorded in `TEAM.md`
(CLI tool → `ux-designer-cli`; Web application → `ux-designer-web`; Mobile app → `ux-designer-mobile`).
If the project type is ambiguous or spans platforms, default to `ux-designer-web` (the most
general of the three) and say so explicitly in the handoff.
**Perspective:** "Does this make sense to a human? Is it pleasant to use?"
**When spawned:** During design step (only when the project has user-facing interfaces)
**Output:** Interaction flow analysis, usability concerns, design pattern recommendations, accessibility notes

### Project Manager
**Perspective:** "Are we building what we said we'd build? Can we resume if interrupted?"
**When spawned:** During plan step, validate step, triage step, and decompose step
**Output:** Task list with dependencies, progress tracking, requirement-to-implementation traceability, resumption state

### Skeptic (the team's "devil's advocate")
**Agent file:** `skeptic.md` (not `devils-advocate` — that name doesn't exist in the library; "devil's
advocate" is this role's description, not its filename)
**Perspective:** "What if we're wrong? What are we not seeing?"
**When spawned:** During design step, plan step, review step, and triage step
**Output:** Assumption challenges (ranked by risk), alternative approaches worth considering, blind spot identification

### Security Researcher
**Perspective:** "How can this be exploited? What are we exposing?"
**When spawned:** During design step (conditional) and review step (conditional)
**Output:** Threat model, vulnerability assessment, security recommendations, OWASP compliance notes

### Accessibility Engineer
**Perspective:** "Can everyone use this? What barriers exist?"
**When spawned:** During design step (conditional) and review step (conditional)
**Output:** WCAG compliance assessment, assistive technology compatibility notes, inclusive design recommendations

### Technical Writer
**Perspective:** "Can someone understand this without asking the author?"
**When spawned:** During the document step
**Output:** API documentation, architecture decision records, usage guides, inline documentation review

### Generator
**Perspective:** "Implement this story precisely and completely."
**When spawned:** During execute step for each story
**Output:** Implemented code with structured JSON status report

### Evaluator
**Perspective:** "Prove to me this implementation is correct."
**When spawned:** During execute step after each generator run
**Output:** Structured JSON verdict with cited evidence

### Reviewer
**Perspective:** "What quality gaps and design drift exist in the codebase?"
**When spawned:** During review step
**Output:** Structured findings by severity, returned as its response (it is `read_only: true` —
it does NOT write `REVIEW-REPORT.md` itself; the review skill synthesizes that file from the
reviewer's, software-architect's, and skeptic's findings)

### Validator
**Perspective:** "What tests are missing? What coverage gaps exist?"
**When spawned:** During validate step
**Output:** VALIDATE-REPORT.md with test coverage findings (the validator IS `read_only: false` —
unlike reviewer/triager, it legitimately writes both the report and new test files itself)

### Triager
**Perspective:** "Should we fix this automatically or ask the user?"
**When spawned:** During triage step
**Output:** Structured FIX/ESCALATE decisions, returned as its response (it is `read_only: true` —
it does NOT write `TRIAGE.md` itself; the triage skill synthesizes that file from the triager's,
qa-engineer's, and skeptic's decisions)

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

### Resolving `subagent_type` (F057, F060, F084)

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
Every other agent in the Role Catalog above (domain-researcher, qa-engineer, ux-designer-*,
project-manager, skeptic, security-researcher, accessibility-engineer, technical-writer) has no
forge override — skip that step for them and inline only the shared definition (or use the
registered `agents:<name>` type directly).

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
