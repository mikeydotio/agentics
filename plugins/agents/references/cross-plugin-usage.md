# Cross-Plugin Usage Guide

How consuming plugins (pilot, rca, future plugins) reference and use shared agents from the `agents` plugin.

## File Path Convention

Shared agents live at `plugins/agents/agents/<name>.md`. Consuming plugins reference them by path from the repository root:

```
plugins/agents/agents/software-architect.md
plugins/agents/agents/generator.md
plugins/agents/agents/evaluator.md
```

## Spawning Pattern

The spawning mechanism is unchanged from the current pattern. The orchestrator (SKILL.md) reads the agent definition and inlines it into the prompt:

```
# In a SKILL.md orchestrator:

1. Read the shared agent definition:
   Read plugins/agents/agents/generator.md

2. Read any pipeline-specific override (if applicable):
   Read plugins/pilot/agent-overrides/generator-context.md

3. Construct the prompt:
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

## Pipeline-Specific Overrides

When a shared agent needs context specific to a pipeline, the consuming plugin maintains override snippets:

```
plugins/pilot/agent-overrides/
├── generator-context.md      # Pilot-specific generator constraints
├── evaluator-context.md      # Pilot-specific evaluation rules
├── reviewer-context.md       # Pilot review step context
└── ...

plugins/rca/agent-overrides/
├── evidence-collector-context.md   # RCA evidence gathering scope
├── hypothesis-challenger-context.md # RCA challenge methodology additions
├── investigator-rca.md             # General investigator with RCA context
└── architect-rca.md                # General architect with remediation focus
```

### Override Layering

The prompt is constructed by concatenation:

1. **Shared agent definition** — the full `<role>` block from `plugins/agents/agents/<name>.md`
2. **Pipeline override** — additional constraints/context from `plugins/<pipeline>/agent-overrides/<name>-context.md`
3. **Dynamic context** — story criteria, design sections, prior feedback, file lists

This is transparent concatenation, not an inheritance system. The override adds to the agent's instructions; it doesn't replace them.

### Override Content Guidelines

Overrides should contain ONLY pipeline-specific information:

**Good override content:**
- "Never modify `.pilot/` files — state files are managed by the orchestrator"
- "Your output will be stored as a storyhook comment — keep JSON under 4KB"
- "This is Phase 2 of an RCA investigation — SYMPTOM.md has been read by the orchestrator"

**Bad override content (belongs in the shared agent):**
- General methodology (TDD protocol, OWASP checklist)
- Output format specifications
- Guardrails and constraints
- Tool restrictions

## Namespace Convention

The `<plugin>:<agent>` notation maps to file paths:

| Notation | File Path |
|----------|-----------|
| `agents:software-architect` | `plugins/agents/agents/software-architect.md` |
| `agents:generator` | `plugins/agents/agents/generator.md` |
| `agents:ux-designer-cli` | `plugins/agents/agents/ux-designer-cli.md` |

This is a documentation convention. The orchestrator in each SKILL.md is responsible for translating to the actual file path.

## Using General-Purpose Agents in Pipelines

General-purpose agents (software-architect, investigator, etc.) can be used in any pipeline with appropriate overrides:

### Example: Software Architect in RCA

The RCA pipeline uses the shared software-architect for remediation design:

```
Read plugins/agents/agents/software-architect.md
Read plugins/rca/agent-overrides/architect-rca.md

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
Read plugins/agents/agents/investigator.md
Read plugins/rca/agent-overrides/investigator-rca.md

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

1. [ ] Replace `agents/<name>.md` references with `plugins/agents/agents/<name>.md`
2. [ ] Extract pipeline-specific instructions into `agent-overrides/<name>-context.md`
3. [ ] Update any hardcoded agent file paths in reference docs
4. [ ] Verify prompt construction includes both shared definition + override
5. [ ] Test with a dry run to confirm agents load correctly
6. [ ] Delete the old `agents/` directory from the consuming plugin
