#!/bin/bash

resolve_loop_owner_root() {
  local root
  root=""
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    root=$(git worktree list --porcelain 2>/dev/null | awk '
      /^worktree / {
        sub(/^worktree /, "")
        print
        exit
      }
    ')
  fi
  if [ -z "$root" ]; then
    root=$(pwd -P)
  fi
  printf '%s\n' "$root"
}

resolve_loop_worktree_root() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -z "$root" ]; then
    root=$(pwd -P)
  elif [ -d "$root" ]; then
    root=$(cd "$root" && pwd -P)
  fi
  printf '%s\n' "$root"
}

loop_state_directory() {
  printf '%s/.local/state\n' "$(resolve_loop_owner_root)"
}

# The debug log is off unless GO_WORKFLOW_DEBUG=1, and it does not live inside
# the user's repository. Loop *state* belongs to the worktree; a debug log does
# not. Writing one unconditionally leaves an untracked file — and creates its
# directory — in whatever project the session happens to be in, and an untracked
# file in someone's checkout is not free: plenty of tooling treats a dirty
# working tree as a signal and refuses to act on it, so a log nobody asked for
# can quietly stop a sync, a release script or a CI gate.
#
# Set LOOP_DEBUG_LOG to choose the path.
loop_log() {
  [ "${GO_WORKFLOW_DEBUG:-0}" = "1" ] || return 0
  local msg="$1"
  local log
  local dir
  local ts
  log="${LOOP_DEBUG_LOG:-${TMPDIR:-/tmp}/go-workflow-loop-debug.log}"
  dir=$(dirname "$log")
  [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || return 0
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '[%s] %s\n' "$ts" "$msg" >> "$log"
}

owner_workflow_for_loop() {
  local loop_name="$1"
  case "$loop_name" in
    start-issue-*) printf '%s\n' "start-issue" ;;
    complete-issue-*) printf '%s\n' "complete-issue" ;;
    address-review-*) printf '%s\n' "address-review" ;;
    e2e-verify-*) printf '%s\n' "e2e-verify" ;;
    *) printf '%s\n' "$loop_name" ;;
  esac
}

legacy_terminal_promises() {
  local loop_name="$1"
  local active_promise="$2"
  local promises
  case "$loop_name" in
    ship) promises='["SHIPPED","INCOMPLETE"]' ;;
    e2e-verify-*) promises='["VERIFIED","E2E_FAIL","INCOMPLETE"]' ;;
    start-issue-*|complete-issue-*|address-review-*) promises='["COMPLETE","INCOMPLETE"]' ;;
    *)
      jq -cn --arg promise "$active_promise" '[$promise]'
      return
      ;;
  esac
  if ! printf '%s\n' "$promises" | jq -e --arg promise "$active_promise" \
    'index($promise) != null' >/dev/null 2>&1; then
    printf "Loop '%s' has unsupported legacy completion promise '%s'.\n" \
      "$loop_name" "$active_promise" >&2
    return 1
  fi
  printf '%s\n' "$promises"
}

validate_terminal_promises_json() {
  local promises="$1"
  local active_promise="$2"
  if ! printf '%s\n' "$promises" | jq -e --arg active "$active_promise" '
    type == "array" and
    length > 0 and
    all(.[]; type == "string" and length > 0) and
    (unique | length) == length and
    index($active) != null
  ' >/dev/null 2>&1; then
    printf "Completion promise '%s' must belong to a non-empty unique terminal_promises array.\n" \
      "$active_promise" >&2
    return 1
  fi
}

