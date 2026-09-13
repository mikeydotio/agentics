#!/usr/bin/env bats
# Tests for forge-contract-check.sh — the F103 regression guard that keeps
# forge's storyhook-facing docs/skills from silently drifting back to a dead
# id-first CLI grammar or a fictional relationship vocabulary.
#
# Drives the real `story` CLI's --help / help relate output (never mocked —
# see CLAUDE.md). Requires `story` on PATH; the "CLI missing" case
# deliberately empties PATH to exercise the graceful-degradation path.

SCRIPT="$BATS_TEST_DIRNAME/forge-contract-check.sh"
FORGE_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  FIXTURE_DIR="$(mktemp -d)"
  export FIXTURE_DIR
  mkdir -p "$FIXTURE_DIR/references" "$FIXTURE_DIR/skills/execute"
}

teardown() {
  if [[ -n "${FIXTURE_DIR:-}" && -d "$FIXTURE_DIR" ]]; then
    rm -rf "$FIXTURE_DIR"
  fi
}

jq_field() {
  echo "$output" | jq -r "$1"
}

# --- story CLI unavailable ---

@test "contract-check: ok is false when story CLI is not on PATH" {
  PATH="/usr/bin:/bin" run bash "$SCRIPT" "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.error')" = "story_cli_missing" ]
}

# --- Real committed docs: the actual regression guard ---

@test "contract-check: real committed forge docs are clean" {
  run bash "$SCRIPT" "$FORGE_ROOT"
  echo "$output" >&2
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
  [ "$(jq_field '.relation_violations | length')" -eq 0 ]
}

@test "contract-check: scans a nonzero number of real forge files" {
  run bash "$SCRIPT" "$FORGE_ROOT"
  # A FLOOR, not just non-emptiness. The vacuous path is not omitting the
  # argument — DOCS_ROOT defaults to the plugin root, so a bare run scans the
  # whole corpus. It is passing the REPO root: references/ and skills/ do not
  # exist there, so the script returns files_scanned:[] with contract_ok true.
  # A floor reds on that; `> 0` also would, but only a floor reds on a
  # file-selection glob that quietly stops matching most of the corpus.
  [ "$(jq_field '.files_scanned | length')" -ge 25 ]
}

@test "contract-check: real verb list includes the documented verbs, excludes nothing forged" {
  run bash "$SCRIPT" "$FORGE_ROOT"
  for v in move set comment prioritize block unblock relate unrelate next list decompose graph new; do
    echo "$output" | jq -e --arg v "$v" '.real_verbs | index($v) != null' >/dev/null
  done
}

@test "contract-check: real relationship vocabulary is exactly the 8 documented relations" {
  run bash "$SCRIPT" "$FORGE_ROOT"
  [ "$(jq_field '.real_relations | length')" -eq 8 ]
  for r in relates-to blocks blocked-by parent-of child-of duplicate-of obviates obviated-by; do
    echo "$output" | jq -e --arg r "$r" '.real_relations | index($r) != null' >/dev/null
  done
}

# --- Drift detection: reintroduce a dead id-first command ---

@test "contract-check: catches a reintroduced dead id-first command" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story HP-1 is done
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.verb_violations | length')" -eq 1 ]
  [ "$(jq_field '.verb_violations[0].verb')" = "HP-1" ]
  [ "$(jq_field '.verb_violations[0].file')" = "references/storyhook-contract.md" ]
  [ "$(jq_field '.verb_violations[0].line')" -eq 4 ]
}

@test "contract-check: catches a dead relationship type" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story relate HP-1 precedes HP-2
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
  [ "$(jq_field '.relation_violations | length')" -eq 1 ]
  [ "$(jq_field '.relation_violations[0].relation')" = "precedes" ]
}

@test "contract-check: scans skills/*/SKILL.md as well as references/*.md" {
  cat > "$FIXTURE_DIR/skills/execute/SKILL.md" <<'EOF'
---
name: execute
---

```bash
story HP-9 is done
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.verb_violations[0].file')" = "skills/execute/SKILL.md" ]
}

# --- No false positives ---

@test "contract-check: accepts every real verb/relationship the docs use" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story new "Title"
story move HP-1 done
story comment HP-1 "note"
story prioritize HP-1 high
story relate HP-1 blocks HP-2
story relate HP-2 blocked-by HP-1
story decompose --stdin --json < PLAN.md
story next --json
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
  [ "$(jq_field '.relation_violations | length')" -eq 0 ]
}

@test "contract-check: ignores plain-English 'story' prose inside fenced pseudocode" {
  cat > "$FIXTURE_DIR/references/execution-loop.md" <<'EOF'
# Fixture

```
loop:
  1. Pick next story (story next --json)
  stories_attempted += 1 (if story reached evaluation, regardless of pass/fail)
  If story reached done:
    do the thing
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
}

