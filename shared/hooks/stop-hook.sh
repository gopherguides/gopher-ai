#!/bin/bash
# Generic stop hook - works for any plugin using loop state files
# This hook intercepts session exit and re-feeds the prompt until completion criteria are met.
#
# How it works:
# 1. Check for any active loop state files (.claude/*.loop.local.md)
# 2. If no active loop, allow normal exit
# 3. If loop active, check for completion (max iterations or completion promise)
# 4. If not complete, block exit and re-feed the prompt

set -euo pipefail

# Source shared library for state management
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_PATH="$SCRIPT_DIR/../lib/loop-state.sh"

if [ ! -f "$LIB_PATH" ]; then
  # Library not found - allow exit to prevent broken state
  echo '{}'
  exit 0
fi

source "$LIB_PATH"

# Find any active loop state file
STATE_FILES=$(find_active_loops)

if [ -z "$STATE_FILES" ]; then
  # No active loop - allow normal exit
  echo '{}'
  exit 0
fi

# Process the first active loop (should only be one at a time)
STATE_FILE=$(echo "$STATE_FILES" | head -1)

# Verify state file exists and is readable
if [ ! -f "$STATE_FILE" ] || [ ! -r "$STATE_FILE" ]; then
  echo '{}'
  exit 0
fi

# Read state from file
read_loop_state "$STATE_FILE"

# Validate iteration is a number
if ! [[ "$ITERATION" =~ ^[0-9]+$ ]]; then
  # Invalid state - cleanup and allow exit
  cleanup_loop "$STATE_FILE"
  echo '{}'
  exit 0
fi

# Check if max iterations reached (if set)
if [ -n "$MAX_ITERATIONS" ] && [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  if [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
    cleanup_loop "$STATE_FILE"
    echo '{}'
    exit 0
  fi
fi

# Check for completion promise in transcript
if [ -n "$COMPLETION_PROMISE" ]; then
  if check_completion_promise "$COMPLETION_PROMISE"; then
    cleanup_loop "$STATE_FILE"
    echo '{}'
    exit 0
  fi
fi

# Increment iteration counter
increment_iteration "$STATE_FILE"
NEW_ITERATION=$((ITERATION + 1))

# Build system message with iteration info and guidance
SYSTEM_MSG="Iteration $NEW_ITERATION of loop '$LOOP_NAME'. Continue working on the task."

# Add guidance after many iterations
if [ "$NEW_ITERATION" -ge 15 ]; then
  SYSTEM_MSG="$SYSTEM_MSG WARNING: $NEW_ITERATION iterations reached. If blocked, document what's preventing progress and ask the user for guidance."
fi

SYSTEM_MSG="$SYSTEM_MSG Output <done>$COMPLETION_PROMISE</done> ONLY when ALL completion criteria are met."

# Block exit and re-feed prompt
# Note: Using printf to handle special characters in prompt
printf '{"decision": "block", "reason": "%s", "systemMessage": "%s"}\n' \
  "$(echo "$ORIGINAL_PROMPT" | sed 's/"/\\"/g' | tr '\n' ' ')" \
  "$(echo "$SYSTEM_MSG" | sed 's/"/\\"/g')"
