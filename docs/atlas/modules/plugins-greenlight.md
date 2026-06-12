---
module: plugins/greenlight
summary: "PreToolUse safety hook — three-tier Bash triage (deterministic allow/warn, AI fallback), per-mode disable"
read_when: "Touching tool-call safety gating, greenlight.sh, its config schema, or /greenlight"
sources:
  - path: plugins/greenlight/.claude-plugin/plugin.json
    blob: 39246c09c4ec5c21d786408baba172052a1ad9a3
  - path: plugins/greenlight/README.md
    blob: fe1fff6a447754c8f4ff1e3b567c65571a36490d
  - path: plugins/greenlight/hooks/greenlight.sh
    blob: 72653a429b3e20e77fb1d40d892faa5388aa960b
  - path: plugins/greenlight/hooks/hooks.json
    blob: 20cc2c86286ac87e52943958af770264e327a86c
  - path: plugins/greenlight/references/default-config.yaml
    blob: e11bc45103e37cde5cf05ffa1f95aa0e5763c30e
  - path: plugins/greenlight/skills/greenlight/SKILL.md
    blob: 248805d9ec6de9e782e2b43f02d02ba0018640a4
references_modules: []
generator: cartographer/1
baseline: 0ce4ca44c3cc0b4a95d86862de8dc79914ffacbf
verified: true
---

# Module: plugins/greenlight

## Purpose

Advisory safety triage for every Bash tool call, evaluated before Claude Code's permission prompt.
Tiers: deterministic allow (known readonly), warn-and-pass (known destructive), AI for the rest.
Fail-open by design — it can allow or defer but never deny; every failure path is a silent exit 0.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `/greenlight` | skill | `plugins/greenlight/skills/greenlight/SKILL.md:2` | Config manager: status, enable/disable per mode, mode, ai, model, allow/block/unallow/unblock, test, log, reset |
| `PreToolUse` | hook registration | `plugins/greenlight/hooks/hooks.json:4` | Runs greenlight.sh on every tool call; its 20s timeout bounds the run, AI call included |
| `config.yaml` | config schema | `plugins/greenlight/references/default-config.yaml:2` | Flat `key: value` contract at `~/.config/greenlight/config.yaml`, re-read per call; seeded from this template on first run and reset |
| `greenlight` | plugin manifest | `plugins/greenlight/.claude-plugin/plugin.json:2` | Marketplace identity for the deterministic-parse + AI-fallback safety hook |
| `greenlight` | hook script | `plugins/greenlight/hooks/greenlight.sh:3` | stdin tool-call JSON → `permissionDecision: allow` JSON, `additionalContext` warning, or silent exit 0 — never deny |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `ai_check` | function | `plugins/greenlight/hooks/greenlight.sh:1060` | Anthropic API fallback returning `{answer, rationale}`; true → warn, false → allow (rationale surfaced); failure → silent pass |
| `allow` | function | `plugins/greenlight/hooks/greenlight.sh:83` | Terminal emitter trio with `pass_with_context` and `pass_silent`; every decision exits through one |
| `extract_cmd_subs` | function | `plugins/greenlight/hooks/greenlight.sh:1219` | Pulls inner commands out of `$()`/backticks (nested-paren aware) so substitutions get analyzed instead of blanket-passed |
| `get_cmd_name` | function | `plugins/greenlight/hooks/greenlight.sh:170` | Base-command extraction — strips `env`/`time` prefixes, `VAR=val` assignments, and path prefixes before lookup |
| `is_always_safe` | function | `plugins/greenlight/hooks/greenlight.sh:203` | Case-statement database of unconditionally readonly commands; the deterministic ALLOW tier |
| `is_known_destructive` | function | `plugins/greenlight/hooks/greenlight.sh:291` | Always-destructive database; `destructive_reason` (plugins/greenlight/hooks/greenlight.sh:330) supplies the warning text |
| `is_safe_segment` | function | `plugins/greenlight/hooks/greenlight.sh:935` | Tri-state classifier (safe/uncertain/destructive): custom lists, then databases, then the per-tool `is_safe_*` family dispatched at plugins/greenlight/hooks/greenlight.sh:989 |
| `read_config` | function | `plugins/greenlight/hooks/greenlight.sh:52` | grep+sed flat-YAML reader; the whole config contract rests on single-line `key: value` pairs |
| `split_segments` | function | `plugins/greenlight/hooks/greenlight.sh:1175` | Quote-aware awk splitter on `\|\|` `&&` `\|` `;` — makes the segment, not the command, the unit of analysis |

## Relationships

- `plugins-greenlight.hooks.json -> plugins-greenlight.greenlight.sh (calls)`
- `plugins-greenlight.greenlight.sh -> plugins-greenlight.default-config.yaml (reads)`
- `plugins-greenlight.SKILL.md -> plugins-greenlight.greenlight.sh (calls)`
- `plugins-greenlight.SKILL.md -> plugins-greenlight.default-config.yaml (reads)`

## Type notes

- Disabled-mode gate runs before all analysis: plugins/greenlight/hooks/greenlight.sh:111
- Ships disabled only in bypassPermissions: plugins/greenlight/references/default-config.yaml:8
- Read/Glob/Grep/WebFetch/WebSearch auto-allow: plugins/greenlight/hooks/greenlight.sh:125
- Only Bash is analyzed; Write/Edit untouched: plugins/greenlight/skills/greenlight/SKILL.md:168
- File-write redirections short-circuit to silent pass: plugins/greenlight/hooks/greenlight.sh:162
- custom_allow wins first; custom_pass forces warn: plugins/greenlight/hooks/greenlight.sh:944
- Any destructive segment → warn; AI never consulted: plugins/greenlight/hooks/greenlight.sh:1319
- strict mode never calls AI; uncertain defers: plugins/greenlight/hooks/greenlight.sh:1327
- Unset ANTHROPIC_API_KEY skips AI → silent pass: plugins/greenlight/hooks/greenlight.sh:1064
- Process substitution stays blanket-uncertain: plugins/greenlight/hooks/greenlight.sh:1306

## External deps

- jq — all JSON parsing and decision emission: plugins/greenlight/README.md:56
- curl — carries the AI fallback HTTP call: plugins/greenlight/README.md:57
- awk — quote-aware splitting and per-tool subcommand extraction
- Anthropic Messages API — json_schema verdict call: plugins/greenlight/hooks/greenlight.sh:1094

## Gotchas

- `permissive` = `standard`; CFG_MODE only read at plugins/greenlight/hooks/greenlight.sh:1326
- Lenient checks promised at plugins/greenlight/references/default-config.yaml:13 do not exist
- `terraform state` always safe — dead guard arm at plugins/greenlight/hooks/greenlight.sh:696
- `helm repo` likewise always safe — dead guard at plugins/greenlight/hooks/greenlight.sh:727
- Skill snippets use GNU-only `sed -i` syntax: plugins/greenlight/skills/greenlight/SKILL.md:52