@test "contract-check: ignores bash comment lines inside fenced blocks" {
  cat > "$FIXTURE_DIR/references/story-decomposition.md" <<'EOF'
# Fixture

```bash
# Preview first — verify story count, wave structure, relationships:
story decompose --stdin --dry-run < PLAN.md
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  [ "$(jq_field '.contract_ok')" = "true" ]
}

# --- Inline-backtick extraction (AGE-24) ---
#
# forge documents most of its storyhook surface as inline single-backtick
# prose in tables and paragraphs rather than fenced blocks: at v2.39.1 all
# eight `story project ` occurrences in the scanned corpus sat at fence depth
# 0, so a green result said nothing about the majority of the contract — the
# guard would have caught NONE of storyhook 2.0's `project init` ->
# `project new` rename even with AGE-17's subcommand check landed.
#
# What is checked outside a fence is the backtick SPAN, never the line it sits
# on. That distinction is load-bearing: the span IS the invocation, so the
# surrounding English can neither be mistaken for one nor displace a token.

@test "contract-check: inline single-backtick template signatures still pass" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

| Dependency between stories | `story relate <a> <relationship> <b>` | Only 8 relations exist |
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  # Since AGE-24 this span IS scanned; it passes because `<relationship>` is a
  # placeholder wildcard, not because the line is skipped. The next test is the
  # effect oracle that tells those two reasons apart.
  [ "$(jq_field '.contract_ok')" = "true" ]
}

@test "contract-check: catches an inline-backtick invocation outside any fence" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

| Create a project | `story project init --prefix AGE` | Seeds the state vocabulary |
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.subcommand_violations | length')" -eq 1 ]
  [ "$(jq_field '.subcommand_violations[0].verb')" = "project" ]
  [ "$(jq_field '.subcommand_violations[0].subcommand')" = "init" ]
  [ "$(jq_field '.subcommand_violations[0].line')" -eq 3 ]
  # The reported command is the SPAN alone — proof the extractor read the span
  # and not the table row around it.
  [ "$(jq_field '.subcommand_violations[0].command')" = "story project init --prefix AGE" ]
}

# Failure oracle for the signature test above: a placeholder wildcard must not
# swallow a CONCRETE dead form sharing the same line. Without this, skipping
# inline spans entirely would satisfy the signature test perfectly.
@test "contract-check: each backtick span on a line is checked independently" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

Use `story relate <a> <relationship> <b>`, never `story relate HP-1 precedes HP-2`.
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.relation_violations | length')" -eq 1 ]
  [ "$(jq_field '.relation_violations[0].relation')" = "precedes" ]
  [ "$(jq_field '.relation_violations[0].command')" = "story relate HP-1 precedes HP-2" ]
}

# The class the span boundary exists to exclude: English that reads as an
# invocation once a shell separator precedes the word "story". Scanning the
# whole unfenced line instead of its spans produced 28 of these on the real
# corpus, every one a false positive.
@test "contract-check: unfenced English prose is never treated as an invocation" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

There is no data file to edit; story data lives in a SQLite store outside the repo.
Prefer letting `story decompose --stdin` create these edges automatically.
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
}

# --- Subcommand drift detection (AGE-17) ---
#
# The verb guard used to validate only the FIRST token after `story`, so
# `story project init` checked out as the real verb `project` and passed —
# which is precisely how storyhook 2.0's `project init` -> `project new`
# rename reached main unseen. These tests pin the two-token check.

@test "contract-check: catches the historical 'story project init' rename" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story project init --prefix AGE
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.subcommand_violations | length')" -eq 1 ]
  [ "$(jq_field '.subcommand_violations[0].verb')" = "project" ]
  [ "$(jq_field '.subcommand_violations[0].subcommand')" = "init" ]
  [ "$(jq_field '.subcommand_violations[0].file')" = "references/storyhook-contract.md" ]
  [ "$(jq_field '.subcommand_violations[0].line')" -eq 4 ]
  # `project` IS a real verb — this must NOT be reported as a verb violation.
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
}

@test "contract-check: catches an invented subcommand (failure oracle)" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story project bogus --prefix AGE
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.subcommand_violations[0].subcommand')" = "bogus" ]
}

@test "contract-check: catches an invented subcommand under a compact-alternation verb" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story hooks nonexistent
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.subcommand_violations[0].verb')" = "hooks" ]
  [ "$(jq_field '.subcommand_violations[0].subcommand')" = "nonexistent" ]
}

# Effect oracle (the AGE-16 lock): assert the derivation ACTUALLY RAN and
# consulted BOTH ground-truth sources, rather than defaulting to something
# that trivially satisfies the failure assertions above.
#
#   - `web status` appears ONLY in `story help web`, never in `story --help`.
#   - `type add`   appears ONLY in `story --help`; `story help type` does not exist.
# No single-source implementation can satisfy both at once.
@test "contract-check: real_subcommands proves both help sources were consulted" {
  run bash "$SCRIPT" "$FORGE_ROOT"
  echo "$output" >&2
  # per-verb help only
  echo "$output" | jq -e '.real_subcommands.web | index("status") != null' >/dev/null
  # global --help only
  echo "$output" | jq -e '.real_subcommands.type | index("add") != null' >/dev/null
  # a verb that takes no subcommands must NOT be enforced at all
  echo "$output" | jq -e '.real_subcommands | has("tui") | not' >/dev/null
  # the dead verb form must be absent from the live vocabulary
  echo "$output" | jq -e '.real_subcommands.project | index("init") == null' >/dev/null
  echo "$output" | jq -e '.real_subcommands.project | index("new") != null' >/dev/null
}

@test "contract-check: real_subcommands covers the known subcommand-bearing verbs" {
  run bash "$SCRIPT" "$FORGE_ROOT"
  # 11 today (project web member state store phase hooks scaffold plugin type epic),
  # and `story --help`'s global block alone lists all eleven — it is the enforcement
  # FLOOR that per-verb help only adds to. So dropping below 11 cannot be per-verb
  # parse degradation; it means the global usage block itself changed, which is
  # exactly the drift this guard exists to report. Pin it rather than leave slack.
  [ "$(jq_field '.real_subcommands | length')" -ge 11 ]
  for v in project state type hooks phase web; do
    echo "$output" | jq -e --arg v "$v" '.real_subcommands | has($v)' >/dev/null
  done
}

# --- Subcommand check: no false positives ---

@test "contract-check: accepts the two-token forms the real docs use" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story type add bug --description "A defect"
story state add review --super OPEN
story project new --prefix AGE
story hooks install
story phase list
story web status
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.subcommand_violations | length')" -eq 0 ]
}

@test "contract-check: never flags position 2 of a verb that takes free-form arguments" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story move HP-1 done
story new "Some title"
story comment HP-1 "note"
story summary
story tui
story delete HP-1 "reason"
story show HP-1
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.subcommand_violations | length')" -eq 0 ]
}

@test "contract-check: treats a placeholder in the subcommand slot as a wildcard" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story project <subcommand>
story state [add|remove]
story hooks --help
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.subcommand_violations | length')" -eq 0 ]
}

@test "contract-check: treats a placeholder in the relation slot as a wildcard" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story relate <a> <relationship> <b>
story unrelate <a> <relationship> <b>
story relate [from] [rel] [to]
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.relation_violations | length')" -eq 0 ]
}

# Failure oracle for the exemption above: the wildcard must not swallow a
# CONCRETE dead relation sitting in the same slot. Without this, `relation=""`
# for everything would satisfy the test above perfectly.
@test "contract-check: the relation wildcard still catches a concrete dead relation" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story relate <a> <relationship> <b>
story relate HP-1 precedes HP-2
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.relation_violations | length')" -eq 1 ]
  [ "$(jq_field '.relation_violations[0].relation')" = "precedes" ]
}

# --- Negative-example suppression (AGE-32) ---
#
# A doc must be able to name a dead form IN ORDER TO DENY IT without the guard
# flagging that correct sentence. The marker is bound to the reported TOKEN, so
# it is an executable assertion that the named form is still dead — not a
# blanket line-ignore. Every marker that suppresses nothing is itself an error,
# found by a WHOLE-FILE scan so a marker on an unscanned line fails loud rather
# than sitting as a silent no-op.

@test "contract-check: a token-bound marker suppresses the violation it names" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story HP-N is done <!-- contract-check: expect-dead HP-N -- id-first form does not exist -->
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
  # Effect oracle: proves the line was SCANNED and deliberately suppressed,
  # not merely never read (the AGE-27 failure shape).
  [ "$(jq_field '.suppressions | length')" -eq 1 ]
  [ "$(jq_field '.suppressions[0].token')" = "HP-N" ]
  [ "$(jq_field '.suppressions[0].line')" -eq 4 ]
  [ "$(jq_field '.suppressions[0].reason')" = "id-first form does not exist" ]
  [ "$(jq_field '.stale_suppressions | length')" -eq 0 ]
}

@test "contract-check: a marker naming a DIFFERENT token does not suppress the violation" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story project init <!-- contract-check: expect-dead HP-N -- unrelated dead form -->
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "false" ]
  # The real drift is still reported — the marker cannot shield a same-line substitution.
  [ "$(jq_field '.subcommand_violations | length')" -eq 1 ]
  [ "$(jq_field '.subcommand_violations[0].subcommand')" = "init" ]
  # ...and the marker that shielded nothing is itself an error.
  [ "$(jq_field '.stale_suppressions | length')" -eq 1 ]
  [ "$(jq_field '.stale_suppressions[0].kind')" = "token_mismatch" ]
  [ "$(jq_field '.suppressions | length')" -eq 0 ]
  # The marker text must not leak into the reported command.
  [ "$(jq_field '.subcommand_violations[0].command')" = "story project init" ]
}

@test "contract-check: a marker on a form that is REAL is a stale suppression" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story project new --prefix AGE <!-- contract-check: expect-dead new -- this form is alive -->
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.stale_suppressions | length')" -eq 1 ]
  [ "$(jq_field '.stale_suppressions[0].kind')" = "form_is_valid" ]
  [ "$(jq_field '.stale_suppressions[0].token')" = "new" ]
}

@test "contract-check: a marker on a line the extractor never reads is a stale suppression" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

There is no id-first form: story HP-N is done does not exist. <!-- contract-check: expect-dead HP-N -- denied in prose -->
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Since AGE-24 the unread region is un-backticked prose: this author denied
  # the form but never put it in a span, so nothing reaches the checker. The
  # marker must say so loudly rather than pass as a silent no-op.
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.stale_suppressions | length')" -eq 1 ]
  [ "$(jq_field '.stale_suppressions[0].kind')" = "not_scanned" ]
}

@test "contract-check: a marker with no reason is malformed and suppresses nothing" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story HP-N is done <!-- contract-check: expect-dead HP-N -->
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.verb_violations | length')" -eq 1 ]
  [ "$(jq_field '.suppressions | length')" -eq 0 ]
  [ "$(jq_field '.stale_suppressions | length')" -eq 1 ]
  [ "$(jq_field '.stale_suppressions[0].kind')" = "malformed" ]
}

@test "contract-check: a placeholder-token marker is a signature, not a suppression" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

Write `<!-- contract-check: expect-dead <token> -- why it is dead -->` to deny a form.

```bash
story next --json
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Documenting the convention must not self-apply.
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.suppressions | length')" -eq 0 ]
  [ "$(jq_field '.stale_suppressions | length')" -eq 0 ]
}

@test "contract-check: the marker binds to the subcommand and relation slots too" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story project init <!-- contract-check: expect-dead init -- renamed to `new` in storyhook 2.0 -->
story relate HP-1 precedes HP-2 <!-- contract-check: expect-dead precedes -- never existed -->
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.subcommand_violations | length')" -eq 0 ]
  [ "$(jq_field '.relation_violations | length')" -eq 0 ]
  [ "$(jq_field '.suppressions | length')" -eq 2 ]
}

