#!/bin/bash
# Initialize a persistent loop for any command
# Usage: setup-loop.sh <loop-name> <completion-promise> [max-iterations] [initial-phase]
#
# Example:
#   setup-loop.sh "start-issue-123" "COMPLETE"
#   setup-loop.sh "create-project" "DONE" 50
#   setup-loop.sh "address-review-42" "COMPLETE" "" "fixing"

set -euo pipefail

LOOP_NAME="${1:-}"
COMPLETION_PROMISE="${2:-COMPLETE}"
MAX_ITERATIONS="${3:-}"  # Optional, defaults to unlimited
INITIAL_PHASE="${4:-}"   # Optional, defaults to empty

if [ -z "$LOOP_NAME" ]; then
  echo "Error: loop-name is required"
  echo "Usage: setup-loop.sh <loop-name> <completion-promise> [max-iterations] [initial-phase]"
  exit 1
fi

# Sanitize loop name for use in filename
SAFE_LOOP_NAME=$(echo "$LOOP_NAME" | sed 's/[^a-zA-Z0-9_-]/-/g')
STATE_FILE=".claude/${SAFE_LOOP_NAME}.loop.local.md"

# Create .claude directory if it doesn't exist
mkdir -p .claude

# Check for existing loop — preserve phase if re-initializing
EXISTING_PHASE=""
if [ -f "$STATE_FILE" ]; then
  EXISTING_PHASE=$(grep '^phase:' "$STATE_FILE" | sed 's/phase: *//' || true)
  echo "Warning: Loop '$LOOP_NAME' already active. Resetting (preserving phase: ${EXISTING_PHASE:-<none>})..."
fi

# Preserve existing phase from state file, fall back to INITIAL_PHASE for fresh runs
# This allows re-entry to maintain phase context (e.g., watching) across stop-hook restarts
# while INITIAL_PHASE provides a default for first-time initialization
PHASE="${EXISTING_PHASE:-$INITIAL_PHASE}"

# Create state file with YAML frontmatter
cat > "$STATE_FILE" << EOF
---
loop_name: $LOOP_NAME
iteration: 1
max_iterations: $MAX_ITERATIONS
completion_promise: $COMPLETION_PROMISE
phase: $PHASE
started_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
---

Persistent loop initialized for: $LOOP_NAME
Completion promise: $COMPLETION_PROMISE
Max iterations: ${MAX_ITERATIONS:-unlimited}

This loop will continue until:
1. The completion promise <done>$COMPLETION_PROMISE</done> is output
2. Max iterations is reached (if set)
3. User cancels with /cancel-loop
EOF

echo "Loop initialized: $LOOP_NAME"
echo "Output <done>$COMPLETION_PROMISE</done> when all completion criteria are met."
