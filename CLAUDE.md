# Handy Plugins Marketplace

This repo is a Claude Code plugin marketplace owned by mikeydotio.

## Structure

- `.claude-plugin/marketplace.json` — marketplace manifest listing all plugins
- `plugins/<name>/` — individual plugin directories

## Plugin Anatomy

Each plugin under `plugins/` follows this structure:

```
plugins/my-plugin/
├── .claude-plugin/
│   └── plugin.json          # Required: { "name", "description" }
├── skills/                  # Skills (preferred format)
│   └── skill-name/
│       └── SKILL.md         # YAML frontmatter + markdown instructions
├── commands/                # Legacy command format
│   └── command-name.md
├── .mcp.json                # Optional: MCP server config
└── README.md                # Optional: documentation
```

## When Adding a New Plugin

1. Create the plugin directory under `plugins/`
2. Add `.claude-plugin/plugin.json` with at minimum `name` and `description`
3. Add the plugin to `.claude-plugin/marketplace.json` in the `plugins` array:
   ```json
   {
     "name": "my-plugin",
     "description": "What it does",
     "source": "./plugins/my-plugin"
   }
   ```
4. Skills use `skills/<name>/SKILL.md` format with YAML frontmatter (`name`, `description` required)
