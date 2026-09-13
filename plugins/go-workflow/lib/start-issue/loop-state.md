# Start-Issue Durable Loop State

Loaded by `skills/start-issue/SKILL.md` after argument parsing. It owns standalone/embedded state initialization and terminal result mechanics.

## Embedded Workflow Contract

Start-issue is embedded only when both caller variables are explicitly set.
Never infer composition from a generic inherited `STATE_FILE`:

```bash
EMBEDDED_WORKFLOW=false
source "<PLUGIN_ROOT>/lib/loop-state.sh"
CURRENT_CHECKOUT_ROOT=$(git rev-parse --show-toplevel)
RESOLVED_ORIGINAL_REPO_ROOT=$(git -C "$CURRENT_CHECKOUT_ROOT" worktree list --porcelain | awk '/^worktree / { sub(/^worktree /, ""); print; exit }')
if [ -z "$RESOLVED_ORIGINAL_REPO_ROOT" ] || [ "${RESOLVED_ORIGINAL_REPO_ROOT#/}" = "$RESOLVED_ORIGINAL_REPO_ROOT" ] || [ ! -d "$RESOLVED_ORIGINAL_REPO_ROOT" ]; then
  echo "Error: Could not resolve the absolute primary worktree root."
  exit 1
fi
if [ -n "${CALLER_LOOP_STATE_FILE:-}" ] && [ -n "${CALLER_WORKFLOW_STATE_PATH:-}" ]; then
  EMBEDDED_WORKFLOW=true
  STATE_FILE="$CALLER_LOOP_STATE_FILE"
  WORKFLOW_STATE_PATH=$(child_workflow_path "$CALLER_WORKFLOW_STATE_PATH" "start_issue")
  initialize_workflow_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
  ORIGINAL_REPO_ROOT=$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')
  WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" '[]')
  REPO_SLUG=$(get_loop_field "$STATE_FILE" "repo_slug" '[]')
elif [ -n "${CALLER_LOOP_STATE_FILE:-}" ] || [ -n "${CALLER_WORKFLOW_STATE_PATH:-}" ]; then
  echo "Error: Embedded start-issue requires both caller state variables."
  exit 1
else
  ORIGINAL_REPO_ROOT="$RESOLVED_ORIGINAL_REPO_ROOT"
  STATE_FILE="$ORIGINAL_REPO_ROOT/.local/state/start-issue-$ISSUE_NUM.loop.local.json"
  mkdir -p "$(dirname "$STATE_FILE")"
  STATE_FILE=$(cd "$(dirname "$STATE_FILE")" && pwd)/$(basename "$STATE_FILE")
  WORKFLOW_STATE_PATH='[]'
  WORKTREE_PATH="$CURRENT_CHECKOUT_ROOT"
  REPO_SLUG=$(cd "$CURRENT_CHECKOUT_ROOT" && gh api "repos/{owner}/{repo}" --jq '.full_name')
fi
```
When embedded, every phase and field operation uses `STATE_FILE` plus
`WORKFLOW_STATE_PATH`. Start-issue never changes the root completion promise or
terminal allowlist, never initializes another loop, and returns only through
`set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" RESULT REASON PHASE`.

## Loop Initialization

