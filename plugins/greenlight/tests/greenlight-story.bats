#!/usr/bin/env bats
# AGE-26 — greenlight's classification of the storyhook `story` CLI.
#
# Before this suite, `story) return 0 ;;` sat in `is_always_safe()` — the table
# whose header promises "pure readonly — no flags or arguments can make them
# destructive". Measured against the real storyhook 2.0.0, that promise was
# false for every clause: `story purge` and `story project delete` are
# documented "There is no undo", `story update` "atomically replaces the running
# executable", `story project new` writes `.storyhook.toml` and `AGENTS.md` into
# the cwd, `story web start` binds the machine's Tailscale IP, and
# `story plugin install` installs third-party code.
#
# THE GENERATING PRINCIPLE (apply this to a verb you do not find below):
#
#   ALLOW (0)  iff the worst case is a wrong story RECORD in the current
#              project, repairable by another `story` command.
#   DESTRUCTIVE (2) only if `is_known_destructive` ALREADY ranks an equivalent
#              operation at 2 by command name. Membership requires naming the
#              existing peer. No peer -> 1, however bad the verb feels.
#   UNCERTAIN (1) everything else, including every verb not recognised.
#
# The peer rule is what makes bucket 2 safe to own: it cannot grow without
# someone first adding an unconditional entry to `is_known_destructive`, which
# is a far louder act than editing an allowlist. It is also why no rename was
# needed — if every `story` verb at 2 mirrors an existing entry at 2, then
# "destructive" is already the correct word for all of them.
#
# Full council trail (3 seats, ranked-choice, every seat voted against its own
# round-1 proposal): .council/age26-greenlight-story-verb-surface/DECISION.md
#
# ⚠ DELIBERATELY NOT BUILT — a narrowing guard that greps shipped docs for
# "verbs an agent is told to type". It was proposed, voted for, and withdrawn by
# all three seats on measurement: the ONLY occurrences of `story purge` and
# `story project delete` in shipped plugins/** were inside greenlight's own
# comment describing this defect, so such a guard would have read the sentence
# documenting the bug as a mandate to keep `story purge` auto-approved — while
# reporting green. The reusable rule: bounded-capture-guard.sh is sound because
# a `timeout` call is shell syntax in a shell file, a decidable predicate over a
# formal grammar; `story purge` in a markdown skill is prose. Same shape, not
# the same thing. `test_story_allowlist_is_pinned` below covers narrowing
# instead, by asserting SET EQUALITY, which is bidirectional.

HOOK="$BATS_TEST_DIRNAME/../hooks/greenlight.sh"
PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_HOME="$(mktemp -d)"
  export TEST_HOME
}

teardown() {
  rm -rf "$TEST_HOME"
  return 0
}

# Build the payload with `jq -n` — never string-interpolate a command into an
# unquoted heredoc. Several cases below contain their own `$(...)`, and an
# unquoted delimiter re-expands them, which once *executed* a test payload
# instead of describing it to the hook (see greenlight.bats's note).
run_bash() {
  local command="$1" perm_mode="${2:-default}"
  local json
  json="$(jq -cn --arg cmd "$command" --arg mode "$perm_mode" \
    '{tool_name: "Bash", tool_input: {command: $cmd}, permission_mode: $mode}')"
  run env HOME="$TEST_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" <<< "$json"
}

run_bash_explorer() {
  local command="$1"
  local json
  json="$(jq -cn --arg cmd "$command" \
    '{tool_name: "Bash", tool_input: {command: $cmd}, permission_mode: "default"}')"
  run env HOME="$TEST_HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    GREENLIGHT_PLAN_EXPLORER=1 bash "$HOOK" <<< "$json"
}

decision() {
  echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null
}

has_context() {
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext // empty' >/dev/null 2>&1
}

context_text() {
  echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}

# --- Bucket ALLOW: the forge hot path must not regress ------------------------
#
# If any of these ever goes red, greenlight has started stalling the autonomous
# execute loop. The three assertions in greenlight.bats's "F076/F077: story CLI
# subcommands are allowed" test are deliberately left in place untouched as an
# independent witness to the same property.