ensure_loop_state_schema() {
  local state_file="$1"
  local schema_version
  local loop_name
  local active_promise
  local owner_workflow
  local expected_owner
  local promises
  local legacy_mode
  local legacy_phase
  local tmp_file

  if [ ! -f "$state_file" ] || [ ! -r "$state_file" ]; then
    printf 'Loop state is not readable: %s\n' "$state_file" >&2
    return 1
  fi
  if ! jq -e 'type == "object"' "$state_file" >/dev/null 2>&1; then
    printf 'Loop state must be a valid JSON object: %s\n' "$state_file" >&2
    return 1
  fi

  schema_version=$(jq -r '.schema_version // empty' "$state_file")
  loop_name=$(jq -r 'if (.loop_name | type) == "string" then .loop_name else "" end' "$state_file")
  active_promise=$(jq -r 'if (.completion_promise | type) == "string" then .completion_promise else "" end' "$state_file")
  if [ -z "$loop_name" ] || [ -z "$active_promise" ]; then
    printf 'Loop state is missing loop_name or completion_promise: %s\n' "$state_file" >&2
    return 1
  fi
  expected_owner=$(owner_workflow_for_loop "$loop_name")

  if [ -z "$schema_version" ]; then
    case "$loop_name" in
      complete-issue-*)
        printf "Legacy composed loop state cannot be migrated safely because child ownership is unknown: %s. Cancel it and restart complete-issue.\n" \
          "$state_file" >&2
        return 1
        ;;
      e2e-verify-*)
        legacy_mode=$(jq -r 'if (.mode | type) == "string" then .mode else "" end' "$state_file")
        legacy_phase=$(jq -r 'if (.phase | type) == "string" then .phase else "" end' "$state_file")
        if [ "$legacy_mode" = "ship" ] || [ "$legacy_mode" = "fix-and-ship" ] ||
           [ "$legacy_phase" = "shipping" ]; then
          printf "Legacy composed E2E state cannot be migrated safely because ship ownership is unknown: %s. Cancel it and restart e2e-verify.\n" \
            "$state_file" >&2
          return 1
        fi
        ;;
    esac
    if ! jq -e '(.components == null) or (.components | type == "object")' \
      "$state_file" >/dev/null 2>&1; then
      printf 'Legacy loop state has an invalid components field: %s\n' "$state_file" >&2
      return 1
    fi
    promises=$(legacy_terminal_promises "$loop_name" "$active_promise") || return 1
    tmp_file="${state_file}.tmp.$$"
    if ! jq --arg owner "$expected_owner" --argjson promises "$promises" '
      .schema_version = 2 |
      .owner_workflow = $owner |
      .terminal_promises = $promises |
      .components = (.components // {})
    ' "$state_file" > "$tmp_file"; then
      rm -f "$tmp_file"
      printf 'Unable to migrate legacy loop state: %s\n' "$state_file" >&2
      return 1
    fi
    mv "$tmp_file" "$state_file"
    schema_version=2
    loop_log "migrated loop state: file=$state_file schema=2"
  fi

  if ! jq -e '.schema_version == 2' "$state_file" >/dev/null 2>&1; then
    printf "Unsupported loop state schema '%s': %s\n" "$schema_version" "$state_file" >&2
    return 1
  fi
  owner_workflow=$(jq -r 'if (.owner_workflow | type) == "string" then .owner_workflow else "" end' "$state_file")
  if [ "$owner_workflow" != "$expected_owner" ]; then
    printf "Loop state owner '%s' does not match loop '%s'.\n" "$owner_workflow" "$loop_name" >&2
    return 1
  fi
  promises=$(jq -c '.terminal_promises' "$state_file")
  validate_terminal_promises_json "$promises" "$active_promise" || return 1
  if ! jq -e '.components | type == "object"' "$state_file" >/dev/null 2>&1; then
    printf 'Loop state components must be an object: %s\n' "$state_file" >&2
    return 1
  fi
}

normalize_workflow_state_path() {
  local path="${1:-${WORKFLOW_STATE_PATH:-[]}}"
  if ! printf '%s\n' "$path" | jq -ce '
    select(type == "array" and all(.[]; type == "string" and length > 0))
  ' 2>/dev/null; then
    printf 'WORKFLOW_STATE_PATH must be a JSON array of non-empty strings.\n' >&2
    return 1
  fi
}