@test "contract-check: the real corpus carries exactly one suppression and none stale" {
  run bash "$SCRIPT" "$FORGE_ROOT"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.stale_suppressions | length')" -eq 0 ]
  # references/storyhook-contract.md names the dead id-first form in order to
  # deny it — the single undecidable site the inline widening (AGE-24) exposed.
  # Pinning the count keeps the escape hatch from spreading unnoticed: a second
  # suppression is a deliberate decision, not a ride-along.
  #
  # The second one IS such a decision (AGE-31). The same sentence now denies the
  # TEMPLATE spelling `story <id> is done` as well as the concrete `HP-N` one,
  # which makes this a LIVE tripwire on the real corpus rather than only in
  # fixtures: revert either half of AGE-31 and this test reds. Reverting the
  # widening leaves the `<id>` marker suppressing nothing; reverting the marker
  # repair leaves the `<id>` violation unsuppressed.
  [ "$(jq_field '.suppressions | length')" -eq 2 ]
  [ "$(jq_field '[.suppressions[].file] | unique | join(",")')" = "references/storyhook-contract.md" ]
  [ "$(jq_field '[.suppressions[].token] | sort | join(",")')" = "<id>,HP-N" ]
}

# --- Placeholder verbs (AGE-31) ---
#
# The verb slot admits angle placeholders, and an angle placeholder there is a
# VIOLATION rather than a wildcard — the inverse of the subcommand and relation
# slots. The asymmetry is deliberate and load-bearing: position 2's legal set is
# sometimes genuinely unknowable (an OPEN verb takes free-form arguments there),
# so `story project <subcommand>` is a true statement; position 1's legal set is
# always the derived verb list, never free-form, so `story <id> is done` asserts
# a grammar that does not exist. That is precisely the id-first drift F103 was
# built to kill, in the spelling documentation actually uses.

@test "contract-check: a placeholder verb is caught alongside its concrete spelling" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story <id> is done
story HP-12 is done
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "false" ]
  # Both spellings, one test: an implementation that satisfies this by
  # disabling the verb check wholesale loses HP-12 and fails here.
  [ "$(jq_field '.verb_violations | length')" -eq 2 ]
  [ "$(jq_field '[.verb_violations[].verb] | sort | join(",")')" = "<id>,HP-12" ]
  [ "$(jq_field '.verb_violations[0].line')" -eq 4 ]
  [ "$(jq_field '.verb_violations[1].line')" -eq 5 ]
}

@test "contract-check: a placeholder verb is caught in an inline span too" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

Mark a story finished with `story <id> is done` when the work lands.
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.verb_violations | length')" -eq 1 ]
  [ "$(jq_field '.verb_violations[0].verb')" = "<id>" ]
  # Effect oracle for AGE-24's unit rule: outside a fence the SPAN is handed to
  # the checker, so the reported command is the span alone — never the sentence.
  [ "$(jq_field '.verb_violations[0].command')" = "story <id> is done" ]
}

@test "contract-check: flags and shell variables in the verb slot stay clean" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story --help
story -h
story $verb list
story ${VERB} list
story help <command>
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # `story --help` is the invocation this very script executes to derive its
  # vocabulary. Flagging it would red the gate on a doc documenting the guard's
  # own ground truth. Pinning it here makes a future any-token widening red THIS
  # test loudly instead of reding the pre-push gate on someone else's document.
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
}

@test "contract-check: a placeholder naming the verb slot is a wildcard, not a violation" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

The guard reports any `story <verb> ...` invocation the live CLI would reject.
Every `story <VERB> --json` form is machine-readable, and `story <the-verb> x`,
`story <sub-command> y`, `story <cmd-name> z` and `story <Sub_Command> w` all
name the slot itself.
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
}

@test "contract-check: entity placeholders are flagged even when they look like words" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```bash
story <transaction> is done
story <redaction> is done
story <compaction> is done
story <verbatim> is done
story <verbose> is done
story <story-id> is done
story <target> is done
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # The rejected half of the segment table. These are the tokens a SUBSTRING
  # rule silently exempts — `action` inside `<transaction>`, `verb` inside
  # `<verbatim>` — every one a false negative in the direction this guard
  # cannot afford. Equality-per-segment is what keeps them visible.
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.verb_violations | length')" -eq 7 ]
}

@test "contract-check: one line, one wildcard and one violation, only the violation reported" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

Use `story <verb> --json`, never `story <id> is done`.
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Failure oracle for the wildcard rule. Skipping every angle placeholder
  # satisfies the wildcard test above perfectly; only this one can tell
  # "exempted the wildcard" from "stopped checking placeholders".
  [ "$(jq_field '.verb_violations | length')" -eq 1 ]
  [ "$(jq_field '.verb_violations[0].verb')" = "<id>" ]
}

@test "contract-check: a marker suppresses a placeholder-token violation it names" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

There is no id-first form (`story <id> is done` does not exist). <!-- contract-check: expect-dead <id> -- the id-first grammar this sentence exists to deny -->
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
  # Assert the SUPPRESSION, not merely the absence of a violation — that is what
  # distinguishes "deliberately denied" from "never scanned" (the vacuous-green
  # shape AGE-24 and AGE-27 both exist to catch).
  [ "$(jq_field '.suppressions | length')" -eq 1 ]
  [ "$(jq_field '.suppressions[0].token')" = "<id>" ]
  [ -n "$(jq_field '.suppressions[0].reason')" ]
  [ "$(jq_field '.stale_suppressions | length')" -eq 0 ]
}

@test "contract-check: a marker naming a different placeholder does not suppress" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

There is no id-first form (`story <id> is done` does not exist). <!-- contract-check: expect-dead <ident> -- names the wrong token -->
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Failure oracle for the suppression above: without this, "always suppress a
  # placeholder" passes that test perfectly. The hatch stayed TOKEN-bound.
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.verb_violations | length')" -eq 1 ]
  [ "$(jq_field '.suppressions | length')" -eq 0 ]
}

@test "contract-check: the AGE-11 site in the committed ADR stays clean" {
  # docs/decisions/forge-hardening.md describes this guard using the very
  # spelling the guard now inspects, inside the ADR whose next paragraph reads
  # "A guard you can satisfy by deleting true sentences is the wrong guard."
  # It is not in the scan set today; AGE-30 is the change that would pull it in.
  # Committing its text as a fixture makes the confirmed site a test, not a memory.
  local adr="$FORGE_ROOT/../../docs/decisions/forge-hardening.md"
  [ -f "$adr" ] || skip "ADR not present in this checkout"
  sed -n '62,80p' "$adr" > "$FIXTURE_DIR/references/storyhook-contract.md"
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
}

@test "contract-check: a quoted convention example does not become a stale suppression" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

Annotate the denied line, e.g. `<!-- contract-check: expect-dead <id> -- why it is dead -->`.
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # AGE-37 LOCK. collect_markers cannot yet tell an APPLIED marker from a QUOTED
  # one, so narrowing the placeholder exemption in classify_stale_markers would
  # extend AGE-37's existing defect class to placeholder tokens and red the
  # pre-push gate on a correct document. This asserts the ordering: anyone who
  # narrows it before AGE-37 lands fails here immediately.
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.stale_suppressions | length')" -eq 0 ]
}

@test "contract-check: every marker in the real corpus is accounted for" {
  run bash "$SCRIPT" "$FORGE_ROOT"
  echo "$output" >&2
  local scanned markers accounted
  scanned="$(jq_field '.files_scanned[]')"
  [ -n "$scanned" ]
  # Count applied markers, excluding the literal `<token>` convention signature.
  markers="$(printf '%s\n' "$scanned" | xargs grep -ho 'contract-check: expect-dead [^ ]*' \
              | grep -cv 'expect-dead <token>' || true)"
  accounted=$(( $(jq_field '.suppressions | length') + $(jq_field '.stale_suppressions | length') ))
  # The invariant keeping the escape hatch honest: a marker either suppresses
  # something or is reported stale. Never silently nothing. This holds it from
  # OUTSIDE the script, so it costs nothing and cannot red the gate on the
  # AGE-37 class the way narrowing classify_stale_markers would.
  [ "$markers" -eq "$accounted" ]
}

# --- Fence structure (AGE-29) ---
#
# The detector is a run-length fence RECOGNISER, not a 1-bit toggle. It exists
# because the toggle could not represent fenced-block structure, and every way
# of failing to represent it lands on the same consequence: a line's extraction
# unit flips between LINE and SPAN, and a whole-line-scanned English sentence
# reads as an invocation (AGE-24 measured 28 such false positives corpus-wide).
#
# The asymmetry that drives the closer rule is CommonMark's, not ours: a list
# marker is CONTAINER syntax. It is legal before an OPENER — which is why
# `4. ```bash` at skills/execute/SKILL.md:172 is a real fence — and never legal
# before a CLOSER. A detector that accepts a marker in both positions
# desynchronises the moment a document quotes a list fence, which is exactly
# what a doc teaching markdown does.
#
# Each test below names the mutation it exists to catch. Every one was run.

