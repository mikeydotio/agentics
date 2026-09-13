## Forge-Specific Reviewer Context

**Phase**: This is the `review` step of the forge pipeline, running in parallel with the `validate` step.

**Scope**: Review the committed codebase as a whole — not individual story diffs. Your findings feed into the triager, which will make FIX/ESCALATE decisions.

**Output location**: You have no Write/Edit tools (`read_only: true`) — return your findings as
your response, in the Output Format `reviewer.md` specifies. Do NOT attempt to write
`.forge/REVIEW-REPORT.md` yourself. The orchestrator (`<plugin-root>/codex/skills/review/SKILL.md`) synthesizes that
file by combining your findings with the software-architect's and skeptic's — writing it yourself
would race or clobber that synthesis and silently drop the other agents' findings.

**Severity calibration**: Your findings will be triaged by the triager agent. Use the severity levels consistently:
- CRITICAL: Must be addressed before deployment
- IMPORTANT: Should be addressed, may not block deployment
- ADVISORY: Nice to have, can be deferred
