---
name: deploy
description: Deployment step. Never proceeds without explicit user permission via DEPLOY-APPROVAL.md. Produces COMPLETION.md.
---

Resolve `<plugin-root>` three directories above this loaded file's containing directory.
Read `<plugin-root>/codex/references/runtime.md` before this step.

# Deploy: Ship It

You are the deploy skill. Your job is to deploy the project according to its deployment needs. **You never run without explicit user permission** — the orchestrator writes `DEPLOY-APPROVAL.md` only after the user approves.

**Read inputs:**
- `.forge/DEPLOY-APPROVAL.md` (required — must exist before deploy runs)
- `.forge/DOCUMENTATION.md` (for deployment docs)
- `.forge/DESIGN.md` (for infrastructure context)
- `.forge/IDEA.md` (for deployment requirements)
- `.forge/handoffs/handoff-document.md` (for context)

## Safety Gate

**CRITICAL:** If `.forge/DEPLOY-APPROVAL.md` does not exist, do NOT proceed. Exit with:
"Deploy requires explicit approval. Run `$forge:forge continue` after the post-document pause to approve deployment."

## Steps

### 1. Assess Deployment Needs

Read IDEA.md and DESIGN.md to determine what deployment means for this project:

- **Web application**: Deploy to hosting platform (Vercel, Railway, AWS, etc.)
- **CLI tool**: Publish to package registry (npm, PyPI, crates.io)
- **Library**: Publish package, update docs
- **Infrastructure**: Apply terraform/CDK/ansible changes
- **Internal tool**: Copy to target location, restart services
- **No deployment needed**: Some projects just need to be built and tested

### 2. Present Deployment Plan

Use the native question tool to confirm the deployment approach:
- **header:** "Deploy Plan"
- **question:** "Here's what I'll do to deploy: [plan]. Proceed?"
- **options:**
  - "Go ahead (Recommended)" / "Execute the deployment plan. Pros: ships the project. Cons: rollback may be needed if issues surface post-deploy."
  - "Adjust the plan" / "I want changes to the deployment approach. Pros: catches deployment risks. Cons: delays shipping."
  - "Cancel deployment" / "Skip deployment entirely. Pros: no deployment risk. Cons: project remains unshipped."

If "Cancel" → write COMPLETION.md without deployment, mark as complete.

### 3. Execute Deployment

Follow the deployment plan. Be conservative:
- Run pre-deployment checks (tests, build, lint)
- Execute deployment steps
- Verify deployment succeeded (health checks, smoke tests)
- Report results

### 4. Write COMPLETION.md

Write `.forge/COMPLETION.md`:

```markdown
# Pipeline Complete

## Timestamp
[ISO 8601]

## Project
[Project name from IDEA.md]

## Pipeline Summary
- Steps completed: [list]
- Fix cycles: [count]
- ESCALATE stories resolved: [count]
- Deployment: [deployed to X / not deployed / skipped]

## What Was Built
[Brief description of what the project does]

## Key Metrics
- Stories completed: [count]
- Tests: [pass/fail/total]
- Documentation: [files created]

## Deviations from Original Idea
[Any significant changes from IDEA.md requirements]

## Known Issues
[ESCALATE items that were resolved, any remaining concerns]

## Post-Deployment Notes
[Any manual steps, monitoring to set up, follow-up tasks]
```

## Exit

**If `--orchestrated`:**
1. Write `.forge/COMPLETION.md`
2. Deploy is the pipeline's one terminal step exit — `--terminal` commits and cancels any pending
   freshen signal instead of queueing a next command (there is no next step):
   ```bash
   bash "<plugin-root>/bin/forge-step-exit.sh" --host codex --step deploy \
     --summary "pipeline complete" --terminal
   ```
3. Report completion to user — this is the end of the pipeline

**If standalone:** Same as orchestrated — deploy is always the final step.