@test "contract-check: a fence opened on a list-marker line is scanned, and the prose after it is not" {
  cat > "$FIXTURE_DIR/references/step-handoff.md" <<'EOF'
# Fixture

4. ```bash
   story bogusverb HP-1
   ```
5. Each story (story metadata lives in the store) is tracked by `story list`.
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '.files_scanned | length')" -eq 1 ]
  [ "$(jq_field '.contract_ok')" = "false" ]
  # Bidirectional in one document: the fenced body must be REACHED, and the
  # prose after the block must stay span-scanned. A detector anchored at column
  # 0 reports nothing; one that matches the closer but not the opener reports
  # `metadata` at line 6 — a true English sentence — and still misses this.
  [ "$(jq_field '.verb_violations | length')" -eq 1 ]
  [ "$(jq_field '.verb_violations[0].verb')" = "bogusverb" ]
  [ "$(jq_field '.verb_violations[0].line')" -eq 4 ]
}

@test "contract-check: a whitespace-indented fence body is scanned as a line" {
  cat > "$FIXTURE_DIR/references/step-handoff.md" <<'EOF'
# Fixture

1. Claim the story:
   ```bash
   story bogusverb HP-1
   ```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # AGE-29's filed spelling, and the corpus majority: 30 indented markers across
  # 8 of 29 files. Pinned separately from the marker-line case so a regression is
  # attributable to the right half.
  [ "$(jq_field '.verb_violations | length')" -eq 1 ]
  [ "$(jq_field '.verb_violations[0].verb')" = "bogusverb" ]
}

@test "contract-check: a list fence quoted inside a fenced block is content, not a closer" {
  cat > "$FIXTURE_DIR/references/step-handoff.md" <<'EOF'
# Fixture

```markdown
- ```js
```

Each story (story metadata lives in the store) is tracked by `story list`.
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # The document that decided AGE-29. A regex that accepts a list marker before
  # a CLOSER treats `- ```js` as the end of the block, inverts depth, and reds
  # the gate on the sentence at line 7. Nothing lexical distinguishes `- ```js`
  # here from the legal opener `4. ```bash` above — only fence depth does, which
  # is why no regex-only detector can pass both of these tests.
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
}

@test "contract-check: a shorter marker cannot close a longer fence" {
  cat > "$FIXTURE_DIR/references/step-handoff.md" <<'EOF'
# Fixture

````markdown
Open a fenced block by writing:

```bash
````

Recovery; story data lives in a SQLite store.
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Reds under the pre-AGE-29 detector too: this is a defect the shipped guard
  # already had (filed as AGE-41), not one AGE-29 introduced. `;` is a shell
  # separator, so the trailing sentence violates the moment it is scanned whole.
  # Mutation: drop `run >= flen`, or hardcode flen=3.
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
}

@test "contract-check: a bare marker carrying a list marker is not a closer" {
  cat > "$FIXTURE_DIR/references/step-handoff.md" <<'EOF'
# Fixture

```markdown
- ```
```

Each story (story metadata lives in the store) is tracked by `story list`.
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # The `!marked` half of the closer rule. Without it a BARE marker with a list
  # prefix closes the block and produces the identical false positive this
  # detector exists to prevent — the defect was present in the first draft of
  # the run-length detector and is caught by nothing else in this file.
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
}

@test "contract-check: a marker carrying an info string is not a closer" {
  cat > "$FIXTURE_DIR/references/step-handoff.md" <<'EOF'
# Fixture

````markdown
````js
const x = 1;
````

Each story (story metadata lives in the store) is tracked by `story list`.
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # The `bare == ""` half of the closer rule, isolated. CommonMark: a closing
  # fence may not carry an info string. The fences here are equal length and
  # unmarked, so neither `run >= flen` nor `!marked` rejects `````js` — this is
  # the only shape in which that condition is load-bearing, which is why the
  # obvious antiB fixture does NOT pin it (mutation testing caught that: dropping
  # `bare == ""` reded nothing until this test existed).
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
}

@test "contract-check: a CRLF document does not latch the fence open" {
  printf '# Fixture\r\n\r\n1. ```bash\r\n   story bogusverb HP-1\r\n   ```\r\n\r\nEach story (story metadata lives in the store) is tracked.\r\n' \
    > "$FIXTURE_DIR/references/step-handoff.md"
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # A CRLF closer is "```\r". Matching the info string against [ \t] rather than
  # [[:space:]] leaves \r behind, the closer is rejected, depth latches to EOF,
  # and the trailing prose is whole-line scanned — an EXTRA `metadata` violation
  # on top of the real one. Mutation: narrow [[:space:]] back to [ \t].
  [ "$(jq_field '.verb_violations | length')" -eq 1 ]
  [ "$(jq_field '.verb_violations[0].verb')" = "bogusverb" ]
}

@test "contract-check: fence-shaped content inside a fence is still scanned" {
  cat > "$FIXTURE_DIR/references/step-handoff.md" <<'EOF'
# Fixture

````markdown
``` story bogusverb HP-1
````
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # A fence-shaped line that is NOT a valid closer must fall through and still
  # be emitted as a LINE unit. Mutation: add a `next` to the non-closer branch —
  # the line is silently dropped, nothing else in the suite notices, and the
  # result is a vacuous green. No corpus file exercises this shape.
  [ "$(jq_field '[.verb_violations[].verb] | join(",")')" = "bogusverb" ]
}

@test "contract-check: every list-marker spelling opens a fence, and a bare number does not" {
  cat > "$FIXTURE_DIR/references/step-handoff.md" <<'EOF'
# Fixture

- ```bash
  story bogusalpha HP-1
  ```

1) ```bash
   story bogusbeta HP-1
   ```

4. ```bash
   story bogusgamma HP-1
   ```

4.```bash
Each story (story metadata lives in the store) is tracked by `story list`.
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Branch coverage for the marker alternation. Neither the bullet nor the `)`
  # spelling occurs anywhere in the corpus, so narrowing the class to `[0-9]+\.`
  # would pass every other test in this file. The final block is the negative
  # case: `4.```bash` has no separator after the marker, so it is NOT a fence and
  # the sentence under it must stay span-scanned. Mutation: weaken
  # `[[:space:]]+` to `*`, and that sentence reports `metadata`.
  [ "$(jq_field '[.verb_violations[].verb] | sort | join(",")')" = "bogusalpha,bogusbeta,bogusgamma" ]
}

@test "contract-check: both invocations on a two-span line are checked" {
  cat > "$FIXTURE_DIR/references/step-handoff.md" <<'EOF'
# Fixture

1. ```bash
   story move HP-1 in-progress
   ```
2. Generate the report: `story summary` + `story bogusverb`
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Pins the extraction UNIT, which no other fixture does. The dead form is the
  # SECOND span, so it is reachable only while the line is span-scanned: collapse
  # the line into one LINE unit and the documented "only the first qualifying
  # invocation per unit is checked" limitation swallows it silently. That is a
  # coverage REGRESSION rather than a false positive, and it is invisible to
  # violation counts — a column-0-anchored detector widened only for leading
  # whitespace reports contract_ok true with zero violations here.
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '[.verb_violations[].verb] | join(",")')" = "bogusverb" ]
}

@test "contract-check: a dead form planted in a real list-marker fence is caught" {
  local tree="$FIXTURE_DIR/real"
  mkdir -p "$tree"
  cp -R "$FORGE_ROOT/references" "$tree/references"
  cp -R "$FORGE_ROOT/skills" "$tree/skills"
  cp -R "$FORGE_ROOT/claude" "$tree/claude"
  local target="$tree/claude/skills/execute/SKILL.md"
  # Fail loud if the document was restructured rather than silently testing nothing.
  [ "$(grep -cFx '4. ```bash' "$target")" -eq 1 ]
  # Plant the exact grammar this guard was built to kill, in a real forge doc,
  # inside the fence shape the shipped detector cannot see.
  awk '{ print } $0 == "4. ```bash" { print "   story HP-N is done" }' "$target" > "$target.tmp"
  mv "$target.tmp" "$target"
  run bash "$SCRIPT" "$tree"
  echo "$output" >&2
  [ "$(jq_field '.files_scanned | length')" -ge 25 ]
  [ "$(jq_field '.contract_ok')" = "false" ]
  # Reach proven on real content, asserted through the public JSON only, so this
  # survives any future change to how the detector is implemented.
  [ "$(jq_field '[.verb_violations[] | select(.verb == "HP-N") | .file] | join(",")')" = "claude/skills/execute/SKILL.md" ]
}

