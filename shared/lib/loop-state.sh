#!/bin/bash
# Shared functions for loop state management
# Used by stop-hook.sh and other loop-related scripts

# Read loop state from a state file
# Sets global variables: ITERATION, MAX_ITERATIONS, COMPLETION_PROMISE, LOOP_NAME, PHASE, ORIGINAL_PROMPT
read_loop_state() {
  local state_file="$1"
  ITERATION=$(grep '^iteration:' "$state_file" | sed 's/iteration: *//')
  MAX_ITERATIONS=$(grep '^max_iterations:' "$state_file" | sed 's/max_iterations: *//')
  COMPLETION_PROMISE=$(grep '^completion_promise:' "$state_file" | sed 's/completion_promise: *//')
  LOOP_NAME=$(grep '^loop_name:' "$state_file" | sed 's/loop_name: *//')
  PHASE=$(grep '^phase:' "$state_file" | sed 's/phase: *//' || true)
  # Get content after the second --- (the prompt/body)
  ORIGINAL_PROMPT=$(awk '/^---$/{p++; next} p==2' "$state_file")
}

# Increment the iteration counter in a state file
increment_iteration() {
  local state_file="$1"
  local new_iteration=$((ITERATION + 1))

  # Use portable sed syntax (works on both macOS and Linux)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/^iteration: .*/iteration: $new_iteration/" "$state_file"
  else
    sed -i "s/^iteration: .*/iteration: $new_iteration/" "$state_file"
  fi
}

# Set the phase field in a state file
set_loop_phase() {
  local state_file="$1"
  local new_phase="$2"

  if grep -q '^phase:' "$state_file"; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s/^phase: .*/phase: $new_phase/" "$state_file"
    else
      sed -i "s/^phase: .*/phase: $new_phase/" "$state_file"
    fi
  else
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "/^completion_promise:/a\\
phase: $new_phase" "$state_file"
    else
      sed -i "/^completion_promise:/a phase: $new_phase" "$state_file"
    fi
  fi
}

# Remove a loop state file (cleanup)
cleanup_loop() {
  local state_file="$1"
  rm -f "$state_file"
}

# Check if the completion promise appears in recent transcript output
# Returns 0 if found, 1 if not found
check_completion_promise() {
  local promise="$1"
  local transcript=".claude/transcript.jsonl"

  if [ -f "$transcript" ]; then
    # Check the last 10 lines of transcript for the completion promise
    # The promise should be wrapped in <done>...</done> tags
    if tail -10 "$transcript" | grep -q "<done>$promise</done>"; then
      return 0
    fi
  fi
  return 1
}

# Find all active loop state files
find_active_loops() {
  find .claude -name "*.loop.local.md" 2>/dev/null
}

# Get the count of active loops
count_active_loops() {
  local count
  count=$(find_active_loops | wc -l | tr -d ' ')
  echo "$count"
}
