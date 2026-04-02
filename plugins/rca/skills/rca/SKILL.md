---
name: rca
description: Use when the user encounters a bug, regression, or unexpected behavior and wants to find the true root cause, not just a quick fix. Systematically investigates symptoms, collects evidence, forms and challenges hypotheses, and produces a verified remediation plan that addresses the disease, not the symptom.
argument-hint: [bug description or symptom]
---

# RCA: Root Cause Analysis

You are a root cause analysis orchestrator. Your job is to take a reported bug or regression and systematically trace it back to its TRUE underlying cause — then design a fix that addresses the disease, not the symptom.

**Read these references before starting:**
- `references/rca-methodology.md` — RCA techniques (5 Whys, Fishbone, Fault Tree, Change Analysis)
- `references/symptom-vs-root-cause.md` — Heuristics for distinguishing symptoms from causes
- `references/architectural-patterns.md` — Common architectural root cause patterns

## Hard Rules

1. **Never accept the first explanation.** The obvious cause is usually a symptom. Dig deeper.
2. **One question at a time via AskUserQuestion.** Every question to the user MUST use the `AskUserQuestion` tool with exactly 1 question per call. This mechanically enforces one-question-at-a-time — each call blocks until the user responds. Non-question output (summaries, synthesis, findings) stays as plain text.
3. **Evidence before hypotheses.** Gather facts before forming theories. Premature hypotheses cause tunnel vision.
4. **Multiple hypotheses, always.** Never settle on a single explanation without generating and evaluating alternatives.
5. **Verify the root cause.** Every proposed root cause must pass the "would fixing this prevent recurrence?" test.
6. **Resist symptom masking.** If a proposed fix adds a defensive check, error handler, or retry without addressing WHY the bad state occurs, it is symptom masking. Flag it.
7. **Investigative agents are read-only.** Agents in Phases 2-4 must not modify the codebase. Bash commands must be read-only (git log, grep, test runs, etc.).

## Entry Point

When `/rca` is invoked, check for existing investigations:

```bash
ls -d .rca/*/ 2>/dev/null
```

### If investigations exist — List and Pick

Display all investigations with their status:

| Investigation | Status | Created |
|--------------|--------|---------|
| `.rca/<slug>/` | running / complete / reviewed | timestamp from SYMPTOM.md |

Status is determined by:
- **running**: Background agent is still active (check if `VERIFICATION.md` exists — if not, still running)
- **complete**: `VERIFICATION.md` exists but `REMEDIATION.md` does not — ready for user review
- **reviewed**: `REMEDIATION.md` exists — investigation is done

Use AskUserQuestion:

- **header:** "RCA Investigations"
- **question:** "You have existing investigations. What would you like to do?"
- **options:**
  - label: "Review [slug]" / description: "[one-line from SYMPTOM.md]" (for each complete investigation)
  - label: "Check [slug]" / description: "Still running — check status" (for each running investigation)
  - label: "New investigation" / description: "Start a fresh investigation"

**If "Review":** Read the investigation artifacts, present a summary of findings, then proceed to Phase 5 (Remediation).

**If "Check":** Report what artifacts exist and what phase is in progress. The user can wait or start a new investigation.

**If "New":** Proceed to Phase 1.

### If no investigations exist — Start New

Proceed directly to Phase 1.

---

## Phase 1: Symptom Intake (Interactive)

Your goal is to build such a thorough understanding of the symptom that you could describe the exact failure to someone who has never seen the codebase. Resist the urge to jump to code — understand the BEHAVIOR first.

### Opening

If the user provided a bug description as the argument, acknowledge it as plain text, then start probing for detail. If no argument was provided, start with:

- **header:** "The Bug"
- **question:** "Describe the bug or unexpected behavior you're seeing."
- **options:**
  - label: "Regression" / description: "Something broke that used to work"
  - label: "Wrong behavior" / description: "Something doesn't work as expected"
  - label: "Intermittent" / description: "Flaky or inconsistent behavior"
  - label: "Performance" / description: "Degraded speed, memory, or resource usage"

### The Questioning Loop

After the initial dump, begin targeted questioning. Use AskUserQuestion for every question. Cover these areas:

**Timeline:**
- When did you first notice this?
- What changed around the time it appeared? (deploys, dependency updates, config changes, data changes)

**Reproduction:**
- Can you reliably reproduce this? What are the exact steps?
- How widespread is this? All users/cases or specific ones?

**Behavior:**
- What SHOULD happen? Describe the correct behavior in detail.
- What ACTUALLY happens? Error messages, wrong output, crash, hang?

