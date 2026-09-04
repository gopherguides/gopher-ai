#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOOP_LIB="$ROOT_DIR/shared/lib/loop-state.sh"
SETUP_LOOP="$ROOT_DIR/shared/scripts/setup-loop.sh"
LOOP_TMP_BASE="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
LOOP_TMP_BASE=$(cd "$LOOP_TMP_BASE" && pwd -P) || exit 1
case "$LOOP_TMP_BASE/" in
  "$ROOT_DIR/"*)
    export GIT_CEILING_DIRECTORIES="$LOOP_TMP_BASE${GIT_CEILING_DIRECTORIES:+:$GIT_CEILING_DIRECTORIES}"
    ;;
esac
FIXTURE_BASE=$(mktemp -d "$LOOP_TMP_BASE/gopher-ai-loop-state.XXXXXX")

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected='$expected', actual='$actual')"
    FAIL=$((FAIL + 1))
  fi
}

fixture() {
  local name="$1"
  local dir="$FIXTURE_BASE/$name"
  mkdir -p "$dir/.local/state"
  printf '%s\n' "$dir"
}

run_setup() {
  bash "$SETUP_LOOP" "$@"
}

echo "=== Loop State JSON Tests ==="

FRESH_DIR=$(fixture fresh)
(
  cd "$FRESH_DIR"
  run_setup "test-loop" "TEST_DONE" 10 "init" \
    '{"init":"Start the task."}' "" '["TEST_DONE","TEST_FAIL"]' >/dev/null
)
FRESH_STATE="$FRESH_DIR/.local/state/test-loop.loop.local.json"
assert_eq "fresh schema contract" "true" "$(jq -r '
  .schema_version == 2 and
  .owner_workflow == "test-loop" and
  .terminal_promises == ["TEST_DONE", "TEST_FAIL"] and
  .completion_promise == "TEST_DONE" and
  .session_worktree_path == $expected_worktree and
  .worktree_path == $expected_worktree and
  .components == {}
' --arg expected_worktree "$FRESH_DIR" "$FRESH_STATE")"

REENTRY_BEFORE=$(jq -cS '.iteration = 7 | .phase = "watching" | .custom = "preserved"' "$FRESH_STATE")
printf '%s\n' "$REENTRY_BEFORE" > "$FRESH_STATE"
(
  cd "$FRESH_DIR"
  run_setup "test-loop" "TEST_DONE" 10 "init" '{}' "" \
    '["TEST_DONE","TEST_FAIL"]' >/dev/null
)
assert_eq "sole-target re-entry preserves semantic state" "$REENTRY_BEFORE" \
  "$(jq -cS . "$FRESH_STATE")"

GUARD_DIR=$(fixture guard)
(
  cd "$GUARD_DIR"
  run_setup "outer" "COMPLETE" "" "" '{}' >/dev/null
)
GUARD_STATE="$GUARD_DIR/.local/state/outer.loop.local.json"
GUARD_BEFORE=$(jq -cS . "$GUARD_STATE")
set +e
GUARD_ERROR=$(
  cd "$GUARD_DIR"
  run_setup "inner" "DONE" "" "" '{}' 2>&1
)
GUARD_STATUS=$?
set -e
assert_eq "second active loop is refused" "true" "$([ "$GUARD_STATUS" -ne 0 ] && echo true || echo false)"
assert_eq "second-loop diagnostic names owner" "true" \
  "$(printf '%s\n' "$GUARD_ERROR" | grep -Fq 'outer.loop.local.json' && echo true || echo false)"
assert_eq "guard leaves owner unchanged" "$GUARD_BEFORE" "$(jq -cS . "$GUARD_STATE")"
assert_eq "guard creates no second state" "false" \
  "$([ -e "$GUARD_DIR/.local/state/inner.loop.local.json" ] && echo true || echo false)"

GUARD_ALTERNATE_STATE="$GUARD_DIR/alternate/inner.loop.local.json"
set +e
GUARD_ALTERNATE_ERROR=$(
  cd "$GUARD_DIR"
  run_setup "inner" "DONE" "" "" '{}' "$GUARD_ALTERNATE_STATE" '["DONE"]' 2>&1
)
GUARD_ALTERNATE_STATUS=$?
set -e
assert_eq "explicit paths cannot bypass the owner-directory guard" "true" \
  "$([ "$GUARD_ALTERNATE_STATUS" -ne 0 ] && printf '%s\n' "$GUARD_ALTERNATE_ERROR" | grep -Fq 'owner state directory' && echo true || echo false)"
