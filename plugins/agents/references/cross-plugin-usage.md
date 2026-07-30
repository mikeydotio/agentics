# Cross-Plugin Usage Guide

How consuming plugins (forge, rca, future plugins) reference and use shared agents from the `agents` plugin.

## File Path Convention (F084)

Shared agents live at `plugins/agents/agents/<name>.md`. **Do not reference them by a bare
path from the repository root** (`plugins/agents/agents/software-architect.md`) — a consuming
plugin's SKILL.md runs with the *target project* as cwd (not this marketplace checkout), so a
repo-root-relative path resolves to nothing there. `${CLAUDE_PLUGIN_ROOT}` doesn't fix this either:
inside a consuming plugin (e.g. forge) it resolves to *that plugin's own root*
(`.../plugins/forge`), never to the sibling `agents` plugin.

The portable resolution is to derive the `agents` plugin's root as a **sibling** of the consuming
plugin's own root — every plugin in this marketplace is installed as a sibling directory under the
same parent (see the root `CLAUDE.md`'s "Plugin pattern"):

```bash
AGENTS_PLUGIN_ROOT="$(cd "$(dirname "${CLAUDE_PLUGIN_ROOT}")/agents" && pwd)"
```

Then reference shared files as `"$AGENTS_PLUGIN_ROOT/agents/<name>.md"` and the consuming plugin's
own override as `"${CLAUDE_PLUGIN_ROOT}/agent-overrides/<name>-context.md"` — never a bare
`plugins/agents/agents/<name>.md`. If `$AGENTS_PLUGIN_ROOT` doesn't resolve (the `agents` plugin
isn't installed alongside), treat the shared definition as unavailable: spawn `general-purpose`
with only the override + dynamic context, and say plainly in the handoff that the agent ran
without its shared role definition — don't silently proceed as if nothing were missing.

## Spawning Pattern

Determine `subagent_type` before constructing the prompt — don't default to `general-purpose`
out of habit, since that makes every agent's `tools:`/`read_only:` frontmatter purely cosmetic
(the platform grants `general-purpose` the full tool set regardless of what the `.md` says).
This is the same resolution order used by `/council-vote`
(`plugins/council/skills/council-vote/SKILL.md`, "Dispatching members"):

1. **Preferred:** if `agents:<name>` appears in the available subagent types (in Claude Code,
   the agent-types system reminder), spawn with `subagent_type: "agents:<name>"` directly. The
   platform then applies that agent's own `tools:` allowlist, `read_only`, `model:`, and
   `effort:` frontmatter — no inlining needed for the role definition itself (the
   pipeline-specific override and dynamic context are still concatenated into the prompt, see
   below).
2. **Fallback:** if no `agents:*` types are exposed, spawn `subagent_type: "general-purpose"` and
   inline the full role definition into the prompt (steps below) — this is the only case where
   the shared `.md` needs to be read and pasted in, and the *only* enforcement is whatever the
   prompt asks for (i.e., not real enforcement — note this in any place that claims otherwise).
   The agent's `model:` and `effort:` tiering is lost on this path too: the subagent runs on the
   session's model at the session's effort, so a fallback spawn of a `haiku`/`low` agent costs
   what the session costs, and a fallback spawn of an `xhigh` agent reasons only as hard as the
   session does.
3. **Don't guess.** If you can't tell what's available, try `agents:<name>` once; if it errors,
   retry with `general-purpose` + injected role. Record which path was taken (e.g. in the step's
   handoff) so it's auditable which enforcement level actually applied.

When falling back to `general-purpose`, the orchestrator (SKILL.md) reads the agent definition
and inlines it into the prompt:

```
# In a SKILL.md orchestrator, general-purpose fallback path:

1. Resolve the shared agents plugin root (see File Path Convention above):
   AGENTS_PLUGIN_ROOT="$(cd "$(dirname "${CLAUDE_PLUGIN_ROOT}")/agents" && pwd)"

2. Read the shared agent definition:
   Read "$AGENTS_PLUGIN_ROOT/agents/generator.md"

3. Read any pipeline-specific override (if applicable):
   Read "${CLAUDE_PLUGIN_ROOT}/agent-overrides/generator-context.md"

4. Construct the prompt:
   Agent(
     subagent_type: "general-purpose",
     prompt: <
       [shared agent definition contents]
       [pipeline-specific override contents]
       [dynamic context: story, criteria, design section, prior feedback]
       [<files_to_read> block with relevant files]
     >
   )
```

When the preferred `agents:<name>` type is used instead, the prompt still needs the
pipeline-specific override + dynamic context (steps 3-4 above) — only step 2's inlining of the
shared definition is skipped, since the registered agent type already carries it.

## Pipeline-Specific Overrides

When a shared agent needs context specific to a pipeline, the consuming plugin maintains override snippets:

```
plugins/forge/agent-overrides/
├── generator-context.md      # Forge-specific generator constraints
├── evaluator-context.md      # Forge-specific evaluation rules
├── reviewer-context.md       # Forge review step context
└── ...

plugins/rca/agent-overrides/
├── qa-engineer-context.md          # RCA reproduce-first: minimal failing test for the defect
├── investigator-context.md         # RCA git-forensics grounding + infection-chain tracing
├── evidence-collector-context.md   # RCA evidence gathering scope
├── hypothesis-challenger-context.md # RCA adversarial challenge methodology additions
├── experimenter-context.md         # RCA falsification experiments in a disposable worktree
├── software-architect-context.md   # RCA remediation design, surgical-vs-redesign verdict
├── software-engineer-context.md    # RCA surgical fix implementation
└── technical-writer-context.md     # RCA report / postmortem authoring
```

Every override follows the `<name>-context.md` rule (the `<name>` is the shared agent's `name:`,
e.g. `software-architect-context.md`, never `architect-rca.md`) so the orchestrator can resolve
it mechanically alongside the shared definition — see "Override Layering" and "Namespace
Convention" below.

### Override Layering

The prompt is constructed by concatenation:

1. **Shared agent definition** — the full `<role>` block from `plugins/agents/agents/<name>.md`
2. **Pipeline override** — additional constraints/context from `plugins/<pipeline>/agent-overrides/<name>-context.md`
3. **Dynamic context** — story criteria, design sections, prior feedback, file lists

This is transparent concatenation, not an inheritance system. The override adds to the agent's instructions; it doesn't replace them.

### Override Content Guidelines

Overrides should contain ONLY pipeline-specific information:

**Good override content:**
- "Never modify `.forge/` files — state files are managed by the orchestrator"
- "Your output will be stored as a storyhook comment — keep JSON under 4KB"
- "This is Phase 2 of an RCA investigation — SYMPTOM.md has been read by the orchestrator"

**Bad override content (belongs in the shared agent):**
- General methodology (TDD protocol, OWASP checklist)
- Output format specifications
- Guardrails and constraints
- Tool restrictions

An override that repeats something the agent definition already says is worse than one that
omits it. The override is concatenated *after* the definition, so a restatement lands as a
second, slightly-differently-worded copy of a rule the agent has already read — and the model
spends reasoning reconciling the two before it starts on the actual work. If you find yourself
copying a line out of `plugins/agents/agents/<name>.md`, delete it from the override instead.

## Namespace Convention

The `<plugin>:<agent>` notation maps to files, resolved as described above (never a bare
repo-root-relative path):

| Notation | Resolves to |
|----------|-------------|
| `agents:software-architect` | `subagent_type: "agents:software-architect"` if exposed (preferred), else `$AGENTS_PLUGIN_ROOT/agents/software-architect.md` inlined under `general-purpose` |
| `agents:generator` | `subagent_type: "agents:generator"` if exposed (preferred), else `$AGENTS_PLUGIN_ROOT/agents/generator.md` inlined under `general-purpose` |
| `agents:ux-designer-cli` | `subagent_type: "agents:ux-designer-cli"` if exposed (preferred), else `$AGENTS_PLUGIN_ROOT/agents/ux-designer-cli.md` inlined under `general-purpose` |

The orchestrator in each SKILL.md is responsible for running the Preferred/Fallback/Don't-guess
resolution above — this table is shorthand for that resolution, not a shortcut around it.

## Using General-Purpose Agents in Pipelines

General-purpose agents (software-architect, investigator, etc.) can be used in any pipeline with appropriate overrides. These examples show the `general-purpose` fallback path in full; try the
preferred `agents:<name>` type first per "Spawning Pattern" above.

### Example: Software Architect in RCA

The RCA pipeline uses the shared software-architect for remediation design:

```
AGENTS_PLUGIN_ROOT="$(cd "$(dirname "${CLAUDE_PLUGIN_ROOT}")/agents" && pwd)"
Read "$AGENTS_PLUGIN_ROOT/agents/software-architect.md"
Read "${CLAUDE_PLUGIN_ROOT}/agent-overrides/software-architect-context.md"

Agent(
  subagent_type: "general-purpose",
  prompt: <
    [software-architect definition]
    [RCA override: focus on remediation design, structural fixes,
     blast radius assessment, regression prevention]
    [dynamic: EVIDENCE.md, HYPOTHESES.md, verified root cause]
  >
)
```

### Example: Investigator in RCA

The RCA pipeline uses the shared investigator (which absorbed code-archaeologist + systems-analyst capabilities):

```
AGENTS_PLUGIN_ROOT="$(cd "$(dirname "${CLAUDE_PLUGIN_ROOT}")/agents" && pwd)"
Read "$AGENTS_PLUGIN_ROOT/agents/investigator.md"
Read "${CLAUDE_PLUGIN_ROOT}/agent-overrides/investigator-context.md"

Agent(
  subagent_type: "general-purpose",
  prompt: <
    [investigator definition]
    [RCA override: focus on git history analysis, architecture/coupling
     analysis, evidence dimensions specific to RCA Phase 2]
    [dynamic: SYMPTOM.md, failure area files]
  >
)
```

## Migration Checklist

When updating a consuming plugin to use shared agents:

1. [ ] Replace `agents/<name>.md` references with the resolved-path convention above
   (`$AGENTS_PLUGIN_ROOT/agents/<name>.md`, never a bare `plugins/agents/agents/<name>.md`)
2. [ ] Extract pipeline-specific instructions into `agent-overrides/<name>-context.md`
3. [ ] Update any hardcoded agent file paths in reference docs
4. [ ] Verify prompt construction includes both shared definition + override
5. [ ] Test with a dry run to confirm agents load correctly
6. [ ] Delete the old `agents/` directory from the consuming plugin