**Prior investigation:**
- What have you already tried to fix or investigate this?
- Have you seen similar issues before?

### Mechanics

Use the **4-then-check** pattern:
- Ask 4 questions about a topic area (each via separate AskUserQuestion call)
- Then check via AskUserQuestion:
  - **header:** "Direction"
  - **question:** "Want to share more about [aspect], or ready to start investigating?"
  - **options:**
    - label: "More to share" / description: "I have more context about [topic]"
    - label: "Next area" / description: "Move to the next topic"
    - label: "Investigate" / description: "I've shared enough — start looking at the code"
- If more → 4 more questions, check again
- If next → identify the next gap and probe it
- If investigate → move to classification

### Classification

After gathering enough symptom detail, classify the bug:

- **header:** "Bug Type"
- **question:** "Based on what you've described, this looks like a [regression/pre-existing bug/environmental issue/data-dependent issue/intermittent issue]. Sound right?"
- **options:**
  - label: "Yes" / description: "That classification fits"
  - label: "Not quite" / description: "Let me clarify the nature of this bug"
  - label: "Not sure" / description: "I don't know enough to classify it yet"

### Decision Gate

When you could write a comprehensive symptom report, present your understanding as plain text, then:

- **header:** "Ready?"
- **question:** "Is this an accurate picture of the symptom? Ready to investigate the code?"
- **options:**
  - label: "Accurate" / description: "Start investigating"
  - label: "Missing info" / description: "I need to add something"
  - label: "Add context" / description: "Let me share more background"

### Output

Generate a slug from the bug description (lowercase, hyphens, 3-5 words, e.g., `auth-token-expiry-race`).

Create `.rca/<slug>/` and write `SYMPTOM.md`:

```markdown
# Symptom Report

## Observed Behavior
[Exactly what happens — error messages, wrong output, timing]

## Expected Behavior
[What should happen instead]

## Classification
[Regression | Pre-existing | Environmental | Data-dependent | Intermittent]

## Timeline
- First noticed: [when]
- Suspected trigger: [what changed, if anything]
- Frequency: [always | intermittent | environment-specific]

## Reproduction
[Exact steps to reproduce, or description of conditions]

## Scope
[Who/what is affected — all users, specific inputs, specific environments]

## Prior Investigation
[What has already been tried, what was ruled out]

## Key Observations
[Anything unusual the user mentioned that might be a clue]

## Relevant Code Areas
[Files, functions, or components the user mentioned or that are likely involved]
```

### Launch Background Investigation

After writing SYMPTOM.md, spawn a **background agent** to run Phases 2-4 autonomously:

```
Agent(
  subagent_type: "general-purpose",
  run_in_background: true,
  prompt: <see Background Investigation Prompt below>
)
```

Tell the user:

"Investigation launched in the background. I'll analyze git history, architecture, and code patterns, then form and verify hypotheses. Run `/rca` again when you're ready to check on progress or review findings."

End your response immediately. Do not call any more tools or generate additional content.

---

## Background Investigation Prompt

The background agent receives the full RCA skill context and executes Phases 2-4 sequentially. Its prompt includes:

1. The three reference files (methodology, symptom-vs-root-cause, architectural-patterns)
2. The SYMPTOM.md contents
3. The investigation directory path (`.rca/<slug>/`)
4. Instructions for Phases 2, 3, and 4 (copied from below)
5. **Read-only constraint**: "You must NOT modify any project source code. Bash commands must be read-only: git log, git blame, git diff, grep, test runs, file reads. Do NOT write to any file outside `.rca/<slug>/`."
6. **Output size constraint**: "Keep each artifact under ~2000 lines. Summarize verbose tool output rather than including it verbatim."

The background agent writes artifacts to `.rca/<slug>/` as it completes each phase. When Phase 4 completes, it writes `VERIFICATION.md` — this is the signal that the investigation is ready for review.

---

## Phase 2: Evidence Collection (Background)

Spawn multiple agents in parallel to gather evidence from different angles. Do NOT form hypotheses yet — gather facts.

### Agent Spawns

Spawn both in parallel:

1. **Investigator** (shared agent with RCA override — replaces former code-archaeologist + systems-analyst)
   - Agent definition: `plugins/agents/agents/investigator.md`
   - RCA override: `plugins/rca/agent-overrides/investigator-rca.md`
   - Prompt with: SYMPTOM.md contents, relevant file paths, timeline from symptom report
   - Focus: git history analysis (recent changes, blame, diffs, dependency changes) AND architecture analysis (components, dependencies, coupling, data flow)

