# Council Protocol — Phase-by-Phase

Every prompt template and JSON shape the chair needs to run a full council. The chair
(orchestrator) follows these phases in order. Each phase is bounded — there is no
"maybe we'll add a third round" branch.

## Phase 0 — Slugify and scaffold

Derive `<slug>` from the question:

1. Lowercase, replace non-alphanumeric runs with `-`, strip leading/trailing `-`.
2. Truncate to ≤50 characters at a word boundary.
3. If `.council/<slug>/` already exists, append `-2`, `-3`, etc. until a free slot is
   found. Never overwrite a prior council's artifacts.

Create the directory: `mkdir -p .council/<slug>/`.

## Phase 1 — Convene

Pick exactly 3 archetypes using the rubric in `team-composition.md`. Write
`QUESTION.md` and `PANEL.md`.

### `.council/<slug>/QUESTION.md`

```markdown
# Council Question

**Convened:** <ISO 8601 timestamp>
**Caller:** <calling skill or agent, if known; otherwise "user direct">

## Question

<question verbatim>

## Context

<context summary verbatim, or "Assembled by chair from working tree" plus the
chair's assembled summary if the caller did not provide one>
```

### `.council/<slug>/PANEL.md`

```markdown
# Council Panel

| Seat | Archetype | Why this seat |
|------|-----------|---------------|
| 1 | <archetype-name> | <one sentence> |
| 2 | <archetype-name> | <one sentence> |
| 3 | <archetype-name> | <one sentence> |

## Dispatch notes

<any domain-nuance the chair will inject on top of the archetype's default role,
e.g., "Member 1 (ux-designer-mobile) will be asked to focus on iOS 17+ HIG
guidance for primary CTAs.">
```

## Phase 2 — Independent research (parallel)

Dispatch all 3 members in a **single message** with 3 Agent tool calls. Each member
receives the same context and question, sees no information about the other members, and
returns a structured proposal.

### Member prompt template (round-1 research)

```
You are seated as **Seat <N> — <archetype display name>** on a 3-member council
convened to answer a single question. You are working independently. Do not
speculate about who else is on the panel; assume your seat covers your domain.

## Question

<question verbatim>

## Context

<context summary verbatim>

## Your task

Investigate this question from your domain's perspective. You are read-only —
investigate the codebase, read relevant docs, consult your domain expertise, but
do not modify any files.

When you have an answer, return a single proposal in this exact format. Do not
preface or summarize outside the format.

---PROPOSAL---
summary: <one sentence — the decision you propose>
rationale: <2-5 sentences — why this is the right answer from your perspective>
risks: <one sentence — the biggest risk if we follow your proposal>
confidence: <low | medium | high>
---END PROPOSAL---
```

After all 3 return, write `.council/<slug>/proposals-round-1.md`:

```markdown
# Round 1 Proposals

## Proposal A — Seat 1 (<archetype>)
<proposal block>

## Proposal B — Seat 2 (<archetype>)
<proposal block>

## Proposal C — Seat 3 (<archetype>)
<proposal block>
```

Label proposals A/B/C (not by seat number) so subsequent voting prompts can
present them in a stable, anonymized order.

## Phase 3 — Single-choice vote (parallel)

Dispatch all 3 members again, in parallel. Each receives all 3 proposals
(now labeled A/B/C) and casts one vote.

### Member prompt template (round-1 vote)

```
You are Seat <N> — <archetype>. The council has produced 3 proposals in response
to this question:

<question verbatim>

## Proposal A
<proposal block>

## Proposal B
<proposal block>

## Proposal C
<proposal block>

## Your task

Cast a single vote for the proposal you believe best answers the question. You
may vote for your own proposal. Respond in this exact format and nothing else.

---VOTE---
choice: <A | B | C>
reason: <one sentence>
---END VOTE---
```

Tally and write `.council/<slug>/vote-round-1.md`:

```markdown
# Round 1 Vote (single-choice)

| Seat | Archetype | Voted | Reason |
|------|-----------|-------|--------|
| 1 | <archetype> | <A/B/C> | <reason> |
| 2 | <archetype> | <A/B/C> | <reason> |
| 3 | <archetype> | <A/B/C> | <reason> |

**Tally:** A=<n>, B=<n>, C=<n>

**Result:** <unanimous for X | split N-N-N>
```

