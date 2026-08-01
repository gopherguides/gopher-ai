#!/bin/bash
# Verify hooks.json files are valid and referenced scripts exist
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ERRORS=0

echo "=== Hook Tests ==="

if ! bash "$SCRIPT_DIR/test-loop-state.sh"; then
  ERRORS=$((ERRORS + 1))
fi

# Find all hooks.json files
HOOK_FILES=$(find "$ROOT_DIR/plugins" -name "hooks.json" -type f 2>/dev/null | sort)
TOTAL=0

for hook_file in $HOOK_FILES; do
  TOTAL=$((TOTAL + 1))
  PLUGIN_DIR=$(dirname "$hook_file")
  REL_PATH="${hook_file#"$ROOT_DIR"/}"

  # Test: hooks.json is valid JSON
  echo -n "  $REL_PATH is valid JSON... "
  if ! jq . "$hook_file" >/dev/null 2>&1; then
    echo "FAIL"
    ERRORS=$((ERRORS + 1))
    continue
  fi
  echo "OK"

  echo -n "  $REL_PATH uses supported top-level keys... "
  UNSUPPORTED_KEYS=$(jq -r 'keys_unsorted - ["hooks"] | join(", ")' "$hook_file")
  if [ -n "$UNSUPPORTED_KEYS" ]; then
    echo "FAIL (unsupported: $UNSUPPORTED_KEYS)"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK"
  fi

  echo -n "  $REL_PATH has hooks object... "
  if ! jq -e '.hooks | type == "object"' "$hook_file" >/dev/null 2>&1; then
    echo "FAIL"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK"
  fi

  # Test: All referenced command scripts exist
  # Extract command paths from hooks.json (they use ${CLAUDE_PLUGIN_ROOT} prefix)
  COMMANDS=$(jq -r '.. | .command? // empty' "$hook_file" 2>/dev/null | sort -u)
  PLUGIN_ROOT=$(dirname "$PLUGIN_DIR")

  for cmd in $COMMANDS; do
    # Replace ${CLAUDE_PLUGIN_ROOT} with the actual plugin directory (parent of hooks/)
    ACTUAL_PATH="${cmd//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_ROOT}"

    echo -n "  Referenced script exists: ${cmd}... "
    if [ ! -f "$ACTUAL_PATH" ]; then
      echo "FAIL (not found: $ACTUAL_PATH)"
      ERRORS=$((ERRORS + 1))
    elif [ ! -x "$ACTUAL_PATH" ]; then
      echo "FAIL (not executable)"
      ERRORS=$((ERRORS + 1))
    else
      echo "OK"
    fi
  done
done

echo -n "  go-workflow hooks use lifecycle-appropriate matchers... "
GO_WORKFLOW_HOOKS="$ROOT_DIR/plugins/go-workflow/hooks/hooks.json"
if jq -e '
  .hooks.SessionStart[0].matcher == "startup|resume" and
  .hooks.PreToolUse[0].matcher == "Bash|Read|Edit|Write|Glob|Grep|apply_patch" and
  .hooks.PostToolUse[0].matcher == "Bash|WebFetch|WebSearch" and
  (.hooks.Stop[0] | has("matcher") | not)
' "$GO_WORKFLOW_HOOKS" >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook honors durable driver-input pauses... "
HOOK_TMP_BASE="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
STOP_HOOK_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook.XXXXXX")
STOP_HOOK_STATE="$STOP_HOOK_ROOT/.local/state/ship.loop.local.json"
mkdir -p "$(dirname "$STOP_HOOK_STATE")"
printf '%s\n' '{"loop_name":"ship","iteration":1,"max_iterations":50,"completion_promise":"SHIPPED","phase":"pushing","original_prompt":"ship","session_id":"","awaiting_driver_input":false,"driver_input_reason":""}' > "$STOP_HOOK_STATE"

