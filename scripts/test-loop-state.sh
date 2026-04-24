#!/bin/bash
# Test script for JSON-based loop state functions
# Exercises read/write/increment/phase-set on JSON state files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

source shared/lib/loop-state.sh

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

echo "=== Loop State JSON Tests ==="
echo ""

# --- Test 1: setup-loop creates valid JSON ---
echo "Test 1: setup-loop.sh creates valid JSON"
rm -f .local/state/test-loop.loop.local.json
./shared/scripts/setup-loop.sh "test-loop" "TEST_DONE" 10 "init" '{"init":"Start the task.","fixing":"Fix the issues."}' > /dev/null
assert_eq "state file exists" "true" "$([ -f .local/state/test-loop.loop.local.json ] && echo true || echo false)"
assert_eq "valid JSON" "true" "$(jq empty .local/state/test-loop.loop.local.json 2>/dev/null && echo true || echo false)"
assert_eq "loop_name" "test-loop" "$(jq -r '.loop_name' .local/state/test-loop.loop.local.json)"
assert_eq "iteration" "1" "$(jq -r '.iteration' .local/state/test-loop.loop.local.json)"
assert_eq "max_iterations" "10" "$(jq -r '.max_iterations' .local/state/test-loop.loop.local.json)"
assert_eq "completion_promise" "TEST_DONE" "$(jq -r '.completion_promise' .local/state/test-loop.loop.local.json)"
assert_eq "phase" "init" "$(jq -r '.phase' .local/state/test-loop.loop.local.json)"
assert_eq "session_id field exists" "true" "$(jq -e 'has("session_id")' .local/state/test-loop.loop.local.json >/dev/null 2>&1 && echo true || echo false)"
assert_eq "phase_messages.init" "Start the task." "$(jq -r '.phase_messages.init' .local/state/test-loop.loop.local.json)"
assert_eq "phase_messages.fixing" "Fix the issues." "$(jq -r '.phase_messages.fixing' .local/state/test-loop.loop.local.json)"
echo ""

# --- Test 2: read_loop_state ---
echo "Test 2: read_loop_state reads JSON correctly"
read_loop_state ".local/state/test-loop.loop.local.json"
assert_eq "LOOP_NAME" "test-loop" "$LOOP_NAME"
assert_eq "ITERATION" "1" "$ITERATION"
assert_eq "MAX_ITERATIONS" "10" "$MAX_ITERATIONS"
assert_eq "COMPLETION_PROMISE" "TEST_DONE" "$COMPLETION_PROMISE"
assert_eq "PHASE" "init" "$PHASE"
echo ""

# --- Test 3: increment_iteration ---
echo "Test 3: increment_iteration"
increment_iteration ".local/state/test-loop.loop.local.json"
assert_eq "iteration after increment" "2" "$(jq -r '.iteration' .local/state/test-loop.loop.local.json)"
increment_iteration ".local/state/test-loop.loop.local.json"
assert_eq "iteration after 2nd increment" "3" "$(jq -r '.iteration' .local/state/test-loop.loop.local.json)"
echo ""

# --- Test 4: set_loop_phase ---
echo "Test 4: set_loop_phase"
set_loop_phase ".local/state/test-loop.loop.local.json" "fixing"
assert_eq "phase after set" "fixing" "$(jq -r '.phase' .local/state/test-loop.loop.local.json)"
set_loop_phase ".local/state/test-loop.loop.local.json" "watching"
assert_eq "phase after 2nd set" "watching" "$(jq -r '.phase' .local/state/test-loop.loop.local.json)"
echo ""

# --- Test 5: get/set custom fields ---
echo "Test 5: get_loop_field / set_loop_field"
set_loop_field ".local/state/test-loop.loop.local.json" "pr_number" "42"
assert_eq "pr_number set" "42" "$(get_loop_field .local/state/test-loop.loop.local.json pr_number)"
set_loop_field ".local/state/test-loop.loop.local.json" "discovered_bots" "coderabbitai[bot],copilot[bot]"
assert_eq "discovered_bots" "coderabbitai[bot],copilot[bot]" "$(get_loop_field .local/state/test-loop.loop.local.json discovered_bots)"
echo ""

# --- Test 6: find_active_loops ---
echo "Test 6: find_active_loops"
COUNT=$(count_active_loops)
assert_eq "at least 1 active loop" "true" "$([ "$COUNT" -ge 1 ] && echo true || echo false)"
echo ""

# --- Test 7: cleanup_loop ---
echo "Test 7: cleanup_loop"
cleanup_loop ".local/state/test-loop.loop.local.json"
assert_eq "state file removed" "false" "$([ -f .local/state/test-loop.loop.local.json ] && echo true || echo false)"
echo ""

# --- Test 8: cleanup-loop.sh by name ---
echo "Test 8: cleanup-loop.sh specific loop"
./shared/scripts/setup-loop.sh "cleanup-test" "DONE" > /dev/null
assert_eq "created" "true" "$([ -f .local/state/cleanup-test.loop.local.json ] && echo true || echo false)"
./shared/scripts/cleanup-loop.sh "cleanup-test" > /dev/null
assert_eq "removed" "false" "$([ -f .local/state/cleanup-test.loop.local.json ] && echo true || echo false)"
echo ""

# --- Test 9: setup-loop preserves phase on re-init ---
echo "Test 9: setup-loop preserves phase on re-init"
./shared/scripts/setup-loop.sh "reinit-test" "DONE" 5 "initial" > /dev/null
set_loop_phase ".local/state/reinit-test.loop.local.json" "watching"
./shared/scripts/setup-loop.sh "reinit-test" "DONE" 5 "initial" > /dev/null 2>&1
assert_eq "phase preserved" "watching" "$(jq -r '.phase' .local/state/reinit-test.loop.local.json)"
cleanup_loop ".local/state/reinit-test.loop.local.json"
echo ""

# --- Test 10: atomic writes don't corrupt on concurrent access ---
echo "Test 10: no .tmp files left behind"
./shared/scripts/setup-loop.sh "tmp-test" "DONE" > /dev/null
set_loop_phase ".local/state/tmp-test.loop.local.json" "phase1"
increment_iteration ".local/state/tmp-test.loop.local.json"
set_loop_field ".local/state/tmp-test.loop.local.json" "custom" "value"
TMP_COUNT=$(find .local/state -name "*.tmp" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "no tmp files" "0" "$TMP_COUNT"
cleanup_loop ".local/state/tmp-test.loop.local.json"
echo ""

# --- Cleanup debug log ---
rm -f .local/state/loop-debug.log

# --- Summary ---
echo "==========================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "TESTS FAILED"
  exit 1
fi
echo "ALL TESTS PASSED"
