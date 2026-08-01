#!/bin/bash
# Generic stop hook - works for any plugin using loop state files (JSON-based)
# This hook intercepts session exit and re-feeds the prompt until completion criteria are met.
#
# How it works:
# 1. Read hook input from stdin to get transcript path
# 2. Check for any active loop state files (.local/state/*.loop.local.json)
# 3. If no active loop, allow normal exit
# 4. If loop active, check for completion (max iterations or completion promise in transcript)
# 5. If not complete, block exit and re-feed the prompt
#
# Requires: jq

set -euo pipefail

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Extract transcript path from hook input
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# Source shared library for state management
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_PATH="$SCRIPT_DIR/../lib/loop-state.sh"

if [ ! -f "$LIB_PATH" ]; then
  exit 0
fi

source "$LIB_PATH"

loop_log "stop-hook: entered, transcript=$TRANSCRIPT_PATH"

block_stop() {
  local reason="$1"
  local message="$2"
  if ! printf '%s' "$reason" | grep '[^[:space:]]' >/dev/null; then
    reason="Loop execution is blocked by invalid state."
  fi
  jq -n --arg reason "$reason" --arg msg "$message" \
    '{"decision": "block", "reason": $reason, "systemMessage": $msg}'
}

# Find any active loop state file
STATE_FILES=$(find_active_loops)

if [ -z "$STATE_FILES" ]; then
  loop_log "stop-hook: no active loops found"
  exit 0
fi

STATE_COUNT=$(printf '%s\n' "$STATE_FILES" | wc -l | tr -d ' ')
if [ "$STATE_COUNT" -ne 1 ]; then
  MULTIPLE_REASON=$(printf 'Multiple active loop states were found; ownership is ambiguous:\n%s' "$STATE_FILES")
  loop_log "stop-hook: refusing ambiguous active loops: $STATE_FILES"
  block_stop "$MULTIPLE_REASON" \
    "$MULTIPLE_REASON Cancel the orphaned loop states or restore one caller-owned state before continuing."
  exit 0
fi

STATE_FILE="$STATE_FILES"

# Verify state file exists and is readable
if [ ! -f "$STATE_FILE" ] || [ ! -r "$STATE_FILE" ]; then
  loop_log "stop-hook: state file not readable: $STATE_FILE"
  block_stop "Loop state is not readable: $STATE_FILE" \
    "The active loop state cannot be read. Repair or cancel it before continuing."
  exit 0
fi

# Validate JSON before proceeding
if ! jq empty "$STATE_FILE" 2>/dev/null; then
  loop_log "stop-hook: invalid JSON in state file: $STATE_FILE"
  block_stop "Loop state is invalid JSON: $STATE_FILE" \
    "The active loop state is invalid. Repair or cancel it before continuing."
  exit 0
fi

if ! SCHEMA_ERROR=$(ensure_loop_state_schema "$STATE_FILE" 2>&1); then
  loop_log "stop-hook: invalid state contract: $SCHEMA_ERROR"
  block_stop "$SCHEMA_ERROR" \
    "The active loop state contract is invalid. Repair or cancel it before continuing."
  exit 0
fi

if ! read_loop_state "$STATE_FILE" '[]' 2>/dev/null; then
  loop_log "stop-hook: unable to read state: $STATE_FILE"
  block_stop "Unable to read active loop state: $STATE_FILE" \
    "The active loop state cannot be resumed. Repair or cancel it before continuing."
  exit 0
fi

# Check if loop is stale (from a previous session)
# Primary: Compare session ID (portable, instant)
STORED_SESSION_ID=$(jq -r '.session_id // empty' "$STATE_FILE")

if [ -n "$STORED_SESSION_ID" ] && [ -n "$TRANSCRIPT_PATH" ]; then
  CURRENT_SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl 2>/dev/null || true)
  if [ -n "$CURRENT_SESSION_ID" ] && [ "$STORED_SESSION_ID" != "$CURRENT_SESSION_ID" ]; then
    loop_log "stop-hook: stale session detected (stored=$STORED_SESSION_ID current=$CURRENT_SESSION_ID), cleaning up"
    cleanup_loop "$STATE_FILE"
    exit 0
  fi
fi