if (
  cd "$STOP_HOOK_ROOT"
  source "$ROOT_DIR/plugins/go-workflow/lib/loop-state.sh"
  pause_loop_for_driver "$STOP_HOOK_STATE" "dirty-tree-decision"
  "$ROOT_DIR/plugins/go-workflow/scripts/setup-loop.sh" \
    "ship" "SHIPPED" 50 "" '{}' >/dev/null
  PAUSED_OUTPUT=$(printf '%s\n' '{"transcript_path":""}' | bash "$ROOT_DIR/plugins/go-workflow/hooks/stop-hook.sh")
  [ -z "$PAUSED_OUTPUT" ]
  jq -e '
    .iteration == 1 and
    .phase == "pushing" and
    .awaiting_driver_input == true and
    .driver_input_reason == "dirty-tree-decision"
  ' "$STOP_HOOK_STATE" >/dev/null
  resume_loop_after_driver "$STOP_HOOK_STATE"
  RESUMED_OUTPUT=$(printf '%s\n' '{"transcript_path":""}' | bash "$ROOT_DIR/plugins/go-workflow/hooks/stop-hook.sh")
  printf '%s\n' "$RESUMED_OUTPUT" | jq -e '.decision == "block"' >/dev/null
  jq -e '
    .iteration == 2 and
    .phase == "pushing" and
    .awaiting_driver_input == false and
    .driver_input_reason == ""
  ' "$STOP_HOOK_STATE" >/dev/null
); then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

APPLY_PATCH_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-apply-patch-hook.XXXXXX")
APPLY_PATCH_ROOT=$(cd "$APPLY_PATCH_ROOT" && pwd -P)
APPLY_PATCH_HOME="$APPLY_PATCH_ROOT/home"
APPLY_PATCH_ORIGINAL="$APPLY_PATCH_ROOT/original"
APPLY_PATCH_WORKTREE="$APPLY_PATCH_ROOT/worktree"
mkdir -p "$APPLY_PATCH_HOME/.claude" "$APPLY_PATCH_ORIGINAL"
git -C "$APPLY_PATCH_ORIGINAL" init -q
git -C "$APPLY_PATCH_ORIGINAL" \
  -c user.name="Hook Tests" \
  -c user.email="hooks@example.com" \
  commit --allow-empty -qm "test: initialize hook fixture"
git -C "$APPLY_PATCH_ORIGINAL" worktree add -qb hook-worktree "$APPLY_PATCH_WORKTREE" >/dev/null
mkdir -p "$APPLY_PATCH_WORKTREE/pkg/sub"
ln -s "$APPLY_PATCH_ORIGINAL" "$APPLY_PATCH_WORKTREE/original-link"
mkdir -p "$APPLY_PATCH_ORIGINAL/nested"
ln -s "$APPLY_PATCH_ORIGINAL/nested" "$APPLY_PATCH_WORKTREE/nested-original-link"
jq -n \
  --arg worktree "$APPLY_PATCH_WORKTREE" \
  --arg original "$APPLY_PATCH_ORIGINAL" \
  '{worktree_path: $worktree, original_path: $original}' \
  > "$APPLY_PATCH_HOME/.claude/worktree-state.json"

run_apply_patch_hook() {
  local cwd="$1"
  local patch_command="$2"
  (
    cd "$cwd"
    jq -n \
      --arg cwd "$cwd" \
      --arg command "$patch_command" \
      '{cwd: $cwd, tool_name: "apply_patch", tool_input: {command: $command}}' |
      HOME="$APPLY_PATCH_HOME" /bin/bash "$ROOT_DIR/plugins/go-workflow/hooks/pre-tool-use.sh"
  )
}

expect_apply_patch_allowed() {
  local label="$1"
  local cwd="$2"
  local patch_command="$3"
  local output
  echo -n "  $label... "
  output=$(run_apply_patch_hook "$cwd" "$patch_command")
  if [ -z "$output" ]; then
    echo "OK"
  else
    echo "FAIL"
    ERRORS=$((ERRORS + 1))
  fi
}

expect_apply_patch_blocked() {
  local label="$1"
  local cwd="$2"
  local patch_command="$3"
  local output
  echo -n "  $label... "
  output=$(run_apply_patch_hook "$cwd" "$patch_command")
  if printf '%s\n' "$output" | jq -e \
    '.decision == "block" and (.reason | contains("original repo"))' >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL"
    ERRORS=$((ERRORS + 1))
  fi
}

expect_apply_patch_allowed \
  "PreToolUse allows normalized apply_patch targets in the worktree" \
  "$APPLY_PATCH_WORKTREE/pkg/sub" \
  $'*** Begin Patch\n*** Add File: ../../docs/new.txt\n+new\n*** Update File: ./current.txt\n@@\n-old\n+new\n*** Move to: ../moved.txt\n*** Delete File: ../../obsolete.txt\n*** End Patch'