```bash
EXISTING_PHASE=""
if [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
  EXISTING_PHASE="$PHASE"
fi

if [ "$EMBEDDED_WORKFLOW" = "true" ] || [ -n "$EXISTING_PHASE" ]; then
  PERSISTED_ORIGINAL_REPO_ROOT=$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')
  PERSISTED_WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" '[]')
  PERSISTED_REPO_SLUG=$(get_loop_field "$STATE_FILE" "repo_slug" '[]')
  CURRENT_REPO_SLUG=$(cd "$CURRENT_CHECKOUT_ROOT" && gh api "repos/{owner}/{repo}" --jq '.full_name')
  REGISTERED_WORKTREES=$(git -C "$RESOLVED_ORIGINAL_REPO_ROOT" worktree list --porcelain | awk '/^worktree / { sub(/^worktree /, ""); print }')
  if [ "$PERSISTED_ORIGINAL_REPO_ROOT" != "$RESOLVED_ORIGINAL_REPO_ROOT" ] ||
     [ -z "$PERSISTED_WORKTREE_PATH" ] ||
     [ "${PERSISTED_WORKTREE_PATH#/}" = "$PERSISTED_WORKTREE_PATH" ] ||
     [ ! -d "$PERSISTED_WORKTREE_PATH" ] ||
     ! printf '%s\n' "$REGISTERED_WORKTREES" | awk -v path="$PERSISTED_WORKTREE_PATH" '$0 == path { found = 1 } END { exit found ? 0 : 1 }' ||
     [ -z "$PERSISTED_REPO_SLUG" ] ||
     [ "$PERSISTED_REPO_SLUG" != "$CURRENT_REPO_SLUG" ]; then
    WORKFLOW_REASON=start-issue-worktree-path-invalid
    if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
      set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "incomplete" "$WORKFLOW_REASON" "incomplete"
      echo "START_ISSUE_RESULT=incomplete"
      echo "START_ISSUE_REASON=$WORKFLOW_REASON"
    else
      set_loop_terminal_result "$STATE_FILE" "incomplete" "$WORKFLOW_REASON" "incomplete" "INCOMPLETE"
      echo "<done>INCOMPLETE</done>"
    fi
    exit 1
  fi
  ORIGINAL_REPO_ROOT="$PERSISTED_ORIGINAL_REPO_ROOT"
  WORKTREE_PATH="$PERSISTED_WORKTREE_PATH"
  REPO_SLUG="$PERSISTED_REPO_SLUG"
fi

if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
  echo "Embedded start-issue is using the caller-owned loop state."
elif [ -n "$EXISTING_PHASE" ]; then
  echo "Re-entry detected (phase: $EXISTING_PHASE) — skipping setup-loop."
elif [ ! -x "<PLUGIN_ROOT>/scripts/setup-loop.sh" ]; then
  echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."
  exit 1
else
  /bin/bash "<PLUGIN_ROOT>/scripts/setup-loop.sh" "start-issue-$ISSUE_NUM" "COMPLETE" "" "" '{}' \
    "$STATE_FILE" '["COMPLETE","INCOMPLETE"]'
  initialize_workflow_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "original_repo_root" "$ORIGINAL_REPO_ROOT" '[]'
  set_loop_field "$STATE_FILE" "worktree_path" "$WORKTREE_PATH" '[]'
  set_loop_field "$STATE_FILE" "repo_slug" "$REPO_SLUG" '[]'
fi
```

`ORIGINAL_REPO_ROOT`, `WORKTREE_PATH`, `STATE_FILE`, and `REPO_SLUG` are
resolved once before any worktree transition. Do not derive them again from
the ambient shell directory.

## Workflow Result Contract

Every terminal path persists a result before it returns. For an incomplete
outcome, use the supplied machine-readable reason:

```bash
START_ISSUE_REASON="${WORKFLOW_REASON:?workflow reason is required}"
if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
  set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "incomplete" "$START_ISSUE_REASON" "incomplete"
  echo "START_ISSUE_RESULT=incomplete"
  echo "START_ISSUE_REASON=$START_ISSUE_REASON"
else
  set_loop_terminal_result "$STATE_FILE" "incomplete" "$START_ISSUE_REASON" "incomplete" "INCOMPLETE"
  echo "<done>INCOMPLETE</done>"
fi
```

Stop after this block. The embedded branch returns control to its caller and
does not emit a terminal marker.

## Successful Result

When every completion criterion in the router is satisfied:

```bash
if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
  set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "complete" "" "completed"
  echo "START_ISSUE_RESULT=complete"
else
  set_loop_terminal_result "$STATE_FILE" "complete" "" "completed" "COMPLETE"
  echo "<done>COMPLETE</done>"
fi
```
