---
module: "plugins/agents/agents/ux*"
summary: "Platform-variant UX design reviewers — CLI, mobile, and web specialists with one read-only review contract"
read_when: "Choosing or editing a platform-specific UX reviewer (CLI, mobile, or web)"
sources:
  - path: plugins/agents/agents/ux-designer-cli.md
    blob: 10595e11ce270175e12322409a2b8908eae54dde
  - path: plugins/agents/agents/ux-designer-mobile.md
    blob: 5e69aab6a0ad62ccf0b8d2b06483faee6b176eb8
  - path: plugins/agents/agents/ux-designer-web.md
    blob: 47d2ee61ac977b280271bab4bb2567c765db198b
references_modules: [plugins-agents-references, plugins-council]
generator: cartographer/2
baseline: b4cedefaba8df96ee167877bf2ee9c3143ef0b08
verified: true
---

# Module: plugins/agents/agents/ux*

## Purpose

One UX-reviewer role split by medium into three variants: terminal, handheld device, and browser.
The split exists because conventions don't transfer (plugins/agents/agents/ux-designer-cli.md:14).
Consumers pick the variant matching their platform; all three review and recommend, never edit.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `ux-designer-cli` | agent | `plugins/agents/agents/ux-designer-cli.md:2` | Reviews terminal UX — help text, exit codes, TTY/pipe behavior, stderr discipline; emits a `# CLI UX Review` report |
| `ux-designer-mobile` | agent | `plugins/agents/agents/ux-designer-mobile.md:2` | Reviews mobile UX — HIG/Material conventions, touch targets, gestures, safe areas, offline-first; emits a `# Mobile UX Review` report |
| `ux-designer-web` | agent | `plugins/agents/agents/ux-designer-web.md:2` | Reviews web UX — design tokens, responsive layout, Core Web Vitals, dark mode, motion; emits a `# Web UX Review` report |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `platform` | frontmatter field | `plugins/agents/agents/ux-designer-cli.md:9` | The variant selector (`cli`/`mobile`/`web`); besides name, description, and tools it is the only frontmatter that differs across the trio |
| `tier` | frontmatter field | `plugins/agents/agents/ux-designer-cli.md:6` | `platform-variant` in all three files — the shared tier naming this family in the agent roster |

## Relationships

- `plugins-agents-references.agent-catalog.md -> plugins-agents-agents-ux.ux-designer-cli (reads)`
- `plugins-council.council-vote -> plugins-agents-agents-ux.ux-designer-mobile (calls)`

## Type notes

- Tool grants are asymmetric: CLI variant is offline (plugins/agents/agents/ux-designer-cli.md:4).
- Mobile and web add WebSearch and WebFetch (plugins/agents/agents/ux-designer-mobile.md:4).
- `read_only: true` in every variant (plugins/agents/agents/ux-designer-web.md:8).
- Guardrails restate the no-Write/Edit rule (plugins/agents/agents/ux-designer-web.md:207).
- `pipeline: null` throughout — bound to no pipeline (plugins/agents/agents/ux-designer-cli.md:7).
- All mandate the `<files_to_read>` initial read (plugins/agents/agents/ux-designer-cli.md:16).
- Each caps review output at 2000 lines (plugins/agents/agents/ux-designer-cli.md:189).
- CLI hard floor: never exit 0 on failure (plugins/agents/agents/ux-designer-cli.md:196).
- Mobile hard floor: 44pt/48dp touch targets (plugins/agents/agents/ux-designer-mobile.md:197).
- Web hard floor: respect `prefers-reduced-motion` (plugins/agents/agents/ux-designer-web.md:216).

## External deps

- None — markdown role prompts with no package dependencies.
- Frontmatter tools (Read, Grep, Glob, WebSearch, WebFetch) are Claude Code built-ins.