@test "AGE-26: read verbs are allowed" {
  for cmd in "story list --json" "story next --count 3" "story show ST-1" \
             "story summary" "story search foo" "story export" \
             "story graph --critical-path" "story handoff" "story report --html" \
             "story load-context" "story help storage"; do
    run_bash "$cmd"
    [ "$(decision)" = "allow" ] || { echo "expected allow for: $cmd (got $(decision))"; return 1; }
  done
}

@test "AGE-26: reversible record-annotation verbs are allowed" {
  for cmd in "story new \"a title\"" "story move ST-1 done" \
             "story comment ST-1 \"note\"" "story set ST-1 --title x" \
             "story assign ST-1 mikey" "story block ST-1 \"reason\"" \
             "story unblock ST-1" "story prioritize ST-1 high" \
             "story label ST-1 a,b" "story unlabel ST-1 a" \
             "story relate A blocks B" "story unrelate A blocks B" \
             "story reopen ST-1" "story delete ST-1 \"reason\""; do
    run_bash "$cmd"
    [ "$(decision)" = "allow" ] || { echo "expected allow for: $cmd (got $(decision))"; return 1; }
  done
}

# `delete` is allowed and `purge` is not, and that is not a judgement call —
# storyhook's own two-step design IS the boundary. `story delete` is a soft
# tombstone that `story reopen` undoes; `story purge` refuses a story that was
# not soft-deleted first. Gating `purge` alone therefore gates the entire
# irreversible path without costing the reversible one.
@test "AGE-26: delete is allowed because purge — the irreversible half — is not" {
  run_bash "story delete ST-1 \"duplicate\""
  [ "$(decision)" = "allow" ]
  run_bash "story purge ST-1 --force"
  [ "$(decision)" != "allow" ]
}

# decompose is on the hot path: forge's decompose step instructs an agent to
# type it, in fenced blocks at references/storyhook-contract.md:271-278 and
# references/story-decomposition.md:76-82. Denying it would change a shipped
# instruction's verdict, which is the difference between a minor and a major
# bump. It satisfies the allow principle on its own terms — it creates only
# story records, each individually `story delete`-able.
@test "AGE-26: decompose is allowed (shipped forge step, story-scoped, reversible)" {
  run_bash "story decompose --stdin --dry-run < PLAN.md"
  [ "$(decision)" = "allow" ]
  run_bash "story decompose PLAN.md --json"
  [ "$(decision)" = "allow" ]
}

@test "AGE-26: two-token read actions are allowed" {
  for cmd in "story project list" "story project settings list" \
             "story project settings get sync.auto_transition" \
             "story state list" "story type list" "story hooks list" \
             "story phase list" "story phase show p1" \
             "story epic list" "story epic show E-1" \
             "story web status" "story web address"; do
    run_bash "$cmd"
    [ "$(decision)" = "allow" ] || { echo "expected allow for: $cmd (got $(decision))"; return 1; }
  done
}

# --- Bucket DESTRUCTIVE (2): the five verbs with an existing peer -------------
#
# Each assertion checks BOTH that it is not auto-approved AND that the warning
# names the verb. Without the second clause a maintainer could demote these to
# uncertain and this suite would stay green.

@test "AGE-26: purge and project delete are destructive (peer: rm|rmdir|unlink|shred)" {
  run_bash "story purge ST-1 --force"
  [ "$(decision)" != "allow" ]
  has_context
  [[ "$(context_text)" == *"story purge"* ]]

  run_bash "story project delete --force"
  [ "$(decision)" != "allow" ]
  has_context
  [[ "$(context_text)" == *"story project delete"* ]]
}

@test "AGE-26: update and plugin install are destructive (peer: apt|brew|yum|dnf|pacman)" {
  run_bash "story update --force"
  [ "$(decision)" != "allow" ]
  has_context
  [[ "$(context_text)" == *"story update"* ]]

  run_bash "story plugin install some-target"
  [ "$(decision)" != "allow" ]
  has_context
  [[ "$(context_text)" == *"story plugin install"* ]]

  run_bash "story plugin uninstall some-target"
  [ "$(decision)" != "allow" ]
  has_context
}