assert_eq "cross-directory guard creates no second state" "false" \
  "$([ -e "$GUARD_ALTERNATE_STATE" ] && echo true || echo false)"

GUARD_MUTATION_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-loop-guard-mutation.XXXXXX")
mkdir -p "$GUARD_MUTATION_ROOT/scripts" "$GUARD_MUTATION_ROOT/lib"
cp "$ROOT_DIR/shared/lib/loop-state.sh" "$GUARD_MUTATION_ROOT/lib/loop-state.sh"
sed \
  -e 's/if \[ "$STATE_DIR" != "$OWNER_STATE_DIR" \]; then/if false; then/' \
  -e 's/LOCK_DIR="$OWNER_STATE_DIR\/\.loop-setup\.lock"/LOCK_DIR="$STATE_DIR\/.loop-setup.lock"/' \
  -e 's/find_active_loops "$OWNER_STATE_DIR"/find_active_loops "$STATE_DIR"/' \
  -e 's/count_active_loops "$OWNER_STATE_DIR"/count_active_loops "$STATE_DIR"/' \
  "$ROOT_DIR/shared/scripts/setup-loop.sh" > "$GUARD_MUTATION_ROOT/scripts/setup-loop.sh"
GUARD_MUTATION_STATE="$GUARD_DIR/mutation/inner.loop.local.json"
set +e
(
  cd "$GUARD_DIR"
  bash "$GUARD_MUTATION_ROOT/scripts/setup-loop.sh" \
    "inner" "DONE" "" "" '{}' "$GUARD_MUTATION_STATE" '["DONE"]' >/dev/null 2>&1
)
GUARD_MUTATION_STATUS=$?
set -e
assert_eq "owner guard assertion rejects a cross-directory mutation" "true" \
  "$([ "$GUARD_MUTATION_STATUS" -eq 0 ] && [ -e "$GUARD_MUTATION_STATE" ] && echo true || echo false)"

EXPLICIT_DIR=$(fixture explicit)
EXPLICIT_STATE="$EXPLICIT_DIR/.local/state/custom-owner.loop.local.json"
mkdir -p "$(dirname "$EXPLICIT_STATE")"
(
  cd "$EXPLICIT_DIR"
  run_setup "owner" "DONE" "" "ready" '{}' "$EXPLICIT_STATE" '["DONE"]' >/dev/null
)
assert_eq "explicit absolute state path is preserved" "true" \
  "$(jq -e '.loop_name == "owner" and .phase == "ready"' "$EXPLICIT_STATE" >/dev/null && echo true || echo false)"
assert_eq "explicit path does not create a CWD state file" "false" \
  "$([ -e "$EXPLICIT_DIR/.local/state/owner.loop.local.json" ] && echo true || echo false)"
EXPLICIT_BEFORE=$(jq -cS . "$EXPLICIT_STATE")
set +e
IDENTITY_ERROR=$(
  cd "$EXPLICIT_DIR"
  run_setup "impostor" "DONE" "" "" '{}' "$EXPLICIT_STATE" '["DONE"]' 2>&1
)
IDENTITY_STATUS=$?
set -e
assert_eq "explicit state cannot re-enter another loop identity" "true" \
  "$([ "$IDENTITY_STATUS" -ne 0 ] && printf '%s\n' "$IDENTITY_ERROR" | grep -Fq "belongs to loop 'owner'" && echo true || echo false)"
assert_eq "identity rejection leaves explicit state unchanged" "$EXPLICIT_BEFORE" \
  "$(jq -cS . "$EXPLICIT_STATE")"
set +e
RELATIVE_ERROR=$(
  cd "$EXPLICIT_DIR"
  run_setup "relative" "DONE" "" "" '{}' '.local/state/relative.loop.local.json' '["DONE"]' 2>&1
)
RELATIVE_STATUS=$?
set -e
assert_eq "relative explicit state path is rejected" "true" \
  "$([ "$RELATIVE_STATUS" -ne 0 ] && printf '%s\n' "$RELATIVE_ERROR" | grep -Fq 'absolute path' && echo true || echo false)"