@test "contract-check: no real corpus file leaves the detector latched at EOF" {
  local tree="$FIXTURE_DIR/canary"
  mkdir -p "$tree"
  cp -R "$FORGE_ROOT/references" "$tree/references"
  cp -R "$FORGE_ROOT/skills" "$tree/skills"
  # Append a sentence that is ordinary English when span-scanned (no backticks,
  # so it yields no units at all) and a violation when scanned as a whole LINE.
  # Any file whose fence is still open at EOF therefore reports `data`.
  local f
  while IFS= read -r f; do
    printf '\nRecovery; story data lives in a SQLite store.\n' >> "$f"
  done < <(find "$tree" \( -path '*/references/*.md' -o -name 'SKILL.md' \) -type f)
  run bash "$SCRIPT" "$tree"
  echo "$output" >&2
  [ "$(jq_field '.files_scanned | length')" -ge 25 ]
  # Bounds the failure mode a stateful detector adds over a toggle: a closer that
  # is never matched latches depth ON for the rest of the file. Mutation: change
  # the closer test to `run > flen` (an ordinary off-by-one in exactly this
  # logic) and 26 of 29 files latch, reporting 32 violations.
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
}

# --- Schema stability across every exit path (AGE-18 lock) ---

@test "contract-check: the CLI-missing early exit still emits the new keys" {
  PATH="/usr/bin:/bin" run bash "$SCRIPT" "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.subcommand_violations | length')" -eq 0 ]
  echo "$output" | jq -e 'has("real_subcommands")' >/dev/null
  echo "$output" | jq -e 'has("subcommand_violations")' >/dev/null
  echo "$output" | jq -e 'has("suppressions")' >/dev/null
  echo "$output" | jq -e 'has("stale_suppressions")' >/dev/null
}

# --- Output shape ---

@test "contract-check: output is always valid JSON" {
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" | jq . >/dev/null
}

@test "contract-check: empty docs-root reports ok true, contract_ok true, zero files scanned" {
  run bash "$SCRIPT" "$FIXTURE_DIR"
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.files_scanned | length')" -eq 0 ]
}

# --- Explicit --file arguments (AGE-30) ---
#
# The shape-based scan set cannot reach a file that lives under neither
# references/ nor skills/ — which is every repo-root agent-instruction file
# (AGENTS.md, CLAUDE.md). --file is the interface that closes that, decided by
# /council-vote; see .council/age30-repo-root-scan-interface/DECISION.md.
#
# Two properties below are load-bearing rather than incidental:
#   * The reported path is the string the caller passed, never re-rooted. A
#     violation reported at `references/AGENTS.md` for a file living at the repo
#     root sends its author to a directory that does not exist.
#   * A named file that does not exist is a HARD ERROR, never a silent skip, and
#     must not appear in files_scanned. That array is this guard's anti-vacuity
#     oracle, and an oracle that names a file nobody read is the exact
#     vacuous-green shape the guard exists to prevent.

@test "contract-check: --file scans a file under neither references/ nor skills/" {
  printf 'Close it with `story AGE-1 is done`.\n' > "$FIXTURE_DIR/AGENTS.md"
  run bash "$SCRIPT" --file "$FIXTURE_DIR/AGENTS.md"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.verb_violations | length')" -eq 1 ]
  [ "$(jq_field '.verb_violations[0].verb')" = "AGE-1" ]
}

@test "contract-check: --file reports the path exactly as passed, never re-rooted" {
  printf 'Close it with `story AGE-1 is done`.\n' > "$FIXTURE_DIR/AGENTS.md"
  cd "$FIXTURE_DIR"
  run bash "$SCRIPT" --file AGENTS.md
  [ "$(jq_field '.verb_violations[0].file')" = "AGENTS.md" ]
  [ "$(jq_field '.files_scanned[0]')" = "AGENTS.md" ]
}

@test "contract-check: --file is repeatable and scans exactly the named set" {
  printf 'ok\n' > "$FIXTURE_DIR/AGENTS.md"
  printf 'ok\n' > "$FIXTURE_DIR/CLAUDE.md"
  cd "$FIXTURE_DIR"
  run bash "$SCRIPT" --file AGENTS.md --file CLAUDE.md
  [ "$(jq_field '.ok')" = "true" ]
  [ "$(jq_field '[.files_scanned[]] | sort | join(" ")')" = "AGENTS.md CLAUDE.md" ]
}

# The degradation that makes an exact-membership assertion necessary downstream:
# with no positional root, DOCS_ROOT defaults to the forge PLUGIN root. If
# --file were merely additive to a defaulted root, naming two files would scan
# 31, and a caller whose --file argv expanded empty would scan 29 and report
# green over entirely the wrong input set.
@test "contract-check: --file suppresses the default plugin-root discovery" {
  printf 'ok\n' > "$FIXTURE_DIR/AGENTS.md"
  run bash "$SCRIPT" --file "$FIXTURE_DIR/AGENTS.md"
  [ "$(jq_field '.files_scanned | length')" -eq 1 ]
}

@test "contract-check: an explicit root still unions with --file" {
  printf 'ok\n' > "$FIXTURE_DIR/references/a.md"
  printf 'ok\n' > "$FIXTURE_DIR/AGENTS.md"
  run bash "$SCRIPT" "$FIXTURE_DIR" --file "$FIXTURE_DIR/AGENTS.md"
  [ "$(jq_field '.files_scanned | length')" -eq 2 ]
}

@test "contract-check: a --file that does not exist is a hard error, not a silent skip" {
  run bash "$SCRIPT" --file "$FIXTURE_DIR/nope.md"
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '.error')" = "missing_file" ]
}

# The graft from the runner-up proposal, and the reason it is soundness-critical:
# SCANNED_FILES_JSON was built from the REQUESTED list before the per-file
# existence check, so files_scanned could name a file that was never opened.
# Every downstream membership assertion is an assertion over this field.
@test "contract-check: files_scanned never names a file that was not read" {
  printf 'ok\n' > "$FIXTURE_DIR/AGENTS.md"
  run bash "$SCRIPT" --file "$FIXTURE_DIR/AGENTS.md" --file "$FIXTURE_DIR/nope.md"
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.error')" = "missing_file" ]
  echo "$output" | jq -e '[.files_scanned[] | select(test("nope"))] | length == 0' >/dev/null
}

@test "contract-check: --file without a value is a usage error" {
  run bash "$SCRIPT" --file
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.error')" = "usage" ]
}

@test "contract-check: an unknown flag is a usage error, not a docs-root" {
  run bash "$SCRIPT" --nope
  [ "$status" -eq 0 ]
  [ "$(jq_field '.ok')" = "false" ]
  [ "$(jq_field '.error')" = "usage" ]
}

# --- AGE-43: the harvest must stop at the span that introduced the invocation ---
#
# Inside a fence the extraction unit is the whole LINE (deliberate, AGE-24), so a
# line of CORRECT prose reaches the checker intact. `MID_RE`'s remainder ran past
# the closing backtick of the span that qualified the match, so the harvested
# token kept that backtick and a valid invocation was reported as a violation.
# `story project new` is the modern spelling AGE-15 renamed `story project init`
# to — the guard red on the correct answer.
#
# These are the four shapes measured to reproduce, plus AGE-29's indented fence.
# They are the FALSE-POSITIVE half; the positive controls proving the bound still
# bites live in their own test below, because an all-green fixture asserts nothing
# on its own.

# One fixture carries BOTH halves on purpose. The four backticked shapes are the
# false positives the bound removes; the plain forms below them are dead grammar
# that must STILL be reported, and they are what stops this test passing
# vacuously — an all-green fixture asserts nothing, because "no token ends in a
# backtick" is trivially true of an empty array.
#
# The discrimination is pinned PER ARRAY rather than over a flat join. Measured:
# blanketing `is_placeholder` to return 0 empties subcommand_violations and
# relation_violations while leaving verb_violations intact, because the verb slot
# routes through verb_slot_is_wildcard — a DIFFERENT function. So a combined
# length floor is satisfiable with a whole slot silently dead (1 verb + 2
# subcommand + 0 relation clears a floor of 3), and a flat token set cannot see a
# token MIGRATING between arrays, which is exactly what AGE-70's fix will produce.
@test "contract-check: a backticked invocation inside a fence is not mangled by the harvest" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
Then run `story project new` to start a project.
`story project new` is the modern spelling.
| `story project new` | creates a project |
See `story relate AGE-1 blocks` above.
story HP-1 is done
story project init
story relate AGE-1 precedes AGE-2
```

1. Claim it:
   ```
   Then run `story project init` to start a project.
   Use `story relate AGE-1 precedes AGE-2` to order them.
   ```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # THE INVARIANT. Not "ends in a backtick" — CONTAINS one, so a token mangled at
  # either edge reds it.
  [ "$(jq_field '([.verb_violations[].verb] + [.subcommand_violations[].subcommand] + [.relation_violations[].relation]) | map(select(contains("`"))) | length')" -eq 0 ]
  # Per-array provenance. The failure oracle is executable with no mutation of
  # shipped source: this same fixture on the pre-fix script yields 5 mangled
  # tokens — `new` three times, plus `init` and `blocks` — so the assertion above
  # is proven able to fire, and the pins below are proven to be the surviving set.
  [ "$(jq_field '[.verb_violations[].verb] | sort | join(",")')" = "HP-1" ]
  [ "$(jq_field '[.subcommand_violations[].subcommand] | sort | join(",")')" = "init,init" ]
  [ "$(jq_field '[.relation_violations[].relation] | sort | join(",")')" = "precedes,precedes" ]
}

