# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [v2.39.0] - 2026-08-03

### Fixed
- stop adding `blocked`, which the storyhook template now ships (6717023)
- migrate fixtures and docs to `story project new` (daaa4c1)
- stop silently skipping post-bump hooks when --plugin-root is omitted (af86c9e)
- update the story CLI init invocation for storyhook 2.0 (ac50aed)
- adapt storyhook fixtures to the CLI's current surface (00d2183)

### Changed
- Merge pull request #126 from mikeydotio/docs/backlog-loop-progress (a4cbc72)
- Merge pull request #125 from mikeydotio/fix/AGE-3-semver-post-bump-hooks-skipped (03c0591)
- Merge pull request #124 from mikeydotio/fix/age-2-storyhook-active-role-invariant (4e048e3)
- Merge pull request #123 from mikeydotio/chore/storyhook-prefix-age (10e096e)
- Merge pull request #122 from mikeydotio/feat/claude5-realign-forge (660cc15)

### Documentation
- record AGE-14/AGE-15 in the backlog loop's progress file (9f8828d)
- add PROGRESS.md to drive the autonomous backlog loop (b5b8a1a)
- correct the storyhook state, role, and init-verb contract (80ae367)

### Testing
- stop swallowing storyhook's stderr when fixtures create a project (6a14bda)
- execute decompose's documented storyhook setup (ac8528b)

### Maintenance
- rename the project prefix from HP to AGE (ebe5326)

_[manual]_

## [v2.38.0] - 2026-07-30

### Added
- realign forge for Claude 5 models (41b6793)

### Changed
- Merge pull request #121 from mikeydotio/fix/isolate-storyhook-store-in-tests (900d4dd)
- Merge pull request #120 from mikeydotio/chore/storyhook-store-migration (7b1b1f7)
- Merge pull request #119 from mikeydotio/feat/claude5-realign-agents (e65376b)

### Testing
- run every suite against a storyhook store of its own (5f5e8a5)

### Maintenance
- migrate the tracker to the store and retire .storyhook (908dc68)

_[manual]_

## [v2.37.0] - 2026-07-30

### Added
- realign the shared agent library for Claude 5 models (28d7253)

### Changed
- Merge pull request #116 from mikeydotio/feat/deployit-per-project-config (483b607)

### Documentation
- move the completed tool audit and design principles out of the plugin (96cdd1b)

_[manual]_

## [v2.36.0] - 2026-07-21

### Added
- per-project toolchain pin via .deployit/config.toml (3119442)

### Changed
- Merge pull request #115 from mikeydotio/feat/storywork-actuator-a2 (493b9bd)

### Testing
- add real-story-CLI and real-concurrency coverage (7bbec91)

_[manual]_

## [v2.35.3] - 2026-07-21

### Fixed
- anchor story.sh repo-root to the main worktree, not CWD (67898a6)

_[manual]_

## [v2.35.2] - 2026-07-21

### Fixed
- gate cmd_complete on STORY_DRY_RUN, cover valid_story_id (161d3a6)

_[manual]_

## [v2.35.1] - 2026-07-21

### Fixed
- close review-blocking gaps in story.sh dispatch/claim (b2d59ee)

_[manual]_

## [v2.35.0] - 2026-07-21

### Added
- add story.sh dispatch/complete actuator (343565f)

### Changed
- Merge pull request #114 from mikeydotio/refactor/issue-session-lib-a1 (f13be27)

_[manual]_

## [v2.34.1] - 2026-07-21

### Changed
- extract provider-agnostic session lib (9f1b30d)
- Merge pull request #113 from mikeydotio/release/v2.34.0 (36945cc)

_[manual]_

## [v2.34.0] - 2026-07-20

### Added
- publish the Sparkle appcast to the GitHub release (22ca74a)
- detect Sparkle in the built macOS app and warn on mismatch (22e50d6)