assert_eq "relative path rejection creates no state" "false" \
  "$([ -e "$EXPLICIT_DIR/.local/state/relative.loop.local.json" ] && echo true || echo false)"

CONCURRENT_DIR=$(fixture concurrent)
set +e
(
  cd "$CONCURRENT_DIR"
  run_setup "first" "DONE" "" "" '{}' > first.out 2> first.err
) &
FIRST_PID=$!
(
  cd "$CONCURRENT_DIR"
  run_setup "second" "DONE" "" "" '{}' > second.out 2> second.err
) &
SECOND_PID=$!
wait "$FIRST_PID"
FIRST_STATUS=$?
wait "$SECOND_PID"
SECOND_STATUS=$?
set -e
CONCURRENT_SUCCESS=$(( (FIRST_STATUS == 0 ? 1 : 0) + (SECOND_STATUS == 0 ? 1 : 0) ))
CONCURRENT_STATES=$(find "$CONCURRENT_DIR/.local/state" -maxdepth 1 -name '*.loop.local.json' | wc -l | tr -d ' ')
assert_eq "concurrent setup permits exactly one creator" "1" "$CONCURRENT_SUCCESS"
assert_eq "concurrent setup creates exactly one state" "1" "$CONCURRENT_STATES"

CLEANUP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-loop-cleanup.XXXXXX")
CLEANUP_PRIMARY="$CLEANUP_ROOT/primary"
CLEANUP_LINKED="$CLEANUP_ROOT/linked"
mkdir -p "$CLEANUP_PRIMARY"
git -C "$CLEANUP_PRIMARY" init -q
git -C "$CLEANUP_PRIMARY" -c user.name='Loop State Tests' -c user.email='loop-state@example.com' \
  commit --allow-empty -qm 'test: initialize cleanup fixture'
git -C "$CLEANUP_PRIMARY" worktree add -qb cleanup-linked "$CLEANUP_LINKED" >/dev/null
mkdir -p "$CLEANUP_PRIMARY/.local/state"
printf '%s\n' '{"loop_name":"ship","completion_promise":"SHIPPED"}' \
  > "$CLEANUP_PRIMARY/.local/state/ship.loop.local.json"
(
  cd "$CLEANUP_LINKED"
  bash "$ROOT_DIR/shared/scripts/cleanup-loop.sh" ship >/dev/null
)
assert_eq "linked-worktree cleanup resolves the primary owner state" "false" \
  "$([ -e "$CLEANUP_PRIMARY/.local/state/ship.loop.local.json" ] && echo true || echo false)"

CLEANUP_MUTATION_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-loop-cleanup-mutation.XXXXXX")
mkdir -p "$CLEANUP_MUTATION_ROOT/scripts" "$CLEANUP_MUTATION_ROOT/lib"
cp "$ROOT_DIR/shared/lib/loop-state.sh" "$CLEANUP_MUTATION_ROOT/lib/loop-state.sh"
sed 's#STATE_DIR=$(loop_state_directory)#STATE_DIR="$PWD/.local/state"#' \
  "$ROOT_DIR/shared/scripts/cleanup-loop.sh" > "$CLEANUP_MUTATION_ROOT/scripts/cleanup-loop.sh"
printf '%s\n' '{"loop_name":"ship","completion_promise":"SHIPPED"}' \
  > "$CLEANUP_PRIMARY/.local/state/ship.loop.local.json"
(
  cd "$CLEANUP_LINKED"
  bash "$CLEANUP_MUTATION_ROOT/scripts/cleanup-loop.sh" ship >/dev/null
)
assert_eq "cleanup owner assertion rejects an ambient-path mutation" "true" \
  "$([ -e "$CLEANUP_PRIMARY/.local/state/ship.loop.local.json" ] && echo true || echo false)"
(
  cd "$CLEANUP_LINKED"
  bash "$ROOT_DIR/shared/scripts/cleanup-loop.sh" ship >/dev/null
)