# The winning council proposal disclosed this gap against itself: the pins above
# are all satisfied by an OVER-fix too. A wider bound [^`);|&]* leaves every
# pinned array and the backtick count identical, so nothing above would notice a
# future widening. This arm is the missing half — it pins the reported TOKEN on a
# span whose content legitimately carries `;` and `)`, where a wider bound
# truncates and a correct one does not.
@test "contract-check: the harvest bound is exactly the backtick, not a wider delimiter set" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
Run `story project foo;bar` now.
Run `story project baz)qux` now.
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Measured: widening to [^`);|&]* reports "baz","foo" instead.
  [ "$(jq_field '[.subcommand_violations[].subcommand] | sort | join(",")')" = "baz)qux,foo;bar" ]
}

# The marker arm lives in its OWN fixture, and that placement is load-bearing:
# try_suppress returns BEFORE add_subcommand_violation, so a marker sharing the
# fixture above would silently SUBTRACT from the pinned arrays and quietly weaken
# them. Bidirectional, because the defect INVERTED this mechanism rather than
# merely breaking it — a one-directional arm would miss a regression that
# restored the old behaviour by flipping the other half.
@test "contract-check: an expect-dead marker naming the real token suppresses it" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
Then run `story project init` to start. <!-- contract-check: expect-dead init -- AGE-15 renamed it -->
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Pre-fix this reported `stale: token_mismatch` with the violation STANDING:
  # the author named the correct token and the guard rejected it, a false
  # diagnosis of substitution drift that no author could satisfy, because the
  # only marker that worked named a token carrying a stray backtick.
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '[.suppressions[].token] | join(",")')" = "init" ]
  [ "$(jq_field '.stale_suppressions | length')" -eq 0 ]
}

@test "contract-check: an expect-dead marker naming a backtick-mangled token is stale, not silent" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
Then run `story project init` to start. <!-- contract-check: expect-dead init` -- names the mangled token -->
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # The other half of the inversion. Pre-fix THIS was the spelling that worked;
  # a marker written against the old behaviour must now fail LOUD — twice over,
  # an unsuppressed violation AND a stale marker — never go silently inert.
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '[.subcommand_violations[].subcommand] | join(",")')" = "init" ]
  [ "$(jq_field '[.stale_suppressions[].kind] | join(",")')" = "token_mismatch" ]
}

# ⚠ VACUOUS TODAY, AND KEPT ANYWAY. Both corpora report zero violations, so the
# invariant below is trivially true and contributes ZERO discrimination — it must
# never be counted as coverage. It is a GROWTH TRIPWIRE: AGE-29 (indented fences)
# and AGE-30 (repo-root agent files) both enlarge the whole-LINE unit population
# that makes this defect reachable, so the arm exists to red when real content
# first grows into it. The discriminating arms are the fixtures above.
@test "contract-check: no token from the real corpus or the root argv carries a backtick" {
  run bash "$SCRIPT" "$FORGE_ROOT"
  echo "$output" >&2
  [ "$(jq_field '.files_scanned | length')" -ge 25 ]
  [ "$(jq_field '([.verb_violations[].verb] + [.subcommand_violations[].subcommand] + [.relation_violations[].relation]) | map(select(contains("`"))) | length')" -eq 0 ]
  # AGE-69 hardening. The two assertions above were measured BLIND to the one
  # over-reach this fix makes reachable: extending strip_trailing_glue to the
  # VERB slot reds the real corpus with `contract_ok:false` and violation `<id`,
  # because verb_slot_is_wildcard tests a BALANCED `<...>` placeholder and the
  # strip removes the closing `>`. Neither "no backtick" nor a file count sees
  # that. The suppression assertion is the sharper half: the over-reach destroys
  # the live `<id>` marker, dropping suppressions to ["HP-N"], which is a guard
  # silently losing its escape hatch on real content. This is what makes AGE-74's
  # scope boundary executable rather than a comment.
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '[.suppressions[].token] | sort | join(",")')" = "<id>,HP-N" ]
  # Mirrors the argv the real gate uses (tests/storyhook-contract-root.sh): run
  # from the repo root with repo-relative paths, which --file scans instead of
  # the default directory discovery.
  local repo_root
  repo_root="$(cd "$FORGE_ROOT/../.." && pwd)"
  run bash -c "cd '$repo_root' && bash '$SCRIPT' --file AGENTS.md --file CLAUDE.md"
  echo "$output" >&2
  [ "$(jq_field '.files_scanned | length')" -eq 2 ]
  [ "$(jq_field '([.verb_violations[].verb] + [.subcommand_violations[].subcommand] + [.relation_violations[].relation]) | map(select(contains("`"))) | length')" -eq 0 ]
}

# --- Characterization pins: NOT requirements ---
#
# The three tests below assert behaviour that is still WRONG. They exist so the
# scope boundary of the AGE-43 fix is executable rather than a claim in a comment,
# and so a later correct fix reds a pin that names its own story instead of
# landing silently. Each carries its story ID in the test NAME: if one reds on
# you, read that story — you have probably fixed it, and the pin is what you
# update, not the code you just wrote.

# --- AGE-69: the harvested token is trimmed to the shape a member could have ---
#
# The three arms below BRACKET the rule rather than describe it, which is the
# council's decisive framing (`.council/age69-delimiter-glue-scope/`):
#
#   CEILING  the AGE-43 mid-token arm above — reds on a strip that is not
#            confined to the trailing edge (a `tr -cd`-shaped over-fix)
#   FLOOR    the CRLF arm — reds on any narrowing back to an ENUMERATED set,
#            which is the only way the two losing proposals could be smuggled in
#   BOUNDARY the digit-terminal arm — reds on a one-character error in the
#            class itself, which every other assertion in this file is blind to
#
# An all-green fixture asserts nothing, so each arm carries dead grammar as a
# positive control and every pin is PER ARRAY (AGE-43): a flat join cannot see a
# token migrating between arrays, and blanketing `is_placeholder` empties the
# subcommand and relation arrays while leaving the verb array intact.
@test "contract-check: a delimiter glued to the token no longer reports valid docs as violations" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
(story project new)
story project new; echo done
cd repo; story project new; echo x
story project new, then continue
story project new` to start a project.
story project new.
story project new:
(story project new);
(story relate AGE-1 blocks)
story relate AGE-1 blocks;
story relate AGE-1 blocks.
story HP-1 is done
(story project init)
story relate AGE-1 precedes;
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Rows 4-14 are CORRECT documentation that the shipped script reported as
  # violations: `new)`, `new;`, `new;`, `new\``, `new.`, `new:`, `new);`,
  # `blocks)`, `blocks;`, `blocks.`. The comma was the ONE member already handled
  # (`sub="${sub%,}"`), and generalising that line is the whole fix.
  #
  # Rows 15-17 are the positive controls, and they are what stops this passing
  # vacuously: they are dead grammar that must STILL be reported, and reported
  # with the delimiter REMOVED, which is what distinguishes a strip from a
  # silence. `(story project init);` would be a strip; a missing row would be a
  # silence; both look identical to a length floor.
  [ "$(jq_field '[.verb_violations[].verb] | sort | join(",")')" = "HP-1" ]
  [ "$(jq_field '[.subcommand_violations[].subcommand] | sort | join(",")')" = "init" ]
  [ "$(jq_field '[.relation_violations[].relation] | sort | join(",")')" = "precedes" ]
}

