#!/bin/bash

set -euo pipefail

LOOP_NAME="${1:-}"
COMPLETION_PROMISE="${2:-COMPLETE}"
MAX_ITERATIONS="${3:-}"
INITIAL_PHASE="${4:-}"
PHASE_MESSAGES_JSON="${5:-}"
EXPLICIT_STATE_FILE="${6:-}"
TERMINAL_PROMISES_JSON="${7:-}"

if [ -z "$LOOP_NAME" ]; then
  printf 'Error: loop-name is required\n' >&2
  printf 'Usage: setup-loop.sh <loop-name> <completion-promise> [max-iterations] [initial-phase] [phase-messages-json] [absolute-state-file] [terminal-promises-json]\n' >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/loop-state.sh"

SAFE_LOOP_NAME=$(printf '%s\n' "$LOOP_NAME" | sed 's/[^a-zA-Z0-9_-]/-/g')
OWNER_STATE_DIR=$(loop_state_directory)
mkdir -p "$OWNER_STATE_DIR"
OWNER_STATE_DIR=$(cd "$OWNER_STATE_DIR" && pwd -P)
if [ -n "$EXPLICIT_STATE_FILE" ]; then
  case "$EXPLICIT_STATE_FILE" in
    /*) STATE_FILE="$EXPLICIT_STATE_FILE" ;;
    *)
      printf 'Error: explicit state file must be an absolute path.\n' >&2
      exit 1
      ;;
  esac
else
  STATE_FILE="$OWNER_STATE_DIR/${SAFE_LOOP_NAME}.loop.local.json"
fi
STATE_DIR=$(dirname "$STATE_FILE")
mkdir -p "$STATE_DIR"
STATE_DIR=$(cd "$STATE_DIR" && pwd -P)
STATE_FILE="$STATE_DIR/$(basename "$STATE_FILE")"
if [ "$STATE_DIR" != "$OWNER_STATE_DIR" ]; then
  printf 'Error: explicit state file must be directly under the owner state directory: %s\n' \
    "$OWNER_STATE_DIR" >&2
  exit 1
fi

if [ -z "$TERMINAL_PROMISES_JSON" ]; then
  TERMINAL_PROMISES_JSON=$(jq -cn --arg promise "$COMPLETION_PROMISE" '[$promise]')
fi
validate_terminal_promises_json "$TERMINAL_PROMISES_JSON" "$COMPLETION_PROMISE"
TERMINAL_PROMISES_JSON=$(printf '%s\n' "$TERMINAL_PROMISES_JSON" | jq -c .)

LOCK_DIR="$OWNER_STATE_DIR/.loop-setup.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  printf 'Error: another loop setup is active for %s.\n' "$STATE_DIR" >&2
  exit 1
fi
release_setup_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap release_setup_lock EXIT

STATE_FILES=$(find_active_loops "$OWNER_STATE_DIR")
ACTIVE_COUNT=$(count_active_loops "$OWNER_STATE_DIR")
if [ -f "$STATE_FILE" ]; then
  if [ "$ACTIVE_COUNT" -ne 1 ]; then
    printf 'Error: loop re-entry is ambiguous because multiple active states exist:\n%s\n' \
      "$STATE_FILES" >&2
    exit 1
  fi
  ensure_loop_state_schema "$STATE_FILE"
  STORED_LOOP_NAME=$(jq -r '.loop_name' "$STATE_FILE")
  if [ "$STORED_LOOP_NAME" != "$LOOP_NAME" ]; then
    printf "Error: explicit state belongs to loop '%s', not '%s'.\n" \
      "$STORED_LOOP_NAME" "$LOOP_NAME" >&2
    exit 1
  fi
  if ! jq -e --arg promise "$COMPLETION_PROMISE" \
    '.terminal_promises | index($promise) != null' "$STATE_FILE" >/dev/null 2>&1; then
    printf "Error: requested promise '%s' is not allowlisted by active loop '%s'.\n" \
      "$COMPLETION_PROMISE" "$LOOP_NAME" >&2
    exit 1
  fi
  if [ -n "${7:-}" ] && ! jq -e --argjson declared "$TERMINAL_PROMISES_JSON" \
    '.terminal_promises == $declared' "$STATE_FILE" >/dev/null 2>&1; then
    printf "Error: terminal promise allowlist for active loop '%s' is immutable.\n" \
      "$LOOP_NAME" >&2
    exit 1
  fi
  printf "Loop already active: %s\n" "$LOOP_NAME"
  exit 0
fi

if [ "$ACTIVE_COUNT" -ne 0 ]; then
  printf "Error: cannot start loop '%s'; another loop is already active:\n%s\n" \
    "$LOOP_NAME" "$STATE_FILES" >&2
  exit 1
fi

SESSION_ID=""
if [ -n "${CLAUDE_SESSION_ID:-}" ]; then
  SESSION_ID="$CLAUDE_SESSION_ID"
elif [ -d ".claude" ]; then
  LATEST_TRANSCRIPT=$(find .claude -maxdepth 1 -name '*.jsonl' 2>/dev/null | LC_ALL=C sort | tail -n 1 || true)
  if [ -n "$LATEST_TRANSCRIPT" ]; then
    SESSION_ID=$(basename "$LATEST_TRANSCRIPT" .jsonl)
  fi
fi

MAX_ITER_JSON="null"
if [ -n "$MAX_ITERATIONS" ]; then
  MAX_ITER_JSON="$MAX_ITERATIONS"
fi
if ! printf '%s\n' "$MAX_ITER_JSON" | jq -e \
  '. == null or (type == "number" and floor == . and . > 0)' >/dev/null 2>&1; then
  printf 'Error: max-iterations must be a positive integer.\n' >&2
  exit 1
fi

PHASE_MSGS_JSON="{}"
if [ -n "$PHASE_MESSAGES_JSON" ]; then
  if ! PHASE_MSGS_JSON=$(printf '%s\n' "$PHASE_MESSAGES_JSON" | jq -ce \
    'select(type == "object")' 2>/dev/null); then
    printf 'Error: phase-messages-json must be a JSON object.\n' >&2
    exit 1
  fi
fi

OWNER_WORKFLOW=$(owner_workflow_for_loop "$LOOP_NAME")
TMP_FILE="${STATE_FILE}.tmp.$$"
jq -n \
  --argjson schema_version 2 \
  --arg owner_workflow "$OWNER_WORKFLOW" \
  --arg loop_name "$LOOP_NAME" \
  --argjson iteration 1 \
  --argjson max_iterations "$MAX_ITER_JSON" \
  --arg completion_promise "$COMPLETION_PROMISE" \
  --argjson terminal_promises "$TERMINAL_PROMISES_JSON" \
  --arg phase "$INITIAL_PHASE" \
  --arg started_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg session_id "$SESSION_ID" \
  --argjson phase_messages "$PHASE_MSGS_JSON" \
  '{
    schema_version: $schema_version,
    owner_workflow: $owner_workflow,
    loop_name: $loop_name,
    iteration: $iteration,
    max_iterations: $max_iterations,
    completion_promise: $completion_promise,
    terminal_promises: $terminal_promises,
    phase: $phase,
    bot_review_baseline: "",
    started_at: $started_at,
    session_id: $session_id,
    awaiting_driver_input: false,
    driver_input_reason: "",
    phase_messages: $phase_messages,
    components: {}
  }' > "$TMP_FILE" && mv "$TMP_FILE" "$STATE_FILE"

printf 'Loop initialized: %s\n' "$LOOP_NAME"
printf 'Output <done>%s</done> when all completion criteria are met.\n' "$COMPLETION_PROMISE"