LEGACY_DIR=$(fixture legacy-ship)
LEGACY_STATE="$LEGACY_DIR/.local/state/ship.loop.local.json"
printf '%s\n' '{"loop_name":"ship","iteration":9,"max_iterations":50,"completion_promise":"SHIPPED","phase":"ci-watch","args":"--no-merge","head_sha":"abc123","pr_number":"42","original_prompt":"ship","session_id":"","awaiting_driver_input":false,"driver_input_reason":""}' > "$LEGACY_STATE"
(
  cd "$LEGACY_DIR"
  source "$LOOP_LIB"
  read_loop_state "$LEGACY_STATE" '[]'
  [ "$PHASE" = "ci-watch" ]
)
assert_eq "legacy ship migrates additively" "true" "$(jq -r '
  .schema_version == 2 and
  .owner_workflow == "ship" and
  .terminal_promises == ["SHIPPED", "INCOMPLETE"] and
  .components == {} and
  .phase == "ci-watch" and
  .args == "--no-merge" and
  .head_sha == "abc123" and
  .pr_number == "42"
' "$LEGACY_STATE")"

LEGACY_E2E_DIR=$(fixture legacy-e2e)
LEGACY_E2E_STATE="$LEGACY_E2E_DIR/.local/state/e2e-verify-42.loop.local.json"
printf '%s\n' '{"loop_name":"e2e-verify-42","iteration":2,"completion_promise":"VERIFIED","phase":"building"}' > "$LEGACY_E2E_STATE"
(
  cd "$LEGACY_E2E_DIR"
  source "$LOOP_LIB"
  read_loop_state "$LEGACY_E2E_STATE" '[]'
)
assert_eq "legacy E2E derives all terminal promises" '["VERIFIED","E2E_FAIL","INCOMPLETE"]' \
  "$(jq -c '.terminal_promises' "$LEGACY_E2E_STATE")"

LEGACY_COMPOSED_E2E_DIR=$(fixture legacy-composed-e2e)
LEGACY_COMPOSED_E2E_STATE="$LEGACY_COMPOSED_E2E_DIR/.local/state/e2e-verify-302.loop.local.json"
printf '%s\n' '{"loop_name":"e2e-verify-302","iteration":5,"completion_promise":"VERIFIED","phase":"shipping","mode":"fix-and-ship"}' > "$LEGACY_COMPOSED_E2E_STATE"
LEGACY_COMPOSED_E2E_BEFORE=$(cksum "$LEGACY_COMPOSED_E2E_STATE")
set +e
LEGACY_COMPOSED_E2E_ERROR=$( (
  cd "$LEGACY_COMPOSED_E2E_DIR"
  source "$LOOP_LIB"
  read_loop_state "$LEGACY_COMPOSED_E2E_STATE" '[]'
  ) 2>&1 )
LEGACY_COMPOSED_E2E_STATUS=$?
set -e
assert_eq "legacy composed E2E state fails closed with restart guidance" "true" \
  "$([ "$LEGACY_COMPOSED_E2E_STATUS" -ne 0 ] && printf '%s\n' "$LEGACY_COMPOSED_E2E_ERROR" | grep -Fq 'Cancel it and restart e2e-verify' && echo true || echo false)"
assert_eq "legacy composed E2E rejection is non-mutating" "$LEGACY_COMPOSED_E2E_BEFORE" \
  "$(cksum "$LEGACY_COMPOSED_E2E_STATE")"

UNKNOWN_DIR=$(fixture legacy-unknown)
UNKNOWN_STATE="$UNKNOWN_DIR/.local/state/custom.loop.local.json"
printf '%s\n' '{"loop_name":"custom","iteration":1,"completion_promise":"CUSTOM_DONE","phase":"work"}' > "$UNKNOWN_STATE"
(
  cd "$UNKNOWN_DIR"
  source "$LOOP_LIB"
  read_loop_state "$UNKNOWN_STATE" '[]'
)
assert_eq "unknown legacy loop keeps current-only allowlist" '["CUSTOM_DONE"]' \
  "$(jq -c '.terminal_promises' "$UNKNOWN_STATE")"

