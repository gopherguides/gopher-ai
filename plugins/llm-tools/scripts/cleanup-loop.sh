#!/bin/bash
# Clean up loop state files
# Usage: cleanup-loop.sh [loop-name]
#
# If loop-name is provided, only that loop is cleaned up
# If no loop-name, all loops are cleaned up

set -euo pipefail

LOOP_NAME="${1:-}"

if [ -n "$LOOP_NAME" ]; then
  # Clean up specific loop
  SAFE_LOOP_NAME=$(echo "$LOOP_NAME" | sed 's/[^a-zA-Z0-9_-]/-/g')
  STATE_FILE=".claude/${SAFE_LOOP_NAME}.loop.local.md"

  if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE"
    echo "Loop '$LOOP_NAME' cancelled."
  else
    echo "No active loop found with name '$LOOP_NAME'."
  fi
else
  # Clean up all loops
  LOOP_FILES=$(find .claude -name "*.loop.local.md" 2>/dev/null || true)

  if [ -z "$LOOP_FILES" ]; then
    echo "No active loops found."
  else
    echo "$LOOP_FILES" | while read -r file; do
      loop_name=$(grep '^loop_name:' "$file" 2>/dev/null | sed 's/loop_name: *//' || echo "unknown")
      rm -f "$file"
      echo "Cancelled loop: $loop_name"
    done
    echo "All active loops cancelled."
  fi
fi