# The banner must carry the VERB. DESTRUCTIVE_CMD holds a bare command name for
# every other entry in the table, so the naive wiring renders "Detected
# potentially destructive operation: `story`" — dropping the verb and making the
# split invisible at the only place a human ever sees it.
@test "AGE-26: the destructive banner names the verb, not a bare 'story'" {
  run_bash "story purge ST-1 --force"
  [[ "$(context_text)" != *'`story`'* ]]
  [[ "$(context_text)" == *"no undo"* ]]
}

# --- Bucket UNCERTAIN (1): denied, but NOT labelled destructive ---------------
#
# These have no peer in is_known_destructive, so calling them destructive would
# print a false sentence — the AGE-11 defect class. The absence of
# additionalContext is the assertion that pins them at 1 rather than 2.

@test "AGE-26: boundary-crossing verbs are uncertain, and are not called destructive" {
  for cmd in "story github-sync" "story github-sync --dry-run" \
             "story web start" "story web stop" "story tui" \
             "story hooks install" "story hooks uninstall" \
             "story migrate" "story import stories.json" \
             "story import-project" "story store new /tmp/s.db" \
             "story member add alice" "story project new --prefix ABC" \
             "story state remove in-progress" "story state add review --super OPEN" \
             "story scaffold agents-md" "story commit-sync"; do
    run_bash "$cmd"
    [ "$(decision)" != "allow" ] || { echo "expected NOT allow for: $cmd"; return 1; }
    has_context && { echo "expected NO destructive banner for: $cmd"; return 1; }
  done
  return 0
}

# doctor is denied whole rather than split on --fix. Every flag predicate is a
# bypass surface (--fix=true, abbreviations, a flag after the positional), and
# doctor is not on the hot path, so a false red here is bounded and loud —
# which is the side of the trade this repo's own rule says not to instrument.
@test "AGE-26: doctor is denied whole — no flag parsing anywhere" {
  run_bash "story doctor"
  [ "$(decision)" != "allow" ]
  run_bash "story doctor --fix"
  [ "$(decision)" != "allow" ]
}

# --- Fail-closed default, and the sentinel that earns the right to rely on it -
#
# The `story` verb surface CANNOT be enumerated from the CLI: `story help --all`
# yields 45 headings of which 4 are not commands, the usage block yields 48, and
# `context` and `sync-git` execute while appearing in NEITHER. So no completeness
# guard is possible, and the fail-closed default is what makes that safe. This
# sentinel is what pins it — without it, "whatever we failed to enumerate is
# still denied" would be an untested premise.

@test "AGE-26: an unrecognised verb fails closed (the sentinel)" {
  run_bash "story frobnicate --all"
  [ "$(decision)" != "allow" ]
  run_bash "story zzz-not-a-verb"
  [ "$(decision)" != "allow" ]
  # A REAL verb that appears in neither of storyhook's own enumerations.
  # It is an alias of the allowed `load-context`, so this is a bounded false
  # red, deliberately accepted: one loud prompt, one line to fix if it matters.
  run_bash "story context"
  [ "$(decision)" != "allow" ]
}

@test "AGE-26: an unrecognised action under a two-token verb fails closed" {
  run_bash "story project frobnicate"
  [ "$(decision)" != "allow" ]
  run_bash "story web frobnicate"
  [ "$(decision)" != "allow" ]
}

# --- Extractor: storyhook takes global flags BEFORE the verb ------------------
#
# This is why the extractor is modelled on is_safe_git and NOT is_safe_gh.
# `--store-path <file>` and `--project <slug>` are VALUE-TAKING, so an extractor
# that skips flags without consuming their values reads the PATH as the verb,
# and gh's naive $(i+1) form reads `--json` as the verb. Both misreads land in
# the allow direction if the resulting token is not in the table... which is why
# an unresolvable verb must fail closed rather than fall through.

