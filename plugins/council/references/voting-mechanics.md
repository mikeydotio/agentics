# Voting Mechanics

The council uses two voting methods: a single-choice plurality vote in round 1, and
Instant-Runoff Voting (IRV) in round 2 if round 1 was not unanimous. The chair never
votes — the chair only tabulates and, when IRV genuinely cannot resolve, applies a
documented tiebreaker.

## Round 1 — single-choice plurality

Each of the 3 members casts one vote for one of the 3 proposals (A, B, or C). Members
may vote for their own proposal.

### Possible tallies

With 3 voters and 3 candidates:

| Tally | Outcome |
|-------|---------|
| 3-0-0 | **Unanimous.** Winner is the 3-vote proposal. Skip deliberation and runoff. |
| 2-1-0 | Plurality winner exists but not unanimous. Proceed to deliberation. |
| 1-1-1 | Three-way split. Proceed to deliberation. |

**Only the unanimous case ends the council early.** Even a 2-1 result triggers
deliberation — the dissenter's reasoning might persuade the majority, and the second
member's vote in IRV may flip if their first choice is eliminated.

## Deliberation

After a non-unanimous round 1, each member is shown:
- The vote tally
- Each member's one-sentence reason for their vote

Each member may then revise their own proposal (and only their own) or stand. Revisions
go into round 2 with the same A/B/C labels — so a member who tracked proposal B in
round 1 still sees "proposal B" in round 2 even if B's author revised it. This stability
helps members vote based on familiarity with the proposal's trajectory.

## Round 2 — Instant-Runoff Voting (IRV)

Each member ranks all 3 proposals from 1 (best) to 3 (worst). No ties allowed in
individual rankings.

### Tabulation

1. **Count first-choice votes.** If any proposal has ≥2 first-place votes (a majority of
   3), it wins.
2. **If no majority:** eliminate the proposal with the **fewest first-choice votes**. If
   two proposals are tied for fewest first-choice votes, eliminate the one with the
   **fewest second-choice votes** (a Borda-style tiebreak). If still tied, eliminate the
   one alphabetically later (A > B > C, so eliminate C).
3. **Redistribute.** For each ballot whose first choice was eliminated, promote that
   ballot's second choice to first.
4. **Recount.** With only 2 proposals remaining and 3 ballots, one must have ≥2 votes
   unless all three voters had the same eliminated first choice (impossible in IRV — if
   a proposal had all 3 first-choice votes, it would have won in step 1).

### Worked example — 1-1-1 split

Round-2 rankings:

| Seat | 1st | 2nd | 3rd |
|------|-----|-----|-----|
| 1 | A | B | C |
| 2 | B | A | C |
| 3 | C | A | B |

- First-choice tally: A=1, B=1, C=1. No majority.
- Lowest first-choice votes: all tied (1 each). Apply Borda tiebreak:
  - A second-choice tally: 2 (seats 2, 3)
  - B second-choice tally: 1 (seat 1)
  - C second-choice tally: 0
  - Eliminate C (fewest second-choice votes).
- Redistribute seat 3's ballot: their second choice was A → A gains a vote.
- New tally: A=2, B=1. **A wins.**

### Worked example — irresolvable tie

Round-2 rankings:

| Seat | 1st | 2nd | 3rd |
|------|-----|-----|-----|
| 1 | A | B | C |
| 2 | B | C | A |
| 3 | C | A | B |

- First-choice tally: A=1, B=1, C=1. No majority.
- Second-choice tally: A=1, B=1, C=1. Still tied.
- Alphabetical tiebreak: eliminate C.
- Redistribute seat 3's ballot: their second choice was A → A gains a vote.
- New tally: A=2, B=1. **A wins.** (Resolved by alphabetical elimination — record this
  in `vote-round-2.md`.)

In practice IRV almost always resolves with 3 voters and 3 candidates. A genuinely
irresolvable case (e.g., a perfectly cyclic preference where every elimination path
produces the same tie) is rare but possible — that's when the chair tiebreaker kicks in.

## Chair tiebreaker

The chair only intervenes when IRV — including all programmatic tiebreaks above —
cannot produce a winner. This should be a very narrow set of cases. When it happens,
the chair applies this heuristic in order, picking the first criterion that resolves:

1. **Lowest reversibility cost.** If one tied proposal is more easily undone than the
   others (cheaper rollback, smaller blast radius), prefer it. The council's decision
   is autonomous; the user should be able to override it without expensive rework.
2. **Highest aggregate confidence.** Compute each tied proposal's confidence as the
   author's self-reported confidence (`low`=1, `medium`=2, `high`=3) plus the count of
   other members who ranked it first or second. Pick the highest. Ties → next criterion.
3. **Smallest scope.** Prefer the proposal that changes the fewest files, touches the
   smallest surface area, or makes the smallest commitment. When in doubt, do less.
4. **Alphabetical (A < B < C).** Final deterministic fallback so the chair never
   stalls.

The chair records the criterion that resolved the tie in `vote-round-2.md` and
`DECISION.md` under `Tiebreak reason`. This makes the autonomous decision auditable —
the user can read the heuristic that was applied and either accept it or override.

## Why this design

- **Single-choice round 1 is the cheap check.** Most well-framed questions produce
  unanimity or near-unanimity. When they do, the council short-circuits and returns in
  one round of dispatches.
- **Deliberation is bounded to one round** because in practice the second round of
  deliberation almost never changes minds — and the cost of unbounded back-and-forth
  is unbounded latency. One round captures the marginal value of "I heard your
  reasoning" without paying for noise.
- **IRV beats plurality** for the runoff because with only 3 voters, plurality
  produces frequent unresolved ties. IRV resolves most 3-voter ties programmatically.
- **The chair never votes** because the chair has no domain seat — they're a process
  manager, not a panelist. Adding the chair as a 4th voter would also dilute the
  signal from the actual specialists.