### Fixed
- base new work on the freshest origin tip, not stale local HEAD (35dfc2e)
- anchor REPO_ROOT to the main worktree, not ambient CWD (9e2f30f)
- recognise remotely-merged branches when local main lags (#99) (9021fdb)

### Changed
- Update CLAUDE.md to direct bump+release on every PR merge (1e0e904)
- Merge pull request #112 from mikeydotio/worktree-age-111 (cf010c7)
- extract Sparkle appcast RSS rendering into a shared module (2f35251)
- Merge pull request #110 from mikeydotio/worktree-age-107 (a0f7334)
- Merge pull request #109 from mikeydotio/worktree-age-108 (d6b846f)
- anchor origin_owner_repo to REPO_ROOT (8cab49d)
- Merge pull request #105 from mikeydotio/worktree-age-104 (bf4d47e)
- remove the atlas map-update lesson affordance (4ccf84d)
- remove the atlas plugin, generated map, and wiring (a36eb35)
- Merge pull request #103 from mikeydotio/fix/99-complete-merged-branch-stale-base (518ba67)
- Merge pull request #101 from mikeydotio/release/v2.33.0 (650f2c0)

### Documentation
- correct Sparkle .zip notarization claim; drop stray fence (6ac52da)
- note CWD-independent state anchoring (b9699eb)
- scrub dangling atlas references in comments/specs (afa0a1f)

### Maintenance
- drop atlas-only shared agents (b083e6d)

_[manual]_

## [v2.33.0] - 2026-07-18

### Added
- launch /issue do sessions with --model opusplan (#97) (81f0682)

### Changed
- Merge pull request #100 from mikeydotio/feat/greenlight-plan-explorer (26ec630)
- Merge pull request #98 from mikeydotio/worktree-age-97 (aff5560)

_[manual]_

## [v2.32.0] - 2026-07-18

### Added
- governed-explorer path in research step (Wave 3) (e491efa)
- plan-explorer launcher + /greenlight explore (Wave 2) (d75523c)
- plan-explorer gate policy (Wave 1) (96701b6)

### Changed
- Merge pull request #96 from mikeydotio/fix/test-prompt-extra-delivery (d899fb0)
- Merge pull request #95 from mikeydotio/release/v2.31.0 (15e1bbf)

### Documentation
- document plan-explorer autonomy (0d521b8)
- spec for plan-explorer autonomy (e58e0e7)

### Testing
- align prompt-extra assertions with #87's load-buffer delivery (7870537)

_[manual]_

## [v2.31.0] - 2026-07-14

### Added
- render post-deploy test status on build pages (issue #90) (ebaf9fe)
- run post-deploy tests out-of-band (issue #90) (bb9521c)
- live multi-line delivery checks — `capture` verb + doctor probe (#87) (6c4b062)

### Fixed
- deliver-once + Enter-only retry in pane_send_and_confirm (#86) (8c22d5e)
- deliver multi-line ISSUE_PROMPT via bracketed paste (#87) (04b591b)

### Changed
- Merge pull request #94 from mikeydotio/feat/issue-daemon-seams (5539ca2)
- Merge pull request #93 from mikeydotio/worktree-age-90 (5d1dc79)
- Merge pull request #92 from mikeydotio/fix/freshen-pane-confirm-repaste-86 (c30e50b)
- Merge pull request #91 from mikeydotio/worktree-age-87 (c1d07d3)

### Documentation
- document out-of-band post-deploy tests (issue #90) (63ca5b7)
- record why freshen keeps the last-line liveness probe (#86) (206b3ea)

_[manual]_

## [v2.30.0] - 2026-07-14

### Added
- ISSUE_PROMPT_EXTRA appends a caller clause to the handoff prompt (0f69ec8)
- ISSUE_TARGET_SESSION dispatches into a named tmux session (177b8d2)

### Changed
- Merge pull request #89 from mikeydotio/atlas/update-7387d36 (fe6e538)
- Merge pull request #85 from mikeydotio/worktree-age-82 (7387d36)

### Documentation
- update to v2.29.0 (58 cells re-judged; rca-v2 split into 6 modules + issue-tests into 2; semver worktree-guard, issue autosubmit) (f19cbed)

_[manual]_

## [v2.29.0] - 2026-07-12

### Fixed
- guarantee prompt receipt + auto-submit in `do` (#82) (604c005)

### Changed
- Merge remote-tracking branch 'origin/main' into land-85 (e482f6e)
- Merge pull request #88 from mikeydotio/feat/rca-v2 (74d2e83)

### Documentation
- document the two-phase confirmed prompt handoff (#82) (c284dfe)

### Testing
- make fake tmux stateful to observe receipt/submission (53a7f55)

_[manual]_

## [v2.28.0] - 2026-07-12

### Added
- thin orchestrator router + manifests, README, CLAUDE.md row (98a077b)
- seven pipeline subskills + eight agent-override contexts (5b17988)
- methodology reference set — scientific debugging encoded (3442f50)
- experimenter agent + RCA-focused improvements to qa-engineer, investigator, hypothesis-challenger (11f1d7c)
- deterministic bin layer — 8 JSON-contract scripts + plain-bash test suite (fe9645f)

### Changed
- Merge pull request #84 from mikeydotio/feat/worktree-guards (62e1840)

_[manual]_

## [v2.27.0] - 2026-07-12

### Added
- refuse deploy/bump inside a git worktree (c72ac2c)
- refuse mutating ops inside a git worktree (f49a8b6)
- brief the worktree agent to never bump or deploy (4990dec)

### Changed
- Merge pull request #81 from mikeydotio/worktree-age-79 (40bef09)

_[manual]_

## [v2.26.2] - 2026-07-11

### Fixed
- hash overview scopes over scanned files, not the git tree (333952a)

### Changed
- Merge pull request #80 from mikeydotio/worktree-age-78 (d827a59)

### Documentation
- scopes invalidate via scanned-file digest, not tree SHA (b7fc786)

### Testing
- regression guards for docs-scope self-invalidation (de06c8f)

_[manual]_

## [v2.26.1] - 2026-07-11

### Added
- brief the do-child to read all comments and weigh reopens (ea4cea1)

### Changed
- Merge pull request #77 from mikeydotio/atlas/update-a4486d2 (3d618e4)
- Merge pull request #76 from mikeydotio/atlas/update-cb09ceb (a4486d2)
- Merge pull request #75 from mikeydotio/chore/issue-toolkit-72 (cc5a619)

### Documentation
- update to a4486d2 (36 cells re-judged; map issue plugin + deployit bin re-chunk, drop handle-issue/deployit-bin docs) (dc6193d)
- refresh ARCHITECTURE ledger hashes (clear stale-source flag; no content change) (ecf8872)
- update to cb09ceb (93 cells re-judged, 3 corrected on verify; map reconcile-pr + semver re-chunk, drop stale semver-tests doc) (134d628)

_[manual]_

## [v2.26.0] - 2026-07-09

### Added
- add guard-railed complete verb (plan/execute) (f3c667e)
- add view + create subcommands and the new-verb protocol (a0c9b65)

### Changed
- Merge pull request #73 from mikeydotio/fix/deployit-version-bump-71 (d2276c6)

### Documentation
- rewrite SKILL router + README for the verb grammar (1305d80)

### Maintenance
- rename handle-issue plugin to issue (44d0191)

_[manual]_

## [v2.25.2] - 2026-07-09

### Fixed
- publish index via PR under branch-protection ruleset (4770c56)
- two-tier readiness gate resilient to footer drift (#67) (f7bfe8e)

### Changed
- Merge pull request #70 from mikeydotio/fix/deployit-publish-protect-main-69 (5ccde01)
- Merge pull request #68 from mikeydotio/worktree-age-67 (02e2594)

### Documentation
- troubleshoot stale version-keyed cache after a merged fix (6c800b3)
- document index publishing modes and bypass alternative (38f361e)
- document readiness tiers, doctor, env knobs (#67) (46a77af)

### Testing
- guard against shipped plugin content drift (#71) (6bdb60c)
- cover PR-fallback publish, classifier, and disk-safety (5c61285)
- readiness tier + drift coverage (#67) (24f89bd)

_[manual]_

## [v2.25.1] - 2026-07-07

### Fixed
- name-resolve calls to types only; drop method-name guesses (#65) (240a859)

### Testing
- type-only resolution fixtures + #65 regression tests (2ef348a)

_[manual]_

## [v2.25.0] - 2026-07-07

### Added
- name worktree with same formula as its window (770ba79)
- new plugin to rebase & reconcile a PR onto its base (f25653d)
- auto-gitignore per-issue worktrees (#55) (3c859eb)
- add /semver set and /semver init commands (ed2ea0a)
- prefer-the-map steering + per-file covers probe (99ef58a)
- sync issue label, plan comment, and PR links to GitHub (e55ca1f)

### Fixed
- open per-issue window detached so focus stays put (#54) (eae50fd)

### Documentation
- document worktree gitignore hygiene (#55) (ca31164)
- document set and init commands (4e4c6c0)

### Testing
- cover worktree gitignore hygiene (#55) (4d51ee8)
- cover /semver set and /semver init (c6e87d7)

### Maintenance
- register plugin in marketplace, make test, and docs (d4bc4fc)
- gitignore handle-issue per-issue worktrees (0296630)
- re-project agentics map + CLAUDE.md with new steering (a908938)

_[manual]_

## [v2.24.1] - 2026-07-05

### Fixed
- force plan mode via --permission-mode flag; name the tmux window (36f4797)

### Documentation
- fix 3 lint warnings (ux summary length, 2 unresolvable plugin.json path citations) (6d6dd3e)
- update map to 50c998d (44 docs re-projected, 809 cells judged + verified, 4 stale docs removed) (402cc2b)

_[manual]_

## [v2.24.0] - 2026-07-05

### Added
- add /handle-issue skill router and README (73d454e)
- add list/dispatch helper (bin/handle-issue.sh) (aeb5159)
- scaffold plugin manifest and marketplace registration (f6cfd0e)
- add forge-transition-report.sh to correlate predicted/actual transitions (agentics#33) (7eb33a5)
- thread --transition-id through step-exit for predicted/actual correlation (agentics#33) (9d9f527)
- classify router dispatch into category/auto_advance, add transition_id (agentics#33) (b992bfa)
- log step-exit transitions to freshen's audit log (F047) (4f14f19)
- add capture-pane confirm and transition-log helpers (F045, F047) (e325e49)
- add scaffold scripts for mechanical handoff and plan-mapping fields (F039, F035) (9ead005)
- add forge-predecessor-diff.sh for mechanical diff truncation (F033) (1ab27af)
- add forge-crash-recover.sh for one-call crash recovery (F038) (e841538)
- add forge-integrity.sh for content-hash integrity checks (04fa044)
- add forge-verdict.sh for deterministic verdicts.jsonl logging (F034) (4165c05)
- add forge-lock.sh for deterministic session locking (F030) (587894a)
- add forge-loop-state.sh for deterministic loop bookkeeping (3bfbd84)
- add forge-close-project-story.sh to close the parent for real (8777a07)
- add a blocked-by cycle validator; correct story graph --json claims (3f76933)

### Fixed
- confirm /clear and re-invoke are actually accepted (F045, F041, F056) (e10cd36)
- bound .clear-consumed to a freshness window (f42d1c3)
- make F052's SessionStart(clear) fix order-independent (9ab8638)
- harden command classification and make the AI tier opt-in (e7e4e62)
- scope integrity snapshots by session to prevent concurrent-run collisions (5831654)
- detect ESCALATE via structured story_type field, not title substring (4d501b6)
- checkpoint session-stop ahead of the breaker, bound story handoff, portable duration (f46a4be)
- dedupe Stop-loop breaker ticks and gate reset on freshen /clear (084e48c)
- guard forge-step-exit.sh's no-op commit and fix a freshen JSON-corruption bug (F053) (616712c)
- reject schema-incomplete lock.json before it reaches fromdate (5466e70)
- require minimal shape before an artifact counts as present (F102) (5393995)
- scope prechecks' stub grep to real stub idioms (F105) (f07a5e6)
- reconcile max_total_retries default with realistic retry volume (F097) (a2b567b)
- make the fix-loop archive call unskippable in the router (F003) (ad1882f)
- stop telling read-only reviewer/triager to write their own report (6d4bc3a)
- unify the evaluator verdict schema, resolve the 4KB-vs-comprehensive conflict (5e4f3c3)
- resolve execution-loop spawns to real subagent types, fix drift-check namespace (32e2cbc)
- rename phantom agents to the real roster, wire subagent_type resolution (f7d5581)
- resolve subagent_type to registered agents:<name> types, not general-purpose (2cd215c)
- stop check_storyhook miscounting an empty non-project story list (01a9d73)
- wire the project-story close step into execute/SKILL.md's own Complete checklist (8e7e88b)
- stop decompose's parent story from wedging execute forever (7b5a702)
- rewrite two dead id-first storyhook commands WS1 missed (19e08e2)
- trim wc -l padding before using fix-cycle count in a path (c09e24d)
- correct forge-{fix-archive,prechecks,step-exit}.bats SCRIPT paths (a87aee8)
- make crash-path auto-resume independent of Stop-hook ordering (6b3396a)
- stop execute from writing the terminal COMPLETION.md artifact (e2687f5)
- eliminate the review+validate deadlock, give every state an explicit dispatch (bd9075d)
- delegate /forge status state detection to forge-state.sh (55fa808)
- correct forge-state.sh's story JSON path and harden the state machine (5bf393d)
- parse UTC heartbeat timestamps as UTC on BSD date (d365299)
- stop hard-coding HP- story IDs in decompose SKILL.md's example (925e69b)
- stop routing storyhook state checks through a nonexistent MCP server (03e9534)
- omit --target when the release tag already exists (f015182)
- support a file-based notary keychain for headless deploys (656daae)

### Changed
- tier execute's reference loading and move router entry-guards on demand (F019, F026, F027) (2964ff0)
- fix decompose's step numbering and wire in mapping-scaffold + dedup pointers (30707d9)
- route 9 pipeline skills through forge-step-exit.sh (F020, F032, F088) (f3433b2)
- wire the new bin/ scripts into the loop, delete the prose it replaces (4699530)

### Documentation
- record agentics#33's re-scope from supervisor to instrumentation (10a2b2a)
- wire --record-transition and --transition-id into the router/step-exit protocol (agentics#33) (85f1bfe)
- reflect storyhook#10's resolution in the hardening roadmap/handoff (058383a)
- add hardening roadmap to CLAUDE.md and HANDOFF.md (da7800b)
- remove decompose from project-manager's roster row (8c213b7)
- document the read-back mechanism and defer F046 (7202392)
- flag F074 as out of scope for this repo's execution loop (5bec548)
- refresh config defaults, README, and management skill (90be0bd)
- dedupe Exit-section handoff content against step-handoff.md tables (F020) (160b6b3)
- dedupe deterministic-checks.md and team-roles.md against their sources (F024, F025) (25faabe)
- document the project story's lifecycle, wire in the close step (96ee74a)
- unify the execute handoff path on handoffs/handoff-execute.md (0f88946)
- rewrite execution-loop storyhook mutations to verb-first (9256ee3)
- rewrite decompose flow to the real story decompose --stdin (905cc9a)
- rewrite storyhook-contract.md to the real verb-first CLI (c525217)

### Testing
- add bash test suite and wire into make test (2681257)
- guard state.json writers against non-atomic regressions (agentics#33) (2b7ad5a)
- wire freshen's bats suite into make test (44661fb)
- wire hook-guard and greenlight bats suites into make test (a0b4b27)
- add mock-free bats suite covering the hardening fixes (4f31550)
- add bats coverage for the breaker dedup/reset-gating fixes (dac994b)
- add forge-agent-alignment-check regression guard (773bec5)
- add contract-check regression guard for storyhook CLI drift (F103) (fe54262)
- wire forge's bats suites into make test (787e35b)
- use correct io.mikey reverse-DNS in example bundle id (42ec99c)

_[manual]_

## [v2.23.2] - 2026-06-23

### Fixed
- L7 resolves annotated Symbol cells via the backticked identifier (b26a24c)

_[manual]_

## [v2.23.1] - 2026-06-23

### Fixed
- swap Delete into Install's exact rectangle on swipe (129411c)

### Testing
- cover the Install/Delete swap layout (67f60d3)

_[manual]_

## [v2.23.0] - 2026-06-22

### Added
- extend version sync to marketplace.json (b300f76)
- sync plugin.json versions from VERSION on bump (5f66754)
- publish a GitHub release on every macOS deploy (7dbd26f)
- add deployit-release GitHub release publisher (f5dbacf)
- swipe-to-delete, prominent names, shorter buttons (8116e0f)
- tree-sitter Swift helper (atlas-ts-helper) (267b197)
- edge.semantic relationship richness (1c9420c)
- add `judgment verify-set` — verify the prose delta (b1794fb)
- add `judgment prune` to drop orphaned cells (3e946ec)
- migrate-v1 + hardening + v2 release docs (1b96031)
- v2 protocols, cartographer-as-annotator, e2e flows (e0d130f)
- lint v2 — L7 join, L15, L16 + status divergence (da4be11)
- Ledger v2 + judgment diff (the update engine) (4ab245f)
- project — deterministic doc render (the JOIN) (63ddf10)
- Judgment Cache, orthogonal-hash keys, judge-plan, ingest (84fff35)
- resolve_edges engine + tree-sitter helper backend (4405dba)
- add `extract` Structure Index core (regex backend) (9eb6a8a)

### Fixed
- poll origin in test-cli-rm to fix post-push read race (23d1dcd)
- drop extraction noise found by the v2 dogfood (1d1003b)
- make cartographer output-medium-neutral (9bccd44)

### Changed
- retire v1 — ground command, structure-less ledger, design.md (1f787e7)

### Documentation
- cover marketplace.json in version sync, fix test path (bbca0c6)
- document plugin version sync in CLAUDE.md (d093c6b)
- document the macOS GitHub release flow (cf94b23)
- note v2 Projection architecture in the plugin table (4b1e626)
- add v2 Projection architecture design record (f17fc14)
- full codebase map (35 modules, cartographer/2) (2371f93)
- checkpoint — overview (17e6ecc)
- checkpoint — verified docs (ec70da7)
- checkpoint — verifier fix pass (7 docs) (1966667)
- checkpoint — remove re-partitioned orphans (b4cedef)
- checkpoint — module docs wave 5 (87710dc)
- checkpoint — module docs wave 4 (1f6efa6)
- checkpoint — module docs wave 3 (9932991)
- checkpoint — module docs wave 2 (30258eb)
- checkpoint — module docs wave 1 (3471142)

### Testing
- guard plugin.json version drift and cover the sync hook (8f26acc)

### Maintenance
- gitignore .council/ deliberation artifacts (d878b43)

_[manual]_

## [v2.22.0] - 2026-06-17

### Added
- wire the /atlas repair flow (dispatch, protocol, README) (948584a)
- add map-repairer agent for /atlas repair (c47f2e9)
- verify-cache, ledger finalize --except, repair branch op (6a3f1ce)

_[manual]_

## [v2.21.0] - 2026-06-17

### Added
- atlas lint L12/L13/L14 — dangling `references_modules`, out-of-grammar relationship edge verbs, over-length `read_when`/`summary` (67deab3)
- atlas `cartographer/2` — relationship-verb-selection guidance + `read_when` brevity. **Bumping the generator forces a full map regeneration in every repo on the next `/atlas update`.** (57bcddc)
- scoped `linguist-generated` gitattributes guidance + map commit-isolation convention (6d2e7bf)

### Fixed
- atlas config parser — quote-aware inline-comment stripping; a trailing `# comment` after a list item used to silently break excludes (67deab3)
- atlas lint L7 — accept fully-qualified `Type.member` / arg-labelled symbol names (dropped 138 false positives to 21 on a real map) (67deab3)

_[manual]_

## [v2.20.0] - 2026-06-16

### Added
- pin cartographers to Sonnet 1M; branch-isolate mapping (730ebe3)
- add `branch ensure` subcommand for isolated map runs (438505b)

_[manual]_

## [v2.19.0] - 2026-06-16

### Added
- macOS Sparkle auto-update + first-class presentation (09efaae)
- replace pull-to-refresh with a nav bar Refresh button (46fe916)

_[manual]_

## [v2.18.0] - 2026-06-12

### Added
- incremental-update CLI surface (9640bb2)
- add ledger set-verified and role-by-reference prompt assembly (cdb99b7)
- add full-map orchestration skill, protocols, and wiring CLI (b68d753)
- add cartographer and map-verifier agents with normative map format (c699900)
- add lint, derived INDEX rebuild, router, and session hook (26d15ba)
- add blob-SHA ledger, heartbeat lock, and staleness tiers (5be291d)
- add deterministic scan and partition core with test suite (7a3e4f5)
- scaffold plugin and register in marketplace (8e9df56)

### Fixed
- ground skips markdown prose; lint L6 skips non-citation paths (eda25cb)
- dogfood-driven fixes to INDEX layout, lint rules, and frontmatter round-trip (c5dfb17)
- make validate-agents.sh portable to macOS bash 3.2 (d810687)

### Documentation
- update map (6 docs — phase-7 hardening, README, handoff retirement) (69ab624)
- roadmap complete — all seven phases shipped; retire HANDOFF (dc00e9c)
- full README — quick start, ledger explainer, config, FAQ (1be4fae)
- edge-line length exemption + external-path citation rule (22e5896)
- add atlas to the _template pipeline enum (4d66cb8)
- regenerate plugins-hook-guard after conflict-marker corruption (eaa54c6)
- update map (6 docs — phase-6 incremental layer) (6c8b6fd)
- conflict recipe in README, design-record updates, phase 7 handoff (545be2b)
- replace update-protocol stub with the real incremental + verify protocol (4045ed9)
- re-baseline after roadmap/handoff commit (ac7dff0)
- mark phases 1-5 complete in roadmap, write handoff for 6-7 (65c6f5e)
- final re-baseline for the v1 map (f44d83c)
- drop self-referential docs scope from overview (0ce4ca4)
- encode dogfood protocol lessons — scope exclusion and init ordering (42cc6d0)
- re-baseline ledger after map and wiring commits (b9203a6)
- full codebase map (32 modules) (b1e1f9d)

### Testing
- edge-case sweep — degenerate repos, corruption, hostile config (2659973)
- e2e update-flow scenarios + index.lock retry coverage (343f6e4)

### Maintenance
- add root make test entrypoint covering plugin suites (fa41920)

_[manual]_

## [v2.17.0] - 2026-06-06

### Added
- cut agent tokens with single-call bump and deterministic recommend (14c528d)
- report the semver version in the web UI (5cd5fee)
- capture semver version + guard deploys with a bump (d621fb8)

### Fixed
- prevent context-window overflow on skill invocation (8b73a59)

### Documentation
- document semver awareness (2c468bf)

### Testing
- make the test suite portable to BSD/macOS (567da1b)

_[manual]_

## [v2.16.1] - 2026-05-25

### Fixed
- backend self-loop + verify-live counter (d3d1ed5)

_[manual]_

## [v2.16.0] - 2026-05-25

### Added
- /deployit redeploy + verify-live + stable plist paths (b076572)

_[manual]_

## [v2.15.0] - 2026-05-25

### Added
- pull-to-refresh, product grouping, history pages, auto-prune (aa80a1c)

_[manual]_

## [v2.14.0] - 2026-05-25

### Added
- harden member dispatch + abort path + triggering description (76948e1)

_[manual]_

## [v2.13.0] - 2026-05-24

### Added
- support single-app repo layout (xcodeproj + root project.yml) (6a84a8e)
- SKILL.md orchestrator (ee81b3f)
- url + status commands (77ea4cb)
- macOS .dmg packaging + optional notarization (c9d7610)
- visionos ExportOptions (1cef61f)
- push build entry to index + refresh local backend (ac00225)
- iOS archive + export + stage (c383611)
- metadata derivation from workspace + project.yml (663fe14)
- bootstrap creates state, config, launchd plist (6221db6)
- test runner discovering test-*.sh files (24e089b)
- backend POST /_internal/refresh (90d8990)
- per-build landing, manifest, and artifact endpoints (b2f454e)
- backend listing endpoint with git pull (1770a4a)
- backend skeleton with healthz (d3f28eb)
- CLI skeleton with subcommand stubs (6bed2b7)
- router shell (80a6556)
- plugin manifest + marketplace registration (cbff65e)

### Fixed
- schema-valid index entries; correct platform glob casing; harden subprocess error handling (3dfeb77)
- JSON errors from tailscale failure; absolute plugin-root symlink; surface launchctl status (e06992f)
- return 500 on render errors; harden traversal test; quiet healthz log (5b05185)
- emit JSON for argparse errors; align router shebang dirname (e4c7ce2)
- prevent circuit breaker from killing freshen auto-clear between forge phases (eaf6b5f)

### Documentation
- bootstrap + per-platform + troubleshooting references (494f3ca)

### Testing
- automated gc test (--keep, no-op, bare-fail) (273a959)

_[manual]_

## [v2.12.1] - 2026-04-08

_[force]_

## [v2.12.0] - 2026-04-08

_[force]_

## [v2.11.0] - 2026-04-08

### Maintenance
- track tool config (.storyhook, .semver, .planning) (fb4a49b)

_[manual]_

## [v2.10.0] - 2026-04-07

### Added
- detect incomplete work before starting new pipeline (cd75e83)

_[manual]_

## [v2.9.1] - 2026-04-06

### Fixed
- resolve freshen.sh path relative to script location (c781671)

_[manual]_

## [v2.9.0] - 2026-04-05

### Fixed
- prevent set -e abort on empty ls|head pipelines (988edef)

_[manual]_

## [v2.8.0] - 2026-04-05

### Added
- add hard rule prohibiting background agent spawning (bfefc53)

_[manual]_

## [v2.7.0] - 2026-04-04

### Added
- run investigation in foreground instead of background (21602a9)

_[manual]_

## [v2.6.0] - 2026-04-03

### Added
- extract deterministic plugin logic into scripts for token reduction (0723dd8)

_[manual]_

## [v2.5.0] - 2026-04-03

### Added
- add /forge resume command, pre-compute resume context in hooks (e1c9680)
- add enable/disable commands for troubleshooting (b9be83d)
- rename sentry plugin to greenlight (8c7bca6)

### Fixed
- distinguish ok/error in EXIT trap stderr output (896b6a2)
- add stderr output to prevent infinite stop-hook loop (4ade8d5)

### Changed
- Merge pull request #1 from mikeydotio/fix/freshen-stop-hook-stderr (8a9b47b)

_[manual]_

## [v2.4.0] - 2026-04-02

### Added
- add Python CLI to minimize LLM round trips (1c220f5)

_[manual]_

## [v2.3.0] - 2026-04-01

### Changed
- **Pilot plugin renamed to Forge** — the unified idea-to-deployment pipeline is now `/forge` with all artifacts in `.forge/`, commit prefixes as `forge(<step>):`, and freshen source `--source forge`; all 11 sub-skill names unchanged (c87bb57)

_[manual]_

## [v2.2.0] - 2026-04-01

### Added
- **Agents plugin** (`/agents`) — shared library of 27 research-backed agent definitions replacing per-plugin agent directories; 16 general-purpose agents (software-engineer, qa-engineer, security-researcher, software-architect, project-manager, technical-writer, copy-editor, skeptic, investigator, accessibility-engineer, performance-engineer, devops-engineer, api-designer, observability-engineer, data-engineer, lawyer), 3 platform-specific UX designers (CLI, web, mobile), and 8 pipeline-specific agents (generator, evaluator, reviewer, validator, triager, domain-researcher, evidence-collector, hypothesis-challenger)
- **11 net-new agents** — copy-editor (LLM-tell detection), skeptic (Socratic questioning), investigator (multi-hypothesis RCA), 3 UX designer variants (CLI/web/mobile), performance-engineer, devops-engineer, api-designer, observability-engineer, data-engineer, lawyer (OSS license compatibility)
- **Cross-plugin agent reference mechanism** — consuming plugins reference shared agents by path and layer pipeline-specific overrides via `agent-overrides/` directories
- **Agent design principles reference** — research synthesis from Anthropic's "Building Effective Agents", Agentailor's tool design principles, and multi-agent orchestration research
- **Agent validation script** (`validate-agents.sh`) — structural validation for frontmatter, tool/read-only consistency, naming, guardrails, and mandatory protocols
- **Tool design audit** (`tool-audit.md`) — audit of all plugin tools against 5 Agentailor principles with prioritized findings

### Changed
- **Pipeline agents rewritten with cross-pollination** — generator draws from Software Engineer (TDD) + Security Researcher (secure-by-default); evaluator draws from QA (edge cases) + Skeptic (debiasing); reviewer expanded to 8-dimensional analysis; validator enforces no-mock policy; triager uses 4-dimension decision framework
- **RCA consolidated from 5 to 2 pipeline agents** — code-archaeologist and systems-analyst absorbed into general-purpose Investigator; remediation-architect absorbed into Software Architect with RCA-specific override
- **Storyhook contract rewritten** — removed false "Commands That DO NOT Exist" section; added full MCP tool catalog with 16 tools; added Interface Selection Guide mapping operations to preferred interface (MCP vs CLI)
- **Decompose skill switched to batch operations** — uses `storyhook_decompose_spec` MCP tool (1 call) instead of sequential CLI story creation (60-80+ calls per plan)
- Pilot and RCA SKILL.md files updated to reference shared agent library paths
- CLAUDE.md updated with agents plugin in plugin table

### Removed
- `plugins/pilot/agents/` — 15 agent files replaced by shared library
- `plugins/rca/agents/` — 5 agent files replaced by shared library (3 consolidated into general-purpose agents)

_[manual]_

## [v2.1.1] - 2026-04-01

### Removed
- **Ideate plugin** — fully removed from marketplace and directory; all functionality lives in pilot (`fed674f`)

### Fixed
- Freshen plugin manifest `author` field must be an object, not a string — caused marketplace install failure (`39eba9d`)

_[manual]_

## [v2.1.0] - 2026-04-01

### Added
- **Unified pilot pipeline** — merged ideate and pilot into a single idea-to-deployment plugin with 11 pipeline skills (interrogate, research, design, plan, decompose, execute, review, validate, triage, document, deploy) orchestrated by a state-machine router (`69fa065`..`828d92b`)
- **3 new agents** — reviewer (static gap/defect analysis), validator (test hardening), triager (FIX/ESCALATE deliberation) (`d512d2d`)
- **FIX/ESCALATE triage loop** — after execution, review + validate run in parallel, then triage labels findings as FIX (auto-fix, max 3 cycles) or ESCALATE (user decides); `--yolo` mode fixes everything up to 10 cycles (`d512d2d`)
- **Step exit protocol** — every orchestrated step writes artifacts, handoff to `.pilot/handoffs/`, commits, and queues freshen for context clearing (`69fa065`)
- **Severity levels and report format** references — standardized Critical/Important/Useful finding structure with solution options and pros/cons (`d512d2d`)
- **Legacy migration detection** — pilot orchestrator detects `.planning/ideate/` artifacts and offers to migrate them to `.pilot/` (`828d92b`)
- **Post-document pause** — pipeline always pauses after documentation for user review before deployment; deploy never proceeds without explicit permission

### Changed
- Pilot artifacts now live in `.pilot/` (version-controlled handoffs, fix-cycle archives) instead of `.planning/pilot/`
- Handoffs moved from single `.pilot/handoff.md` to versioned `.pilot/handoffs/handoff-<step>.md` directory
- Session hooks updated to read/write from `.pilot/handoffs/` directory
- 12 agents migrated from ideate to pilot with namespace updates (15 total)
- 10 pilot reference docs updated with `.pilot/` path references
- 3 ideate references migrated to pilot (questioning, team-roles, step-handoff)
- CLAUDE.md updated for unified pipeline architecture

### Deprecated
- **Ideate plugin** (`/ideate`) — use `/pilot` instead; deprecation notices added to SKILL.md and README.md

_[manual]_

## [v2.0.0] - 2026-03-31

### Breaking
- **Ideate phases now clear context between each step** — the orchestrator stops after each phase and re-invokes with fresh context via the freshen plugin, changing the user-facing flow from a single continuous session to a multi-session progression
- **Pilot `max_stories_per_session` default changed from 5 to 1** — each story gets a fresh context window; `max_sessions` raised from 10 to 50 to compensate

### Added
- **Freshen plugin** (`/freshen`) — portable automatic context clearing via tmux send-keys; any plugin can register a post-clear re-invocation signal, and the Stop + SessionStart(clear) hooks handle `/clear` and command dispatch automatically
- **Phase Transition Protocol** for ideate — each phase writes a handoff document (`.planning/handoff-phase-N.md`), commits artifacts, queues a freshen signal, and stops
- **Phase handoff specification** (`references/phase-handoff.md`) — defines handoff format for each phase transition with phase-specific content requirements
- **Cold-Start Essentials** for pilot handoffs — patterns established, micro-decisions, code landmarks, and test state are now mandatory sections
- **Incremental handoff writes** in pilot execution loop — handoff.md updates after every completed story, not just at pause
- **Context Validation step** (6a) in pilot recovery — cross-checks handoff claims against disk state before resuming
- **Missing-handoff protocol** — both ideate and pilot now pause and ask the user what to do via AskUserQuestion when a handoff document is missing, rather than silently continuing with degraded context

### Changed
- Ideate **Pilot Invitation** replaces Phase 4.5 — now a resumption path (not an inline gate) that activates when PLAN.md is found after context clear
- Pilot handoff elevated from "best-effort" to **primary context source** across recovery-protocol.md, handoff-format.md, and SKILL.md
- Fixed broken reference in ideate SKILL.md (`work-handoff.md` → `pilot-handoff.md`)
- Fixed typo in ideate resumption protocol ("pilot" → "ideate")

_[manual]_

## [v1.5.0] - 2026-03-30

### Added
- **Greenlight plugin** (`/greenlight`) — intelligent PreToolUse safety hook that intercepts dangerous commands (destructive git operations, broad file deletions, production deployments) and enforces confirmation or blocking policies (1d9d4ab)

_[manual]_

## [v1.4.0] - 2026-03-30

### Removed
- **Memory plugin** (`/memory`) — collides with built-in Claude Code command; memory functionality will move to the memlayer repo as its own plugin (`a64050e`)

### Changed
- Cleaned up pilot plugin references to memory (execution loop, handoff format, completion sequence) (`a64050e`)

_[manual]_

## [v1.3.0] - 2026-03-30

### Added
- **Pilot plugin** (`/pilot`) — autonomous execution harness with generator-evaluator loop, story decomposition, session locking, auto-resume via crontab, canary mode, and architectural drift detection (`c6cab14`)
- **Memory plugin** (`/memory`) — graph memory interface with local JSONL cache, entity/relation storage, two-tier recall (local + memlayer), and scale-aware warnings (`c6cab14`)
- **Ideate Phase 4.5** — conductor handoff gate offering autonomous execution via `/pilot` after plan approval (`c6cab14`)
- Test infrastructure using bats-core with 15 tests covering state machine, locking, and plan mapping (`c6cab14`)

### Changed
- Renamed project from handy-plugins to agentic-workflows; tracked `.planning/` directory (`ce06592`)
- Updated marketplace to register 5 plugins (ideate, rca, semver, pilot, memory) (`c6cab14`)

_[manual]_

## [v1.2.0] - 2026-03-29

### Added
- Conductor autonomous workflow guide — end-to-end documentation for plan-to-completion autonomous execution (`5434010`)

### Fixed
- Session-start hook now uses `additionalContext` instead of `systemMessage` for proper context injection (`2d47db8`)

### Changed
- Track tool config files (`.storyhook`, `.semver`) and gitignore `.planning/` directory (`5ec366e`)

_[manual]_

## [v1.1.0] - 2026-03-28

### Added
- Git-root enforcement — semver tracking now requires `.semver/` to be at the git root; subprojects must use separate git repos
- Configurable git tagging — new `git_tagging` config option (default: true) to enable/disable tag creation on bump
- `--no-tags` flag for `tracking start` to initialize with tagging disabled

### Changed
- Version-commit is now the primary anchor instead of git tags — `semver current` and bump pre-checks use the last VERSION-changing commit, not the last tag
- Session-start hook output simplified to `<Project> version: <version>` instead of verbose status line
- Validation checks 3, 4, 6 (tag-related) now skip gracefully when `git_tagging: false`
- Post-push hook messages reference "last version change" instead of "last tag"

_[manual]_

## [v1.0.0] - 2026-03-28

### Added
- Initial release of the Agentic Workflows marketplace
- Ideate plugin — idea interrogation, design, planning, and execution with cross-functional agent teams
- RCA plugin — root cause analysis with evidence collection, hypothesis testing, and remediation planning
- Semver plugin — semantic versioning lifecycle management with auto-bump hooks, changelog generation, and sync validation

_[manual]_