@test "AGE-26: global flags before the verb do not hide a destructive verb" {
  for cmd in "story --json purge ST-1 --force" \
             "story --quiet purge ST-1 --force" \
             "story --no-hooks purge ST-1 --force" \
             "story --store-path /tmp/s.db purge ST-1 --force" \
             "story --project foo purge ST-1 --force" \
             "story --store-path=/tmp/s.db purge ST-1 --force" \
             "story --project=foo project delete --force"; do
    run_bash "$cmd"
    [ "$(decision)" != "allow" ] || { echo "expected NOT allow for: $cmd"; return 1; }
  done
}

# The mirror of the test above: proves the extractor genuinely PARSES rather
# than blanket-denying anything containing a flag. Without this, a broken
# extractor that denies everything would pass the whole deny half of this suite.
@test "AGE-26: global flags before the verb still allow a read verb" {
  run_bash "story --json list"
  [ "$(decision)" = "allow" ]
  run_bash "story --no-hooks next"
  [ "$(decision)" = "allow" ]
  run_bash "story --store-path /tmp/s.db list"
  [ "$(decision)" = "allow" ]
}

@test "AGE-26: a path-prefixed story binary is classified the same way" {
  run_bash "/Users/someone/.local/bin/story purge ST-1 --force"
  [ "$(decision)" != "allow" ]
  run_bash "/Users/someone/.local/bin/story list"
  [ "$(decision)" = "allow" ]
}

@test "AGE-26: bare story and an empty verb fail closed" {
  run_bash "story"
  [ "$(decision)" != "allow" ]
}

@test "AGE-26: env and VAR=val prefixes do not hide a destructive verb" {
  run_bash "env STORYHOOK_PROJECT=x story purge ST-1 --force"
  [ "$(decision)" != "allow" ]
  run_bash "STORYHOOK_PROJECT=x story purge ST-1 --force"
  [ "$(decision)" != "allow" ]
}

# --- Interaction with the rest of the hook -----------------------------------

@test "AGE-26: a destructive verb inside a command substitution is caught" {
  run_bash 'echo "$(story purge ST-1 --force)"'
  [ "$(decision)" != "allow" ]
  has_context
  [[ "$(context_text)" == *"command substitution"* ]]
}

@test "AGE-26: a destructive verb in a later segment is caught" {
  run_bash "story list && story purge ST-1 --force"
  [ "$(decision)" != "allow" ]
}

# F075 regression: quote-awareness must survive the split. A verb name occurring
# inside a quoted ARGUMENT is not an invocation.
@test "AGE-26: a verb name inside a quoted argument is not treated as a verb" {
  run_bash 'story comment ST-1 "then run story purge ST-1"'
  [ "$(decision)" = "allow" ]
  run_bash 'story comment ST-1 "map wave -> story"'
  [ "$(decision)" = "allow" ]
}

# --- Plan explorer ------------------------------------------------------------

@test "AGE-26: explorer allows reads and denies the destructive verbs" {
  run_bash_explorer "story list"
  [ "$(decision)" = "allow" ]
  run_bash_explorer "story purge ST-1 --force"
  [ "$(decision)" = "deny" ]
  run_bash_explorer "story project delete --force"
  [ "$(decision)" = "deny" ]
}

# AGE-54 retires blanket approval of uncertainty. Destructive verbs must still
# take the destructive branch, not merely fail because the setting is retired.
# The AI-enabled regression in greenlight-policy.bats separately proves these
# verbs cannot reach an otherwise approving uncertainty evaluator.
@test "AGE-26: plan_explorer_uncertain=allow cannot re-arm a destructive verb" {
  mkdir -p "$TEST_HOME/.config/greenlight"
  cp "$PLUGIN_ROOT/references/default-config.yaml" "$TEST_HOME/.config/greenlight/config.yaml"
  sed -i.bak 's/^plan_explorer_uncertain:.*/plan_explorer_uncertain: allow/' \
    "$TEST_HOME/.config/greenlight/config.yaml"

  grep -q '^plan_explorer_uncertain: allow$' "$TEST_HOME/.config/greenlight/config.yaml"
  run_bash_explorer "some-unknown-command --flag"
  [ "$(decision)" = "deny" ]
  [[ "$output" == *'plan_explorer_uncertain: allow'* ]]

  run_bash_explorer "story purge ST-1 --force"
  [ "$(decision)" = "deny" ]
  [[ "$output" == *'destructive/privileged'* ]]
  run_bash_explorer "story update --force"
  [ "$(decision)" = "deny" ]
  [[ "$output" == *'destructive/privileged'* ]]
}