# Fallback: Timestamp-based stale detection
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  STARTED_AT=$(jq -r '.started_at // empty' "$STATE_FILE")
  if [ -n "$STARTED_AT" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      TRANSCRIPT_BIRTH=$(stat -f %B "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
      LOOP_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$STARTED_AT" +%s 2>/dev/null || echo "0")
    else
      TRANSCRIPT_BIRTH=$(stat -c %W "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
      LOOP_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null || echo "0")
    fi
    if [ "$LOOP_EPOCH" -gt 0 ] && [ "$TRANSCRIPT_BIRTH" -gt 0 ] && [ "$TRANSCRIPT_BIRTH" -gt "$LOOP_EPOCH" ]; then
      loop_log "stop-hook: stale loop detected via timestamp (loop=$STARTED_AT transcript_birth=$TRANSCRIPT_BIRTH)"
      cleanup_loop "$STATE_FILE"
      exit 0
    fi
  fi
fi

# Validate iteration is a number
if ! [[ "$ITERATION" =~ ^[0-9]+$ ]]; then
  loop_log "stop-hook: invalid iteration '$ITERATION'"
  block_stop "Loop state has invalid iteration '$ITERATION': $STATE_FILE" \
    "The active loop iteration is invalid. Repair or cancel it before continuing."
  exit 0
fi

if [ "$AWAITING_DRIVER_INPUT" = "true" ]; then
  loop_log "stop-hook: allowing exit while waiting for driver input: $DRIVER_INPUT_REASON"
  exit 0
fi

# Check if max iterations reached (if set)
if [ -n "$MAX_ITERATIONS" ] && [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  if [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
    loop_log "stop-hook: max iterations reached ($ITERATION >= $MAX_ITERATIONS)"
    cleanup_loop "$STATE_FILE"
    exit 0
  fi
fi

# Check for completion promise in transcript (robust: all text blocks, whitespace-tolerant)
if [ -n "$COMPLETION_PROMISE" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  loop_log "stop-hook: checking completion promise '$COMPLETION_PROMISE'"
  if check_completion_promise "$COMPLETION_PROMISE" "$TRANSCRIPT_PATH"; then
    loop_log "stop-hook: completion promise found, cleaning up"
    cleanup_loop "$STATE_FILE"
    exit 0
  fi
fi

# Increment iteration counter
increment_iteration "$STATE_FILE"
NEW_ITERATION=$((ITERATION + 1))

# Build system message with iteration info and guidance
SYSTEM_MSG="Iteration $NEW_ITERATION of loop '$LOOP_NAME'."

# Phase-aware re-feed: look up phase message from state file, fall back to generic
PHASE_MSG=""
if [ "$LOOP_NAME" = "ship" ] && [ "$PHASE" = "reviewing" ]; then
  RECOVERY_TMP="${STATE_FILE}.tmp"
  jq '
    .review_result = "void" |
    .review_skip_reason = "session-boundary" |
    .phase = "pushing" |
    if (.components.ship? | type) == "object" then
      .components.ship.review_result = "void" |
      .components.ship.review_skip_reason = "session-boundary" |
      .components.ship.phase = "pushing"
    else . end
  ' \
    "$STATE_FILE" > "$RECOVERY_TMP" && mv "$RECOVERY_TMP" "$STATE_FILE"
  PHASE="pushing"
  PHASE_MSG="The prior in-session review is void. Do not start another review. Commit the validated staged diff, push every local commit, and ensure a non-draft PR exists before yielding."
elif [ -n "$PHASE" ]; then
  PHASE_MSG=$(jq -r --arg p "$PHASE" '.phase_messages[$p] // empty' "$STATE_FILE" 2>/dev/null || true)
fi

if [ -n "$PHASE_MSG" ]; then
  REASON="$PHASE_MSG"
  SYSTEM_MSG="$SYSTEM_MSG $PHASE_MSG"
  loop_log "stop-hook: phase '$PHASE' matched phase_messages entry"
else
  # Fallback to generic phase messages for backward compatibility
  case "$PHASE" in
    watching)
      REASON="Resume Step 12: Check bot approval status, poll if needed. Do NOT re-run Steps 1-11."
      SYSTEM_MSG="$SYSTEM_MSG RESUME AT STEP 12a: The fix cycle (Steps 1-11) is already complete. Check bot approval status and poll for re-reviews. Do NOT restart the fix cycle."
      ;;
    reviewing)
      REASON="Continue the review loop: run the next LLM review pass and address findings."
      SYSTEM_MSG="$SYSTEM_MSG Resume the review-fix-verify cycle. Run the next review pass."
      ;;
    fixing)
      REASON="Continue fixing: address remaining review findings, then verify."
      SYSTEM_MSG="$SYSTEM_MSG Continue addressing review findings."
      ;;
    verifying)
      REASON="Continue verification: run build, test, and lint on fixes."
      SYSTEM_MSG="$SYSTEM_MSG Verify fixes pass build, test, and lint."
      ;;
    bot-watching)
      REASON="Resume: poll for bot review approval or new feedback."
      SYSTEM_MSG="$SYSTEM_MSG Resume bot approval polling (Step 11). Check discovered bots for approval status. If bots request changes, go to Step 12. If all approved, go to Step 13."
      ;;
    addressing)
      REASON="Resume: address bot review feedback, then re-watch CI and bots."
      SYSTEM_MSG="$SYSTEM_MSG Resume addressing bot review feedback (Steps 2-11 of address-review). After fixes, return to CI watch."
      ;;
    pushing)
      REASON="Resume: push changes and ensure PR exists."
      SYSTEM_MSG="$SYSTEM_MSG Resume pushing changes to remote and PR creation/detection."
      ;;
    ci-watch)
      REASON="Resume: watch CI status and fix failures."
      SYSTEM_MSG="$SYSTEM_MSG Resume CI monitoring. Run gh pr checks and fix any failures."
      ;;
    merging)
      REASON="Resume: merge the PR."
      SYSTEM_MSG="$SYSTEM_MSG Verify CI green and bot approval, then merge the PR."
      ;;
    *)
      REASON="$ORIGINAL_PROMPT"
      SYSTEM_MSG="$SYSTEM_MSG Continue working on the task."
      ;;
  esac
  loop_log "stop-hook: phase '$PHASE' used fallback message"
fi

# Add guidance after many iterations
if [ "$NEW_ITERATION" -ge 15 ]; then
  SYSTEM_MSG="$SYSTEM_MSG WARNING: $NEW_ITERATION iterations reached. If blocked, document what's preventing progress and ask the user for guidance."
fi

SYSTEM_MSG="$SYSTEM_MSG Output <done>$COMPLETION_PROMISE</done> ONLY when ALL completion criteria are met."

if ! printf '%s' "$REASON" | grep '[^[:space:]]' >/dev/null; then
  REASON="Continue working on the task."
fi

loop_log "stop-hook: blocking exit, reason='$REASON'"

# Block exit and re-feed prompt
jq -n --arg reason "$REASON" --arg msg "$SYSTEM_MSG" \
  '{"decision": "block", "reason": $reason, "systemMessage": $msg}'
