# agentics

Personal Claude Code plugin marketplace — 11 plugins covering idea-to-deployment
pipelines, root cause analysis, versioning, deployment, and session safety.

## Install

```
/plugin marketplace add mikeydotio/agentics
```

Then install any plugin:

```
/plugin install <plugin-name>@agentics
```

## Plugins

| Plugin | Skills | Hooks | Purpose |
|---|---|---|---|
| [agents](plugins/agents) | `/agents` | — | Shared library of 28 research-backed specialist agent definitions (architect, qa-engineer, security-researcher, UX designers, …) used by forge, rca, and council. |
| [forge](plugins/forge) | `/forge` + 11 step skills | SessionStart, Stop | Unified idea-to-deployment pipeline. State-machine router with artifact-based resumption and context clearing between steps. |
| [rca](plugins/rca) | `/rca` + 7 step skills | — | Reproduction-gated root cause analysis for *known* defects. Repro gate → git forensics → hypothesis falsification → ODC classification → gated fix → postmortem. |
| [council](plugins/council) | `/council-vote` | — | Convenes a 3-member sub-agent council to deliberate and vote on a consequential decision when the user is unavailable. Auditable trail in `.council/`. |
| [semver](plugins/semver) | `/semver` | SessionStart, PostToolUse | Semantic version lifecycle: tracking, bumping, changelog generation, sync validation and repair. |
| [deployit](plugins/deployit) | `/deployit` | — | On-tailnet OTA deploys of iOS / macOS / visionOS apps via Tailscale Serve, with a shared cross-machine build index. |
| [issue](plugins/issue) | `/issue` | — | GitHub-issue lifecycle: file, view, dispatch to a fresh session in a tmux window + worktree, and clean up on completion. |
| [reconcile-pr](plugins/reconcile-pr) | `/reconcile-pr` | — | Rebases a PR onto its base branch, resolves conflicts preserving both behaviors, verifies with tests, then force-pushes under a leased safety guard. |
| [greenlight](plugins/greenlight) | `/greenlight` | PreToolUse | Safety hook that classifies commands before they run — deterministic parsing with AI fallback and permission-mode awareness. |
| [freshen](plugins/freshen) | `/freshen` | Stop, SessionStart | Automatic context clearing via tmux — lets plugins trigger `/clear` and re-invocation between workflow phases. |
| [hook-guard](plugins/hook-guard) | — | SessionStart | Circuit breaker for Claude Code hooks — detects rapid repeated firings and breaks Stop-hook infinite loops. |

### forge pipeline skills

`/forge` routes through these in order; each can also be invoked directly.

| Skill | Produces | Purpose |
|---|---|---|
| `/interrogate` | `IDEA.md` | Braindump, lightweight recon, and relentless questioning of a raw idea. |
| `/research` | `research/SUMMARY.md`, `TEAM.md` | Parallel domain research plus an agent team roster recommendation. |
| `/design` | `DESIGN.md` | Architecture design with cross-functional review driven by the roster. |
| `/plan` | `PLAN.md` | Task breakdown into waves with acceptance criteria. |
| `/decompose` | `plan-mapping.json` | Turns waves into storyhook stories with dependencies, priorities, and design context. |
| `/execute` | story implementations | Generator-evaluator loop with retry and session persistence. |
| `/review` | `REVIEW-REPORT.md` | Static gap and defect analysis — code quality, design drift, story hygiene. |
| `/validate` | `VALIDATE-REPORT.md` | Test hardening — runs tests, finds coverage gaps, writes missing tests. |
| `/triage` | `TRIAGE.md` | Labels every review/validation finding FIX or ESCALATE. |
| `/document` | `DOCUMENTATION.md` | Comprehensive project documentation. |
| `/deploy` | `COMPLETION.md` | Deployment gate — never proceeds without explicit approval. |

### rca pipeline skills

| Skill | Produces | Purpose |
|---|---|---|
| `/intake` | IS/IS-NOT grid | Latches a GitHub/storyhook issue and builds the Kepner-Tregoe differential. |
| `/reproduce` | failing test | The firm repro gate — no hypothesis work happens until it passes. |
| `/locate` | `ORIGIN.md` | Deterministic git forensics: bisect, blame, pickaxe, SZZ-lite, hotspots. |
| `/diagnose` | `DIAGNOSIS.md` | Falsifies ≥2 competing hypotheses in worktrees; ODC classification. |
| `/report` | `REPORT.md`, `REMEDIATION.md` | Durable write-up plus the caller gate: fix now, or hand off. |
| `/fix` | the fix + regression test | Two-hats gated implementation, red→green, sibling-pattern sweep. |
| `/postmortem` | `docs/rca/<slug>.md` | Committed blameless postmortem and cleanup. |

## Runtime Dependencies

- **tmux** — required by freshen and every hook-based context-clearing flow (forge step transitions, `/issue do`).
- **storyhook** (major 2) — required by forge's story tracking and the test suite.
- **gh CLI**, authenticated — required by issue, reconcile-pr, and deployit's release path.

## Adding a Plugin

1. Create a directory under `plugins/` with a `.claude-plugin/plugin.json` manifest
2. Add skills in `skills/<name>/SKILL.md`, commands in `commands/<name>.md`
3. Add the plugin entry to `.claude-plugin/marketplace.json`
4. Run `/semver bump` — Claude Code caches plugins by version string, so shipped
   content changes are invisible to installs without one

## Testing and the retired global hook

Each repository owns its testing requirements. Agentics does not install a global
push-test hook. Existing Claude and Codex installations can be inspected with
`python3 hooks/retire-pre-push-hook.py`; add `--apply` to back up and remove them.
See [Global hook retirement](docs/global-hook-retirement.md).
