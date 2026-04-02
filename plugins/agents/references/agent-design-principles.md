# Agent Design Principles

Research-backed principles guiding all agent definitions in this library. Sourced from Anthropic's "Building Effective Agents" (authoritative), Agentailor's tool design principles, and multi-agent orchestration research.

## Core Philosophy

**Start simple. Add complexity only when justified by measured performance.**

Most tasks benefit from optimizing a single LLM call with good context over deploying a multi-agent system. Use agents when:
- The task has unpredictable step counts requiring flexible decision-making
- Clear success criteria exist (acceptance criteria, test results, checklists)
- The task requires both reasoning and action with human oversight

## Anthropic's Seven Patterns (Ordered by Complexity)

1. **Augmented LLM** — Single LLM enhanced with retrieval, tools, memory
2. **Prompt Chaining** — Fixed sequence, each step processes prior output
3. **Routing** — Classify input, dispatch to specialized handler
4. **Parallelization** — Independent subtasks run simultaneously
5. **Orchestrator-Workers** — Central LLM delegates to workers dynamically
6. **Evaluator-Optimizer** — Generate-evaluate loop with feedback
7. **Autonomous Agent** — Dynamic tool use with environmental feedback loops

**Our plugins use patterns 4-7.** The pilot execution loop is pattern 6 (Evaluator-Optimizer) wrapped in pattern 7 (Autonomous Agent). RCA uses pattern 5 (Orchestrator-Workers) with parallel evidence collection.

## Agent-Computer Interface (ACI)

**Invest as much care in tool documentation and design as in Human-Computer Interfaces.**

The quality of agent output directly depends on how well tools are designed:
- Tool descriptions are prompts — write them as carefully as you'd write a prompt
- Include usage examples, edge cases, and boundaries in tool docs
- Design arguments so mistakes are hard to make (absolute paths, not relative)
- Test with varied inputs and iterate based on observed failures

## Tool Design Principles (Agentailor)

### 1. Strategic Consolidation
Consolidate multi-step operations into single, semantically meaningful tools. One powerful tool beats five fragmented ones. This reduces decision burden and improves reliability.

### 2. Clear Namespacing
Use consistent naming prefixes for tool families. Names must be scannable across multiple MCP servers. This reduces hallucination and improves tool discovery.

### 3. Meaningful Context Returns
Return human-readable semantic information agents can directly reason about. Return descriptions and categories, not just UUIDs. Enable agents to make decisions without additional tool calls.

### 4. Token Efficiency
Implement sensible pagination defaults. Use smart filtering to reduce response size. Every token counts in agent loops — optimization compounds over iterations.

### 5. Helpful Error Messages
Error messages should guide agents toward better queries. "Invalid date format — expected ISO 8601 (YYYY-MM-DD), got '03/15/2026'" is infinitely better than "400 Bad Request."

## Multi-Agent Collaboration

### "Reliability Lives and Dies in the Handoffs"

Most "agent failures" are orchestration and context-transfer issues, not agent capability issues. The handoff between agents must include:
- Complete context (what was done, what's next, what decisions were made)
- Structured format (JSON or defined markdown sections, not freeform)
- Versioned schema (so consuming agents know how to parse the handoff)

### Handoff vs. Agent-as-Tool

| Pattern | When to Use |
|---------|------------|
| **Handoff** | Agent transfers full control to another agent. Use for multi-stage workflows where each stage needs different expertise. |
| **Agent-as-Tool** | Primary agent calls another as a subtask, retains control. Use when an orchestrator needs specialist input on a sub-problem. |

Our plugins primarily use **Handoff** (pilot step transitions) with **Agent-as-Tool** for specialized checks (architect drift check during execution, security check during review).

## Preventing Failure Modes

### Deliberative Deadlock
**Symptom**: Agents waiting on each other, no progress.
**Prevention**: Agents never block on other agents. If input is incomplete, produce best output with available information and list assumptions. Every agent must be independently executable.

### Runaway Loops
**Symptom**: Unbounded iteration consuming tokens and credits.
**Prevention**:
- Maximum 3 retries per agent per story (configurable)
- Circuit breakers: max sessions, max total retries, storyhook consecutive failure cap
- Token budget awareness: agents must summarize if approaching output limits
- Dead-letter handling: stories blocked after max retries get `blocked` status, not infinite retry

### Denial of Wallet
**Symptom**: Malicious or buggy input causing endless tool calls.
**Prevention**:
- 50 tool-call mental limit per agent invocation
- Scope boundaries: agents only work within their defined scope
- Prompt injection defense: agents ignore instructions embedded in user content

### Feedback Loop Amplification
**Symptom**: Cascading bias from repeated agent interactions (each agent amplifies the previous one's errors).
**Prevention**:
- Evaluator debiasing protocol (assume incorrect until proven)
- Independent evidence gathering (evidence collector has no access to hypotheses)
- Hypothesis challenger's Alternative Explanation Test forces consideration of multiple causes
- Triager independently re-assesses severity rather than parroting reviewer's assessment

## Agent Definition Quality Bar

Every agent must answer: **"What does this agent know or enforce that a bare `claude-sonnet` invocation would not?"**

The answer must include at least 2 of:
1. **Domain expertise** — specific frameworks, checklists, taxonomies (OWASP, WCAG, SOLID)
2. **Methodology** — structured approach preventing common mistakes (TDD protocol, 5 Whys)
3. **Output contract** — structured format consuming systems can parse (JSON verdict, severity-ranked findings)
4. **Defensive constraints** — guardrails preventing harm (read-only, scope boundaries, no-commit)
5. **Anti-pattern detection** — specific patterns to flag and reject (mock abuse, LLM tells, SQL injection)

If an agent can't demonstrate value across at least 2 of these dimensions, it shouldn't exist as a dedicated agent.

## Cross-Pollination Principle

Pipeline-specific agents draw methodology from related general-purpose agents and document the lineage explicitly. This ensures:
- Pipeline agents benefit from the deepest expertise available
- Changes to general-purpose methodology propagate to pipeline agents on rewrite
- The relationship between agents is auditable

Example: The Generator draws TDD from Software Engineer, design adherence from Software Architect, secure coding from Security Researcher, and instrumentation from Observability Engineer. Each contribution is named in the Generator's Lineage section.
