#!/usr/bin/env bash
# Clear stale Freshen transition markers on ordinary session starts.
rm -f .freshen/*.signal .freshen/.clear-pending .freshen/.clear-consumed 2>/dev/null || true
exit 0
