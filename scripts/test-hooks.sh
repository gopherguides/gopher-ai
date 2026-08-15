#!/bin/bash
# Verify hooks.json files are valid and referenced scripts exist
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_TMP_BASE="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
case "$HOOK_TMP_BASE/" in
  "$ROOT_DIR/"*)
    export GIT_CEILING_DIRECTORIES="$HOOK_TMP_BASE${GIT_CEILING_DIRECTORIES:+:$GIT_CEILING_DIRECTORIES}"
    ;;
esac

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
STOP_HOOK_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook.XXXXXX")
STOP_HOOK_STATE="$STOP_HOOK_ROOT/.local/state/ship.loop.local.json"
STOP_HOOK_TRANSCRIPT="$STOP_HOOK_ROOT/transcript.jsonl"
mkdir -p "$(dirname "$STOP_HOOK_STATE")"
printf '%s\n' '{"loop_name":"ship","iteration":1,"max_iterations":50,"completion_promise":"SHIPPED","phase":"pushing","original_prompt":"ship","session_id":"","awaiting_driver_input":false,"driver_input_reason":""}' > "$STOP_HOOK_STATE"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: ship"}]}}' > "$STOP_HOOK_TRANSCRIPT"

if (
  cd "$STOP_HOOK_ROOT"
  source "$ROOT_DIR/plugins/go-workflow/lib/loop-state.sh"
  pause_loop_for_driver "$STOP_HOOK_STATE" "dirty-tree-decision"
  "$ROOT_DIR/plugins/go-workflow/scripts/setup-loop.sh" \
    "ship" "SHIPPED" 50 "" '{}' >/dev/null
  PAUSED_OUTPUT=$(jq -n --arg transcript "$STOP_HOOK_TRANSCRIPT" '{transcript_path: $transcript}' | bash "$ROOT_DIR/plugins/go-workflow/hooks/stop-hook.sh")
  [ -z "$PAUSED_OUTPUT" ]
  jq -e '
    .iteration == 1 and
    .phase == "pushing" and
    .awaiting_driver_input == true and
    .driver_input_reason == "dirty-tree-decision"
  ' "$STOP_HOOK_STATE" >/dev/null
  resume_loop_after_driver "$STOP_HOOK_STATE"
  RESUMED_OUTPUT=$(jq -n --arg transcript "$STOP_HOOK_TRANSCRIPT" '{transcript_path: $transcript}' | bash "$ROOT_DIR/plugins/go-workflow/hooks/stop-hook.sh")
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
STOP_HOOK_REASON_TRANSCRIPT="$STOP_HOOK_REASON_ROOT/transcript.jsonl"
mkdir -p "$(dirname "$STOP_HOOK_REASON_STATE")"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: start-issue-302"}]}}' > "$STOP_HOOK_REASON_TRANSCRIPT"

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
    STOP_OUTPUT=$(jq -n --arg transcript "$STOP_HOOK_REASON_TRANSCRIPT" '{transcript_path: $transcript}' | bash "$ROOT_DIR/plugins/go-workflow/hooks/stop-hook.sh")
    if ! printf '%s\n' "$STOP_OUTPUT" | has_nonempty_block_reason; then
      REASON_FAILURES=$((REASON_FAILURES + 1))
    fi
  done

  printf '%s\n' '{"loop_name":"start-issue-302","iteration":1,"max_iterations":50,"completion_promise":"COMPLETE","phase":"","original_prompt":"Continue issue 302.","session_id":"","awaiting_driver_input":false,"driver_input_reason":""}' > "$STOP_HOOK_REASON_STATE"
  STOP_OUTPUT=$(jq -n --arg transcript "$STOP_HOOK_REASON_TRANSCRIPT" '{transcript_path: $transcript}' | bash "$ROOT_DIR/plugins/go-workflow/hooks/stop-hook.sh")
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
sed \
  -e 's/^  REASON="Continue working on the task\."$/  REASON=""/' \
  -e 's/^    reason="Loop execution is blocked by invalid state\."$/    reason=""/' \
  "$REASON_MUTATION_ROOT/hooks/stop-hook.sh" > "$REASON_MUTATION_ROOT/hooks/stop-hook-mutated.sh"
printf '%s\n' '{"loop_name":"start-issue-302","iteration":1,"max_iterations":50,"completion_promise":"COMPLETE","phase":"","original_prompt":"","session_id":""}' \
  > "$REASON_MUTATION_ROOT/.local/state/start-issue-302.loop.local.json"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: start-issue-302"}]}}' \
  > "$REASON_MUTATION_ROOT/transcript.jsonl"
MUTATED_REASON_OUTPUT=$(
  cd "$REASON_MUTATION_ROOT"
  jq -n --arg transcript "$REASON_MUTATION_ROOT/transcript.jsonl" '{transcript_path: $transcript}' | bash hooks/stop-hook-mutated.sh
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

echo -n "  Stop hook ignores a foreign transcript when legacy state has no session ID... "
FOREIGN_LEGACY_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-foreign-legacy.XXXXXX")
FOREIGN_LEGACY_STATE="$FOREIGN_LEGACY_ROOT/.local/state/start-issue-309.loop.local.json"
FOREIGN_LEGACY_TRANSCRIPT="$FOREIGN_LEGACY_ROOT/foreign-session.jsonl"
mkdir -p "$(dirname "$FOREIGN_LEGACY_STATE")"
printf '%s\n' '{"schema_version":2,"owner_workflow":"start-issue","loop_name":"start-issue-309","iteration":1,"max_iterations":50,"completion_promise":"COMPLETE","terminal_promises":["COMPLETE","INCOMPLETE"],"components":{},"phase":"implementing","original_prompt":"issue 309","started_at":"2000-01-01T00:00:00Z","session_id":""}' > "$FOREIGN_LEGACY_STATE"
printf '%s\n' '{"role":"assistant","message":{"content":[{"type":"text","text":"Unrelated session output."}]}}' > "$FOREIGN_LEGACY_TRANSCRIPT"
FOREIGN_LEGACY_BEFORE=$(cksum "$FOREIGN_LEGACY_STATE")
FOREIGN_LEGACY_OUTPUT=$(
  cd "$FOREIGN_LEGACY_ROOT"
  jq -n --arg transcript "$FOREIGN_LEGACY_TRANSCRIPT" --arg session "foreign-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if [ -z "$FOREIGN_LEGACY_OUTPUT" ] &&
   [ "$FOREIGN_LEGACY_BEFORE" = "$(cksum "$FOREIGN_LEGACY_STATE")" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook preserves live owner state on an explicit session mismatch... "
FOREIGN_SESSION_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-foreign-session.XXXXXX")
FOREIGN_SESSION_STATE="$FOREIGN_SESSION_ROOT/.local/state/ship.loop.local.json"
FOREIGN_SESSION_TRANSCRIPT="$FOREIGN_SESSION_ROOT/foreign-session.jsonl"
mkdir -p "$(dirname "$FOREIGN_SESSION_STATE")"
printf '%s\n' '{"schema_version":2,"owner_workflow":"ship","loop_name":"ship","iteration":4,"max_iterations":50,"completion_promise":"SHIPPED","terminal_promises":["SHIPPED","INCOMPLETE"],"components":{},"phase":"ci-watch","original_prompt":"ship","session_id":"owner-session"}' > "$FOREIGN_SESSION_STATE"
printf '%s\n' '{"role":"assistant","message":{"content":[{"type":"text","text":"Unrelated session output."}]}}' > "$FOREIGN_SESSION_TRANSCRIPT"
FOREIGN_SESSION_BEFORE=$(cksum "$FOREIGN_SESSION_STATE")
FOREIGN_SESSION_OUTPUT=$(
  cd "$FOREIGN_SESSION_ROOT"
  jq -n --arg transcript "$FOREIGN_SESSION_TRANSCRIPT" --arg session "foreign-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if [ -z "$FOREIGN_SESSION_OUTPUT" ] &&
   [ -e "$FOREIGN_SESSION_STATE" ] &&
   [ "$FOREIGN_SESSION_BEFORE" = "$(cksum "$FOREIGN_SESSION_STATE")" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook claims an empty session ID from owner transcript evidence... "
OWNER_CLAIM_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-owner-claim.XXXXXX")
OWNER_CLAIM_STATE="$OWNER_CLAIM_ROOT/.local/state/ship.loop.local.json"
OWNER_CLAIM_TRANSCRIPT="$OWNER_CLAIM_ROOT/transcript.jsonl"
mkdir -p "$(dirname "$OWNER_CLAIM_STATE")"
printf '%s\n' '{"schema_version":2,"owner_workflow":"ship","loop_name":"ship","iteration":1,"max_iterations":50,"completion_promise":"SHIPPED","terminal_promises":["SHIPPED","INCOMPLETE"],"components":{},"phase":"ci-watch","original_prompt":"ship","session_id":""}' > "$OWNER_CLAIM_STATE"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: ship\nOutput <done>SHIPPED</done> when all completion criteria are met."}]}}' > "$OWNER_CLAIM_TRANSCRIPT"
OWNER_CLAIM_OUTPUT=$(
  cd "$OWNER_CLAIM_ROOT"
  jq -n --arg transcript "$OWNER_CLAIM_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if printf '%s\n' "$OWNER_CLAIM_OUTPUT" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
   jq -e '.iteration == 2 and .session_id == "owner-session"' "$OWNER_CLAIM_STATE" >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Loop setup ignores unrelated repository-local transcript files... "
SETUP_TRANSCRIPT_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-setup-loop-transcript.XXXXXX")
SETUP_TRANSCRIPT_STATE="$SETUP_TRANSCRIPT_ROOT/.local/state/start-issue-309.loop.local.json"
mkdir -p "$SETUP_TRANSCRIPT_ROOT/.claude"
printf '%s\n' '{"role":"assistant","message":{"content":[]}}' > "$SETUP_TRANSCRIPT_ROOT/.claude/foreign-session.jsonl"
(
  cd "$SETUP_TRANSCRIPT_ROOT"
  env -u CLAUDE_SESSION_ID "$ROOT_DIR/shared/scripts/setup-loop.sh" \
    "start-issue-309" "COMPLETE" 50 "implementing" '{}' >/dev/null
)
if jq -e '.session_id == ""' "$SETUP_TRANSCRIPT_STATE" >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook filters concurrent loops by transcript ownership before ambiguity checks... "
CONCURRENT_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-concurrent.XXXXXX")
CONCURRENT_STATE_DIR="$CONCURRENT_ROOT/.local/state"
CONCURRENT_OWNER_STATE="$CONCURRENT_STATE_DIR/start-issue-309.loop.local.json"
CONCURRENT_FOREIGN_STATE="$CONCURRENT_STATE_DIR/ship.loop.local.json"
CONCURRENT_TRANSCRIPT="$CONCURRENT_ROOT/transcript.jsonl"
mkdir -p "$CONCURRENT_STATE_DIR"
printf '%s\n' '{"schema_version":2,"owner_workflow":"start-issue","loop_name":"start-issue-309","iteration":1,"max_iterations":50,"completion_promise":"COMPLETE","terminal_promises":["COMPLETE","INCOMPLETE"],"components":{},"phase":"implementing","original_prompt":"issue 309","session_id":""}' > "$CONCURRENT_OWNER_STATE"
printf '%s\n' '{"schema_version":2,"owner_workflow":"ship","loop_name":"ship","iteration":7,"max_iterations":50,"completion_promise":"SHIPPED","terminal_promises":["SHIPPED","INCOMPLETE"],"components":{},"phase":"ci-watch","original_prompt":"ship","session_id":"foreign-session"}' > "$CONCURRENT_FOREIGN_STATE"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: start-issue-309"}]}}' > "$CONCURRENT_TRANSCRIPT"
CONCURRENT_FOREIGN_BEFORE=$(cksum "$CONCURRENT_FOREIGN_STATE")
CONCURRENT_OUTPUT=$(
  cd "$CONCURRENT_ROOT"
  jq -n --arg transcript "$CONCURRENT_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if printf '%s\n' "$CONCURRENT_OUTPUT" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
   jq -e '.iteration == 2 and .session_id == "owner-session"' "$CONCURRENT_OWNER_STATE" >/dev/null 2>&1 &&
   [ "$CONCURRENT_FOREIGN_BEFORE" = "$(cksum "$CONCURRENT_FOREIGN_STATE")" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook fails closed for the live duplicate-loop shape... "
DUPLICATE_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-duplicates.XXXXXX")
DUPLICATE_STATE_DIR="$DUPLICATE_ROOT/.local/state"
mkdir -p "$DUPLICATE_STATE_DIR"
printf '%s\n' '{"loop_name":"start-issue-301","iteration":1,"max_iterations":50,"completion_promise":"COMPLETE","phase":"implementing","original_prompt":"issue 301","session_id":""}' > "$DUPLICATE_STATE_DIR/start-issue-301.loop.local.json"
printf '%s\n' '{"loop_name":"direct-smoke","iteration":1,"max_iterations":10,"completion_promise":"DONE","phase":"testing","original_prompt":"smoke","session_id":""}' > "$DUPLICATE_STATE_DIR/direct-smoke.loop.local.json"
DUPLICATE_OWNER_BEFORE=$(cksum "$DUPLICATE_STATE_DIR/start-issue-301.loop.local.json")
DUPLICATE_STRAY_BEFORE=$(cksum "$DUPLICATE_STATE_DIR/direct-smoke.loop.local.json")
DUPLICATE_TRANSCRIPT="$DUPLICATE_ROOT/transcript.jsonl"
printf '%s\n' \
  '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: start-issue-301\nLoop initialized: direct-smoke"}]}}' \
  '{"role":"assistant","message":{"content":[{"type":"text","text":"<done>COMPLETE</done>"}]}}' \
  > "$DUPLICATE_TRANSCRIPT"
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
printf '%s\n' \
  '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: e2e-verify-42"}]}}' \
  '{"role":"assistant","message":{"content":[{"type":"text","text":"<done>E2E_FAIL</done>"}]}}' \
  > "$PROMISE_TRANSCRIPT"
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
INVALID_TRANSCRIPT="$INVALID_ROOT/transcript.jsonl"
mkdir -p "$(dirname "$INVALID_STATE")"
printf '%s\n' '{"schema_version":2,"owner_workflow":"ship","loop_name":"ship","iteration":1,"max_iterations":50,"completion_promise":"FOREIGN","terminal_promises":["SHIPPED","INCOMPLETE"],"components":{},"phase":"pushing","original_prompt":"ship","session_id":""}' > "$INVALID_STATE"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: ship"}]}}' > "$INVALID_TRANSCRIPT"
INVALID_BEFORE=$(cksum "$INVALID_STATE")
INVALID_OUTPUT=$(
  cd "$INVALID_ROOT"
  jq -n --arg transcript "$INVALID_TRANSCRIPT" '{transcript_path: $transcript}' | "$CORE_STOP_HOOK"
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
LEGACY_SHIP_TRANSCRIPT="$LEGACY_SHIP_ROOT/transcript.jsonl"
mkdir -p "$(dirname "$LEGACY_SHIP_STATE")"
printf '%s\n' '{"loop_name":"ship","iteration":1,"max_iterations":50,"completion_promise":"SHIPPED","phase":"ci-watch","args":"--no-merge","head_sha":"abc123","original_prompt":"ship","session_id":""}' > "$LEGACY_SHIP_STATE"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: ship"}]}}' > "$LEGACY_SHIP_TRANSCRIPT"
LEGACY_SHIP_OUTPUT=$(
  cd "$LEGACY_SHIP_ROOT"
  jq -n --arg transcript "$LEGACY_SHIP_TRANSCRIPT" '{transcript_path: $transcript}' | "$CORE_STOP_HOOK"
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

echo -n "  Stop hook prunes owned state whose worktree no longer exists... "
STALE_WORKTREE_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-stale-worktree.XXXXXX")
STALE_WORKTREE_STATE="$STALE_WORKTREE_ROOT/.local/state/ship.loop.local.json"
STALE_WORKTREE_TRANSCRIPT="$STALE_WORKTREE_ROOT/transcript.jsonl"
mkdir -p "$(dirname "$STALE_WORKTREE_STATE")"
jq -n \
  --arg owner "$STALE_WORKTREE_ROOT" \
  --arg missing "$STALE_WORKTREE_ROOT/missing-worktree" \
  '{schema_version:2,owner_workflow:"ship",loop_name:"ship",iteration:1,max_iterations:50,completion_promise:"SHIPPED",terminal_promises:["SHIPPED","INCOMPLETE"],components:{},phase:"pushing",original_prompt:"ship",session_id:"owner-session",session_worktree_path:$owner,worktree_path:$missing}' \
  > "$STALE_WORKTREE_STATE"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: ship"}]}}' > "$STALE_WORKTREE_TRANSCRIPT"
STALE_WORKTREE_OUTPUT=$(
  cd "$STALE_WORKTREE_ROOT"
  jq -n --arg transcript "$STALE_WORKTREE_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if [ -z "$STALE_WORKTREE_OUTPUT" ] && [ ! -e "$STALE_WORKTREE_STATE" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Linked-worktree Stop hook ignores state owned by another worktree... "
WORKTREE_FIXTURE=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-worktree.XXXXXX")
WORKTREE_MAIN="$WORKTREE_FIXTURE/main"
WORKTREE_LINKED="$WORKTREE_FIXTURE/linked"
mkdir -p "$WORKTREE_MAIN"
git -C "$WORKTREE_MAIN" init -b main -q
git -C "$WORKTREE_MAIN" -c user.name='Hook Tests' -c user.email='hooks@example.com' \
  commit --allow-empty -qm 'test: initialize owner root'
git -C "$WORKTREE_MAIN" worktree add -qb linked-fixture "$WORKTREE_LINKED" >/dev/null
mkdir -p "$WORKTREE_MAIN/.local/state"
jq -n \
  --arg worktree "$WORKTREE_MAIN" \
  '{schema_version:2,owner_workflow:"start-issue",loop_name:"start-issue-42",iteration:1,max_iterations:50,completion_promise:"COMPLETE",terminal_promises:["COMPLETE","INCOMPLETE"],components:{},phase:"implementing",original_prompt:"issue 42",session_id:"owner-session",session_worktree_path:$worktree,worktree_path:$worktree}' \
  > "$WORKTREE_MAIN/.local/state/start-issue-42.loop.local.json"
WORKTREE_TRANSCRIPT="$WORKTREE_LINKED/transcript.jsonl"
printf '%s\n' \
  '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: start-issue-42"}]}}' \
  '{"role":"assistant","message":{"content":[{"type":"text","text":"<done>COMPLETE</done>"}]}}' \
  > "$WORKTREE_TRANSCRIPT"
WORKTREE_STATE_BEFORE=$(cksum "$WORKTREE_MAIN/.local/state/start-issue-42.loop.local.json")
WORKTREE_OUTPUT=$(
  cd "$WORKTREE_LINKED"
  jq -n --arg transcript "$WORKTREE_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if [ -z "$WORKTREE_OUTPUT" ] &&
   [ -e "$WORKTREE_MAIN/.local/state/start-issue-42.loop.local.json" ] &&
   [ "$WORKTREE_STATE_BEFORE" = "$(cksum "$WORKTREE_MAIN/.local/state/start-issue-42.loop.local.json")" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook separates the session checkout from a linked workflow target... "
rm -f "$WORKTREE_MAIN/.local/state/start-issue-42.loop.local.json"
jq -n \
  --arg owner "$WORKTREE_MAIN" \
  --arg target "$WORKTREE_LINKED" \
  '{schema_version:2,owner_workflow:"start-issue",loop_name:"start-issue-43",iteration:1,max_iterations:50,completion_promise:"COMPLETE",terminal_promises:["COMPLETE","INCOMPLETE"],components:{},phase:"implementing",original_prompt:"issue 43",session_id:"owner-session",session_worktree_path:$owner,worktree_path:$target}' \
  > "$WORKTREE_MAIN/.local/state/start-issue-43.loop.local.json"
WORKTREE_TRANSCRIPT="$WORKTREE_MAIN/transcript.jsonl"
printf '%s\n' \
  '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: start-issue-43"}]}}' \
  '{"role":"assistant","message":{"content":[{"type":"text","text":"<done>COMPLETE</done>"}]}}' \
  > "$WORKTREE_TRANSCRIPT"
WORKTREE_OUTPUT=$(
  cd "$WORKTREE_MAIN"
  jq -n --arg transcript "$WORKTREE_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if [ -z "$WORKTREE_OUTPUT" ] &&
   [ ! -e "$WORKTREE_MAIN/.local/state/start-issue-43.loop.local.json" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook clears targetless ship recovery phases... "
NO_TARGET_STATE="$WORKTREE_MAIN/.local/state/ship.loop.local.json"
NO_TARGET_TRANSCRIPT="$WORKTREE_MAIN/no-target.jsonl"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: ship"}]}}' > "$NO_TARGET_TRANSCRIPT"
NO_TARGET_FAILURES=0
for NO_TARGET_PHASE in reviewing pushing; do
  jq -n \
    --arg worktree "$WORKTREE_MAIN" \
    --arg phase "$NO_TARGET_PHASE" \
    '{schema_version:2,owner_workflow:"ship",loop_name:"ship",iteration:1,max_iterations:50,completion_promise:"SHIPPED",terminal_promises:["SHIPPED","INCOMPLETE"],components:{},phase:$phase,original_prompt:"ship",session_id:"owner-session",session_worktree_path:$worktree,worktree_path:$worktree}' \
    > "$NO_TARGET_STATE"
  NO_TARGET_OUTPUT=$(
    cd "$WORKTREE_MAIN"
    jq -n --arg transcript "$NO_TARGET_TRANSCRIPT" --arg session "owner-session" \
      '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
  )
  if [ -n "$NO_TARGET_OUTPUT" ] || [ -e "$NO_TARGET_STATE" ]; then
    NO_TARGET_FAILURES=$((NO_TARGET_FAILURES + 1))
  fi
done
if [ "$NO_TARGET_FAILURES" -eq 0 ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook preserves targetless recovery state owned by another session... "
jq -n \
  --arg worktree "$WORKTREE_MAIN" \
  '{schema_version:2,owner_workflow:"ship",loop_name:"ship",iteration:1,max_iterations:50,completion_promise:"SHIPPED",terminal_promises:["SHIPPED","INCOMPLETE"],components:{},phase:"pushing",original_prompt:"ship",session_id:"foreign-session",session_worktree_path:$worktree,worktree_path:$worktree}' \
  > "$NO_TARGET_STATE"
FOREIGN_NO_TARGET_BEFORE=$(cksum "$NO_TARGET_STATE")
FOREIGN_NO_TARGET_OUTPUT=$(
  cd "$WORKTREE_MAIN"
  jq -n --arg transcript "$NO_TARGET_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if [ -z "$FOREIGN_NO_TARGET_OUTPUT" ] &&
   [ -e "$NO_TARGET_STATE" ] &&
   [ "$FOREIGN_NO_TARGET_BEFORE" = "$(cksum "$NO_TARGET_STATE")" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook preserves clean pushed-PR wait phases... "
CLEAN_WAIT_FAILURES=0
for CLEAN_WAIT_PHASE in ci-watch bot-watching merging; do
  jq -n \
    --arg worktree "$WORKTREE_MAIN" \
    --arg phase "$CLEAN_WAIT_PHASE" \
    '{schema_version:2,owner_workflow:"ship",loop_name:"ship",iteration:1,max_iterations:50,completion_promise:"SHIPPED",terminal_promises:["SHIPPED","INCOMPLETE"],components:{},phase:$phase,original_prompt:"ship",session_id:"owner-session",session_worktree_path:$worktree,worktree_path:$worktree}' \
    > "$NO_TARGET_STATE"
  CLEAN_WAIT_OUTPUT=$(
    cd "$WORKTREE_MAIN"
    jq -n --arg transcript "$NO_TARGET_TRANSCRIPT" --arg session "owner-session" \
      '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
  )
  if ! printf '%s\n' "$CLEAN_WAIT_OUTPUT" | jq -e '.decision == "block"' >/dev/null 2>&1 ||
     [ ! -e "$NO_TARGET_STATE" ]; then
    CLEAN_WAIT_FAILURES=$((CLEAN_WAIT_FAILURES + 1))
  fi
done
if [ "$CLEAN_WAIT_FAILURES" -eq 0 ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook accepts a staged repository target... "
STAGED_TARGET_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-staged-target.XXXXXX")
git -C "$STAGED_TARGET_ROOT" init -b main -q
git -C "$STAGED_TARGET_ROOT" -c user.name='Hook Tests' -c user.email='hooks@example.com' \
  commit --allow-empty -qm 'test: initialize staged target'
printf '%s\n' 'staged target' > "$STAGED_TARGET_ROOT/target.txt"
git -C "$STAGED_TARGET_ROOT" add target.txt
STAGED_TARGET_STATE="$STAGED_TARGET_ROOT/.local/state/ship.loop.local.json"
STAGED_TARGET_TRANSCRIPT="$STAGED_TARGET_ROOT/transcript.jsonl"
mkdir -p "$(dirname "$STAGED_TARGET_STATE")"
jq -n \
  --arg worktree "$STAGED_TARGET_ROOT" \
  '{schema_version:2,owner_workflow:"ship",loop_name:"ship",iteration:1,max_iterations:50,completion_promise:"SHIPPED",terminal_promises:["SHIPPED","INCOMPLETE"],components:{},phase:"pushing",original_prompt:"ship",session_id:"owner-session",session_worktree_path:$worktree,worktree_path:$worktree}' \
  > "$STAGED_TARGET_STATE"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: ship"}]}}' > "$STAGED_TARGET_TRANSCRIPT"
STAGED_TARGET_OUTPUT=$(
  cd "$STAGED_TARGET_ROOT"
  jq -n --arg transcript "$STAGED_TARGET_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if printf '%s\n' "$STAGED_TARGET_OUTPUT" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
   [ -e "$STAGED_TARGET_STATE" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook accepts commits ahead of the configured upstream... "
UNPUSHED_FIXTURE=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-unpushed.XXXXXX")
UNPUSHED_REMOTE="$UNPUSHED_FIXTURE/remote.git"
UNPUSHED_WORKTREE="$UNPUSHED_FIXTURE/worktree"
git init --bare -q "$UNPUSHED_REMOTE"
git init -b main -q "$UNPUSHED_WORKTREE"
git -C "$UNPUSHED_WORKTREE" -c user.name='Hook Tests' -c user.email='hooks@example.com' \
  commit --allow-empty -qm 'test: initialize upstream target'
git -C "$UNPUSHED_WORKTREE" remote add origin "$UNPUSHED_REMOTE"
git -C "$UNPUSHED_WORKTREE" push -qu origin main
git -C "$UNPUSHED_WORKTREE" -c user.name='Hook Tests' -c user.email='hooks@example.com' \
  commit --allow-empty -qm 'test: create unpushed target'
UNPUSHED_STATE="$UNPUSHED_WORKTREE/.local/state/ship.loop.local.json"
UNPUSHED_TRANSCRIPT="$UNPUSHED_WORKTREE/transcript.jsonl"
mkdir -p "$(dirname "$UNPUSHED_STATE")"
jq -n \
  --arg worktree "$UNPUSHED_WORKTREE" \
  '{schema_version:2,owner_workflow:"ship",loop_name:"ship",iteration:1,max_iterations:50,completion_promise:"SHIPPED",terminal_promises:["SHIPPED","INCOMPLETE"],components:{},phase:"pushing",original_prompt:"ship",session_id:"owner-session",session_worktree_path:$worktree,worktree_path:$worktree}' \
  > "$UNPUSHED_STATE"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: ship"}]}}' > "$UNPUSHED_TRANSCRIPT"
UNPUSHED_OUTPUT=$(
  cd "$UNPUSHED_WORKTREE"
  jq -n --arg transcript "$UNPUSHED_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if printf '%s\n' "$UNPUSHED_OUTPUT" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
   [ -e "$UNPUSHED_STATE" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook uses the persisted nonstandard base branch... "
NONSTANDARD_FIXTURE=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-nonstandard-base.XXXXXX")
NONSTANDARD_REMOTE="$NONSTANDARD_FIXTURE/remote.git"
NONSTANDARD_WORKTREE="$NONSTANDARD_FIXTURE/worktree"
git init --bare -q "$NONSTANDARD_REMOTE"
git init -b develop -q "$NONSTANDARD_WORKTREE"
git -C "$NONSTANDARD_WORKTREE" -c user.name='Hook Tests' -c user.email='hooks@example.com' \
  commit --allow-empty -qm 'test: initialize nonstandard base'
git -C "$NONSTANDARD_WORKTREE" remote add origin "$NONSTANDARD_REMOTE"
git -C "$NONSTANDARD_WORKTREE" push -qu origin develop
git -C "$NONSTANDARD_WORKTREE" checkout -qb feature
git -C "$NONSTANDARD_WORKTREE" -c user.name='Hook Tests' -c user.email='hooks@example.com' \
  commit --allow-empty -qm 'test: create fully pushed feature'
git -C "$NONSTANDARD_WORKTREE" push -qu -u origin feature
NONSTANDARD_STATE="$NONSTANDARD_WORKTREE/.local/state/ship.loop.local.json"
NONSTANDARD_TRANSCRIPT="$NONSTANDARD_WORKTREE/transcript.jsonl"
mkdir -p "$(dirname "$NONSTANDARD_STATE")"
jq -n \
  --arg worktree "$NONSTANDARD_WORKTREE" \
  '{schema_version:2,owner_workflow:"ship",loop_name:"ship",iteration:1,max_iterations:50,completion_promise:"SHIPPED",terminal_promises:["SHIPPED","INCOMPLETE"],components:{},phase:"pushing",base_branch:"develop",original_prompt:"ship",session_id:"owner-session",session_worktree_path:$worktree,worktree_path:$worktree}' \
  > "$NONSTANDARD_STATE"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: ship"}]}}' > "$NONSTANDARD_TRANSCRIPT"
NONSTANDARD_OUTPUT=$(
  cd "$NONSTANDARD_WORKTREE"
  jq -n --arg transcript "$NONSTANDARD_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if printf '%s\n' "$NONSTANDARD_OUTPUT" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
   [ -e "$NONSTANDARD_STATE" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

git -C "$WORKTREE_LINKED" -c user.name='Hook Tests' -c user.email='hooks@example.com' \
  commit --allow-empty -qm 'test: create repository target'
RETRY_STATE="$WORKTREE_MAIN/.local/state/ship.loop.local.json"
RETRY_TRANSCRIPT="$WORKTREE_LINKED/retry.jsonl"

echo -n "  Stop hook accepts a non-default branch ahead of the default branch... "
jq -n \
  --arg worktree "$WORKTREE_LINKED" \
  '{schema_version:2,owner_workflow:"ship",loop_name:"ship",iteration:1,max_iterations:50,completion_promise:"SHIPPED",terminal_promises:["SHIPPED","INCOMPLETE"],components:{},phase:"pushing",original_prompt:"ship",session_id:"owner-session",session_worktree_path:$worktree,worktree_path:$worktree}' \
  > "$RETRY_STATE"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: ship"}]}}' > "$RETRY_TRANSCRIPT"
NONDEFAULT_TARGET_OUTPUT=$(
  cd "$WORKTREE_LINKED"
  jq -n --arg transcript "$RETRY_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if printf '%s\n' "$NONDEFAULT_TARGET_OUTPUT" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
   [ -e "$RETRY_STATE" ]; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook resets the retry cap after content-only progress... "
printf '%s\n' 'first revision' > "$WORKTREE_LINKED/progress.txt"
jq -n \
  --arg worktree "$WORKTREE_LINKED" \
  '{schema_version:2,owner_workflow:"ship",loop_name:"ship",iteration:1,max_iterations:50,completion_promise:"SHIPPED",terminal_promises:["SHIPPED","INCOMPLETE"],components:{},phase:"pushing",original_prompt:"ship",session_id:"owner-session",session_worktree_path:$worktree,worktree_path:$worktree}' \
  > "$RETRY_STATE"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: ship"}]}}' > "$RETRY_TRANSCRIPT"
for _ in 1 2; do
  (
    cd "$WORKTREE_LINKED"
    jq -n --arg transcript "$RETRY_TRANSCRIPT" --arg session "owner-session" \
      '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
  ) >/dev/null
done
printf '%s\n' 'second revision' > "$WORKTREE_LINKED/progress.txt"
PROGRESS_OUTPUT=$(
  cd "$WORKTREE_LINKED"
  jq -n --arg transcript "$RETRY_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if printf '%s\n' "$PROGRESS_OUTPUT" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
   jq -e '.unchanged_block_count == 1' "$RETRY_STATE" >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook tracks filesystem progress before Git initialization... "
NONREPOSITORY_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-nonrepository.XXXXXX")
NONREPOSITORY_STATE="$NONREPOSITORY_ROOT/.local/state/create-go-project-example-project.loop.local.json"
NONREPOSITORY_TRANSCRIPT="$NONREPOSITORY_ROOT/transcript.jsonl"
mkdir -p "$(dirname "$NONREPOSITORY_STATE")" "$NONREPOSITORY_ROOT/example-project"
jq -n \
  --arg worktree "$NONREPOSITORY_ROOT" \
  '{schema_version:2,owner_workflow:"create-go-project-example-project",loop_name:"create-go-project-example-project",iteration:1,max_iterations:50,completion_promise:"COMPLETE",terminal_promises:["COMPLETE","INCOMPLETE"],components:{},phase:"implementing",original_prompt:"create example project",session_id:"owner-session",session_worktree_path:$worktree,worktree_path:$worktree}' \
  > "$NONREPOSITORY_STATE"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: create-go-project-example-project"}]}}' > "$NONREPOSITORY_TRANSCRIPT"
printf '%s\n' 'first revision' > "$NONREPOSITORY_ROOT/example-project/main.go"
for _ in 1 2; do
  (
    cd "$NONREPOSITORY_ROOT"
    jq -n --arg transcript "$NONREPOSITORY_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
  ) >/dev/null
done
printf '%s\n' 'unrelated revision' > "$NONREPOSITORY_ROOT/unrelated.txt"
(
  cd "$NONREPOSITORY_ROOT"
  jq -n --arg transcript "$NONREPOSITORY_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
) >/dev/null
NONREPOSITORY_SCOPED_COUNT=$(jq -r '.unchanged_block_count' "$NONREPOSITORY_STATE")
printf '%s\n' 'second revision' > "$NONREPOSITORY_ROOT/example-project/main.go"
NONREPOSITORY_OUTPUT=$(
  cd "$NONREPOSITORY_ROOT"
  jq -n --arg transcript "$NONREPOSITORY_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if [ "$NONREPOSITORY_SCOPED_COUNT" -eq 3 ] &&
   printf '%s\n' "$NONREPOSITORY_OUTPUT" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
   jq -e '.unchanged_block_count == 1' "$NONREPOSITORY_STATE" >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook excludes its own state mutations from the retry cap... "
SELF_STATE_ROOT=$(mktemp -d "$HOOK_TMP_BASE/gopher-ai-stop-hook-self-state.XXXXXX")
git -C "$SELF_STATE_ROOT" init -b main -q
git -C "$SELF_STATE_ROOT" -c user.name='Hook Tests' -c user.email='hooks@example.com' \
  commit --allow-empty -qm 'test: initialize self-state target'
printf '%s\n' 'staged target' > "$SELF_STATE_ROOT/target.txt"
git -C "$SELF_STATE_ROOT" add target.txt
SELF_STATE_FILE="$SELF_STATE_ROOT/.local/state/ship.loop.local.json"
SELF_STATE_TRANSCRIPT="$SELF_STATE_ROOT/transcript.jsonl"
mkdir -p "$(dirname "$SELF_STATE_FILE")"
jq -n \
  --arg worktree "$SELF_STATE_ROOT" \
  '{schema_version:2,owner_workflow:"ship",loop_name:"ship",iteration:1,max_iterations:50,completion_promise:"SHIPPED",terminal_promises:["SHIPPED","INCOMPLETE"],components:{},phase:"pushing",original_prompt:"ship",session_id:"owner-session",session_worktree_path:$worktree,worktree_path:$worktree}' \
  > "$SELF_STATE_FILE"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: ship"}]}}' > "$SELF_STATE_TRANSCRIPT"
for _ in 1 2; do
  (
    cd "$SELF_STATE_ROOT"
    jq -n --arg transcript "$SELF_STATE_TRANSCRIPT" --arg session "owner-session" \
      '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
  ) >/dev/null
done
if jq -e '.unchanged_block_count == 2' "$SELF_STATE_FILE" >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook resets the retry cap after a phase change... "
SELF_STATE_TMP="${SELF_STATE_FILE}.tmp"
jq '.phase = "ci-watch"' "$SELF_STATE_FILE" > "$SELF_STATE_TMP"
mv "$SELF_STATE_TMP" "$SELF_STATE_FILE"
SELF_STATE_PHASE_OUTPUT=$(
  cd "$SELF_STATE_ROOT"
  jq -n --arg transcript "$SELF_STATE_TRANSCRIPT" --arg session "owner-session" \
    '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
)
if printf '%s\n' "$SELF_STATE_PHASE_OUTPUT" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
   jq -e '.unchanged_block_count == 1' "$SELF_STATE_FILE" >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

echo -n "  Stop hook caps identical blocks and includes recovery details... "
jq -n \
  --arg worktree "$WORKTREE_LINKED" \
  '{schema_version:2,owner_workflow:"ship",loop_name:"ship",iteration:1,max_iterations:50,completion_promise:"SHIPPED",terminal_promises:["SHIPPED","INCOMPLETE"],components:{},phase:"pushing",original_prompt:"ship",session_id:"owner-session",session_worktree_path:$worktree,worktree_path:$worktree}' \
  > "$RETRY_STATE"
printf '%s\n' '{"role":"user","message":{"content":[{"type":"tool_result","content":"Loop initialized: ship"}]}}' > "$RETRY_TRANSCRIPT"
RETRY_FIRST=""
RETRY_THIRD=""
RETRY_FOURTH=""
for RETRY_ATTEMPT in 1 2 3 4; do
  RETRY_OUTPUT=$(
    cd "$WORKTREE_LINKED"
    jq -n --arg transcript "$RETRY_TRANSCRIPT" --arg session "owner-session" \
      '{transcript_path: $transcript, session_id: $session}' | "$CORE_STOP_HOOK"
  )
  case "$RETRY_ATTEMPT" in
    1) RETRY_FIRST="$RETRY_OUTPUT" ;;
    3) RETRY_THIRD="$RETRY_OUTPUT" ;;
    4) RETRY_FOURTH="$RETRY_OUTPUT" ;;
  esac
done
if printf '%s\n' "$RETRY_FIRST" | jq -e --arg state "$RETRY_STATE" '
     .decision == "block" and
     (.systemMessage | contains($state)) and
     (.systemMessage | contains("/go-workflow:cancel-loop"))
   ' >/dev/null 2>&1 &&
   printf '%s\n' "$RETRY_THIRD" | jq -e '.decision == "block"' >/dev/null 2>&1 &&
   [ -z "$RETRY_FOURTH" ] &&
   [ ! -e "$RETRY_STATE" ]; then
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
