#!/usr/bin/env bash
# forge-archive.sh — Archive .forge/ directory to a tarball before starting a new pipeline
# Usage: forge-archive.sh [forge-dir] [archive-dir]
set -euo pipefail

FORGE_DIR="${1:-.forge}"
ARCHIVE_DIR="${2:-.forge-archives}"

# Validate forge dir exists
if [ ! -d "$FORGE_DIR" ]; then
  jq -n '{ok: false, error: "no_forge_dir", message: "No .forge directory found"}'
  exit 0
fi

# Extract project name from IDEA.md H1 heading
project_slug="unnamed"
if [ -f "$FORGE_DIR/IDEA.md" ]; then
  raw_name=$(grep -m1 '^# ' "$FORGE_DIR/IDEA.md" | sed 's/^# //' | tr -d '\r') || true
  if [ -n "$raw_name" ]; then
    project_slug=$(echo "$raw_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
    project_slug="${project_slug:0:40}"
  fi
fi

# Build timestamp and filename
timestamp=$(date +%Y%m%d-%H%M%S)
archive_name="forge-${project_slug}-${timestamp}.tar.gz"

# Create archive directory
mkdir -p "$ARCHIVE_DIR"

# Create tarball (include everything, even gitignored files)
tar czf "${ARCHIVE_DIR}/${archive_name}" -C "$(dirname "$FORGE_DIR")" "$(basename "$FORGE_DIR")"

# Verify tarball was created
if [ ! -f "${ARCHIVE_DIR}/${archive_name}" ]; then
  jq -n '{ok: false, error: "tar_failed", message: "Failed to create archive tarball"}'
  exit 0
fi

# Get tarball size for reporting
archive_size=$(stat -c%s "${ARCHIVE_DIR}/${archive_name}" 2>/dev/null || stat -f%z "${ARCHIVE_DIR}/${archive_name}" 2>/dev/null || echo "0")

# Delete .forge/
rm -rf "$FORGE_DIR"

jq -n \
  --arg archive_name "$archive_name" \
  --arg archive_path "${ARCHIVE_DIR}/${archive_name}" \
  --arg project_slug "$project_slug" \
  --argjson archive_size "$archive_size" \
  '{
    ok: true,
    archive_name: $archive_name,
    archive_path: $archive_path,
    project_slug: $project_slug,
    archive_size: $archive_size
  }'
