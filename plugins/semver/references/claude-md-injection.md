# CLAUDE.md Injection

When version tracking is started, a clearly-delimited section is injected into the project's CLAUDE.md. This makes Claude version-aware across all sessions.

## Injection Template

```markdown
<!-- semver:start -->
## Semantic Versioning

This project uses semantic versioning managed by the `/semver` plugin.

### Version Awareness
- Read the `VERSION` file at the start of each conversation to know the current version.
- Read `.semver/config.yaml` to understand the versioning configuration.
- When discussing releases, deployments, or changes, reference the current version.

### Commit Discipline
- Write meaningful, descriptive commit messages. Each commit message may appear in an auto-generated changelog.
- Use conventional-commit-style prefixes when they fit naturally: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.
- The first line of the commit message should be a concise summary (under 72 characters). Add detail in the body if needed.

### Version Bump Guidance
When recommending or performing a version bump:
- **patch** (0.0.x): Bug fixes, documentation corrections, minor refactors with no behavior change.
- **minor** (0.x.0): New features, new capabilities, non-breaking additions to the public API or user-facing behavior.
- **major** (x.0.0): Breaking changes — removed features, changed interfaces, incompatible API modifications, behavior changes that require consumers to update.

When you notice the user has completed a logical unit of work, suggest running `/semver bump` with the appropriate level.

### Hooks
- Custom pre-bump and post-bump hooks can be added in `.semver/hooks/`.
- Never trigger `/semver bump` from within a hook — this causes infinite recursion.

### Configuration
Versioning settings are in `.semver/config.yaml`. Do not modify this file unless the user explicitly asks to change semver settings.
<!-- semver:end -->
```

## Insertion Protocol

1. **Check for existing injection**: Search CLAUDE.md for `<!-- semver:start -->`. If found, replace the block between start and end markers with the current template (idempotent update).
2. **If no existing injection**: Append the block to the end of CLAUDE.md, preceded by a blank line separator.
3. **If no CLAUDE.md exists**: Create CLAUDE.md with just this block.

## Removal Protocol

Remove the injected section and its surrounding blank lines:

**Using sed:**
```bash
sed -i '/^<!-- semver:start -->$/,/^<!-- semver:end -->$/d' CLAUDE.md
```

**Using Claude's Edit tool:** Find the block between the sentinel comments (inclusive) and remove it.

After removal, if CLAUDE.md is empty (only whitespace remaining), leave it in place — the user may have other reasons for the file to exist.

## Sentinel Markers

- Start: `<!-- semver:start -->`
- End: `<!-- semver:end -->`

These are HTML comments — invisible in rendered markdown, machine-parseable, and extremely unlikely to appear naturally in a CLAUDE.md file. The same pattern is used by tools like direnv and nvm for shell config injection.

## Important Notes

- The injected content references `.semver/config.yaml` rather than hardcoding settings, keeping the CLAUDE.md block stable even when config changes.
- The injection should happen as part of `tracking start`, not on every session.
- The removal should happen as part of `tracking stop`.
- Never inject duplicate blocks — always check for existing markers first.
