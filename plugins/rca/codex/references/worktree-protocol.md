# Experiment Worktree Protocol

The investigation's isolation guarantee: **production code in the main tree is never modified
— even temporarily — before fix approval.** Anything mutating (instrumentation, defect
toggling, `git bisect` moving HEAD) happens in a disposable linked worktree that the main
tree never sees.

## Lifecycle

```bash
# create (lazily — first mutating need, not before)
bash "<plugin-root>/bin/rca-worktree.sh" create <slug> \
  --copy <path-to-untracked-repro-test> [--setup-cmd "<deps install>"]

# orient after context loss / crash
bash "<plugin-root>/bin/rca-worktree.sh" status <slug>

# destroy (eagerly — end of diagnose, abandon, postmortem cleanup)
bash "<plugin-root>/bin/rca-worktree.sh" destroy <slug>
```

- Location: `<repo>/.claude/worktrees/rca/<slug>/worktree` on branch `rca/<slug>` (state JSON
  in the parent dir; mirrored to `.rca/<slug>/worktree.json`). The scaffold ensures
  `.claude/worktrees/` is gitignored in the target project.
- Create runs `git worktree prune` first and resolves the MAIN repo root even when invoked
  from inside another linked worktree (an `/issue do` session) — the experiment worktree
  always attaches to the main repository.
- **Untracked files do not travel.** Linked worktrees share `.git`, not untracked/ignored
  files — the repro test (untracked until the fix commit) must be `--copy`'d in, as must any
  fixture it needs. Once copied, untracked files safely survive bisect's checkouts.
- **Dependencies do not travel either** (node_modules, DerivedData, venvs are ignored files).
  `--setup-cmd` runs the stack's install inside the worktree (`rca-stack.sh detect` emits a
  `setup_cmd` per stack). No known setup command for a deps-needing stack → ask the user once,
  persist in meta.json (`stack.setup_cmd`). If none exists at all, degrade: skip bisect and
  mutation experiments, verify hypotheses observationally, and record the gap in DIAGNOSIS.md
  — the isolation rule is never relaxed to compensate.

## What runs where

| Operation | Main tree | Worktree |
|---|---|---|
| Reading code, git log/blame/pickaxe/hotspots | ✅ | — |
| Writing `.rca/` artifacts, NEW test files | ✅ | — |
| Running the repro/full suite (no code changes) | ✅ | ✅ |
| Instrumentation, defect toggling, any prod-code edit pre-approval | ❌ never | ✅ |
| `git bisect` | ❌ never | ✅ |
| The approved fix itself | ✅ (fix step, feature branch) | ❌ |

## The cleanliness check (hard verification)

After EVERY write-capable agent returns (experimenter especially), the dispatching skill runs
`git status --porcelain` in the MAIN tree and fails loudly if anything appears beyond the
allowed set (`.rca/` artifacts + declared new test files + the scaffold's `.gitignore`
append). Workspace scoping in the agent brief is prompt-level; this check is the real guard.

## Crash recovery & leak detection

`worktree.json` present in `.rca/<slug>/` means a worktree exists (or leaked) —
`rca-status.sh` surfaces `worktree_live: true` at every state, and the orchestrator offers
cleanup on resume/abandon. A worktree mid-bisect is safe to destroy: the bisect driver traps
`git bisect reset`, and `destroy` uses `--force` + prune regardless.