expect_apply_patch_blocked \
  "PreToolUse blocks apply_patch Add File in the original repo" \
  "$APPLY_PATCH_WORKTREE" \
  $'*** Begin Patch\n*** Add File: '"$APPLY_PATCH_ORIGINAL"$'/added.txt\n+new\n*** End Patch'

expect_apply_patch_blocked \
  "PreToolUse blocks normalized apply_patch Update File in the original repo" \
  "$APPLY_PATCH_WORKTREE/pkg/sub" \
  $'*** Begin Patch\n*** Update File: ../../../original/updated.txt\n@@\n-old\n+new\n*** End Patch'

expect_apply_patch_blocked \
  "PreToolUse blocks apply_patch symlink escapes into the original repo" \
  "$APPLY_PATCH_WORKTREE" \
  $'*** Begin Patch\n*** Add File: original-link/escaped.txt\n+blocked\n*** End Patch'

expect_apply_patch_blocked \
  "PreToolUse resolves parent traversal after apply_patch symlinks" \
  "$APPLY_PATCH_WORKTREE" \
  $'*** Begin Patch\n*** Add File: nested-original-link/../escaped-parent.txt\n+blocked\n*** End Patch'

expect_apply_patch_blocked \
  "PreToolUse blocks apply_patch Delete File in the original repo" \
  "$APPLY_PATCH_WORKTREE" \
  $'*** Begin Patch\n*** Delete File: '"$APPLY_PATCH_ORIGINAL"$'/deleted.txt\n*** End Patch'

expect_apply_patch_blocked \
  "PreToolUse blocks apply_patch Move to the original repo" \
  "$APPLY_PATCH_WORKTREE/pkg/sub" \
  $'*** Begin Patch\n*** Update File: ./source.txt\n*** Move to: '"$APPLY_PATCH_ORIGINAL"$'/moved.txt\n@@\n-old\n+new\n*** End Patch'

expect_apply_patch_blocked \
  "PreToolUse checks every target in a multi-file apply_patch" \
  "$APPLY_PATCH_WORKTREE" \
  $'*** Begin Patch\n*** Update File: ./allowed.txt\n@@\n-old\n+new\n*** Add File: '"$APPLY_PATCH_ORIGINAL"$'/blocked.txt\n+blocked\n*** End Patch'

