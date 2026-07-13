# Architectural Root Cause Patterns

Common architectural patterns that cause bugs. When investigating a root cause, check if it
matches one of these. Each pattern carries a typical ODC signature (`odc-classification.md`) —
matching a pattern is evidence for that classification and, usually, for a design-level
verdict with the narrow patch + escalation path.

## Leaky Abstractions

**What it is:** An abstraction that exposes internal implementation details to its consumers.

**How it causes bugs:** Consumers depend on internal behavior that changes during refactoring. The abstraction promises one thing but delivers another under certain conditions.

**Symptoms:**
- Bug appears after "harmless" internal refactoring
- Fix requires knowledge of another component's internals
- Different consumers handle the same abstraction differently

**Root cause fix:** Strengthen the abstraction boundary. Make the contract explicit (types, validation, documentation). Ensure internal changes can't leak through.

## Shared Mutable State

**What it is:** Multiple components read and write the same data without proper coordination.

**How it causes bugs:** Race conditions, stale reads, inconsistent updates. The bug is often intermittent and environment-dependent.

**Symptoms:**
- Bug is intermittent or timing-dependent
- Bug appears under load but not in testing
- Multiple components access the same global/shared resource
- Fix involves adding locks, mutexes, or synchronization

**Root cause fix:** Eliminate the sharing (give each component its own state), make the state immutable (copy-on-write), or centralize access through a single owner with a clear API.

## Temporal Coupling

**What it is:** Operations that must happen in a specific order but the order isn't enforced by the system.

**How it causes bugs:** When the order changes (new code path, async execution, error recovery), the implicit contract is violated.

**Symptoms:**
- Bug only appears in certain execution paths
- Fix involves "make sure X happens before Y"
- Code comments warn about ordering ("must call init() first")
- Bug appears after introducing concurrency or async

**Root cause fix:** Make the ordering explicit. Use type states, builder patterns, or state machines. If ordering can't be enforced, make operations idempotent and order-independent.

## Missing or Violated Invariants

**What it is:** A correctness rule that should always be true but isn't enforced by the system.

**How it causes bugs:** Code assumes the invariant holds, but nothing prevents it from being violated. The bug is the gap between assumption and reality.

**Symptoms:**
- Null pointer / undefined reference errors
- Data in an "impossible" state
- Code has defensive checks scattered throughout instead of validation at entry
- Bug fix involves adding yet another check for the same condition

**Root cause fix:** Make the invariant explicit and enforce it at the boundary where data enters the system. Use types, validation, or constructor constraints. The goal: make the invalid state unrepresentable.

## Abstraction Mismatch

**What it is:** The abstraction model doesn't match the problem domain. The code models the wrong thing, or models the right thing at the wrong level.

**How it causes bugs:** Edge cases multiply because the abstraction doesn't naturally handle them. Every new feature requires workarounds.

**Symptoms:**
- The bug is in "glue code" between components
- Type conversions or data transformations at boundaries are complex and error-prone
- The same concept is represented differently in different components
- Adding a simple feature requires changes in many places

**Root cause fix:** Redesign the abstraction to match the domain. For immediate bug fixing, identify the specific mismatch causing the current bug and fix that interface, flagging the broader redesign as follow-up.

## Implicit Coupling

**What it is:** Components that appear independent but are secretly connected through shared conventions, configuration, naming, or side effects.

**How it causes bugs:** Changing one component breaks another with no obvious connection. The coupling isn't visible in import/dependency graphs.

**Symptoms:**
- Bug in component A is caused by a change in "unrelated" component B
- Components share configuration keys, magic strings, or naming conventions
- Components communicate through side effects (file system, environment variables, global state)
- No explicit dependency but behavioral dependency exists

**Root cause fix:** Make the coupling explicit. If components need to communicate, give them an explicit interface. If they share configuration, centralize it with a single source of truth. If they share conventions, encode those in types or shared constants.

## Error Propagation Failures

**What it is:** Errors that are swallowed, transformed, or lost as they propagate through the system.

**How it causes bugs:** The original error is informative but by the time it reaches the user or log, it's been caught, wrapped, or silenced into uselessness. The bug is hard to diagnose because the real error is hidden.

**Symptoms:**
- Generic error messages ("something went wrong")
- Silent failures (operation appears to succeed but doesn't)
- Error handling that catches everything (`catch (e) {}`)
- Errors logged at the wrong level or in the wrong place

**Root cause fix:** Design an explicit error propagation strategy. Errors at boundaries should be translated (not swallowed). Each layer should add context, not remove it. Errors should fail LOUD at the point of detection.

## Diagnostic Checklist

When investigating a bug, check each pattern:

| Pattern | Check | How to Detect | Typical ODC signature |
|---------|-------|---------------|----------------------|
| Leaky abstraction | Do consumers depend on internal behavior? | Grep for internal details used outside the component | Interface / Incorrect |
| Shared mutable state | Is state accessed by multiple components? | Find global variables, singletons, shared caches; co-change couplings from `rca-hotspots.sh` | Timing/Serialization / Missing |
| Temporal coupling | Must operations happen in a specific order? | Look for init(), setup(), "must call before" comments | Timing/Serialization or Relationship / Missing |
| Missing invariant | Is there an assumption that's not enforced? | Find defensive null checks, "impossible" state handling | Checking or Function / Missing |
| Abstraction mismatch | Does the model match the domain? | Look for complex type conversions at boundaries | Function/Class / Incorrect |
| Implicit coupling | Are "unrelated" components secretly connected? | Check shared config keys, magic strings, side effects; co-change pairs with no import edge | Relationship / Missing |
| Error propagation | Are errors lost or transformed? | Follow an error from throw to user/log — is context preserved? | Interface or Checking / Extraneous (swallowing) |