# --- Structural pins ----------------------------------------------------------

# THE BLANKET-RESTORATION GUARD, layer 1 (source).
# is_always_safe is consulted at :1222, BEFORE the conditional dispatch at
# :1227 — so re-adding `story)` to it makes is_safe_story dead code and
# silently restores the old behaviour, while every behavioural test above that
# only checks the allow bucket stays green. This layer names that mistake.
@test "AGE-26: no story arm survives in is_always_safe (blanket-restoration guard)" {
  local body
  body="$(awk '/^is_always_safe\(\) \{/,/^\}/' "$HOOK")"
  if printf '%s\n' "$body" | grep -qE '^[[:space:]]*[^#]*\bstory\)'; then
    echo "A 'story)' arm has returned to is_always_safe."
    echo "That table's header promises 'no flags or arguments can make them"
    echo "destructive', which is false for the story CLI (AGE-26): story purge"
    echo "and story project delete are 'There is no undo', and story update"
    echo "replaces its own binary. It ALSO makes is_safe_story dead code,"
    echo "because is_always_safe is consulted first (:1222 before :1227)."
    return 1
  fi
}

# THE WIDENING PIN — asserts SET EQUALITY between the verbs is_safe_story
# allows and the literal set below. This is bidirectional by construction, so
# it reds on a NARROWING (deleting `move`) exactly as it reds on a WIDENING
# (adding `purge`). That is why no separate narrowing guard exists: the second
# test was never needed, only a second corpus, and a prose corpus is the part
# that could not be made sound.
@test "AGE-26: the story allowlist is pinned (widening and narrowing both red)" {
  local expected actual
  expected="assign block comment decompose delete export graph handoff help label link list load-context move new next prioritize relate reopen report search set show summary unblock unlabel unlink unrelate"

  # Extract the single-token allow arms from is_safe_story's verb case.
  actual="$(awk '/^is_safe_story\(\) \{/,/^\}/' "$HOOK" \
    | sed -n '/# BEGIN allow-verbs/,/# END allow-verbs/p' \
    | grep -oE '^[[:space:]]*[a-z|-]+\)' \
    | tr -d ' )' | tr '|' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')"

  if [ "$actual" != "$expected" ]; then
    echo "greenlight's story allowlist has changed."
    echo "  expected: $expected"
    echo "  actual  : $actual"
    echo
    echo "This layer is asking you to justify the change against the AGE-26"
    echo "principle, not to be silenced by updating the pin:"
    echo "  ALLOW iff the worst case is a wrong story RECORD in the current"
    echo "  project, repairable by another story command."
    echo "If the verb belongs, update this pin AND say why in the commit."
    echo "If a verb was REMOVED, check it is not one shipped docs tell an agent"
    echo "to type — that would change a shipped instruction's verdict and make"
    echo "the release a MAJOR bump."
    return 1
  fi
}

# Pins bucket 2's membership rule mechanically: every verb greenlight calls
# destructive must name a peer that is ALREADY unconditionally destructive in
# is_known_destructive. This is what stops bucket 2 growing on severity
# intuition — the rule that won the council.
@test "AGE-26: every destructive story verb has a peer in is_known_destructive" {
  local kd
  kd="$(awk '/^is_known_destructive\(\) \{/,/^\}/' "$HOOK")"
  # purge / project delete mirror the file-removal peer
  printf '%s\n' "$kd" | grep -qE '(^|[|[:space:]])rm\|rmdir\|unlink\|shred\)'
  # update / plugin install|uninstall mirror the package-installation peer
  printf '%s\n' "$kd" | grep -qE 'apt-get\|apt\|yum\|dnf\|pacman\|zypper\|brew\)'
}
