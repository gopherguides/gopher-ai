#!/bin/bash
# Shared functions for loop state management (JSON-based)
# Used by stop-hook.sh and other loop-related scripts
# Requires: jq

# Debug log file location
LOOP_DEBUG_LOG=".claude/loop-debug.log"

# Write a timestamped entry to the debug log
loop_log() {
  local msg="$1"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  mkdir -p .claude
  echo "[$ts] $msg" >> "$LOOP_DEBUG_LOG"
}

# Read loop state from a JSON state file
# Sets global variables: ITERATION, MAX_ITERATIONS, COMPLETION_PROMISE, LOOP_NAME, PHASE, ORIGINAL_PROMPT
read_loop_state() {
  local state_file="$1"
  ITERATION=$(jq -r '.iteration // 0' "$state_file")
  MAX_ITERATIONS=$(jq -r '.max_iterations // empty' "$state_file")
  COMPLETION_PROMISE=$(jq -r '.completion_promise // empty' "$state_file")
  LOOP_NAME=$(jq -r '.loop_name // empty' "$state_file")
  PHASE=$(jq -r '.phase // empty' "$state_file")
  ORIGINAL_PROMPT=$(jq -r '.original_prompt // empty' "$state_file")
  loop_log "read_loop_state: file=$state_file loop=$LOOP_NAME iter=$ITERATION phase=$PHASE"
}

# Increment the iteration counter in a state file (atomic write via temp file)
increment_iteration() {
  local state_file="$1"
  local tmp_file="${state_file}.tmp"
  jq '.iteration = (.iteration + 1)' "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
  loop_log "increment_iteration: file=$state_file new_iteration=$((ITERATION + 1))"
}

# Set the phase field in a state file (atomic write via temp file)
set_loop_phase() {
  local state_file="$1"
  local new_phase="$2"
  local tmp_file="${state_file}.tmp"
  jq --arg phase "$new_phase" '.phase = $phase' "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
  loop_log "set_loop_phase: file=$state_file phase=$new_phase"
}

# Get a custom field from the state file
get_loop_field() {
  local state_file="$1"
  local field="$2"
  jq -r --arg f "$field" '.[$f] // empty' "$state_file"
}

# Set a custom field in the state file (atomic write via temp file)
set_loop_field() {
  local state_file="$1"
  local field="$2"
  local value="$3"
  local tmp_file="${state_file}.tmp"
  jq --arg f "$field" --arg v "$value" '.[$f] = $v' "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
}

# Remove a loop state file (cleanup)
cleanup_loop() {
  local state_file="$1"
  loop_log "cleanup_loop: file=$state_file"
  rm -f "$state_file"
}

# Check if the completion promise appears in recent transcript output
# Checks ALL text blocks in last N assistant messages (not just the last one)
# Returns 0 if found, 1 if not found
check_completion_promise() {
  local promise="$1"
  local transcript="$2"

  if [ -z "$transcript" ]; then
    transcript=".claude/transcript.jsonl"
  fi

  if [ ! -f "$transcript" ]; then
    loop_log "check_completion_promise: transcript not found at $transcript"
    return 1
  fi

  local last_lines
  last_lines=$(grep '"role":"assistant"' "$transcript" 2>/dev/null | tail -n 100 || true)

  if [ -z "$last_lines" ]; then
    loop_log "check_completion_promise: no assistant messages in transcript"
    return 1
  fi

  set +e
  local all_text
  all_text=$(echo "$last_lines" | jq -rs '
    [.[] | .message.content[]? | select(.type == "text") | .text] | join("\n")
  ' 2>/dev/null)
  local jq_exit=$?
  set -e

  if [ $jq_exit -ne 0 ]; then
    loop_log "check_completion_promise: jq failed with exit $jq_exit"
    return 1
  fi

  # Trim whitespace and check for promise in any text block
  if echo "$all_text" | grep -q "<done>${promise}</done>"; then
    loop_log "check_completion_promise: FOUND promise '$promise'"
    return 0
  fi

  # Also check with whitespace tolerance (promise may have surrounding spaces/newlines)
  if echo "$all_text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -q "<done>[[:space:]]*${promise}[[:space:]]*</done>"; then
    loop_log "check_completion_promise: FOUND promise '$promise' (with whitespace)"
    return 0
  fi

  loop_log "check_completion_promise: NOT found promise '$promise'"
  return 1
}

# Find all active loop state files
find_active_loops() {
  find .claude -name "*.loop.local.json" 2>/dev/null
}

# Get the count of active loops
count_active_loops() {
  local count
  count=$(find_active_loops | wc -l | tr -d ' ')
  echo "$count"
}

# Wrapper for setup-loop.sh script so it works when sourced as a library
# Compatible with both bash (BASH_SOURCE) and zsh (CLAUDE_PLUGIN_ROOT)
setup_loop() {
  local script_dir
  if [ -n "${BASH_SOURCE[0]:-}" ]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    script_dir="${CLAUDE_PLUGIN_ROOT}/scripts"
  else
    echo "Error: Cannot locate setup-loop.sh (set CLAUDE_PLUGIN_ROOT)" >&2
    return 1
  fi
  "$script_dir/setup-loop.sh" "$@"
}