**If unanimous** (all three voted the same proposal): skip phases 4 and 5, go
directly to phase 6 and record `DECISION.md` with `vote_method: unanimous`.

**Otherwise:** proceed to phase 4.

## Phase 4 — Deliberation (one round, parallel)

Share the round-1 tally and rationales with all 3 members. Each may revise
their proposal in light of what they've learned, or stand.

### Member prompt template (deliberation)

```
You are Seat <N> — <archetype>. The first vote produced a split:

<paste the tally and reason column from vote-round-1.md>

Here are the original proposals again:

## Proposal A
<proposal block>

## Proposal B
<proposal block>

## Proposal C
<proposal block>

## Your task

You may revise your own proposal based on what you've learned from the other
members' reasoning, or stand by it unchanged. You may NOT revise another
member's proposal. Be specific about what you changed and why.

Respond in this exact format and nothing else.

---REVISION---
seat: <your seat number>
action: <revise | stand>
revised_proposal: <if revising, the full new proposal in the round-1 format;
                   if standing, repeat your original proposal>
delta: <if revising, one sentence on what changed; if standing, "no change">
---END REVISION---
```

Write `.council/<slug>/deliberation.md` (the raw revision payloads) and
`.council/<slug>/proposals-round-2.md` (the proposal slate going into the
runoff, re-labeled A/B/C in the same order as round-1 so members can map
their familiarity).

## Phase 5 — Ranked-choice runoff (parallel)

Dispatch all 3 members again, in parallel. Each ranks all 3 round-2 proposals 1–3.

### Member prompt template (ranked-choice)

```
You are Seat <N> — <archetype>. After deliberation, the proposal slate is:

## Proposal A
<round-2 proposal A>

## Proposal B
<round-2 proposal B>

## Proposal C
<round-2 proposal C>

## Your task

Rank all three proposals from best (1) to worst (3). You may rank your own
proposal. No ties allowed in your ranking.

Respond in this exact format and nothing else.

---RANKING---
first: <A | B | C>
second: <A | B | C>
third: <A | B | C>
reason: <one sentence summarizing why your top choice is best>
---END RANKING---
```

Tally with IRV (see `voting-mechanics.md`). Write `.council/<slug>/vote-round-2.md`:

```markdown
# Round 2 Vote (ranked-choice IRV)

| Seat | Archetype | 1st | 2nd | 3rd | Reason |
|------|-----------|-----|-----|-----|--------|
| 1 | ... | A | B | C | ... |
| 2 | ... | B | A | C | ... |
| 3 | ... | C | A | B | ... |

## IRV tabulation

Round 1: A=1, B=1, C=1 — no majority, lowest eliminated: <X>
Round 2 (after eliminating <X>): <tally>

**Winner:** <proposal letter>
**Method:** <IRV majority | chair tiebreaker>
**Tiebreak reason (if chair):** <heuristic invoked>
```

## Phase 6 — Decide and return

Write `.council/<slug>/DECISION.md`:

```markdown
# Council Decision

**Question:** <question>
**Decided:** <ISO 8601 timestamp>
**Method:** <unanimous-round-1 | ranked-choice-majority | chair-tiebreaker>

## Winning proposal

<full proposal text — summary + rationale + risks + confidence>

## Why this won

<one paragraph: who voted for it, in which round, what dissent existed, whether
deliberation moved any members>

## Dissent

<if any member ranked the winner last or opposed throughout, summarize their
concern in one sentence. If unanimous, write "None — unanimous decision.">

## Audit trail

- [QUESTION.md](QUESTION.md)
- [PANEL.md](PANEL.md)
- [proposals-round-1.md](proposals-round-1.md)
- [vote-round-1.md](vote-round-1.md)
- [deliberation.md](deliberation.md) <!-- only if non-unanimous -->
- [proposals-round-2.md](proposals-round-2.md) <!-- only if non-unanimous -->
- [vote-round-2.md](vote-round-2.md) <!-- only if non-unanimous -->
```

Return to the caller in this exact shape (plain text, not JSON — the caller is
a Claude agent, not a program):

```
## Council Decision

**Proposal:** <full winning proposal summary line>

<2-5 sentence rationale from the winning proposal>

**Why this won:** <one paragraph from DECISION.md "Why this won" section>

**Dissent:** <one sentence, or "None — unanimous">

**Audit trail:** `.council/<slug>/DECISION.md`
```

The caller is then responsible for acting on the decision. The council is done.