# THE FLOOR. Two enumerated delimiter sets were proposed and both were killed by
# this fixture: CR is not a character anyone thinks to enumerate, so every
# enumerated set reports `new)^M` here — byte-identical to no fix at all.
#
# It is worse than a missed false positive. The carriage return also mangles the
# POSITIVE control (`init` -> `init^M`), so on a CRLF document EVERY reported
# token is unsatisfiable by any `expect-dead` marker and the suppression
# mechanism silently dies. That is this repo's canonical failure shape, and only
# a derived complement closes it.
@test "contract-check: a CRLF document is not mangled by the carriage return" {
  printf '# Fixture\r\n\r\n```\r\n(story project new)\r\n(story project init)\r\n```\r\n' \
    > "$FIXTURE_DIR/references/storyhook-contract.md"
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # `new` is live and must go green; `init` is dead and must be reported CLEAN,
  # so the author can actually name it in a marker.
  [ "$(jq_field '[.subcommand_violations[].subcommand] | join(",")')" = "init" ]
  [ "$(jq_field '[.subcommand_violations[].subcommand] | map(select(test("\\r"))) | length')" -eq 0 ]
}

# THE BOUNDARY, and the arm that earns its place twice. The class `[!A-Za-z0-9]`
# has exactly one interesting one-character error and one interesting quoting
# error, and NOTHING ELSE IN THIS FILE SEES EITHER — measured, AGE-43's per-array
# pins, AGE-43's over-fix arm, the AGE-70 pin and the real 29-file corpus are all
# byte-identical under both mutants, and the corpus stays GREEN:
#
#   [!A-Za-z]      also strips trailing DIGITS
#   ["!"A-Za-z0-9] quoting the `!` destroys the negation, so the loop eats the
#                  token's ALPHANUMERICS instead of its delimiters
#
# The live-stem rows are the load-bearing ones and the reason this is a
# FALSE-NEGATIVE detector rather than a token-value pin. `init2` merely
# mis-reports as `init` (still dead, still reported, easy to read as plausible).
# `new2` and `blocks2` VANISH ENTIRELY, because their stems are live vocabulary —
# so the assertion must prove they are PRESENT, not merely that some token has
# the right spelling.
@test "contract-check: the strip stops at alphanumerics — a digit-terminal token keeps its digit" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
story project init2;
story project new2;
story relate AGE-1 precedes2)
story relate AGE-1 blocks2)
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # `init2`/`precedes2` catch the MANGLE; `new2`/`blocks2` catch the SILENCE.
  [ "$(jq_field '[.subcommand_violations[].subcommand] | sort | join(",")')" = "init2,new2" ]
  [ "$(jq_field '[.relation_violations[].relation] | sort | join(",")')" = "blocks2,precedes2" ]
}

# THE CEILING, extended to the array AGE-43 never covered. Every one of AGE-43's
# over-fix pins lives in the subcommand array, so a strip that is not confined to
# the trailing edge is caught in one array and invisible in the other — the same
# per-array blindness AGE-43 was itself decided on. `pre;cedes` collapses to the
# live relation `precedes` under any such over-fix and the violation disappears.
@test "contract-check: the relation array also pins a mid-token delimiter" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
Use `story relate AGE-1 pre;cedes AGE-2` to order them.
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '[.relation_violations[].relation] | join(",")')" = "pre;cedes" ]
}

# Strip-to-empty is ACCEPTED, and this arm records it as a deliberate ruling
# rather than an accident. A token consisting only of delimiters trims to "",
# which `is_placeholder` already treats as a wildcard — so `story project ;`
# becomes silent. That is a CONSISTENCY GAIN, not a new hole: the control row
# proves bare `story project` was ALREADY silent on the shipped script, so the
# degenerate forms now agree with the argument-less one instead of contradicting
# it. The live positive control in the same array is what stops this arm being an
# absence assertion that a blanket silence would satisfy.
@test "contract-check: a token of only delimiters is a wildcard, like the argument-less form" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
story project
story project ;
story project .
story project init.
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '[.subcommand_violations[].subcommand] | join(",")')" = "init" ]
}

# The marker inversion, on a NON-backtick delimiter. AGE-43 measured this for the
# backtick and pinned both directions; the same inversion is reachable through
# every other glue character, so it is pinned here too — in its OWN fixture,
# because try_suppress returns BEFORE add_subcommand_violation and a marker
# sharing a fixture would silently SUBTRACT from the pinned arrays above.
@test "contract-check: an expect-dead marker naming the real token suppresses a glued violation" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
(story project init) <!-- contract-check: expect-dead init -- AGE-15 renamed it -->
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Measured pre-fix: `stale: token_mismatch` with the violation STANDING. The
  # author named the correct, typeable token and the guard rejected it — a false
  # diagnosis of substitution drift no author could satisfy, because the only
  # marker that worked named a token carrying a stray `)`.
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '[.suppressions[].token] | join(",")')" = "init" ]
  [ "$(jq_field '.stale_suppressions | length')" -eq 0 ]
}

@test "contract-check: an expect-dead marker naming a glue-mangled token is stale, not silent" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
(story project init) <!-- contract-check: expect-dead init) -- names the mangled token -->
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # The other half. Pre-fix THIS was the spelling that worked; a marker written
  # against the old behaviour must now fail LOUD — an unsuppressed violation AND
  # a stale marker — never go silently inert. Both directions are pinned because
  # the defect INVERTED the mechanism rather than merely breaking it.
  [ "$(jq_field '.contract_ok')" = "false" ]
  [ "$(jq_field '[.subcommand_violations[].subcommand] | join(",")')" = "init" ]
  [ "$(jq_field '[.stale_suppressions[].kind] | join(",")')" = "token_mismatch" ]
}

# The complement rule is SOUND only because no vocabulary member ends in a
# non-alphanumeric: that is what makes it impossible for a trailing strip to turn
# a non-member INTO a member, i.e. to manufacture a false negative. The premise
# is a property of storyhook's data, not of this repo, so it is asserted rather
# than assumed — and asserted against the RUN'S OWN derived lists, never a
# literal copied from the implementation. A copied list would be AGE-35's
# self-consistent sweep: green because both sides came from the same place.
#
# Scoped to the two arrays this fix strips. `real_verbs` is AGE-74's premise.
@test "contract-check: every derived subcommand and relation ends in an alphanumeric" {
  run bash "$SCRIPT" "$FORGE_ROOT"
  echo "$output" >&2
  # A FLOOR first, so the assertion below cannot pass over an empty derivation —
  # which is exactly how a vocabulary-premise arm goes vacuous.
  [ "$(jq_field '([.real_relations[]] + [.real_subcommands[][]]) | length')" -ge 40 ]
  [ "$(jq_field '([.real_relations[]] + [.real_subcommands[][]]) | map(select(test("[^A-Za-z0-9]$"))) | length')" -eq 0 ]
}

@test "contract-check: AGE-74 pin — the verb capture group still absorbs . - _ (characterization)" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
story next.
story next-
story next_
story next)
story next;
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # `next` is a live verb, so all five lines are CORRECT documentation. The first
  # three are reported anyway, because the verb capture group's own character
  # class is `[A-Za-z0-9_.-]` — it absorbs `.`, `-` and `_` before any token-level
  # strip can see them. Rows 7-8 are the control proving this is a DIFFERENT
  # mechanism from AGE-69's: the class cannot absorb `)` or `;`, so those two are
  # green on the shipped script and were never part of this defect.
  #
  # AGE-69's strip is deliberately NOT applied here. Measured: doing so reds the
  # REAL corpus, because `verb_slot_is_wildcard` tests a BALANCED `<...>`
  # placeholder and removing the `>` destroys the live `<id>` suppression — the
  # hardened corpus arm above is the second, independent catch for that.
  # Measured: it also migrates tokens BETWEEN violation arrays, which is exactly
  # what AGE-43's per-array pins exist to detect.
  [ "$(jq_field '[.verb_violations[].verb] | sort | join(",")')" = "next-,next.,next_" ]
  [ "$(jq_field '.subcommand_violations | length')" -eq 0 ]
  [ "$(jq_field '.relation_violations | length')" -eq 0 ]
}

# --- AGE-70: the relation slot is resolved by a span-aware split ---
#
# `read -ra` splits the remainder on whitespace and the slot is a FIXED INDEX,
# so a multi-word span embedded in the argument list contributes its own words
# and displaces every later index. `story relate `story next --id` blocks AGE-2`
# reported `next` — a word from inside the span — instead of `blocks`.
#
# The five arms below BRACKET the rule (AGE-69's framing). Scope was ruled
# UNANIMOUSLY 3-0 by council: the SPLITTER ships, `MID_RE`'s bound does NOT
# change. Full trail `.council/age70-slot-displacement-scope/DECISION.md`.
#
# ⚠ THE REASON THE BOUND IS OUT OF SCOPE, because it is not obvious and the
# chair's own candidate died on it. The same span grammar is SAFE in the
# splitter and UNSAFE in the bound. Inside a fence the unit is the whole LINE
# (AGE-24), so the input is prose with shell embedded in it, and every grammar
# strong enough to parse the shell also misparses the English — `don't` is not
# an open quote. What differs is the CONSEQUENCE: in the splitter a misparse
# merges two tokens and the guard still reports (loud, local); in the bound it
# TRUNCATES before slot 1, the slot reads empty, `is_placeholder("")` returns 0,
# and the guard reports GREEN. A silent false negative in a drift guard is the
# one direction it cannot afford. The deferred half is AGE-79, which carries
# five counter-examples as pre-registered acceptance criteria.

