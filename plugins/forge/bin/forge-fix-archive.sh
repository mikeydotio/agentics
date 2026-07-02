#!/usr/bin/env bash
# forge-fix-archive.sh — Archive current fix cycle and increment counter
# Usage: forge-fix-archive.sh [forge-dir]
set -euo pipefail

FORGE_DIR="${1:-.forge}"

FILES_TO_ARCHIVE=("TRIAGE.md" "PLAN.md" "plan-mapping.json")

# Count existing cycle directories to determine next number
next_cycle=0
if [ -d "$FORGE_DIR/fix-cycles" ]; then
  next_cycle=$(find "$FORGE_DIR/fix-cycles" -maxdepth 1 -type d -name 'cycle-*' | wc -l | tr -d ' ')
fi

# Determine which files exist
archived=()
for f in "${FILES_TO_ARCHIVE[@]}"; do
  if [ -f "$FORGE_DIR/$f" ]; then
    archived+=("$f")
  fi
done

# Nothing to archive
if [ ${#archived[@]} -eq 0 ]; then
  jq -n '{ok: false, error: "nothing_to_archive", message: "No fix cycle artifacts found"}'
  exit 0
fi

# Create cycle directory and move files
cycle_dir="$FORGE_DIR/fix-cycles/cycle-${next_cycle}"
mkdir -p "$cycle_dir"

for f in "${archived[@]}"; do
  mv "$FORGE_DIR/$f" "$cycle_dir/$f"
done

# Build archived array as JSON
archived_json=$(printf '%s\n' "${archived[@]}" | jq -R . | jq -s .)

jq -n \
  --argjson cycle "$next_cycle" \
  --argjson archived "$archived_json" \
  '{ok: true, cycle: $cycle, archived: $archived}'