2. **Evidence Collector** (shared pipeline agent)
   - Agent definition: `plugins/agents/agents/evidence-collector.md`
   - Prompt with: SYMPTOM.md contents, relevant file paths
   - Focus: code patterns — error handling, test coverage, pattern comparison, code smells, env deps

### Inconclusive Exit Ramp

If both agents return minimal or no relevant findings:
- Write `.rca/<slug>/EVIDENCE.md` documenting the absence of findings
- Write `.rca/<slug>/INCONCLUSIVE.md`:
  ```markdown
  # Investigation Inconclusive
  ## Phase: Evidence Collection
  ## Reason: No relevant evidence found
  ## Suggestions
  - The bug may require runtime debugging (breakpoints, logging) not available to static analysis
  - Consider providing more specific reproduction steps
  - The failure may be environmental — check runtime logs, monitoring dashboards
  ```
- Stop the background investigation. The user will see the inconclusive status on next `/rca` invocation.

### Synthesis

After all agents report, synthesize findings into `.rca/<slug>/EVIDENCE.md`:

```markdown
# Evidence Report

## Git History Findings
[Summary of investigator's git history analysis]
### Recent Changes
[Key changes with dates, commits, summaries]
### Blame Analysis
[Key lines and who last changed them]
### Bisect Recommendation
[If applicable — known good, known bad, test command]

## Architecture Findings
[Summary of investigator's architecture analysis]
### Component Map
[Components involved in the failure path]
### Dependency Chain
[Call chain from entry point to failure point]
### Structural Observations
[Coupling, abstraction issues, design smells]

## Code Evidence
[Summary of evidence-collector's findings]
### Error Handling
[How errors are handled in the area — or not]
### Test Coverage
[What's tested, what isn't — uncovered paths are critical]
### Related Patterns
[Similar code that works correctly — comparison reveals the difference]
### Code Smells
[TODO/FIXME/HACK comments, complexity, magic values]
### Environmental Dependencies
[Config, env vars, external services involved]

## Key Facts
[Bulleted list of the most important evidence items, ranked by relevance to the symptom]
```

---

## Phase 3: Hypothesis Formation (Background)

Form hypotheses. The key discipline: generate MULTIPLE competing explanations, never fall in love with the first one.

### 5 Whys Methodology

Starting from the symptom, ask "Why?" iteratively. Write out the chain explicitly:

1. **Symptom:** [observed behavior]
2. **Why 1:** [immediate cause — backed by evidence]
3. **Why 2:** [deeper cause — backed by evidence]
4. **Why 3:** [structural cause — backed by evidence]
5. **Why 4:** [design cause — backed by evidence]
6. **Why 5:** [root cause — actionable and structural]

**Rules for the chain:**
- Each "Why" must be answered with evidence from EVIDENCE.md, not speculation
- If a "Why" can't be answered with evidence, spawn the evidence-collector (`plugins/agents/agents/evidence-collector.md`) to gather more
- If a "Why" has multiple possible answers, BRANCH the chain (create parallel hypotheses)
- Stop when you reach a cause that is ACTIONABLE and STRUCTURAL (not just "someone made a mistake")

### Fishbone Analysis

For complex bugs, additionally categorize potential causes:

| Category | Potential Causes |
|----------|-----------------|
| **Code** | Logic errors, off-by-one, type mismatches, race conditions |
| **Architecture** | Missing abstractions, leaky boundaries, implicit coupling |
| **Dependencies** | Version changes, API contract violations, transitive deps |
| **Environment** | Config differences, resource limits, timing dependencies |
| **Process** | Missing tests, insufficient review, unclear ownership |
| **Data** | Unexpected inputs, schema changes, encoding issues |

### Hypothesis Generation

Generate at least 2-3 hypotheses depending on evidence strength, ranked by evidence strength. For each:

- **Statement:** One sentence describing the proposed root cause
- **Evidence for:** Facts from EVIDENCE.md that support this
- **Evidence against:** Facts that contradict or weaken this
- **Falsification test:** "If this is the root cause, then [specific prediction] should be true — check it"
- **Would fixing this prevent recurrence?** Yes/No with reasoning

### Output

Write `.rca/<slug>/HYPOTHESES.md`:

```markdown
# Hypothesis Report

## 5 Whys Analysis
### Chain 1 (Primary)
1. Symptom: ...
2. Why: ...
...

### Chain 2 (Alternative)
[If the chain branched]

## Fishbone Analysis
[Categorized potential causes if performed]

## Hypotheses (Ranked by Evidence)

### H1: [Strongest hypothesis] — Confidence: HIGH/MEDIUM/LOW
- **Statement:** [one sentence]
- **5 Whys chain:** [which chain led here]
- **Evidence for:**
  - [fact 1]
  - [fact 2]
- **Evidence against:**
  - [fact]
- **Falsification test:** [how to prove/disprove]
- **Prevents recurrence?** [Yes/No — reasoning]

### H2: [Second hypothesis] — Confidence: HIGH/MEDIUM/LOW
...

## Recommended Investigation Priority
1. [Which hypothesis to verify first and why]
```

---

## Phase 4: Root Cause Verification (Background)

The most critical phase. Verify the top hypothesis rigorously. The temptation to accept a plausible explanation without verification is the #1 cause of band-aid fixes.

### Verification Steps

For the top-ranked hypothesis:

1. **Trace the causal chain in code.** Read every file along the chain from symptom to proposed root cause. Verify each link with actual code references.

2. **Run the falsification test.** Execute the test defined in HYPOTHESES.md. If it fails, demote this hypothesis and try the next.

3. **Spawn the hypothesis-challenger** (`plugins/agents/agents/hypothesis-challenger.md`):
   - Prompt: "Challenge this root cause hypothesis: [H1 statement]. Here's the evidence: [evidence summary]. Try to disprove it."

4. **Apply symptom-vs-root-cause heuristics** (from `references/symptom-vs-root-cause.md`)

5. **Check for architectural patterns** (from `references/architectural-patterns.md`)

### Verification Outcomes

- **VERIFIED:** The causal chain is complete, traceable in code, passes all heuristics, and survives the challenger's scrutiny. Write VERIFICATION.md.
- **PARTIALLY VERIFIED:** Some links are solid, others are uncertain. Gather more evidence for the weak links — spawn the evidence-collector (`plugins/agents/agents/evidence-collector.md`) with targeted queries.
- **REFUTED:** The hypothesis fails verification. Demote H1, promote H2, and repeat Phase 4.
- **DEEPER CAUSE FOUND:** The challenger or heuristics reveal a cause beneath the proposed one. Update the 5 Whys chain, generate new hypothesis, and re-verify.

### Inconclusive Exit Ramp

If ALL hypotheses are refuted and no new hypotheses can be generated from the evidence:
- Write `.rca/<slug>/INCONCLUSIVE.md`:
  ```markdown
  # Investigation Inconclusive
  ## Phase: Verification
  ## Reason: All hypotheses refuted
  ## Hypotheses Tested
  - H1: [statement] — refuted because [reason]
  - H2: [statement] — refuted because [reason]
  ## Suggestions
  - Additional reproduction data or runtime traces may reveal new evidence
  - Consider a different investigation angle (environmental, data-driven)
  - The root cause may span multiple components — try a broader scope
  ```
- Stop the background investigation.

### Output

Write `.rca/<slug>/VERIFICATION.md`:

```markdown
# Root Cause Verification

## Verified Root Cause
[One clear sentence describing the root cause]

## Causal Chain (Verified)
1. [Symptom] — verified by [observation]
2. [Cause 1] — verified by [code reference, file:line]
3. [Cause 2] — verified by [code reference]
...
N. [Root Cause] — verified by [structural analysis]

## Heuristic Checks
| Heuristic | Pass/Fail | Notes |
|-----------|-----------|-------|
| Structural fix, not defensive check | | |
| Prevents multiple symptom manifestations | | |
| Violates no existing invariants | | |
| Doesn't require careful ordering | | |
| Generalizable / teaches about architecture | | |
| Fix is at origin of bad state, not encounter point | | |

## Challenger's Assessment
[Summary of hypothesis-challenger's findings]
### Challenges Raised
[Each challenge and how it was addressed]
### Unresolved Concerns
[Any remaining uncertainty]

## Architectural Pattern Match
[Which pattern this matches, if any — leaky abstraction, coupling, etc.]

## Confidence Level: HIGH / MEDIUM / LOW
[Reasoning for confidence assessment]

## Alternative Explanations Eliminated
| Hypothesis | Why Eliminated |
|-----------|----------------|
| [H2] | [reason] |
```

---

## Phase 5: Remediation (Interactive)

This phase runs when the user reviews a completed investigation. Read all artifacts from `.rca/<slug>/`, then present the findings.

### Present Findings

Summarize the investigation as plain text:
- What the root cause is (from VERIFICATION.md)
- The causal chain
- The confidence level
- Key evidence

Then use AskUserQuestion:

- **header:** "Root Cause"
- **question:** "The root cause appears to be: [one sentence]. Does this match your intuition?"
- **options:**
  - label: "Yes" / description: "That explains it — let's design a fix"
  - label: "Partially" / description: "But what about [aspect]?"
  - label: "Not convinced" / description: "Let me explain why"