has_nonempty_block_reason() {
  jq -e '
    .decision == "block" and
    ((.reason // "") | test("[^[:space:]]"))
  ' >/dev/null 2>&1
}

echo -n "  Stop hook supplies a non-empty block reason without phase context... "
STOP_HOOK_REASON_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-reason.XXXXXX")
STOP_HOOK_REASON_STATE="$STOP_HOOK_REASON_ROOT/.local/state/start-issue-302.loop.local.json"
mkdir -p "$(dirname "$STOP_HOOK_REASON_STATE")"

if (
  cd "$STOP_HOOK_REASON_ROOT"
  REASON_FAILURES=0
  for STATE_JSON in \
    '{"loop_name":"start-issue-302","iteration":1,"max_iterations":50,"completion_promise":"COMPLETE","phase":"","original_prompt":"","session_id":"","awaiting_driver_input":false,"driver_input_reason":""}' \
    '{"loop_name":"start-issue-302","iteration":1,"max_iterations":50,"completion_promise":"COMPLETE","phase":"","session_id":"","awaiting_driver_input":false,"driver_input_reason":""}' \
    '{"loop_name":"start-issue-302","iteration":1,"max_iterations":50,"completion_promise":"COMPLETE","phase":"","original_prompt":"   ","session_id":"","awaiting_driver_input":false,"driver_input_reason":""}' \
    '{"loop_name":"start-issue-302","iteration":1,"max_iterations":50,"completion_promise":"COMPLETE","phase":"custom","phase_messages":{"custom":"   "},"original_prompt":"Continue issue 302.","session_id":"","awaiting_driver_input":false,"driver_input_reason":""}'
  do
    printf '%s\n' "$STATE_JSON" > "$STOP_HOOK_REASON_STATE"
    STOP_OUTPUT=$(printf '%s\n' '{"transcript_path":""}' | bash "$ROOT_DIR/plugins/go-workflow/hooks/stop-hook.sh")
    if ! printf '%s\n' "$STOP_OUTPUT" | has_nonempty_block_reason; then
      REASON_FAILURES=$((REASON_FAILURES + 1))
    fi
  done

  printf '%s\n' '{"loop_name":"start-issue-302","iteration":1,"max_iterations":50,"completion_promise":"COMPLETE","phase":"","original_prompt":"Continue issue 302.","session_id":"","awaiting_driver_input":false,"driver_input_reason":""}' > "$STOP_HOOK_REASON_STATE"
  STOP_OUTPUT=$(printf '%s\n' '{"transcript_path":""}' | bash "$ROOT_DIR/plugins/go-workflow/hooks/stop-hook.sh")
  if ! printf '%s\n' "$STOP_OUTPUT" | jq -e '.reason == "Continue issue 302."' >/dev/null; then
    REASON_FAILURES=$((REASON_FAILURES + 1))
  fi
  [ "$REASON_FAILURES" -eq 0 ]
); then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Non-empty reason assertion rejects a deliberate empty-reason mutation... "
REASON_MUTATION_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-reason-mutation.XXXXXX")
mkdir -p "$REASON_MUTATION_ROOT/hooks" "$REASON_MUTATION_ROOT/lib" "$REASON_MUTATION_ROOT/.local/state"
cp "$ROOT_DIR/shared/hooks/stop-hook.sh" "$REASON_MUTATION_ROOT/hooks/stop-hook.sh"
cp "$ROOT_DIR/shared/lib/loop-state.sh" "$REASON_MUTATION_ROOT/lib/loop-state.sh"
sed 's/^  REASON="Continue working on the task\."$/  REASON=""/' \
  "$REASON_MUTATION_ROOT/hooks/stop-hook.sh" > "$REASON_MUTATION_ROOT/hooks/stop-hook-mutated.sh"
printf '%s\n' '{"loop_name":"start-issue-302","iteration":1,"max_iterations":50,"completion_promise":"COMPLETE","phase":"","original_prompt":"","session_id":""}' \
  > "$REASON_MUTATION_ROOT/.local/state/start-issue-302.loop.local.json"
MUTATED_REASON_OUTPUT=$(
  cd "$REASON_MUTATION_ROOT"
  printf '%s\n' '{"transcript_path":""}' | bash hooks/stop-hook-mutated.sh
)
if grep -F -q 'REASON=""' "$REASON_MUTATION_ROOT/hooks/stop-hook-mutated.sh" &&
   ! printf '%s\n' "$MUTATED_REASON_OUTPUT" | has_nonempty_block_reason; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

CORE_STOP_HOOK="$ROOT_DIR/shared/hooks/stop-hook.sh"
CORE_LOOP_LIB="$ROOT_DIR/shared/lib/loop-state.sh"

echo -n "  Stop hook fails closed for the live duplicate-loop shape... "
DUPLICATE_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-duplicates.XXXXXX")
DUPLICATE_STATE_DIR="$DUPLICATE_ROOT/.local/state"
mkdir -p "$DUPLICATE_STATE_DIR"
printf '%s\n' '{"loop_name":"start-issue-301","iteration":1,"max_iterations":50,"completion_promise":"COMPLETE","phase":"implementing","original_prompt":"issue 301","session_id":""}' > "$DUPLICATE_STATE_DIR/start-issue-301.loop.local.json"
printf '%s\n' '{"loop_name":"direct-smoke","iteration":1,"max_iterations":10,"completion_promise":"DONE","phase":"testing","original_prompt":"smoke","session_id":""}' > "$DUPLICATE_STATE_DIR/direct-smoke.loop.local.json"
DUPLICATE_OWNER_BEFORE=$(cksum "$DUPLICATE_STATE_DIR/start-issue-301.loop.local.json")
DUPLICATE_STRAY_BEFORE=$(cksum "$DUPLICATE_STATE_DIR/direct-smoke.loop.local.json")
DUPLICATE_TRANSCRIPT="$DUPLICATE_ROOT/transcript.jsonl"
printf '%s\n' '{"role":"assistant","message":{"content":[{"type":"text","text":"<done>COMPLETE</done>"}]}}' > "$DUPLICATE_TRANSCRIPT"
DUPLICATE_OUTPUT=$(
  cd "$DUPLICATE_ROOT"
  printf '%s\n' "{\"transcript_path\":\"$DUPLICATE_TRANSCRIPT\"}" | "$CORE_STOP_HOOK"
)
if printf '%s\n' "$DUPLICATE_OUTPUT" | jq -e '
    .decision == "block" and
    (.reason | test("[^[:space:]]")) and
    (.reason | contains("start-issue-301.loop.local.json")) and
    (.reason | contains("direct-smoke.loop.local.json"))
  ' >/dev/null 2>&1 &&
  [ "$DUPLICATE_OWNER_BEFORE" = "$(cksum "$DUPLICATE_STATE_DIR/start-issue-301.loop.local.json")" ] &&
  [ "$DUPLICATE_STRAY_BEFORE" = "$(cksum "$DUPLICATE_STATE_DIR/direct-smoke.loop.local.json")" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook validates the active promise and matches only that marker... "
PROMISE_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-promises.XXXXXX")
PROMISE_STATE="$PROMISE_ROOT/.local/state/e2e-verify-42.loop.local.json"
PROMISE_TRANSCRIPT="$PROMISE_ROOT/transcript.jsonl"
mkdir -p "$(dirname "$PROMISE_STATE")"
printf '%s\n' '{"schema_version":2,"owner_workflow":"e2e-verify","loop_name":"e2e-verify-42","iteration":1,"max_iterations":30,"completion_promise":"VERIFIED","terminal_promises":["VERIFIED","E2E_FAIL","INCOMPLETE"],"components":{},"phase":"e2e-testing","original_prompt":"verify","session_id":""}' > "$PROMISE_STATE"
printf '%s\n' '{"role":"assistant","message":{"content":[{"type":"text","text":"<done>E2E_FAIL</done>"}]}}' > "$PROMISE_TRANSCRIPT"
PROMISE_BLOCK=$(
  cd "$PROMISE_ROOT"
  printf '%s\n' "{\"transcript_path\":\"$PROMISE_TRANSCRIPT\"}" | "$CORE_STOP_HOOK"
)
PROMISE_BLOCK_OK=false
if printf '%s\n' "$PROMISE_BLOCK" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
   [ -f "$PROMISE_STATE" ]; then
  PROMISE_BLOCK_OK=true
fi
(
  cd "$PROMISE_ROOT"
  source "$CORE_LOOP_LIB"
  set_loop_completion_promise "$PROMISE_STATE" "E2E_FAIL"
)
PROMISE_COMPLETE=$(
  cd "$PROMISE_ROOT"
  printf '%s\n' "{\"transcript_path\":\"$PROMISE_TRANSCRIPT\"}" | "$CORE_STOP_HOOK"
)
if [ "$PROMISE_BLOCK_OK" = true ] && [ -z "$PROMISE_COMPLETE" ] && [ ! -e "$PROMISE_STATE" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook rejects an unallowlisted active promise without mutation... "
INVALID_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-invalid.XXXXXX")
INVALID_STATE="$INVALID_ROOT/.local/state/ship.loop.local.json"
mkdir -p "$(dirname "$INVALID_STATE")"
printf '%s\n' '{"schema_version":2,"owner_workflow":"ship","loop_name":"ship","iteration":1,"max_iterations":50,"completion_promise":"FOREIGN","terminal_promises":["SHIPPED","INCOMPLETE"],"components":{},"phase":"pushing","original_prompt":"ship","session_id":""}' > "$INVALID_STATE"
INVALID_BEFORE=$(cksum "$INVALID_STATE")
INVALID_OUTPUT=$(
  cd "$INVALID_ROOT"
  printf '%s\n' '{"transcript_path":""}' | "$CORE_STOP_HOOK"
)
if printf '%s\n' "$INVALID_OUTPUT" | jq -e '
    .decision == "block" and
    (.reason | test("[^[:space:]]")) and
    (.reason | contains("FOREIGN"))
  ' >/dev/null 2>&1 &&
  [ "$INVALID_BEFORE" = "$(cksum "$INVALID_STATE")" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Legacy standalone ship migrates across a Stop boundary and re-enters at root... "
LEGACY_SHIP_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-legacy-ship.XXXXXX")
LEGACY_SHIP_STATE="$LEGACY_SHIP_ROOT/.local/state/ship.loop.local.json"
mkdir -p "$(dirname "$LEGACY_SHIP_STATE")"
printf '%s\n' '{"loop_name":"ship","iteration":1,"max_iterations":50,"completion_promise":"SHIPPED","phase":"ci-watch","args":"--no-merge","head_sha":"abc123","original_prompt":"ship","session_id":""}' > "$LEGACY_SHIP_STATE"
LEGACY_SHIP_OUTPUT=$(
  cd "$LEGACY_SHIP_ROOT"
  printf '%s\n' '{"transcript_path":""}' | "$CORE_STOP_HOOK"
)
LEGACY_REENTRY=$(
  cd "$LEGACY_SHIP_ROOT"
  source "$CORE_LOOP_LIB"
  read_loop_state "$LEGACY_SHIP_STATE" '[]'
  printf '%s|%s|%s|%s' "$PHASE" "$(get_loop_field "$LEGACY_SHIP_STATE" args '[]')" \
    "$(get_loop_field "$LEGACY_SHIP_STATE" head_sha '[]')" "$(jq -r '.iteration' "$LEGACY_SHIP_STATE")"
)
if printf '%s\n' "$LEGACY_SHIP_OUTPUT" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
   [ "$LEGACY_REENTRY" = 'ci-watch|--no-merge|abc123|2' ] &&
   jq -e '.schema_version == 2 and .components == {}' "$LEGACY_SHIP_STATE" >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Linked-worktree Stop hook resolves the primary owner state... "
WORKTREE_FIXTURE=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-worktree.XXXXXX")
WORKTREE_MAIN="$WORKTREE_FIXTURE/main"
WORKTREE_LINKED="$WORKTREE_FIXTURE/linked"
mkdir -p "$WORKTREE_MAIN"
git -C "$WORKTREE_MAIN" init -q
git -C "$WORKTREE_MAIN" -c user.name='Hook Tests' -c user.email='hooks@example.com' \
  commit --allow-empty -qm 'test: initialize owner root'
git -C "$WORKTREE_MAIN" worktree add -qb linked-fixture "$WORKTREE_LINKED" >/dev/null
mkdir -p "$WORKTREE_MAIN/.local/state"
printf '%s\n' '{"schema_version":2,"owner_workflow":"start-issue","loop_name":"start-issue-42","iteration":1,"max_iterations":50,"completion_promise":"COMPLETE","terminal_promises":["COMPLETE","INCOMPLETE"],"components":{},"phase":"implementing","original_prompt":"issue 42","session_id":""}' > "$WORKTREE_MAIN/.local/state/start-issue-42.loop.local.json"
WORKTREE_TRANSCRIPT="$WORKTREE_LINKED/transcript.jsonl"
printf '%s\n' '{"role":"assistant","message":{"content":[{"type":"text","text":"<done>COMPLETE</done>"}]}}' > "$WORKTREE_TRANSCRIPT"
WORKTREE_OUTPUT=$(
  cd "$WORKTREE_LINKED"
  printf '%s\n' "{\"transcript_path\":\"$WORKTREE_TRANSCRIPT\"}" | "$CORE_STOP_HOOK"
)
if [ -z "$WORKTREE_OUTPUT" ] && [ ! -e "$WORKTREE_MAIN/.local/state/start-issue-42.loop.local.json" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Linked-worktree ambient stray state is ignored... "
mkdir -p "$WORKTREE_MAIN/.local/state" "$WORKTREE_LINKED/.local/state"
printf '%s\n' '{"schema_version":2,"owner_workflow":"start-issue","loop_name":"start-issue-43","iteration":1,"max_iterations":50,"completion_promise":"COMPLETE","terminal_promises":["COMPLETE","INCOMPLETE"],"components":{},"phase":"implementing","original_prompt":"issue 43","session_id":""}' > "$WORKTREE_MAIN/.local/state/start-issue-43.loop.local.json"
printf '%s\n' '{"loop_name":"direct-smoke","iteration":1,"completion_promise":"DONE","phase":"testing"}' > "$WORKTREE_LINKED/.local/state/direct-smoke.loop.local.json"
WORKTREE_OUTPUT=$(
  cd "$WORKTREE_LINKED"
  printf '%s\n' "{\"transcript_path\":\"$WORKTREE_TRANSCRIPT\"}" | "$CORE_STOP_HOOK"
)
if [ -z "$WORKTREE_OUTPUT" ] &&
   [ ! -e "$WORKTREE_MAIN/.local/state/start-issue-43.loop.local.json" ] &&
   [ -e "$WORKTREE_LINKED/.local/state/direct-smoke.loop.local.json" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo ""
if [ $TOTAL -eq 0 ]; then
  echo "No hooks.json files found (skipped)."
  exit 0
fi

if [ $ERRORS -gt 0 ]; then
  echo "FAILED: $ERRORS hook test(s) failed"
  exit 1
else
  echo "All hook tests passed ($TOTAL hooks.json file(s))."
fi
