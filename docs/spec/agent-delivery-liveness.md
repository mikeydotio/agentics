# Agent delivery liveness — AGE-104

The approved plan is recorded on AGE-104. This specification covers Agents, Forge and
RCA after the Forge Codex merge f3129c8. Council voting and AGE-77 permission enforcement
remain separate.

## Origin and competing explanations

Hypothesis A: workers finish correctly but transport/identity loses results. Hypothesis B:
the owner has no durable pending record or finite deadline, so any absent result wedges it.
Both are reachable: original Agents Codex step 4 and RCA runtime only call wait_agent;
Forge explicitly requires foreground calls. Changing worker prompts alone cannot make a
silent worker resolve. The fix therefore puts deadline arithmetic and identity acceptance
in a production helper, with owner-side entry/exit guards. Native API behavior is an
external boundary, not emulated by a second policy implementation.

## Dispatch inventory

| Owner | Supported entrypoints | Delivery ownership |
|---|---|---|
| Agents | Codex run; shared cross-plugin examples | One role task, canonical writer classification |
| Forge | Claude/Codex research, design, plan, decompose, execute, review, validate, triage, document and router combined dispatch | Readers in fixed waves; generators/validators/research writers isolated |
| RCA | Claude/Codex reproduce, locate, diagnose (evidence, experiment, challenge), report, fix, postmortem; standalone entry | Keep each original gate and independent challenge |
| Workflow/Agent terminology | No separate Workflow plugin found; examples in cross-plugin usage | Same owner helper, never an independent unlimited wait |

## Failure inventory

| Failure | Evidence/classification | Required handling |
|---|---|---|
| Silence, idle without result, lost result | Reachable at original wait sites | Probe once, bounded reader retry, terminal failure |
| Stale requested name or duplicate | Observed Council precedent; reachable here | Actual ID plus batch/task/digest/attempt validation |
| Dead/denied/unavailable worker | Reachable | Visible failure; no permission/capability retry |
| Writer partial changes | Reachable | Preserve changes, no replay, incomplete handoff |
| Crash before dispatch / during native send / after acceptance | Reachable | Durable queued/prepared/attempted/pending/accepted distinction |
| Corrupt state, lock contention, persistence error | Reachable | Fail closed, preserve contextual diagnostics |
| Cleanup cannot stop worker | Reachable | 30 seconds total, durable survivors, block fresh work |
| Wall clock discontinuity / different owner | Reachable | Interrupted outcome, no renewed deadline |
| Partial report resembles complete artifact | Reachable in Forge/RCA artifact ladders | Delivery guard takes precedence |
| Host itself dead | External limitation | Recovery evidence; no claim of unattended timer execution |

## Implementation contract

The complete command/event, envelope, budget and recovery contract is shipped in each
plugin's references/delivery.md. Canonical modules and reference are owned by Agents;
scripts/sync-agent-delivery.py packages identical consumer copies and checks drift.
Task identity is random per batch/attempt plus SHA-256 of exact task text. Runtime records
are local ignored state; failure summaries belong in existing handoffs.

Budgets: ordinary readers 900+300+300 seconds; Forge evaluator/reviewer/triager
600+120+120; all writers 1800+300+0. Waves serialize writers and fix reader capacity.
Each task ceiling and sum-of-wave batch ceiling precedes dispatch. Stop/probe allowance
is inside existing ceilings; terminal cleanup alone adds at most 30 seconds.
Monotonic time owns arithmetic; UTC timestamps aid inspection. These defaults are
operational limits, not measured percentiles.

Failure/recovery must not consume a Forge evaluator retry or satisfy an RCA gate.
Explicit reconciliation preserves terminal evidence and requires confirmed shutdown,
integrity checks, and owner review of partial artifacts. A missing legacy record is
unknown, not proof of no dispatch. New runs cannot automatically replace failed ones.

## Validation and limits

Tests invoke the production state/persistence/guard APIs and CLI. Controlled clocks and
external messages exercise the successful baseline, silence, precise deadline boundaries,
correlation, waves, crash/recovery, write failure, corruption and cleanup. Owner tests
use real repositories and artifacts with only native transport/time controlled.
Negative controls disable deadline, identity, persistence and guard behavior and must fail.
Installed-package checks run local helper copies without sibling imports.

The first test import failed because the production helper did not exist. This proves
the new interface is absent, not a live worker wedge; successful production baselines
and fault arms must pass after implementation. Static instruction contracts and executable
policy evidence are not proof of model compliance. Native transport smoke limitations
must be reported explicitly. No full repository suite or release operation is part of
this worktree's validation.

