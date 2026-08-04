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
  [ "$(jq_field '.files_scanned | length')" -gt 0 ]
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

@test "contract-check: ignores inline single-backtick template signatures outside fenced blocks" {
  cat > "$FIXTURE_DIR/references/storyhook-contract.md" <<'EOF'
# Fixture

| Dependency between stories | `story relate <a> <relationship> <b>` | Only 8 relations exist |
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  [ "$(jq_field '.contract_ok')" = "true" ]
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

There is no id-first form (`story HP-N is done`). <!-- contract-check: expect-dead HP-N -- denied in prose -->
EOF
  run bash "$SCRIPT" "$FIXTURE_DIR"
  echo "$output" >&2
  # Pre-AGE-24 this line sits at fence depth 0 and is never extracted. The
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

@test "contract-check: real committed forge docs carry no suppressions and none stale" {
  run bash "$SCRIPT" "$FORGE_ROOT"
  echo "$output" >&2
  [ "$(jq_field '.contract_ok')" = "true" ]
  [ "$(jq_field '.stale_suppressions | length')" -eq 0 ]
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
