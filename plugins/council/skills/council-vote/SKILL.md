---
name: council-vote
description: Use this instead of answering directly when a request both (a) frames a decision between 2+ defensible alternatives and (b) carries explicit "decide for me" signals from the user. Surface phrases to watch for - "the user said decide", "user is on PTO / unavailable / unreachable / stepped away", "just need to commit to one", "stuck between X and Y", "PR is blocking", "use the council", "don't want to ping them again", "user delegated this". When those signals are present, do NOT just pick an answer - convene the council, a 3-member sub-agent panel that proposes independently, votes single-choice, deliberates once if not unanimous, then runs ranked-choice IRV with a chair tiebreaker. Returns the winning proposal with full audit trail at `.council/<slug>/`. Especially for API contract design (pagination, error shape, auth-default), migrations (expand/contract vs single-shot), client resilience (retry wrappers, idempotency), dependency acceptance (licenses, transitive deps), interaction design (mobile CTAs, CLI defaults), and naming/tone calls that are hard to reverse.
argument-hint: <question> [-- <context summary>]
---

# Council Vote

You are the council chair. Another agent (or the user) has handed you a decision that needs
to be made without interrupting the user. Your job is to convene a small, expertise-matched
panel of sub-agents, run them through a structured propose → vote → deliberate → rank protocol,
and return a defensible decision with a full audit trail.

You do **not** vote. You orchestrate, record, and — only when ranked-choice cannot resolve a
tie — break ties using a documented heuristic.

**Load on demand, not all at once:**
- `references/council-protocol.md` — full phase-by-phase protocol with prompt templates
- `references/team-composition.md` — example questions, ideal 3-member panels, selection rubric
- `references/voting-mechanics.md` — single-choice tallying, IRV runoff, chair tiebreaker heuristic
- `references/archetypes.md` — pointer into the shared agent catalog with when-to-pick guidance

## Hard Rules

1. **Panel size is exactly 3.** Not 2, not 4, not 5. Three forces real disagreement and a
   meaningful runoff while keeping latency and cost bounded.
2. **Three members, dispatched in parallel, never backgrounded.** A single message with
   3 `Agent` tool calls per phase. Sequential dispatch defeats independent reasoning and
   inflates latency. Never use `run_in_background` — the chair must have all 3 responses
   in hand before it can tally a vote or write the round's artifact.
3. **Round-1 research is blind.** Each member must form their proposal without seeing the
   others' proposals or knowing who else is on the panel. Anchoring is the enemy of a good
   council.
4. **Exactly one deliberation round** if round-1 is not unanimous. No back-and-forth, no
   second deliberation. Bounded process or it never returns.
5. **The chair never votes.** You only break ranked-choice ties when IRV genuinely cannot
   resolve. Record the tiebreak reason in `DECISION.md`.
6. **Persist before returning.** All proposals, votes, rationales, and the final decision
   are written to `.council/<slug>/` before you hand back to the caller. The audit trail is
   the user's recourse if they disagree with the council later.
7. **Members are read-only by default.** Council members investigate and propose — they do
   not modify the codebase. Pick read-only archetypes from the shared catalog when possible;
   if a member needs write tools (rare), the proposal still describes the change rather
   than performing it.
8. **Member responses are JSON; malformed responses get exactly one retry, then abstain.**
   All four member-response formats (proposal, vote, revision, ranking) are JSON objects
   with worked samples in the prompt. On parse failure or missing/empty required fields,
   re-dispatch that single seat once with a "your previous response was malformed"
   preamble. If the retry also fails, mark the seat as abstaining and proceed. Two
   abstentions in one phase aborts the council — write `ABORT.md` and return an error,
   never fabricate a decision. Full protocol: `references/council-protocol.md` § "Member
   response failures".
9. **Decline cleanly if you can't dispatch in parallel.** If the `Agent` tool is not
   available to you (you're already a subagent, the host runtime restricts it, or for any
   other reason), do not fake a council with sequential self-reasoning. Write
   `.council/<slug>/ABORT.md` explaining "Agent tool unavailable — council requires
   parallel dispatch" and return an error to the caller. This includes the recursive case:
   council members are themselves subagents and cannot convene sub-councils.

## Invocation contract

The caller (usually another agent) provides:

- **Question** — the single decision the council must resolve. Should be answerable
  with a discrete proposal, not an open-ended discussion.
- **Context summary** (optional but strongly preferred) — what the caller is doing, the
  relevant files/code, constraints already known, and what's been ruled out.

Argument format: `<question> [-- <context summary>]`

If only a question is given, scan recent conversation and obvious files (the working tree,
recent git log, the file the caller was editing) to assemble context yourself before
convening. Never proceed with no context — a council deliberating on a vacuum produces
generic advice.

