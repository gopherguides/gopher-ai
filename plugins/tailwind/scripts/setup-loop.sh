#!/bin/bash
# Initialize a persistent loop for any command (JSON-based)
# Usage: setup-loop.sh <loop-name> <completion-promise> [max-iterations] [initial-phase] [phase-messages-json]
#
# Example:
#   setup-loop.sh "start-issue-123" "COMPLETE"
#   setup-loop.sh "create-project" "DONE" 50
#   setup-loop.sh "address-review-42" "COMPLETE" "" "fixing"
#   setup-loop.sh "ship" "SHIPPED" 50 "" '{"reviewing":"Resume LLM review pass."}'

set -euo pipefail

LOOP_NAME="${1:-}"
COMPLETION_PROMISE="${2:-COMPLETE}"
MAX_ITERATIONS="${3:-}"  # Optional, defaults to null
INITIAL_PHASE="${4:-}"   # Optional, defaults to empty
PHASE_MESSAGES_JSON="${5:-}"  # Optional JSON object of phase->message mappings

if [ -z "$LOOP_NAME" ]; then
  echo "Error: loop-name is required"
  echo "Usage: setup-loop.sh <loop-name> <completion-promise> [max-iterations] [initial-phase] [phase-messages-json]"
  exit 1
fi

# Sanitize loop name for use in filename
SAFE_LOOP_NAME=$(echo "$LOOP_NAME" | sed 's/[^a-zA-Z0-9_-]/-/g')
STATE_FILE=".claude/${SAFE_LOOP_NAME}.loop.local.json"

# Create .claude directory if it doesn't exist
mkdir -p .claude

# Check for existing loop — preserve phase and bot_review_baseline if re-initializing
EXISTING_PHASE=""
EXISTING_BASELINE=""
if [ -f "$STATE_FILE" ]; then
  EXISTING_PHASE=$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null || true)
  EXISTING_BASELINE=$(jq -r '.bot_review_baseline // empty' "$STATE_FILE" 2>/dev/null || true)
  echo "Warning: Loop '$LOOP_NAME' already active. Resetting (preserving phase: ${EXISTING_PHASE:-<none>}, baseline: ${EXISTING_BASELINE:-<none>})..."
fi

# Preserve existing phase from state file, fall back to INITIAL_PHASE for fresh runs
PHASE="${EXISTING_PHASE:-$INITIAL_PHASE}"

# Derive session ID from transcript path or env
SESSION_ID=""
if [ -n "${CLAUDE_SESSION_ID:-}" ]; then
  SESSION_ID="$CLAUDE_SESSION_ID"
elif [ -d ".claude" ]; then
  # Try to find the most recent transcript file and use its name as session ID
  LATEST_TRANSCRIPT=$(find .claude -name "*.jsonl" -maxdepth 1 2>/dev/null | sort -t/ -k2 | tail -1 || true)
  if [ -n "$LATEST_TRANSCRIPT" ]; then
    SESSION_ID=$(basename "$LATEST_TRANSCRIPT" .jsonl)
  fi
fi

# Build max_iterations as number or null
MAX_ITER_JSON="null"
if [ -n "$MAX_ITERATIONS" ]; then
  MAX_ITER_JSON="$MAX_ITERATIONS"
fi

# Build phase_messages as object or empty object
PHASE_MSGS_JSON="{}"
if [ -n "$PHASE_MESSAGES_JSON" ]; then
  # Validate it's valid JSON
  if echo "$PHASE_MESSAGES_JSON" | jq empty 2>/dev/null; then
    PHASE_MSGS_JSON="$PHASE_MESSAGES_JSON"
  fi
fi

# Create JSON state file (atomic write via temp file)
TMP_FILE="${STATE_FILE}.tmp"
jq -n \
  --arg loop_name "$LOOP_NAME" \
  --argjson iteration 1 \
  --argjson max_iterations "$MAX_ITER_JSON" \
  --arg completion_promise "$COMPLETION_PROMISE" \
  --arg phase "$PHASE" \
  --arg bot_review_baseline "${EXISTING_BASELINE:-}" \
  --arg started_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg session_id "$SESSION_ID" \
  --argjson phase_messages "$PHASE_MSGS_JSON" \
  '{
    loop_name: $loop_name,
    iteration: $iteration,
    max_iterations: $max_iterations,
    completion_promise: $completion_promise,
    phase: $phase,
    bot_review_baseline: $bot_review_baseline,
    started_at: $started_at,
    session_id: $session_id,
    phase_messages: $phase_messages
  }' > "$TMP_FILE" && mv "$TMP_FILE" "$STATE_FILE"

echo "Loop initialized: $LOOP_NAME"
echo "Output <done>$COMPLETION_PROMISE</done> when all completion criteria are met."
