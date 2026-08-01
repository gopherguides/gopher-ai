#!/bin/bash
# Verify hooks.json files are valid and referenced scripts exist
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ERRORS=0

echo "=== Hook Tests ==="

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
  PAUSED_OUTPUT=$(printf '%s\n' '{"transcript_path":""}' | "$ROOT_DIR/plugins/go-workflow/hooks/stop-hook.sh")
  [ -z "$PAUSED_OUTPUT" ]
  jq -e '
    .iteration == 1 and
    .phase == "pushing" and
    .awaiting_driver_input == true and
    .driver_input_reason == "dirty-tree-decision"
  ' "$STOP_HOOK_STATE" >/dev/null
  resume_loop_after_driver "$STOP_HOOK_STATE"
  RESUMED_OUTPUT=$(printf '%s\n' '{"transcript_path":""}' | "$ROOT_DIR/plugins/go-workflow/hooks/stop-hook.sh")
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