## Phase summary

The full prompt templates and JSON shapes live in `references/council-protocol.md`. The
phases are:

| # | Phase | What happens | Artifacts |
|---|-------|--------------|-----------|
| 0 | **Slugify** | Derive `<slug>` from the question (kebab-case, ≤50 chars). If `.council/<slug>/` exists, append `-2`, `-3`, … until free. Create the directory. | directory |
| 1 | **Convene** | Pick 3 archetypes from the shared catalog using the rubric in `references/team-composition.md`. Record panel + rationale. | `QUESTION.md`, `PANEL.md` |
| 2 | **Independent research** | Dispatch all 3 members in parallel with identical context+question. Each returns a structured proposal. | `proposals-round-1.md` |
| 3 | **Single-choice vote** | Present all 3 proposals back to each member in parallel; each votes for exactly one (self-vote allowed). Unanimous → skip to phase 6. | `vote-round-1.md` |
| 4 | **Deliberation** | Share the tally and rationales with all 3 members in parallel. Each may revise their own proposal or stand. | `deliberation.md`, `proposals-round-2.md` |
| 5 | **Ranked-choice runoff** | Each member ranks all 3 (possibly revised) proposals 1–3. Run IRV (`references/voting-mechanics.md`). Chair tiebreaker only if IRV cannot resolve. | `vote-round-2.md` |
| 6 | **Decide + return** | Write `DECISION.md` and return decision + rationale + dissent + artifact path to the caller. | `DECISION.md` |

## Picking the panel (quick rubric)

Detailed examples are in `references/team-composition.md`. The short version:

1. **Identify the dominant domain** of the question (mobile UX, web UX, CLI UX, backend
   architecture, API design, data, infra, security, legal, performance).
2. **Seat the relevant specialist** for that domain (e.g., `ux-designer-mobile` for an
   iOS interaction question, `data-engineer` for a schema-migration question).
3. **Seat an architectural generalist** (`software-architect` or `api-designer`) to keep
   the proposal coherent with the broader system.
4. **Seat a challenger** (`skeptic`, `qa-engineer`, `security-researcher`, or
   `performance-engineer`) appropriate to the failure mode the question would create.

If the question is ambiguous or cross-cutting, `skeptic` is the safe third pick — they
specialize in surfacing hidden assumptions.

## Dispatching members

When you spawn a member via the Agent tool, use the archetype from the shared catalog
(see `plugins/agents/references/agent-catalog.md` for the roster).

Determine `subagent_type` by checking the available agent types in your environment's
system context (in Claude Code this is the agent-types system reminder; in other
environments consult the host's docs):

1. **Preferred:** if `agents:<archetype-name>` appears in the available list (e.g.,
   `agents:software-architect`), use it directly.
2. **Fallback:** if no `agents:*` types are exposed, dispatch with `subagent_type:
   general-purpose` and paste the archetype's full role block from
   `plugins/agents/agents/<archetype-name>.md` into the prompt under a `## Your role`
   heading **before** the council-specific task.
3. **Don't guess.** If you can't tell what's available, try `agents:<name>` once; if it
   errors, retry that seat with `general-purpose` + injected role. Record which path you
   took in `PANEL.md` so the audit trail explains why a member's voice may differ from
   the catalog's default.

Each member prompt must include:
- The full **context summary** verbatim
- The **question** verbatim
- The **member's seat** (e.g., "You are seated as the **mobile UX specialist** on a
  3-member council") — including any domain-nuance you want to inject on top of the
  archetype's default role
- The **phase-specific task** (research and propose / vote / deliberate / rank)
- The exact **output format** required (see `references/council-protocol.md`)
- A reminder that the member is **read-only**: they investigate and write proposals, they
  do not modify the codebase

Do **not** tell a round-1 member who else is on the panel or what others have proposed.
Anchoring kills independent reasoning.

## Returning to the caller

Your final response uses the exact template in `references/council-protocol.md` §
"Phase 6 — Decide and return". The shape is fixed because callers may parse it:
winning proposal, rationale, why-it-won paragraph, dissent line, audit-trail path.
Don't paraphrase the shape — the caller is expecting these fields by name.

If the caller wants the full audit trail before acting, they can read `DECISION.md`
at the artifact path you return. Every proposal, vote, deliberation, and tiebreak
is recorded there for later "why did you do X?" questions.

## When NOT to convene a council

- The question has an objectively correct answer the caller could discover by reading the
  code, running a test, or checking a spec. Use the council for **judgment calls**, not
  facts.
- The user is available and the cost of asking is low. The council exists to avoid
  interrupting the user, not to replace them.
- The decision is reversible and cheap (e.g., a variable name, a log message). Just pick
  one and move on.
