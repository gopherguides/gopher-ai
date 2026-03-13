#!/bin/bash
# Generic stop hook - works for any plugin using loop state files
# This hook intercepts session exit and re-feeds the prompt until completion criteria are met.
#
# How it works:
# 1. Read hook input from stdin to get transcript path
# 2. Check for any active loop state files (.claude/*.loop.local.md)
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
  # Library not found - allow exit to prevent broken state
  exit 0
fi

source "$LIB_PATH"

# Find any active loop state file
STATE_FILES=$(find_active_loops)

if [ -z "$STATE_FILES" ]; then
  # No active loop - allow normal exit
  exit 0
fi

# Process the first active loop (should only be one at a time)
STATE_FILE=$(echo "$STATE_FILES" | head -1)

# Verify state file exists and is readable
if [ ! -f "$STATE_FILE" ] || [ ! -r "$STATE_FILE" ]; then
  exit 0
fi

# Read state from file
read_loop_state "$STATE_FILE"

# Check if loop is stale (from a previous session)
# Compare state file's started_at against the current transcript file's creation time.
# If the transcript is newer than the loop, the loop is from a dead session.
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  STARTED_AT=$(grep '^started_at:' "$STATE_FILE" | sed 's/started_at: *//')
  if [ -n "$STARTED_AT" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      TRANSCRIPT_BIRTH=$(stat -f %B "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
      LOOP_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$STARTED_AT" +%s 2>/dev/null || echo "0")
    else
      TRANSCRIPT_BIRTH=$(stat -c %W "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
      LOOP_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null || echo "0")
    fi
    if [ "$LOOP_EPOCH" -gt 0 ] && [ "$TRANSCRIPT_BIRTH" -gt 0 ] && [ "$TRANSCRIPT_BIRTH" -gt "$LOOP_EPOCH" ]; then
      cleanup_loop "$STATE_FILE"
      exit 0
    fi
  fi
fi

# Validate iteration is a number
if ! [[ "$ITERATION" =~ ^[0-9]+$ ]]; then
  # Invalid state - cleanup and allow exit
  cleanup_loop "$STATE_FILE"
  exit 0
fi

# Check if max iterations reached (if set)
if [ -n "$MAX_ITERATIONS" ] && [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  if [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
    cleanup_loop "$STATE_FILE"
    exit 0
  fi
fi

# Check for completion promise in transcript
if [ -n "$COMPLETION_PROMISE" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  LAST_LINES=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 100 || true)

  if [ -n "$LAST_LINES" ]; then
    set +e
    LAST_OUTPUT=$(echo "$LAST_LINES" | jq -rs '
      map(.message.content[]? | select(.type == "text") | .text) | last // ""
    ' 2>&1)
    JQ_EXIT=$?
    set -e

    if [ $JQ_EXIT -eq 0 ] && echo "$LAST_OUTPUT" | grep -q "<done>$COMPLETION_PROMISE</done>"; then
      cleanup_loop "$STATE_FILE"
      exit 0
    fi
  fi
fi

# Increment iteration counter
increment_iteration "$STATE_FILE"
NEW_ITERATION=$((ITERATION + 1))

# Build system message with iteration info and guidance
SYSTEM_MSG="Iteration $NEW_ITERATION of loop '$LOOP_NAME'."

# Phase-aware re-feed: use targeted message based on current phase
if [ "$PHASE" = "watching" ]; then
  REASON="Resume Step 12: Check bot approval status, poll if needed. Do NOT re-run Steps 1-11."
  SYSTEM_MSG="$SYSTEM_MSG RESUME AT STEP 12a: The fix cycle (Steps 1-11) is already complete. Check bot approval status and poll for re-reviews. Do NOT restart the fix cycle."
elif [ "$PHASE" = "reviewing" ]; then
  REASON="Continue the review loop: run the next LLM review pass and address findings."
  SYSTEM_MSG="$SYSTEM_MSG Resume the review-fix-verify cycle. Run the next review pass."
elif [ "$PHASE" = "fixing" ]; then
  REASON="Continue fixing: address remaining review findings, then verify."
  SYSTEM_MSG="$SYSTEM_MSG Continue addressing review findings."
elif [ "$PHASE" = "verifying" ]; then
  REASON="Continue verification: run build, test, and lint on fixes."
  SYSTEM_MSG="$SYSTEM_MSG Verify fixes pass build, test, and lint."
elif [ "$PHASE" = "addressing" ]; then
  REASON="Resume: address bot review feedback, then re-watch CI and bots."
  SYSTEM_MSG="$SYSTEM_MSG Resume addressing bot review feedback (Steps 2-11 of address-review). After fixes, return to CI watch."
elif [ "$PHASE" = "pushing" ]; then
  REASON="Resume: push changes and ensure PR exists."
  SYSTEM_MSG="$SYSTEM_MSG Resume pushing changes to remote and PR creation/detection."
elif [ "$PHASE" = "ci-watch" ]; then
  REASON="Resume: watch CI status and fix failures."
  SYSTEM_MSG="$SYSTEM_MSG Resume CI monitoring. Run gh pr checks and fix any failures."
elif [ "$PHASE" = "merging" ]; then
  REASON="Resume: merge the PR."
  SYSTEM_MSG="$SYSTEM_MSG Verify CI green and bot approval, then merge the PR."
else
  REASON="$ORIGINAL_PROMPT"
  SYSTEM_MSG="$SYSTEM_MSG Continue working on the task."
fi

# Add guidance after many iterations
if [ "$NEW_ITERATION" -ge 15 ]; then
  SYSTEM_MSG="$SYSTEM_MSG WARNING: $NEW_ITERATION iterations reached. If blocked, document what's preventing progress and ask the user for guidance."
fi

SYSTEM_MSG="$SYSTEM_MSG Output <done>$COMPLETION_PROMISE</done> ONLY when ALL completion criteria are met."

# Block exit and re-feed prompt
jq -n --arg reason "$REASON" --arg msg "$SYSTEM_MSG" \
  '{"decision": "block", "reason": $reason, "systemMessage": $msg}'
