#!/bin/bash
# Clean up loop state files
# Usage: cleanup-loop.sh [loop-name]
#
# If loop-name is provided, only that loop is cleaned up
# If no loop-name, all loops are cleaned up

set -euo pipefail

LOOP_NAME="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/loop-state.sh"
STATE_DIR=$(loop_state_directory)

if [ -n "$LOOP_NAME" ]; then
  # Clean up specific loop
  SAFE_LOOP_NAME=$(echo "$LOOP_NAME" | sed 's/[^a-zA-Z0-9_-]/-/g')
  STATE_FILE="$STATE_DIR/${SAFE_LOOP_NAME}.loop.local.json"

  if [ -f "$STATE_FILE" ]; then
    if ! cleanup_loop "$STATE_FILE"; then
      echo "Loop '$LOOP_NAME' kept: its E2E browser session could not be stopped. Run /cancel-loop again to retry."
      exit 1
    fi
    echo "Loop '$LOOP_NAME' cancelled."
  else
    echo "No active loop found with name '$LOOP_NAME'."
  fi
else
  # Clean up all loops
  LOOP_FILES=$(find_active_loops "$STATE_DIR")

  if [ -z "$LOOP_FILES" ]; then
    echo "No active loops found."
  else
    RETAINED=0
    while read -r file; do
      loop_name=$(jq -r '.loop_name // "unknown"' "$file" 2>/dev/null || echo "unknown")
      if cleanup_loop "$file"; then
        echo "Cancelled loop: $loop_name"
      else
        echo "Kept loop: $loop_name (its E2E browser session could not be stopped)"
        RETAINED=$((RETAINED + 1))
      fi
    done <<< "$LOOP_FILES"
    if [ "$RETAINED" -gt 0 ]; then
      echo "$RETAINED loop(s) kept for browser cleanup. Run /cancel-loop again to retry."
      exit 1
    fi
    echo "All active loops cancelled."
  fi
fi
