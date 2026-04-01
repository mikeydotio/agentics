# Severity Levels

Standard severity definitions used across review, validation, and triage reports.

## Levels

### Critical
**Meaningful risk to system, data security, or data integrity.**

Examples:
- SQL injection vulnerability in user input handling
- Missing authentication check on admin endpoints
- Data corruption possible under concurrent writes
- Unencrypted storage of sensitive credentials
- Memory leak that will crash the system under normal load

**Triage default**: ESCALATE (unless the fix is unambiguous)

### Important
**Usability issues — formatting, UI layout, non-critical broken features.**

Examples:
- Form validation error messages are unclear
- Mobile layout breaks at certain screen sizes
- Pagination doesn't handle empty results gracefully
- Date formatting inconsistent across the application
- Error messages expose internal details to users

**Triage default**: FIX (if solution is clear), ESCALATE (if trade-offs exist)

### Useful
**Nothing is wrong, but there's an opportunity for improved UX or code quality.**

Examples:
- Loading states could be smoother
- Error recovery flow could be more forgiving
- Code duplication across similar handlers
- Test coverage gap in non-critical path
- Documentation could clarify a confusing API

**Triage default**: FIX (low risk, clear improvement)

## Severity Assignment Guidelines

1. **Start from impact, not category.** A missing null check is Critical if it can crash the system, Useful if it only affects a debug log.
2. **Consider the user.** If a real user would notice and be frustrated, it's at least Important.
3. **Err toward higher severity** when unsure — triage can downgrade, but missed critical issues are costly.
4. **Don't inflate severity** to force attention — the triage team will discount findings from agents that cry wolf.