CORRUPT_DIR=$(fixture corrupt-known)
CORRUPT_STATE="$CORRUPT_DIR/.local/state/ship.loop.local.json"
printf '%s\n' '{"loop_name":"ship","iteration":1,"completion_promise":"FOREIGN","phase":"pushing"}' > "$CORRUPT_STATE"
CORRUPT_BEFORE=$(jq -cS . "$CORRUPT_STATE")
set +e
CORRUPT_ERROR=$( (
  cd "$CORRUPT_DIR"
  source "$LOOP_LIB"
  read_loop_state "$CORRUPT_STATE" '[]'
  ) 2>&1 )
CORRUPT_STATUS=$?
set -e
assert_eq "known legacy foreign promise is rejected" "true" \
  "$([ "$CORRUPT_STATUS" -ne 0 ] && printf '%s\n' "$CORRUPT_ERROR" | grep -Fq 'FOREIGN' && echo true || echo false)"
assert_eq "failed legacy migration is non-mutating" "$CORRUPT_BEFORE" "$(jq -cS . "$CORRUPT_STATE")"

LEGACY_COMPOSED_DIR=$(fixture legacy-complete-issue)
LEGACY_COMPOSED_STATE="$LEGACY_COMPOSED_DIR/.local/state/complete-issue-302.loop.local.json"
printf '%s\n' '{"loop_name":"complete-issue-302","iteration":8,"completion_promise":"COMPLETE","phase":"verifying","pr_number":"302"}' > "$LEGACY_COMPOSED_STATE"
LEGACY_COMPOSED_BEFORE=$(cksum "$LEGACY_COMPOSED_STATE")
set +e
LEGACY_COMPOSED_ERROR=$( (
  cd "$LEGACY_COMPOSED_DIR"
  source "$LOOP_LIB"
  read_loop_state "$LEGACY_COMPOSED_STATE" '[]'
  ) 2>&1 )
LEGACY_COMPOSED_STATUS=$?
set -e
assert_eq "legacy composed state fails closed with restart guidance" "true" \
  "$([ "$LEGACY_COMPOSED_STATUS" -ne 0 ] && printf '%s\n' "$LEGACY_COMPOSED_ERROR" | grep -Fq 'Cancel it and restart complete-issue' && echo true || echo false)"
assert_eq "legacy composed rejection is non-mutating" "$LEGACY_COMPOSED_BEFORE" \
  "$(cksum "$LEGACY_COMPOSED_STATE")"

PATH_DIR=$(fixture paths)
PATH_STATE="$PATH_DIR/.local/state/complete-issue-42.loop.local.json"
(
  cd "$PATH_DIR"
  run_setup "complete-issue-42" "COMPLETE" 100 "implementing" '{}' "" \
    '["COMPLETE","INCOMPLETE"]' >/dev/null
  source "$LOOP_LIB"
  E2E_PATH=$(child_workflow_path '[]' 'e2e_verify')
  SHIP_PATH=$(child_workflow_path "$E2E_PATH" 'ship')
  initialize_workflow_state "$PATH_STATE" "$E2E_PATH"
  initialize_workflow_state "$PATH_STATE" "$SHIP_PATH"
  set_loop_field "$PATH_STATE" "pr_number" "42" "$E2E_PATH"
  set_loop_json_field "$PATH_STATE" "pages_tested" '3' "$E2E_PATH"
  set_loop_json_field "$PATH_STATE" "required" 'true' "$E2E_PATH"
  set_loop_field "$PATH_STATE" "transient" "remove-me" "$SHIP_PATH"
  delete_loop_field "$PATH_STATE" "transient" "$SHIP_PATH"
  set_loop_phase "$PATH_STATE" "e2e-testing" "$E2E_PATH"
  set_workflow_result "$PATH_STATE" "$SHIP_PATH" "shipped" "" "complete"
)
assert_eq "child paths nest beneath components" \
  '["components","e2e_verify","components","ship"]' \
  "$(source "$LOOP_LIB"; child_workflow_path '["components","e2e_verify"]' ship)"
assert_eq "path helpers mutate only named subtrees" "true" "$(jq -r '
  .phase == "implementing" and
  .components.e2e_verify.phase == "e2e-testing" and
  .components.e2e_verify.pr_number == "42" and
  .components.e2e_verify.pages_tested == 3 and
  .components.e2e_verify.required == true and
  .components.e2e_verify.components.ship == {result:"shipped",reason:"",phase:"complete",components:{}} and
  (.components.e2e_verify.components.ship | has("transient") | not) and
  (.pr_number == null)
