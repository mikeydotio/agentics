# Forge hardening decisions

Rationale extracted from forge's runtime prompts, which now carry the rules without the
derivations. Nothing here is needed to *run* the pipeline; it is needed to *change* it without
undoing a deliberate choice.

See also [`forge-auto-resume.md`](forge-auto-resume.md) for the hook-coordination decisions.

## Why `max_total_retries` is 100

The three runaway safeguards are independently configurable but must not contradict each other in
scale:

- `max_retries` (4) caps attempts on a **single** story — 1 initial plus up to 3 retries, then the
  story blocks.
- `max_total_retries` (100) caps the sum of every failed attempt across the **whole plan**,
  regardless of which story.
- `max_sessions` (200) caps execute sessions. At `max_stories_per_session: 1` that is effectively
  the number of stories attempted across a full run.

The subtlety is that `total_retries` increments once per failed evaluation or pre-check (see
`references/execution-loop-retry.md`), **not** only when a story exhausts its own retries. A
plan of dozens to ~100 stories, at a realistic 30–50% first-attempt retry rate, therefore accrues
retries in the tens purely from normal, healthy operation.

The earlier default of 20 would false-halt such a plan partway through, well before `max_sessions`
came into play — defeating the long-run autonomy `max_sessions: 200` exists to provide. 100 gives
realistic multi-wave plans headroom under normal failure rates while still tripping well before the
`max_sessions` budget when failures are systemic rather than incidental: a broken
generator/evaluator pairing that fails every attempt trips this in roughly 25 stories, not 200.

**If you change `max_retries` or `max_sessions`, re-derive this.** The three are independently
configurable, not independent in practical scale.

## Why the fix-loop archive call is unconditional

`forge-fix-archive.sh` is the only thing that increments the fix-cycle counter that `forge-state.sh`
gates `max_fix_cycles` / `max_fix_cycles_yolo` against. Skipping it — or dispatching to `plan` by
any route that bypasses it — defeats the runaway-fix-loop safeguard entirely, silently: the loop
runs forever with a counter that never advances.

This is why the router must branch on `state` before `dispatch`. `fix_loop`'s `dispatch` value is
the literal string `"plan --orchestrated"`, byte-for-byte identical to a genuine first-time
transition into `plan` from `design`. Checking `dispatch` first routes a fix-loop re-entry straight
past the archive call with nothing to indicate it happened.

## Why blocked stories are promoted with `--type escalate`, not a title prefix

`stories_all_done` can only become true once a story reaches `done`, so a blocked story that the
user elects to escalate must be closed rather than left blocked. Setting the structured
`story_type` field is what makes it resurface at the post-document ESCALATE gate;
`forge-state.sh` detects that field, **not** a title substring. The `ESCALATE:` title prefix is
kept only for human readability. Setting the prefix without the type silently discards the work.

## Why the config defaults live in exactly one place

`skills/forge/SKILL.md`'s Settings block is the single source. A second copy in
`skills/execute/SKILL.md` carried an explicit instruction to keep it "byte-for-byte" in sync and had
drifted anyway — it was missing `governed_explorer`. A hand-synced duplicate of machine-readable
defaults is a defect waiting to happen; the instruction to sync it by hand is not a mitigation.

## How a doc names a dead `story` form in order to deny it

`forge-contract-check.sh` reports any `story <verb> …` invocation the live CLI would reject. Some
documentation has to name a dead form **in order to correct the reader** — `references/storyhook-contract.md`
says the id-first form does not exist, and an LLM-facing doc especially needs that, because omission
leaves a wrong prior intact where only negation overwrites it. Widening the guard's reach (AGE-24
inline spans, AGE-31 placeholder verbs) turns those true sentences into violations.

The standing principle, settled by AGE-11's council and reaffirmed here:

> A guard you can satisfy by deleting true sentences is the wrong guard.

So the denied form's own line may carry a marker:

```
<!-- contract-check: expect-dead <token> -- <reason> -->
```

Four properties are load-bearing; none is decoration.

- **Bound to the reported TOKEN, not to the line.** It suppresses only a violation whose token
  matches, so a *different* drift appearing on the same line is still reported. A line-scoped
  ignore would shield same-line substitutions and could never itself fail.
- **Markers are found by a whole-file scan, deliberately independent of extraction.** A marker that
  suppresses nothing is a failure (`stale_suppressions`, which fails `contract_ok`). Siting the
  staleness check inside the per-line loop would make it unable to fire for a marker on a line the
  extractor never reads — precisely the case it exists to catch. This is what stops the escape
  hatch becoming the silent no-op class this repo has shipped before (AGE-18, AGE-21, AGE-27).
- **The reason is mandatory**, so the marker cannot decay into a mute button.
- **A placeholder token (`<token>`) is a signature, not a suppression** — mirroring the rule already
  applied to the subcommand and relation slots. That is what lets the convention be written down
  inside a scanned file without self-applying.

Because the marker asserts the form is still dead, the guard gets *stronger*: if storyhook ever made
the form real, the doc's denial would be false and the marker reports `form_is_valid`. Stale markers
are discriminated — `form_is_valid`, `not_scanned`, `token_mismatch`, `malformed` — because the four
call for different corrections.

Two things were considered and rejected. A **per-file allowlist** is too coarse: `storyhook-contract.md`
is the densest source of *real* invocations in the corpus, so exempting the file would unguard exactly
the document the guard exists for. A **negation-context heuristic** ("there is no…", "does not
exist") fails **open** — it would swallow genuine drift that happens to sit near those words, and
makes the guard's correctness depend on English phrasing.

The marker syntax is HTML-comment delimited. Matching it syntax-agnostically (so it also works in a
`#` comment) was requested by two council seats and deliberately **deferred to AGE-30**, which is the
story that would widen the scan to `bin/*.sh`; a bare substring cannot be quoted in a scanned
document without self-applying, and there is no second wrapper to serve until that widening exists.

Ruled by `/council-vote`, unanimous 3-0 in round one, two of three seats voting against their own
proposals. Full audit trail: `.council/age32-negative-example-suppression/DECISION.md`.

## What was deliberately not built

A full forge supervisor. `forge-state.sh` emits `category` / `auto_advance` / `transition_id` as
**telemetry only** — nothing acts on them. Reimplementing the router's judgment (the mandatory
archive call, the three human-gate states) in bash would create a second source of truth for
exactly the class of drift `forge-contract-check.sh` exists to catch.

**Revisit on a concrete signal**, not on a schedule: `transitions.log` data showing category-1
transitions carry a non-trivial cost, a predicted/actual mismatch indicating a real misroute, or a
persistent orphaned-predicted count.
