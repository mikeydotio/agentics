# agentic-workflows

Personal Claude Code plugin marketplace.

## Install

```
/plugin marketplace add mikeydotio/agentic-workflows
```

Then install any plugin:

```
/plugin install <plugin-name>@agentic-workflows
```

## Adding a Plugin

1. Create a directory under `plugins/` with a `.claude-plugin/plugin.json` manifest
2. Add skills in `skills/<name>/SKILL.md`, commands in `commands/<name>.md`
3. Add the plugin entry to `.claude-plugin/marketplace.json`
