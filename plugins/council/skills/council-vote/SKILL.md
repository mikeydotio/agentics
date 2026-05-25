---
name: council-vote
description: Use when you need a decision from the user mid-task but the user is unavailable, prefers not to be interrupted, or has explicitly delegated the choice. Convenes a 3-member sub-agent council that independently proposes solutions, votes single-choice, deliberates once if not unanimous, then runs a ranked-choice runoff with a chair tiebreaker. Returns a defensible decision plus a full audit trail at `.council/<slug>/`. Use this instead of guessing silently or blocking on AskUserQuestion when the user has signaled they want autonomous progress.
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
2. **Members are dispatched in parallel within each phase.** A single message with 3 Agent
   tool calls per phase. Sequential dispatch defeats independent reasoning and burns time.
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
8. **Three members, three Agent calls, one message.** Never spawn members serially; never
   use `run_in_background` for council work.

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
| 0 | **Slugify** | Derive `<slug>` from the question (kebab-case, ≤50 chars). Create `.council/<slug>/`. | directory |
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
(see `plugins/agents/references/agent-catalog.md` for the roster). Determine
`subagent_type` from what's available in the running environment; if the agentics agents
plugin is installed it will be `agents:<archetype-name>`, otherwise fall back to
`general-purpose` and inject the archetype's role explicitly in the prompt.

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

Your final response to the caller contains:

1. **Winning proposal** — the full proposal text, not a summary.
2. **One-paragraph rationale** explaining why this proposal won (which members voted for
   it, which rounds were needed, what dissent existed).
3. **Dissent summary** — if any member opposed, summarize their concern in one sentence so
   the caller can decide whether to escalate.
4. **Artifact path** — `.council/<slug>/DECISION.md` and the directory containing the
   full transcript.

If the caller wants the audit trail before acting, they can read `DECISION.md`. If the
user later asks "why did you do X?", every proposal, vote, and tiebreak is recorded.

## When NOT to convene a council

- The question has an objectively correct answer the caller could discover by reading the
  code, running a test, or checking a spec. Use the council for **judgment calls**, not
  facts.
- The user is available and the cost of asking is low. The council exists to avoid
  interrupting the user, not to replace them.
- The decision is reversible and cheap (e.g., a variable name, a log message). Just pick
  one and move on.
- The caller is itself a council member. No recursive councils.