' "$PATH_STATE")"

JSON_BEFORE=$(jq -cS . "$PATH_STATE")
set +e
JSON_ERROR=$( (
  cd "$PATH_DIR"
  source "$LOOP_LIB"
  set_loop_json_field "$PATH_STATE" "invalid" '{not-json}' '["components","e2e_verify"]'
  ) 2>&1 )
JSON_STATUS=$?
set -e
assert_eq "invalid JSON field value is rejected" "true" \
  "$([ "$JSON_STATUS" -ne 0 ] && printf '%s\n' "$JSON_ERROR" | grep -Fq 'valid JSON' && echo true || echo false)"
assert_eq "invalid JSON update leaves state unchanged" "$JSON_BEFORE" "$(jq -cS . "$PATH_STATE")"

ROOT_RESULT_DIR=$(fixture root-result)
ROOT_RESULT_STATE="$ROOT_RESULT_DIR/.local/state/ship.loop.local.json"
(
  cd "$ROOT_RESULT_DIR"
  run_setup "ship" "SHIPPED" 50 "pushing" '{}' "" \
    '["SHIPPED","INCOMPLETE"]' >/dev/null
  source "$LOOP_LIB"
  set_workflow_result "$ROOT_RESULT_STATE" '[]' "incomplete" "ci-failed" "incomplete"
)
assert_eq "root workflow result preserves released outcome fields" "true" "$(jq -r '
  .result == "incomplete" and
  .reason == "ci-failed" and
  .workflow_result == "incomplete" and
  .workflow_reason == "ci-failed" and
  .phase == "incomplete"
' "$ROOT_RESULT_STATE")"

STRING_SCHEMA_DIR=$(fixture string-schema)
STRING_SCHEMA_STATE="$STRING_SCHEMA_DIR/.local/state/custom.loop.local.json"
printf '%s\n' '{"schema_version":"2","owner_workflow":"custom","loop_name":"custom","iteration":1,"completion_promise":"DONE","terminal_promises":["DONE"],"components":{},"phase":"work"}' > "$STRING_SCHEMA_STATE"
set +e
STRING_SCHEMA_ERROR=$( (
  cd "$STRING_SCHEMA_DIR"
  source "$LOOP_LIB"
  read_loop_state "$STRING_SCHEMA_STATE" '[]'
  ) 2>&1 )
STRING_SCHEMA_STATUS=$?
set -e
assert_eq "string schema version is rejected" "true" \
  "$([ "$STRING_SCHEMA_STATUS" -ne 0 ] && printf '%s\n' "$STRING_SCHEMA_ERROR" | grep -Fq 'Unsupported' && echo true || echo false)"

TERMINAL_DIR=$(fixture terminal-result)
TERMINAL_STATE="$TERMINAL_DIR/.local/state/e2e-verify-42.loop.local.json"
(
  cd "$TERMINAL_DIR"
  run_setup "e2e-verify-42" "VERIFIED" 30 "e2e-testing" '{}' "" \
    '["VERIFIED","E2E_FAIL","INCOMPLETE"]' >/dev/null
)
for E2E_FAILURE_STATE in \
  fail \
  partial \
  skipped-server-failed \
  missing-browser-tooling \
  uninspected-screenshots; do
  (
    cd "$TERMINAL_DIR"
    source "$LOOP_LIB"
    set_loop_completion_promise "$TERMINAL_STATE" "VERIFIED"
    set_loop_terminal_result "$TERMINAL_STATE" "e2e-fail" "$E2E_FAILURE_STATE" "e2e-failed" "E2E_FAIL"
  )
  assert_eq "terminal result persists $E2E_FAILURE_STATE atomically" "true" "$(jq -r --arg reason "$E2E_FAILURE_STATE" '
    .result == "e2e-fail" and
    .reason == $reason and
    .workflow_result == "e2e-fail" and
    .workflow_reason == $reason and
    .phase == "e2e-failed" and
    .completion_promise == "E2E_FAIL"
  ' "$TERMINAL_STATE")"
