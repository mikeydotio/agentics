# File Locking Protocol

The bump command modifies VERSION and CHANGELOG, commits, and tags — all as an atomic operation. A file lock prevents concurrent bumps from corrupting these files.

## Platform Detection

```bash
# Generate a per-project lock path
PROJECT_HASH="$(printf '%s' "$PWD" | md5sum 2>/dev/null | cut -c1-8 || printf '%s' "$PWD" | md5 2>/dev/null | cut -c1-8)"
LOCK_PATH="/tmp/semver-${PROJECT_HASH}.lock"
```

## Linux: flock

```bash
if command -v flock &>/dev/null; then
  (
    flock -n 200 || { echo "Error: Another semver operation is in progress. Try again shortly."; exit 1; }
    # === Critical section ===
    # Read VERSION, increment, write VERSION, update CHANGELOG, git add, git commit, git tag
    # === End critical section ===
  ) 200>"$LOCK_PATH"
fi
```

Benefits:
- Kernel-managed — automatically released if process dies
- Non-blocking with `-n` flag — fails immediately if lock is held
- File descriptor based — clean and idiomatic

## macOS Fallback: mkdir

```bash
if ! command -v flock &>/dev/null; then
  LOCK_DIR="${LOCK_PATH}.d"

  # Stale lock detection: if lock is older than 5 minutes, assume stale
  if [ -d "$LOCK_DIR" ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0) ))
    if [ "$LOCK_AGE" -gt 300 ]; then
      echo "Warning: Removing stale lock (age: ${LOCK_AGE}s)"
      rmdir "$LOCK_DIR" 2>/dev/null
    fi
  fi

  mkdir "$LOCK_DIR" 2>/dev/null || { echo "Error: Another semver operation is in progress. Try again shortly."; exit 1; }
  trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT INT TERM

  # === Critical section ===
  # Read VERSION, increment, write VERSION, update CHANGELOG, git add, git commit, git tag
  # === End critical section ===
fi
```

Benefits:
- `mkdir` is atomic on all POSIX filesystems
- Works on macOS without additional tools
- Stale lock detection prevents permanent deadlocks

Drawbacks:
- Not automatically cleaned up if process is killed with SIGKILL
- Requires stale lock detection as safety net

## Combined Pattern

Use this in the SKILL.md bump command instructions:

```bash
PROJECT_HASH="$(printf '%s' "$PWD" | md5sum 2>/dev/null | cut -c1-8 || printf '%s' "$PWD" | md5 2>/dev/null | cut -c1-8)"
LOCK_PATH="/tmp/semver-${PROJECT_HASH}.lock"

acquire_lock() {
  if command -v flock &>/dev/null; then
    exec 200>"$LOCK_PATH"
    flock -n 200 || { echo "Error: Another semver operation is in progress."; return 1; }
  else
    LOCK_DIR="${LOCK_PATH}.d"
    if [ -d "$LOCK_DIR" ]; then
      LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0) ))
      [ "$LOCK_AGE" -gt 300 ] && rmdir "$LOCK_DIR" 2>/dev/null
    fi
    mkdir "$LOCK_DIR" 2>/dev/null || { echo "Error: Another semver operation is in progress."; return 1; }
    trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT INT TERM
  fi
}

release_lock() {
  if command -v flock &>/dev/null; then
    exec 200>&-
    rm -f "$LOCK_PATH"
  else
    rmdir "${LOCK_PATH}.d" 2>/dev/null
    trap - EXIT INT TERM
  fi
}
```

## What the Lock Protects

The lock must wrap the entire read-modify-write-commit-tag sequence:

1. Read current version from VERSION
2. Compute new version
3. Write new version to VERSION
4. Update CHANGELOG with new entry
5. `git add VERSION CHANGELOG.md`
6. `git commit -m "chore(release): <version>"`
7. `git tag <version_prefix><version>`

If any step fails, the lock is released and partial changes should be cleaned up (git checkout the modified files).
