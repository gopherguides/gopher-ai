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
CURRENT_SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null)
HOOK_CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
if [ -z "$CURRENT_SESSION_ID" ] && [ -n "$TRANSCRIPT_PATH" ]; then
  CURRENT_SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl 2>/dev/null || true)
fi

# Source shared library for state management
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_PATH="$SCRIPT_DIR/../lib/loop-state.sh"

if [ ! -f "$LIB_PATH" ]; then
  exit 0
fi

source "$LIB_PATH"

resolve_current_worktree() {
  local candidate="$HOOK_CWD"
  local root
  if [ -z "$candidate" ] || [ ! -d "$candidate" ]; then
    candidate=$(pwd -P)
  fi
  root=$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$root" ] && [ -d "$root" ]; then
    root=$(cd "$root" && pwd -P)
  else
    root=$(cd "$candidate" && pwd -P)
  fi
  printf '%s\n' "$root"
}

CURRENT_WORKTREE_PATH=$(resolve_current_worktree)

loop_log "stop-hook: entered, transcript=$TRANSCRIPT_PATH worktree=$CURRENT_WORKTREE_PATH"

block_stop() {
  local reason="$1"
  local message="$2"
  local state_context="${3:-${STATE_FILE:-unknown}}"
  if ! printf '%s' "$reason" | grep '[^[:space:]]' >/dev/null; then
    reason="Loop execution is blocked by invalid state."
  fi
  message="$message State file(s): $state_context. Cancel with /go-workflow:cancel-loop."
  jq -n --arg reason "$reason" --arg msg "$message" \
    '{"decision": "block", "reason": $reason, "systemMessage": $msg}'
}

transcript_owns_loop() {
  local loop_name="$1"

  [ -n "$loop_name" ] &&
    [ -n "$TRANSCRIPT_PATH" ] &&
    [ -f "$TRANSCRIPT_PATH" ] &&
    grep -Fq -- "Loop initialized: $loop_name" "$TRANSCRIPT_PATH"
}

session_owns_loop_state() {
  local state_file="$1"
  local stored_session_id
  local stored_worktree_path
  local loop_name

  [ -f "$state_file" ] && [ -r "$state_file" ] && jq empty "$state_file" 2>/dev/null || return 1

  stored_session_id=$(jq -r '.session_id // empty' "$state_file" 2>/dev/null)
  stored_worktree_path=$(jq -r '.worktree_path // empty' "$state_file" 2>/dev/null)
  loop_name=$(jq -r '.loop_name // empty' "$state_file" 2>/dev/null)

  if [ -n "$stored_worktree_path" ]; then
    [ -d "$stored_worktree_path" ] || return 1
    stored_worktree_path=$(cd "$stored_worktree_path" && pwd -P)
    [ "$stored_worktree_path" = "$CURRENT_WORKTREE_PATH" ] || return 1
  fi

  if [ -n "$stored_session_id" ]; then
    [ -n "$CURRENT_SESSION_ID" ] && [ "$stored_session_id" = "$CURRENT_SESSION_ID" ]
    return
  fi

  transcript_owns_loop "$loop_name"
}

state_has_stale_worktree() {
  local state_file="$1"
  local stored_worktree_path
  stored_worktree_path=$(jq -r '.worktree_path // empty' "$state_file" 2>/dev/null)
  [ -n "$stored_worktree_path" ] && [ ! -d "$stored_worktree_path" ]
}

repository_target_required_for() {
  local owner_workflow="$1"
  local phase="$2"
  case "$owner_workflow:$phase" in
    ship:reviewing|ship:pushing)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

loop_requires_repository_target() {
  repository_target_required_for "$OWNER_WORKFLOW" "$PHASE"
}

repository_has_target() {
  local worktree_path="$1"
  local current_branch
  local upstream
  local default_ref
  local candidate
  local ahead

  git -C "$worktree_path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 2

  if ! git -C "$worktree_path" diff --cached --quiet --; then
    return 0
  fi

  upstream=$(git -C "$worktree_path" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
  if [ -n "$upstream" ]; then
    ahead=$(git -C "$worktree_path" rev-list --count "$upstream"..HEAD 2>/dev/null || printf '0')
    if [ "$ahead" -gt 0 ]; then
      return 0
    fi
  fi

  current_branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null || true)
  default_ref=$(git -C "$worktree_path" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -z "$default_ref" ]; then
    for candidate in origin/main origin/master main master; do
      if git -C "$worktree_path" rev-parse --verify --quiet "$candidate^{commit}" >/dev/null; then
        default_ref="$candidate"
        break
      fi
    done
  fi
  if [ -n "$current_branch" ] && [ -n "$default_ref" ] &&
     [ "$current_branch" != "${default_ref#origin/}" ]; then
    ahead=$(git -C "$worktree_path" rev-list --count "$default_ref"..HEAD 2>/dev/null || printf '0')
    if [ "$ahead" -gt 0 ]; then
      return 0
    fi
  fi

  return 1
}

state_has_no_repository_target() {
  local state_file="$1"
  local owner_workflow
  local phase
  local worktree_path
  local target_status=0
  owner_workflow=$(jq -r '.owner_workflow // empty' "$state_file" 2>/dev/null)
  phase=$(jq -r '.phase // empty' "$state_file" 2>/dev/null)
  worktree_path=$(jq -r '.worktree_path // empty' "$state_file" 2>/dev/null)
  repository_target_required_for "$owner_workflow" "$phase" || return 1
  [ -n "$worktree_path" ] && [ -d "$worktree_path" ] || return 1
  repository_has_target "$worktree_path" || target_status=$?
  [ "$target_status" -eq 1 ]
}