done
TERMINAL_BEFORE=$(jq -cS . "$TERMINAL_STATE")
set +e
TERMINAL_ERROR=$( (
  cd "$TERMINAL_DIR"
  source "$LOOP_LIB"
  set_loop_terminal_result "$TERMINAL_STATE" "bad" "foreign" "bad" "FOREIGN"
  ) 2>&1 )
TERMINAL_STATUS=$?
set -e
assert_eq "terminal result rejects foreign promise" "true" \
  "$([ "$TERMINAL_STATUS" -ne 0 ] && printf '%s\n' "$TERMINAL_ERROR" | grep -Fq 'FOREIGN' && echo true || echo false)"
assert_eq "foreign terminal result leaves state unchanged" "$TERMINAL_BEFORE" \
  "$(jq -cS . "$TERMINAL_STATE")"

(
  cd "$PATH_DIR"
  source "$LOOP_LIB"
  set_loop_completion_promise "$PATH_STATE" "INCOMPLETE"
)
assert_eq "allowlisted terminal setter updates active promise" "INCOMPLETE" \
  "$(jq -r '.completion_promise' "$PATH_STATE")"
PROMISE_BEFORE=$(jq -cS . "$PATH_STATE")
set +e
PROMISE_ERROR=$( (
  cd "$PATH_DIR"
  source "$LOOP_LIB"
  set_loop_completion_promise "$PATH_STATE" "FOREIGN"
  ) 2>&1 )
PROMISE_STATUS=$?
set -e
assert_eq "foreign terminal promise is rejected" "true" \
  "$([ "$PROMISE_STATUS" -ne 0 ] && printf '%s\n' "$PROMISE_ERROR" | grep -Fq 'FOREIGN' && echo true || echo false)"
assert_eq "foreign terminal mutation leaves state unchanged" "$PROMISE_BEFORE" "$(jq -cS . "$PATH_STATE")"
set +e
ALLOWLIST_ERROR=$( (
  cd "$PATH_DIR"
  source "$LOOP_LIB"
  set_loop_json_field "$PATH_STATE" "terminal_promises" '["FOREIGN"]' '[]'
  ) 2>&1 )
ALLOWLIST_STATUS=$?
set -e
assert_eq "generic field helper cannot mutate terminal allowlist" "true" \
  "$([ "$ALLOWLIST_STATUS" -ne 0 ] && printf '%s\n' "$ALLOWLIST_ERROR" | grep -Fq 'dedicated helper' && echo true || echo false)"
assert_eq "terminal allowlist remains immutable" "$PROMISE_BEFORE" "$(jq -cS . "$PATH_STATE")"

# --- Debug log: off by default, never inside the user's repository ---
DEBUG_PROBE_DIR=$(mktemp -d "$LOOP_TMP_BASE/gopher-ai-loop-debug.XXXXXX")
(
  cd "$DEBUG_PROBE_DIR"
  # shellcheck source=/dev/null
  . "$LOOP_LIB"
  unset GO_WORKFLOW_DEBUG
  loop_log "quiet by default"
)
assert_eq "no debug log without GO_WORKFLOW_DEBUG" "0" \
  "$(find "$DEBUG_PROBE_DIR" -name 'loop-debug.log' 2>/dev/null | wc -l | tr -d ' ')"

DEBUG_PROBE_LOG="$DEBUG_PROBE_DIR/explicit/loop-debug.log"
(
  cd "$DEBUG_PROBE_DIR"
  # shellcheck source=/dev/null
  . "$LOOP_LIB"
  GO_WORKFLOW_DEBUG=1 LOOP_DEBUG_LOG="$DEBUG_PROBE_LOG" loop_log "noisy on request"
)
assert_eq "GO_WORKFLOW_DEBUG=1 logs to LOOP_DEBUG_LOG" "true" \
  "$([ -s "$DEBUG_PROBE_LOG" ] && echo true || echo false)"
assert_eq "logging on request still writes nothing else into the cwd" "1" \
  "$(find "$DEBUG_PROBE_DIR" -name 'loop-debug.log' 2>/dev/null | wc -l | tr -d ' ')"
rm -rf "$DEBUG_PROBE_DIR"
echo ""

echo "==========================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "TESTS FAILED"
  exit 1
fi
echo "ALL TESTS PASSED"
