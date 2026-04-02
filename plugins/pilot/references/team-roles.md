# Agent Team Roles

> **Note**: Agent definitions have moved to the shared library at `plugins/agents/agents/`. See `plugins/agents/references/agent-catalog.md` for the full roster.

The pilot pipeline uses a cross-functional team of specialized agents. Each agent has a distinct perspective, toolset, and responsibility. The orchestrator spawns them at the appropriate step.

## Role Catalog

### Domain Researcher
**Perspective:** "What already exists? What are the established patterns?"
**When spawned:** During interrogation (to check existing solutions) and research step (to research best practices)
**Output:** Research findings with confidence levels, existing solution analysis, best practice recommendations

### Software Architect
**Perspective:** "Does this design hold together? Are the abstractions right?"
**When spawned:** During design step, review step, and execution drift checks
**Output:** Architecture review, component diagram descriptions, interface definitions, integration concerns

### Senior Software Engineer
**Perspective:** "How do I build this correctly and maintainably?"
**When spawned:** During execution (available via team roster)
**Output:** Working code, implementation notes, technical debt flags

### QA Engineer
**Perspective:** "How do I break this? What hasn't been tested?"
**When spawned:** During plan step, validate step, and triage step
**Output:** Test plan, test cases (unit/integration/e2e), edge case catalog, test coverage analysis

### UX Designer
**Perspective:** "Does this make sense to a human? Is it pleasant to use?"
**When spawned:** During design step (only when the project has user-facing interfaces)
**Output:** Interaction flow analysis, usability concerns, design pattern recommendations, accessibility notes

### Project Manager
**Perspective:** "Are we building what we said we'd build? Can we resume if interrupted?"
**When spawned:** During plan step, validate step, triage step, and decompose step
**Output:** Task list with dependencies, progress tracking, requirement-to-implementation traceability, resumption state

### Devil's Advocate
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
**Output:** REVIEW-REPORT.md with findings by severity

### Validator
**Perspective:** "What tests are missing? What coverage gaps exist?"
**When spawned:** During validate step
**Output:** VALIDATE-REPORT.md with test coverage findings

### Triager
**Perspective:** "Should we fix this automatically or ask the user?"
**When spawned:** During triage step
**Output:** TRIAGE.md with FIX/ESCALATE decisions for each finding

## Spawning Philosophy

Not every agent is needed for every project. The research step produces a `TEAM.md` recommending which conditional agents to activate based on the project type:

- **CLI tool:** Engineer, Architect, QA, Security, Technical Writer, Devil's Advocate
- **Web application:** All agents including UX and Accessibility
- **Library/SDK:** Engineer, Architect, QA, Technical Writer, Devil's Advocate
- **Data pipeline:** Engineer, Architect, QA, Security, Technical Writer
- **Infrastructure:** Engineer, Architect, Security, Technical Writer

The Devil's Advocate and Domain Researcher are always included regardless of project type.