# THE REQUIREMENT, and it replaces a characterization pin that was actively
# harmful. The old `AGE-70 pin` asserted the relation array equalled `next` —
# the value THE BUG PRODUCES. Measured: reverting this fix scores a
# byte-identical 82 ok / 1 not ok against a correct fix, because that pin agreed
# with the revert. A characterization pin asserting equality to a wrong value is
# a MUTANT'S ALIBI: it does not merely fail to detect a regression, it certifies
# it. Rows 4-7 are the four span shapes; rows 8-9 are the positive controls that
# stop this passing vacuously, and row 9 is a token the shipped script could
# never name at all (it reported `1`).
@test "contract-check: a span in the argument list no longer displaces the relation slot" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
story relate `story next --id` blocks AGE-2
story relate "AGE 1" blocks AGE-2
story relate 'AGE 1' blocks AGE-2
story relate $(story next --id) blocks AGE-2
story relate `AGE-1` precedes AGE-2
story relate "AGE 1" precedes AGE-2
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Pre-fix this array was `1,1,1,next,next,precedes` — four correct documents
  # reported, and the one real violation named with the WRONG token.
  [ "$(jq_field '[.relation_violations[].relation] | sort | join(",")')" = "precedes,precedes" ]
  # PER ARRAY (AGE-43): this fix migrates tokens, and a flat join cannot see a
  # token moving between arrays.
  [ "$(jq_field '.verb_violations | length')" -eq 0 ]
  [ "$(jq_field '.subcommand_violations | length')" -eq 0 ]
}

# THE CEILING. A `$( … )` nested inside another `$( … )` is where a
# span-aware-opener/first-occurrence-closer mismatch shows up: cutting the
# remainder at the FIRST `)` lands on the INNER construct's closer, leaves the
# fragment unbalanced, and reproduces this story's own headline false positive.
# Reds on any future bound that cuts at a first occurrence rather than a
# matching closer. Row 5 is the positive control.
@test "contract-check: a nested command substitution does not displace the relation slot" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
echo $(story relate $(story next --id) blocks AGE-2)
echo $(story relate $(story next --id) precedes AGE-2)
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Both reported `next` pre-fix — including line 5, where the real dead
  # relation `precedes` was never named.
  [ "$(jq_field '[.relation_violations[].relation] | join(",")')" = "precedes" ]
}

# THE FLOOR, and the arm that pins the scope ruling itself. Ordinary English
# apostrophes — a contraction and a possessive — are the reachable input that
# killed the rejected candidate: a bound derived from a span grammar pairs
# `it's` with a later `'` and truncates before slot 1, silently. Reds on any
# reintroduction of an apostrophe-sensitive bound. Both rows are dead grammar,
# so this arm is all positive control.
@test "contract-check: an apostrophe in prose does not silence the relation slot" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
it's odd; story relate 'AGE 1' precedes AGE-2
don't run (story relate AGE-1's parent precedes AGE-2)
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Line 4 reported `1` pre-fix — a word from inside the quoted span. Line 5
  # reported `parent` pre-fix and must CONTINUE to: the fix may not silence it.
  [ "$(jq_field '[.relation_violations[].relation] | sort | join(",")')" = "parent,precedes" ]
}

# THE BOUNDARY. AGE-43's truncation is load-bearing and NOTHING ELSE IN THIS
# FILE SEES IT — measured three times independently across two council
# sittings: deleting it scores 82/1, byte-identical to a correct fix. Line 4 is
# PROSE after a closed span; without the bound the word `precedes` is read as an
# argument and a correct document is reported. Line 5 is the positive control in
# the same array.
@test "contract-check: prose after a closed span is not read as an argument" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
`story relate AGE-1` precedes AGE-2 in the plan.
story relate `AGE-1` precedes AGE-2
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  [ "$(jq_field '[.relation_violations[].relation] | join(",")')" = "precedes" ]
}

# THE OTHER FLOOR — the splitter must degrade toward the shipped behaviour, not
# toward silence. A delimiter opens a span ONLY if its closer appears later;
# without that rule an unbalanced opener swallows the rest of the line into one
# argument, the slot reads empty, and a real violation vanishes. Measured: a
# candidate lacking it reds AGE-69's own arm above (81/2), because
# `story project new` to start a project.` is exactly this shape one slot over.
@test "contract-check: an unbalanced delimiter is literal, not an open span" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
story relate "AGE 1
story relate `AGE-1 precedes AGE-2
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Both tokens are exactly what the shipped script reported. The fix is not
  # allowed to buy its false-positive removal with a new silence.
  [ "$(jq_field '[.relation_violations[].relation] | sort | join(",")')" = "1,precedes" ]
}

# The `set -euo pipefail` class arm, and it asserts PRESENCE rather than
# content. A helper whose last statement is a test returns 1, which kills the
# whole script AT THE CALL SITE with exit 1 and ZERO BYTES of output — no JSON
# at all. Both chairs hit that trap while building this fix. Every other
# assertion in this file reads a field and is therefore blind to it: an empty
# output cannot fail a comparison it never reaches.
@test "contract-check: a degenerate remainder still emits parseable JSON" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
story relate
story relate
story project
(story relate )
story relate ''
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  echo "$output" | jq -e . >/dev/null
  [ "$(jq_field '.ok')" = "true" ]
}

# The subcommand slot takes the same split, and this arm is the ONLY thing that
# detects reverting it. The council's mutation battery ruled that call site
# "structurally unverifiable" — `is_placeholder` is leading-only and the slot is
# always index 0, so no LATER-index displacement is reachable there — and
# measured a revert at 82/1, byte-identical to baseline. That reasoning is
# sound about DISPLACEMENT and wrong about the reported TOKEN: a span opening
# mid-word is not leading, so `is_placeholder` never sees it, and the two
# splitters disagree about where the token ENDS.
#
# The token is what matters, because it is what an `expect-dead` marker must
# name (AGE-43's inversion class): an author looking at `story project ne"w x"`
# can type the span and cannot be expected to type `ne"w`. Row 6 is the
# wildcard control and row 7 the live-vocabulary control, so this cannot pass
# by blanket silence.
#
# Note the two mechanisms COMPOSE, and the expected values pin that composition:
# the split decides where the token ends, then AGE-69's `strip_trailing_glue`
# trims to the shape a vocabulary member could have. So `ne"w x"` is reported as
# `ne"w x` — the closing quote is trailing glue — while `a"b c"d` keeps its
# whole span because it already ends alphanumeric. Pinning both shapes is what
# stops a future change to either mechanism sliding past this arm.
@test "contract-check: a span in the subcommand slot is one token, not a prefix" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
story project ne"w x"
story project a"b c"d
story project "my thing"
story project init
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Pre-fix: `a"b`, `init`, `ne"w` — the first two truncated mid-span at the
  # whitespace the split should never have seen.
  [ "$(jq_field '[.subcommand_violations[].subcommand] | sort | join(",")')" = "a\"b c\"d,init,ne\"w x" ]
  [ "$(jq_field '.relation_violations | length')" -eq 0 ]
}

@test "contract-check: AGE-79 pin — a non-backtick opener still truncates before the relation slot (characterization)" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

```
(story relate `AGE-1` precedes AGE-2)
(story relate `story next --id` precedes AGE-2)
```
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # NOT A REQUIREMENT. Both lines carry the dead relation `precedes` and both go
  # silent, because `MID_RE` truncates the remainder at the next backtick for
  # EVERY qualifying opener while only a backtick opener actually introduces a
  # span. AGE-43 bought this knowingly; AGE-70's council re-affirmed it 3-0
  # rather than ship a bound that regressed five other inputs.
  #
  # A correct AGE-79 fix REDS this pin by design — read that story, it carries
  # the five counter-examples any candidate must clear first, and a measured
  # ladder of three candidates so you need not re-derive it.
  [ "$(jq_field '.relation_violations | length')" -eq 0 ]
}
