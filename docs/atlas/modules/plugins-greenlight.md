---
module: plugins/greenlight
summary: "PreToolUse safety hook: deterministic allow/pass classification for Bash commands, plus opt-in AI fallback."
read_when: "Touching greenlight's Bash safety classification, config, or AI fallback"
sources:
  - path: plugins/greenlight/.claude-plugin/plugin.json
    blob: 84b5d5fc27ada54106a99691cc7c2de0ca87b3df
  - path: plugins/greenlight/README.md
    blob: f930f291dc43f3be2ed0c5e0f98ea7e0b5980f09
  - path: plugins/greenlight/hooks/greenlight.sh
    blob: 5a77823c3f947ef5d5dac09ef16812c5d6a4a5a3
  - path: plugins/greenlight/hooks/hooks.json
    blob: 20cc2c86286ac87e52943958af770264e327a86c
  - path: plugins/greenlight/references/default-config.yaml
    blob: 1c182fe5713da064d5dbc48c3025f7a62d47b23f
  - path: plugins/greenlight/skills/greenlight/SKILL.md
    blob: 19c7e050709dc297261ce74a7f43fb9c744f6600
  - path: plugins/greenlight/tests/greenlight.bats
    blob: 7a121dd25715b00fa222ce3e59a12ce93ecc75a0
  - path: plugins/greenlight/tests/run-tests.sh
    blob: fb724aa07154a6df7e529601a4e6374ee0eed7ce
generator: cartographer/4
baseline: a4486d2b70ad4124762f9d777af6a7dc007bdc6c
---

# Module: plugins/greenlight

## Purpose

greenlight is a PreToolUse hook that gates every Bash tool call through a three-tier decision pipeline (plugins/greenlight/hooks/greenlight.sh:1-20): deterministic allow for 150+ known-safe commands (plugins/greenlight/hooks/greenlight.sh:253-346), deterministic pass-with-warning for known-destructive ones (plugins/greenlight/hooks/greenlight.sh:353-406), and an opt-in Claude Haiku fallback for genuinely uncertain commands (plugins/greenlight/hooks/greenlight.sh:1151-1258). It exists so an autonomous inner loop (e.g. forge's execute step, called out by name in plugins/greenlight/README.md:5 and the story/git fast-path comments at plugins/greenlight/hooks/greenlight.sh:332-343) can run git/test/build commands without a human present for every call, while still surfacing genuine destructiveness (rm, sudo, chmod) for confirmation. Config is a flat YAML file bootstrapped from references/default-config.yaml on first run and re-read on every invocation, so behavior changes take effect without restarting Claude Code (plugins/greenlight/hooks/greenlight.sh:29-38, 70-87).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Stateless per-invocation: the hook is a fresh bash process for every PreToolUse event, reading all input from stdin once with no persistent state across calls (plugins/greenlight/hooks/greenlight.sh:22). User config at ~/.config/greenlight/config.yaml is auto-initialized by copying the bundled references/default-config.yaml only when absent, then never overwritten by the hook itself (plugins/greenlight/hooks/greenlight.sh:35-38). The three-way verdict of is_safe_segment (0=safe, 1=uncertain, 2=known-destructive) travels as the function's bash exit code, but the offending command name travels separately through a shared mutable global, DESTRUCTIVE_CMD, set inside is_safe_segment and read by the caller after the call returns (plugins/greenlight/hooks/greenlight.sh:1024, 1045, 1055-1071). The decision helpers allow/pass_with_context/pass_silent each call exit 0 directly (plugins/greenlight/hooks/greenlight.sh:101-120), so the unconditional 'pass to normal permission system' at the script's tail (plugins/greenlight/hooks/greenlight.sh:1444-1445) is reached only when no earlier helper fired.

## External deps


## Gotchas

A quoted '>' or '->' inside a string argument (e.g. a commit message 'refactor: rename A -> B') used to be misdetected as real shell redirection; strip_quoted_spans() now strips quoted spans before the redirection grep runs (plugins/greenlight/hooks/greenlight.sh:174-213). A known-destructive command nested inside $(...) or backticks used to collapse into the generic 'uncertain' bucket, losing its destructive warning; the command-substitution loop now checks each inner segment's exit code for the destructive value (2) explicitly rather than treating any nonzero result as merely uncertain (plugins/greenlight/hooks/greenlight.sh:1388-1398). Config-file edits use a mktemp+sed+mv rewrite instead of `sed -i`, because BSD sed's `-i` requires a backup-suffix argument and silently misparses the GNU-style invocation (plugins/greenlight/skills/greenlight/SKILL.md:51-56, 70-75). The bats test helper builds hook input JSON with `jq -n` rather than string-interpolating into an unquoted heredoc, because an earlier draft's heredoc re-expanded a test payload's own $(...) and actually executed a destructive rm -rf instead of merely describing it to the hook (plugins/greenlight/tests/greenlight.bats:24-33).