repository_state_fingerprint() {
  local worktree_path="$1"
  local phase="$2"
  local reason="$3"
  local head
  local upstream
  local upstream_head
  head=$(git -C "$worktree_path" rev-parse HEAD 2>/dev/null || true)
  upstream=$(git -C "$worktree_path" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
  upstream_head=$(git -C "$worktree_path" rev-parse '@{upstream}' 2>/dev/null || true)
  {
    printf '%s\n' "$worktree_path" "$phase" "$reason" "$head" "$upstream" "$upstream_head"
    git -C "$worktree_path" status --porcelain=v1 --untracked-files=all -- \
      . ':(exclude).local/state/**' 2>/dev/null || true
    git -C "$worktree_path" diff --no-ext-diff --binary --cached -- \
      . ':(exclude).local/state/**' 2>/dev/null || true
    git -C "$worktree_path" diff --no-ext-diff --binary -- \
      . ':(exclude).local/state/**' 2>/dev/null || true
    while IFS= read -r -d '' untracked_file; do
      printf '%s\0' "$untracked_file"
      git -C "$worktree_path" hash-object -- "$untracked_file" 2>/dev/null || true
    done < <(git -C "$worktree_path" ls-files --others --exclude-standard -z -- \
      . ':(exclude).local/state/**' 2>/dev/null)
  } | cksum | awk '{print $1 ":" $2}'
}

# Find any active loop state file
STATE_FILES=$(find_active_loops)

OWNED_STATE_FILES=""
while IFS= read -r CANDIDATE_STATE_FILE; do
  [ -n "$CANDIDATE_STATE_FILE" ] || continue
  if state_has_stale_worktree "$CANDIDATE_STATE_FILE"; then
    loop_log "stop-hook: pruning stale loop state '$CANDIDATE_STATE_FILE'"
    cleanup_loop "$CANDIDATE_STATE_FILE"
    continue
  fi
  if session_owns_loop_state "$CANDIDATE_STATE_FILE"; then
    if state_has_no_repository_target "$CANDIDATE_STATE_FILE"; then
      loop_log "stop-hook: pruning targetless loop state '$CANDIDATE_STATE_FILE'"
      cleanup_loop "$CANDIDATE_STATE_FILE"
      continue
    fi
    if [ -z "$OWNED_STATE_FILES" ]; then
      OWNED_STATE_FILES="$CANDIDATE_STATE_FILE"
    else
      OWNED_STATE_FILES="$OWNED_STATE_FILES
$CANDIDATE_STATE_FILE"
    fi
  else
    loop_log "stop-hook: current session does not own loop state '$CANDIDATE_STATE_FILE', skipping"
  fi
done <<< "$STATE_FILES"
STATE_FILES="$OWNED_STATE_FILES"

if [ -z "$STATE_FILES" ]; then
  loop_log "stop-hook: no active loops owned by current session"
  exit 0
fi

STATE_COUNT=$(printf '%s\n' "$STATE_FILES" | wc -l | tr -d ' ')
if [ "$STATE_COUNT" -ne 1 ]; then
  MULTIPLE_REASON=$(printf 'Multiple active loop states were found; ownership is ambiguous:\n%s' "$STATE_FILES")
  loop_log "stop-hook: refusing ambiguous active loops: $STATE_FILES"
  block_stop "$MULTIPLE_REASON" \
    "$MULTIPLE_REASON Cancel the orphaned loop states or restore one caller-owned state before continuing." \
    "$STATE_FILES"
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

STORED_SESSION_ID=$(jq -r '.session_id // empty' "$STATE_FILE")
if [ -z "$STORED_SESSION_ID" ] && [ -n "$CURRENT_SESSION_ID" ]; then
  set_loop_field "$STATE_FILE" "session_id" "$CURRENT_SESSION_ID" '[]'
  loop_log "stop-hook: claimed loop state '$STATE_FILE' for session '$CURRENT_SESSION_ID'"
fi
STORED_WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$STATE_FILE")
if [ -z "$STORED_WORKTREE_PATH" ]; then
  set_loop_field "$STATE_FILE" "worktree_path" "$CURRENT_WORKTREE_PATH" '[]'
  STORED_WORKTREE_PATH="$CURRENT_WORKTREE_PATH"
  loop_log "stop-hook: claimed loop state '$STATE_FILE' for worktree '$CURRENT_WORKTREE_PATH'"
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

TARGET_STATUS=0
if loop_requires_repository_target; then
  repository_has_target "$STORED_WORKTREE_PATH" || TARGET_STATUS=$?
  if [ "$TARGET_STATUS" -eq 1 ]; then
    loop_log "stop-hook: no repository target remains; cleaning up '$STATE_FILE'"
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

MAX_UNCHANGED_BLOCKS=3
BLOCK_FINGERPRINT=$(repository_state_fingerprint "$STORED_WORKTREE_PATH" "$PHASE" "$REASON")
UNCHANGED_BLOCK_COUNT=$(record_loop_block_attempt "$STATE_FILE" "$BLOCK_FINGERPRINT")
if [ "$UNCHANGED_BLOCK_COUNT" -gt "$MAX_UNCHANGED_BLOCKS" ]; then
  loop_log "stop-hook: unchanged block cap reached ($UNCHANGED_BLOCK_COUNT > $MAX_UNCHANGED_BLOCKS); cleaning up '$STATE_FILE'"
  cleanup_loop "$STATE_FILE"
  exit 0
fi
SYSTEM_MSG="$SYSTEM_MSG Unchanged repository-state block $UNCHANGED_BLOCK_COUNT of $MAX_UNCHANGED_BLOCKS; the loop self-expires before another identical block."

loop_log "stop-hook: blocking exit, reason='$REASON' unchanged_blocks=$UNCHANGED_BLOCK_COUNT"

block_stop "$REASON" "$SYSTEM_MSG" "$STATE_FILE"
