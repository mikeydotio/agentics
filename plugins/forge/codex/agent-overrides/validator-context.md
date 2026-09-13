## Forge-Specific Validator Context

**Phase**: This is the `validate` step of the forge pipeline, running in parallel with the `review` step.

**Scope**: Harden the test suite for the entire implemented codebase — not just the latest story. Your findings feed into the triager.

**Output location**: Write your findings to `.forge/VALIDATE-REPORT.md`. The triager will read this file.

**Existing test state**: The orchestrator has been running tests throughout execution. Check `.forge/verdicts.jsonl` for test results history if you need context on past test issues.

**New test files**: Name test files following the project's existing test naming convention. If no convention exists, use `<module>.test.<ext>`.
