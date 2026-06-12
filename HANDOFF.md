# HANDOFF — atlas plugin build (Phase 7 remains)

Branch: `feat/atlas-plugin` (do not push without running `make test`; the
pre-push hook enforces it). Plan of record:
`/Users/mikey/.claude/plans/design-a-codebase-mapping-skill-fancy-river.md`.
Contributor onboarding: `plugins/atlas/references/design.md` (decision record +
roadmap — read first).

## State

Phases 1–6 complete and committed. On top of the Phase 1–5 core (scan,
partition, ground, blob-SHA ledger, lock, status tiers, lint L1–L11, INDEX
rebuild, guarded commit, CLAUDE.md init/remove, shared agents, /atlas skill,
full-map protocol, SessionStart hook), Phase 6 delivered the incremental
layer: `references/update-protocol.md` is the real protocol (quarantine →
diff/plan → ≥50% escalation → mechanical renames → orphan removal → anchored
regen waves via diffpack → verify → overview → init-before-final-finalize →
index/lint → guarded commit), plus the read-only `/atlas verify` flow and the
conflict recipe (README + protocol). New deterministic surface: `doc
apply-renames`, `doc remove`, `diffpack`, `ledger diff` now emitting
`dirty_paths` + `new_file_assignments`, and a churn-free `ledger finalize`
(unchanged docs stay byte-identical — the hash-gating proof, pinned by
`tests/test-update-flow.sh`). 111 atlas tests green; `make test` green.

Phase 6 was dogfooded on this repo: a real `/atlas update` after the phase-6
commits regenerated only the affected docs, and a conflict-marker sabotage was
detected (tier 3) and regenerated per the quarantine path.

## Next: Phase 7 — hardening, docs, release (plan §Phase 7)

- Full README per `plugins/semver/README.md` quality bar: quick start,
  commands table, map tour, blob-ledger explainer, staleness tiers, conflict
  recipe, config reference, limitations, FAQ.
- Edge-case sweep: empty repo, zero mappable files, single-file repo,
  binary-heavy repo, hand-corrupted docs/atlas, impossible globs, INDEX
  budget overflow path, non-git refusal.
- `linguist-generated` guidance in README (suggest, never write unasked).
- `plugins/agents/agents/_template.md` pipeline enum: add `atlas`.
- map-format.md: exempt Relationships edge lines from the 100-char rule
  (long module ids make compliance impossible; several docs note this).
- `ground`: skip .md files when extracting definition candidates (prose
  noise); L6 residue for ./-prefixed and server-side paths.
- Dogfood findings to surface to the user (map Gotchas carry citations):
  deployit troubleshooting documents a `questions` array the CLI never emits;
  forge README ships a pre-refactor 15-agent roster; forge skills name
  devils-advocate/senior-engineer/ux-designer which have no library files;
  freshen SKILL.md:64 contradicts its one-source-at-a-time CLI; greenlight
  `permissive` mode behaves identically to `standard` and terraform/helm
  case-guards are dead; rca-status.sh never surfaces INCONCLUSIVE.md; the
  root bats suite tests a nonexistent "pilot" plugin; forge bin .bats files
  resolve paths that can't work in place.
- Update design.md roadmap to complete; delete/empty HANDOFF.md.
- Release: `/semver bump minor` (expect v2.18.0), verify CHANGELOG, push via
  HTTPS override, PR per branch+PR flow, install from marketplace and
  smoke-test `/atlas` in a scratch project.
