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

# Check for completion promise in transcript using proper JSON parsing
if [ -n "$COMPLETION_PROMISE" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  # Get the last assistant message from the transcript
  LAST_ASSISTANT=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 || true)

  if [ -n "$LAST_ASSISTANT" ]; then
    # Extract text content from the message using jq
    MESSAGE_TEXT=$(echo "$LAST_ASSISTANT" | jq -r '
      .message.content[]? |
      select(.type == "text") |
      .text // empty
    ' 2>/dev/null | tr '\n' ' ' || true)

    # Check if the completion promise (wrapped in <done>...</done>) appears in the text
    if echo "$MESSAGE_TEXT" | grep -q "<done>$COMPLETION_PROMISE</done>"; then
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

# Phase-aware re-feed: use targeted message for watching phase
if [ "$PHASE" = "watching" ]; then
  REASON="Resume Step 12: Check bot approval status, poll if needed. Do NOT re-run Steps 1-11."
  SYSTEM_MSG="$SYSTEM_MSG RESUME AT STEP 12a: The fix cycle (Steps 1-11) is already complete. Check bot approval status and poll for re-reviews. Do NOT restart the fix cycle."
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
# Note: Using printf to handle special characters in prompt
printf '{"decision": "block", "reason": "%s", "systemMessage": "%s"}\n' \
  "$(echo "$REASON" | sed 's/"/\\"/g' | tr '\n' ' ')" \
  "$(echo "$SYSTEM_MSG" | sed 's/"/\\"/g')"