validate_workflow_field_update() {
  local path="$1"
  local field="$2"
  if [ "$path" = "[]" ]; then
    case "$field" in
      schema_version|owner_workflow|loop_name|completion_promise|terminal_promises|components)
        printf "Root loop field '%s' must be updated by its dedicated helper.\n" "$field" >&2
        return 1
        ;;
    esac
  fi
}

child_workflow_path() {
  local parent_path
  local component="$2"
  parent_path=$(normalize_workflow_state_path "$1") || return 1
  if [ -z "$component" ]; then
    printf 'Component name must be non-empty.\n' >&2
    return 1
  fi
  jq -cn --argjson parent "$parent_path" --arg component "$component" \
    '$parent + ["components", $component]'
}

initialize_workflow_state() {
  local state_file="$1"
  local path
  local tmp_file
  path=$(normalize_workflow_state_path "${2:-${WORKFLOW_STATE_PATH:-[]}}") || return 1
  ensure_loop_state_schema "$state_file" || return 1
  if ! jq -e --argjson path "$path" '
    (getpath($path) == null) or (getpath($path) | type == "object")
  ' "$state_file" >/dev/null 2>&1; then
    printf 'Workflow state path does not resolve to an object: %s\n' "$path" >&2
    return 1
  fi
  tmp_file="${state_file}.tmp.$$"
  jq --argjson path "$path" '
    setpath($path; (getpath($path) // {})) |
    setpath($path + ["components"]; (getpath($path + ["components"]) // {}))
  ' "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
}

read_loop_state() {
  local state_file="$1"
  local path
  path=$(normalize_workflow_state_path "${2:-${WORKFLOW_STATE_PATH:-[]}}") || return 1
  ensure_loop_state_schema "$state_file" || return 1
  ITERATION=$(jq -r '.iteration // 0' "$state_file")
  MAX_ITERATIONS=$(jq -r '.max_iterations // empty' "$state_file")
  COMPLETION_PROMISE=$(jq -r '.completion_promise // empty' "$state_file")
  TERMINAL_PROMISES=$(jq -c '.terminal_promises' "$state_file")
  LOOP_NAME=$(jq -r '.loop_name // empty' "$state_file")
  OWNER_WORKFLOW=$(jq -r '.owner_workflow // empty' "$state_file")
  PHASE=$(jq -r --argjson path "$path" 'getpath($path + ["phase"]) // empty' "$state_file")
  ORIGINAL_PROMPT=$(jq -r '.original_prompt // empty' "$state_file")
  AWAITING_DRIVER_INPUT=$(jq -r '.awaiting_driver_input // false' "$state_file")
  DRIVER_INPUT_REASON=$(jq -r '.driver_input_reason // empty' "$state_file")
  loop_log "read_loop_state: file=$state_file loop=$LOOP_NAME iter=$ITERATION phase=$PHASE"
}

increment_iteration() {
  local state_file="$1"
  local tmp_file="${state_file}.tmp.$$"
  ensure_loop_state_schema "$state_file" || return 1
  jq '.iteration = ((.iteration // 0) + 1)' "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
  loop_log "increment_iteration: file=$state_file"
}

record_loop_block_attempt() {
  local state_file="$1"
  local fingerprint="$2"
  local tmp_file="${state_file}.tmp.$$"
  ensure_loop_state_schema "$state_file" || return 1
  jq --arg fingerprint "$fingerprint" '
    if (.last_block_fingerprint // "") == $fingerprint then
      .unchanged_block_count = ((.unchanged_block_count // 0) + 1)
    else
      .last_block_fingerprint = $fingerprint |
      .unchanged_block_count = 1
    end
  ' "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
  jq -r '.unchanged_block_count' "$state_file"
}

set_loop_phase() {
  local state_file="$1"
  local new_phase="$2"
  local path
  local tmp_file="${state_file}.tmp.$$"
  path=$(normalize_workflow_state_path "${3:-${WORKFLOW_STATE_PATH:-[]}}") || return 1
  initialize_workflow_state "$state_file" "$path" || return 1
  jq --argjson path "$path" --arg phase "$new_phase" \
    'setpath($path + ["phase"]; $phase)' "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
  loop_log "set_loop_phase: file=$state_file path=$path phase=$new_phase"
}

get_loop_field() {
  local state_file="$1"
  local field="$2"
  local path
  path=$(normalize_workflow_state_path "${3:-${WORKFLOW_STATE_PATH:-[]}}") || return 1
  ensure_loop_state_schema "$state_file" || return 1
  jq -r --argjson path "$path" --arg field "$field" \
    'getpath($path + [$field]) // empty' "$state_file"
}

set_loop_field() {
  local state_file="$1"
  local field="$2"
  local value="$3"
  local path
  local tmp_file="${state_file}.tmp.$$"
  path=$(normalize_workflow_state_path "${4:-${WORKFLOW_STATE_PATH:-[]}}") || return 1
  validate_workflow_field_update "$path" "$field" || return 1
  initialize_workflow_state "$state_file" "$path" || return 1
  jq --argjson path "$path" --arg field "$field" --arg value "$value" \
    'setpath($path + [$field]; $value)' "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
}

set_loop_json_field() {
  local state_file="$1"
  local field="$2"
  local value="$3"
  local path
  local compact_value
  local tmp_file="${state_file}.tmp.$$"
  path=$(normalize_workflow_state_path "${4:-${WORKFLOW_STATE_PATH:-[]}}") || return 1
  validate_workflow_field_update "$path" "$field" || return 1
  if ! compact_value=$(printf '%s\n' "$value" | jq -ce . 2>/dev/null); then
    printf 'Loop field value must be valid JSON.\n' >&2
    return 1
  fi
  initialize_workflow_state "$state_file" "$path" || return 1
  jq --argjson path "$path" --arg field "$field" --argjson value "$compact_value" \
    'setpath($path + [$field]; $value)' "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
}

delete_loop_field() {
  local state_file="$1"
  local field="$2"
  local path
  local tmp_file="${state_file}.tmp.$$"
  path=$(normalize_workflow_state_path "${3:-${WORKFLOW_STATE_PATH:-[]}}") || return 1
  validate_workflow_field_update "$path" "$field" || return 1
  ensure_loop_state_schema "$state_file" || return 1
  jq --argjson path "$path" --arg field "$field" \
    'delpaths([$path + [$field]])' "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
}

set_workflow_result() {
  local state_file="$1"
  local path
  local result="$3"
  local reason="$4"
  local phase="$5"
  local tmp_file="${state_file}.tmp.$$"
  path=$(normalize_workflow_state_path "${2:-${WORKFLOW_STATE_PATH:-[]}}") || return 1
  initialize_workflow_state "$state_file" "$path" || return 1
  jq --argjson path "$path" --arg result "$result" --arg reason "$reason" --arg phase "$phase" '
    setpath($path + ["result"]; $result) |
    setpath($path + ["reason"]; $reason) |
    setpath($path + ["phase"]; $phase) |
    if ($path | length) == 0 then
      .workflow_result = $result |
      .workflow_reason = $reason
    else . end
  ' "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
}

set_loop_terminal_result() {
  local state_file="$1"
  local result="$2"
  local reason="$3"
  local phase="$4"
  local promise="$5"
  local tmp_file="${state_file}.tmp.$$"
  ensure_loop_state_schema "$state_file" || return 1
  if ! jq -e --arg promise "$promise" '.terminal_promises | index($promise) != null' \
    "$state_file" >/dev/null 2>&1; then
    printf "Completion promise '%s' is not allowlisted for this loop.\n" "$promise" >&2
    return 1
  fi
  jq --arg result "$result" --arg reason "$reason" --arg phase "$phase" --arg promise "$promise" '
    .result = $result |
    .reason = $reason |
    .workflow_result = $result |
    .workflow_reason = $reason |
    .phase = $phase |
    .completion_promise = $promise
  ' "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
}

set_loop_completion_promise() {
  local state_file="$1"
  local promise="$2"
  local tmp_file="${state_file}.tmp.$$"
  ensure_loop_state_schema "$state_file" || return 1
  if ! jq -e --arg promise "$promise" '.terminal_promises | index($promise) != null' \
    "$state_file" >/dev/null 2>&1; then
    printf "Completion promise '%s' is not allowlisted for this loop.\n" "$promise" >&2
    return 1
  fi
  jq --arg promise "$promise" '.completion_promise = $promise' \
    "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
}

pause_loop_for_driver() {
  local state_file="$1"
  local reason="$2"
  local tmp_file="${state_file}.tmp.$$"
  ensure_loop_state_schema "$state_file" || return 1
  jq --arg reason "$reason" \
    '.awaiting_driver_input = true | .driver_input_reason = $reason' \
    "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
  loop_log "pause_loop_for_driver: file=$state_file reason=$reason"
}

resume_loop_after_driver() {
  local state_file="$1"
  local tmp_file="${state_file}.tmp.$$"
  ensure_loop_state_schema "$state_file" || return 1
  jq '.awaiting_driver_input = false | .driver_input_reason = ""' \
    "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
  loop_log "resume_loop_after_driver: file=$state_file"
}

cleanup_loop() {
  local state_file="$1"
  loop_log "cleanup_loop: file=$state_file"
  rm -f "$state_file"
}

check_completion_promise() {
  local promise="$1"
  local transcript="$2"
  local last_lines
  local all_text
  local jq_exit

  if [ -z "$transcript" ]; then
    transcript=".claude/transcript.jsonl"
  fi
  if [ ! -f "$transcript" ]; then
    loop_log "check_completion_promise: transcript not found at $transcript"
    return 1
  fi
  last_lines=$(grep '"role":"assistant"' "$transcript" 2>/dev/null | tail -n 100 || true)
  if [ -z "$last_lines" ]; then
    loop_log "check_completion_promise: no assistant messages in transcript"
    return 1
  fi
  set +e
  all_text=$(printf '%s\n' "$last_lines" | jq -rs '
    [.[] | .message.content[]? | select(.type == "text") | .text] | join("\n")
  ' 2>/dev/null)
  jq_exit=$?
  set -e
  if [ "$jq_exit" -ne 0 ]; then
    loop_log "check_completion_promise: jq failed with exit $jq_exit"
    return 1
  fi
  if printf '%s\n' "$all_text" | grep -Fq "<done>${promise}</done>"; then
    loop_log "check_completion_promise: FOUND promise '$promise'"
    return 0
  fi
  if printf '%s\n' "$all_text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    grep -q "<done>[[:space:]]*${promise}[[:space:]]*</done>"; then
    loop_log "check_completion_promise: FOUND promise '$promise' (with whitespace)"
    return 0
  fi
  loop_log "check_completion_promise: NOT found promise '$promise'"
  return 1
}

find_active_loops() {
  local state_dir="${1:-$(loop_state_directory)}"
  if [ ! -d "$state_dir" ]; then
    return 0
  fi
  find "$state_dir" -maxdepth 1 -name '*.loop.local.json' 2>/dev/null | LC_ALL=C sort
}

count_active_loops() {
  local state_dir="${1:-$(loop_state_directory)}"
  local count
  count=$(find_active_loops "$state_dir" | wc -l | tr -d ' ')
  printf '%s\n' "$count"
}

setup_loop() {
  local script_dir
  if [ -n "${BASH_SOURCE[0]:-}" ]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    script_dir="${CLAUDE_PLUGIN_ROOT}/scripts"
  else
    printf 'Error: Cannot locate setup-loop.sh (set CLAUDE_PLUGIN_ROOT)\n' >&2
    return 1
  fi
  "$script_dir/setup-loop.sh" "$@"
}
