# Shared Agent Catalog

Complete roster of agents available in the shared library at `plugins/agents/agents/`.

## General-Purpose Agents

| Name | Tools | R/O | Tags | Description |
|------|-------|-----|------|-------------|
| [software-engineer](../agents/software-engineer.md) | Read, Write, Edit, Bash, Grep, Glob | no | implementation | Red-green TDD, SOLID, YAGNI, DRY — writes minimum correct code |
| [qa-engineer](../agents/qa-engineer.md) | Read, Write, Edit, Bash, Grep, Glob | no | testing | No-mock enforcement, 11-category edge cases, production workflow tests, .env scaffolding |
| [security-researcher](../agents/security-researcher.md) | Read, Grep, Glob, Bash, WebSearch | yes | review, investigation | OWASP Top 10 audit, trust boundary mapping, exploit scenarios, CVE scanning |
| [software-architect](../agents/software-architect.md) | Read, Grep, Glob | yes | design, review | SOLID enforcement, coupling analysis, interface contracts, system diagrams, dependency direction |
| [project-manager](../agents/project-manager.md) | Read, Write, Grep, Glob | no | design | Wave decomposition, requirement traceability, scope creep detection, deviation tracking |
| [technical-writer](../agents/technical-writer.md) | Read, Write, Edit, Grep, Glob | no | documentation | Documentation placement framework, audience targeting, ADRs, signal-to-noise optimization |
| [copy-editor](../agents/copy-editor.md) | Read, Write, Edit, Grep, Glob | no | documentation | LLM-tell detection, human voice calibration, engagement optimization, error message design |
| [skeptic](../agents/skeptic.md) | Read, Grep, Glob | yes | challenge, review | Socratic questioning, assumption mapping, gap detection, stress testing, constructive challenge |
| [investigator](../agents/investigator.md) | Read, Grep, Glob, Bash, WebSearch | yes | investigation, research | 5 Whys, Fishbone, multi-hypothesis, red herring detection, evidence-vs-theory separation |
| [accessibility-engineer](../agents/accessibility-engineer.md) | Read, Grep, Glob, WebSearch | yes | review, design | WCAG 2.2 AA, per-platform assistive tech, ADHD/cognitive/motor/vestibular considerations |
| [performance-engineer](../agents/performance-engineer.md) | Read, Grep, Glob, Bash | yes | review, investigation | Big-O analysis, profiling methodology, bottleneck identification, caching strategy, budgets |
| [devops-engineer](../agents/devops-engineer.md) | Read, Write, Edit, Bash, Grep, Glob | no | operations, implementation | CI/CD pipelines, deployment strategies, containerization, monitoring/alerting, IaC |
| [api-designer](../agents/api-designer.md) | Read, Grep, Glob | yes | design, review | Consistency enforcement, versioning, breaking change detection, pagination, error contracts |
| [observability-engineer](../agents/observability-engineer.md) | Read, Write, Edit, Bash, Grep, Glob | no | operations, implementation | Structured logging, metrics (4 golden signals), distributed tracing, SLOs, alert design |
| [data-engineer](../agents/data-engineer.md) | Read, Write, Edit, Bash, Grep, Glob | no | design, implementation | Schema design, migration planning, query optimization, data integrity, backup/recovery |
| [lawyer](../agents/lawyer.md) | Read, Grep, Glob, WebSearch | yes | review, legal | OSS license compatibility, GDPR/CCPA, billing compliance, ToS review, business licensing |

## Platform-Specific UX Designers

| Name | Tools | Platform | Description |
|------|-------|----------|-------------|
| [ux-designer-cli](../agents/ux-designer-cli.md) | Read, Grep, Glob | CLI | Terminal conventions, help text, exit codes, ANSI color a11y, piping, TTY detection |
| [ux-designer-web](../agents/ux-designer-web.md) | Read, Grep, Glob, WebSearch, WebFetch | Web | Design tokens, responsive, Core Web Vitals, dark mode, component patterns, motion a11y |
| [ux-designer-mobile](../agents/ux-designer-mobile.md) | Read, Grep, Glob, WebSearch, WebFetch | Mobile | HIG/Material Design, touch targets, gestures, safe areas, offline-first, thumb zone |

## Pipeline-Specific Agents

### Pilot Pipeline

| Name | Tools | R/O | Description |
|------|-------|-----|-------------|
| [generator](../agents/generator.md) | Read, Write, Edit, Bash, Grep, Glob | no | Implements stories with TDD, secure-by-default, design adherence. Draws from Software Engineer + Architect + Security. |
| [evaluator](../agents/evaluator.md) | Read, Bash, Grep, Glob | yes | Verifies implementations with debiasing, multi-dimensional checks. Draws from QA + Skeptic + Security + Performance. |
| [reviewer](../agents/reviewer.md) | Read, Grep, Glob, Bash | yes | 8-dimensional codebase analysis (architecture, security, perf, coverage, API, observability, copy, legal). |
| [validator](../agents/validator.md) | Read, Write, Edit, Bash, Grep, Glob | no | Test hardening with no-mock, edge cases, security/perf/data tests. Draws from QA + Security + Performance + Data. |
| [triager](../agents/triager.md) | Read, Grep, Glob | yes | FIX/ESCALATE decisions with 4-dimension framework. Draws from PM + Skeptic + Architect + Security. |
| [domain-researcher](../agents/domain-researcher.md) | Read, Grep, Glob, WebSearch, WebFetch | yes | Structured research with source hierarchy, license analysis, hype checking. Draws from Investigator + Lawyer + Skeptic. |

### RCA Pipeline

| Name | Tools | R/O | Description |
|------|-------|-----|-------------|
| [evidence-collector](../agents/evidence-collector.md) | Read, Grep, Glob, Bash | yes | 7-category evidence taxonomy, facts-only discipline. Draws from Investigator + Observability + Data + Security. |
| [hypothesis-challenger](../agents/hypothesis-challenger.md) | Read, Grep, Glob, Bash | yes | 5 challenge strategies, absorbs archaeologist + analyst + remediation roles. Draws from Skeptic + Architect + Security. |

## Team Composition by Project Type

| Project Type | Recommended Agents |
|-------------|-------------------|
| **CLI tool** | software-engineer, software-architect, qa-engineer, security-researcher, technical-writer, ux-designer-cli, skeptic |
| **Web application** | All general-purpose + ux-designer-web + accessibility-engineer |
| **Mobile app** | All general-purpose + ux-designer-mobile + accessibility-engineer |
| **Library/SDK** | software-engineer, software-architect, qa-engineer, api-designer, technical-writer, skeptic |
| **Data pipeline** | software-engineer, software-architect, qa-engineer, data-engineer, security-researcher, observability-engineer |
| **API service** | software-engineer, software-architect, qa-engineer, api-designer, security-researcher, devops-engineer, observability-engineer |
| **Infrastructure** | software-engineer, software-architect, security-researcher, devops-engineer, observability-engineer |
| **SaaS product** | All general-purpose + platform UX + accessibility-engineer + lawyer |

The Skeptic and Investigator are always recommended regardless of project type.