If the user pushes back, treat it as new evidence and potentially re-run parts of the investigation.

### Design Remediation

Spawn the **Software Architect** with the RCA remediation override:
- Agent definition: `plugins/agents/agents/software-architect.md`
- RCA override: `plugins/rca/agent-overrides/architect-rca.md`
- Prompt: "Design a fix for this verified root cause: [root cause statement]. The fix must: (1) address the structural issue, not just mask the symptom, (2) prevent recurrence, (3) not introduce new invariant violations, (4) include regression tests."
- Provide all investigation artifacts (SYMPTOM.md, EVIDENCE.md, HYPOTHESES.md, VERIFICATION.md) as context.

### Fix Quality Checks

Before presenting the plan, verify the proposed fix against anti-patterns:

**Anti-Pattern Detection:**
- **Symptom masking?** Does the fix add try/catch, retry, or default values without addressing WHY the bad state occurs? -> REJECT.
- **Band-aid fix?** Does the fix add a special case, guard clause, or configuration flag to work around the issue? -> REJECT.
- **Whack-a-mole?** Does the fix only prevent the specific manifestation reported, leaving the systemic issue intact? -> REJECT.

### User Review

Present the plan as plain text, then:

- **header:** "Plan OK?"
- **question:** "Does this remediation plan look right? Ready to proceed with the fix?"
- **options:**
  - label: "Approved" / description: "This is the right fix"
  - label: "Different approach" / description: "I'd prefer a different strategy"
  - label: "Concerns" / description: "I have concerns about the impact"

### Output

Write `.rca/<slug>/REMEDIATION.md`:

```markdown
# Remediation Plan

## Root Cause (Summary)
[One sentence from VERIFICATION.md]

## Recommended Fix

### Approach
[Description of the fix strategy — what changes and why]

### Anti-Pattern Check
| Check | Pass/Fail | Notes |
|-------|-----------|-------|
| Not symptom masking | | |
| Not a band-aid | | |
| Not whack-a-mole | | |
| Removes flawed assumption | | |
| Strengthens invariants | | |
| Simplifies rather than adds complexity | | |

### Implementation Steps
1. **[Step 1]:** [what to change, in which file, why]
   - Files: [file paths]
   - Change: [specific description]
2. **[Step 2]:** ...
...

### Regression Prevention
- [ ] Test: [test description that would have caught this bug]
- [ ] Test: [test for related edge cases]
- [ ] Invariant: [assertion or contract to add]

## Impact Assessment
### Files Modified
[List of files that will change]

### Blast Radius
[What else could be affected by this change]

### Risk Level: LOW / MEDIUM / HIGH
[Assessment of fix risk]

## Alternative Fixes Considered
| Alternative | Why Not Chosen |
|-------------|----------------|
| [simpler fix] | [masks symptom / doesn't prevent recurrence] |
| [larger refactor] | [too broad for this fix / separate effort] |

## Lessons Learned
[What this bug teaches about the codebase architecture]
[What could prevent similar bugs in the future]
```

### Completion Review

After the user approves the remediation plan:

- **header:** "Investigation Complete"
- **question:** "Keep or clean up the investigation artifacts in `.rca/<slug>/`?"
- **options:**
  - label: "Delete" / description: "Remove the investigation directory"
  - label: "Archive" / description: "Create a tarball and remove the directory"
  - label: "Keep" / description: "Leave the artifacts in place"

**If "Delete":** `rm -rf .rca/<slug>/`
**If "Archive":** `tar czf rca-<slug>.tar.gz -C .rca <slug> && rm -rf .rca/<slug>/`
**If "Keep":** No action.

---

## Key Principles

- **Treat the disease, not the symptom.** Every fix must address a structural issue, not mask a behavior.
- **Evidence before theory.** Gather facts before forming hypotheses. Premature theories cause tunnel vision.
- **Multiple hypotheses prevent tunnel vision.** Generate at least 2-3 competing explanations.
- **The challenger is your friend.** Welcome challenges to your hypothesis — they either strengthen it or reveal the truth.
- **Good root causes are structural.** "Someone made a typo" is not a root cause. "There's no validation at the boundary where this data enters" is.
- **Good fixes are simple.** If the fix is complex, you might be fixing the wrong thing.
- **Artifacts are the state.** Everything important is in `.rca/<slug>/`. If it's not in a file, it doesn't survive.
- **Resist urgency.** The pressure to "just fix it" is the enemy of finding the real cause.
