# Report Format

Standard structure for review and validation report findings. Both reports use the same format so triage can process them uniformly.

## Finding Structure

Every finding in REVIEW-REPORT.md and VALIDATE-REPORT.md must follow this structure:

```markdown
### [Finding Title]
- **Severity**: Critical | Important | Useful
- **Description**: [what's wrong or could be better]
- **Location**: [file:line or component — be specific]
- **Option 1 (Recommended)**: [solution] — Pros: ... Cons: ...
- **Option 2**: [solution] — Pros: ... Cons: ...
- **Option 3**: [solution] — Pros: ... Cons: ...
```

### Required Fields

- **Title**: Short, descriptive, unique within the report
- **Severity**: One of: Critical, Important, Useful (see `references/severity-levels.md`)
- **Description**: What's wrong, why it matters, who it affects
- **Location**: File path and line number where possible. For systemic issues, name the component or pattern.
- **Options**: At least 2 solution options, each with pros and cons. Mark one as recommended.

### Option Format

Each option should include:
- A concrete solution (not just "fix it")
- Pros: what this approach gets right
- Cons: trade-offs, risks, or downsides

The recommended option should be the one the agent would choose if they had to decide. But the triage team makes the final call.

## Report Structure

Both reports share this skeleton:

```markdown
# [Review/Validation] Report

## Summary
[2-3 sentence overall assessment]

## Findings

### [Finding 1]
[Finding structure as above]

### [Finding 2]
...

## Strengths
[What's working well — patterns to reinforce]
```

Review adds: `## Design Alignment` and `## Story Hygiene`
Validation adds: `## Test Suite Results`, `## Requirement Coverage`, and `## Tests Written`

## Deduplication

When multiple agents flag the same issue:
1. Merge into a single finding
2. Use the highest severity from any agent
3. Combine solution options from all agents
4. Note which agents flagged it (builds confidence in the finding)

## What NOT to Report

- Style preferences without functional impact
- Theoretical risks without practical attack paths or failure scenarios
- Issues in code that isn't part of the current project scope
- "Nice to have" improvements to third-party dependencies
- Findings that are already documented as accepted trade-offs in DESIGN.md
