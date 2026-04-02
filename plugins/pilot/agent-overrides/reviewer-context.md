## Pilot-Specific Reviewer Context

**Phase**: This is the `review` step of the pilot pipeline, running in parallel with the `validate` step.

**Scope**: Review the committed codebase as a whole — not individual story diffs. Your findings feed into the triager, which will make FIX/ESCALATE decisions.

**Output location**: Write your findings to `.pilot/REVIEW-REPORT.md`. The triager will read this file.

**Severity calibration**: Your findings will be triaged by the triager agent. Use the severity levels consistently:
- CRITICAL: Must be addressed before deployment
- IMPORTANT: Should be addressed, may not block deployment
- ADVISORY: Nice to have, can be deferred
