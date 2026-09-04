# Complete Issue — Loop State Plumbing

Loaded by `SKILL.md` "Loop Initialization & Re-entry". Complete-issue owns the
one physical loop state file for the full composed run. Its path is normalized
once under `ORIGINAL_REPO_ROOT` and remains unchanged if start-issue creates or
selects a worktree.

An unversioned complete-issue state from the released multi-loop model cannot
identify which separate child state it owned. Re-entry fails closed without
mutating that file and directs the user to cancel and restart complete-issue;
it never invents empty component state or repeats nested work silently.

## Bootstrap Block

```bash
CURRENT_CHECKOUT_ROOT=$(git rev-parse --show-toplevel)
ORIGINAL_REPO_ROOT=$(git -C "$CURRENT_CHECKOUT_ROOT" worktree list --porcelain | awk '/^worktree / { sub(/^worktree /, ""); print; exit }')
if [ -z "$ORIGINAL_REPO_ROOT" ] || [ "${ORIGINAL_REPO_ROOT#/}" = "$ORIGINAL_REPO_ROOT" ] || [ ! -d "$ORIGINAL_REPO_ROOT" ]; then
  echo "Error: Could not resolve the absolute primary worktree root."
  exit 1
fi
REPO_SLUG=$(cd "$CURRENT_CHECKOUT_ROOT" && gh api "repos/{owner}/{repo}" --jq '.full_name')
STATE_FILE="$ORIGINAL_REPO_ROOT/.local/state/complete-issue-${ISSUE_NUM}.loop.local.json"
mkdir -p "$(dirname "$STATE_FILE")"
STATE_FILE=$(cd "$(dirname "$STATE_FILE")" && pwd)/$(basename "$STATE_FILE")
WORKFLOW_STATE_PATH='[]'
if [ -f "$STATE_FILE" ] && [ -n "$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null)" ]; then
  echo "Re-entry detected — skipping setup-loop."
else
  /bin/bash "<PLUGIN_ROOT>/scripts/setup-loop.sh" "complete-issue-${ISSUE_NUM}" "COMPLETE" 100 "" \
    '{"implementing":"Resume start-issue implementation from its component phase.","reviewing":"The prior in-session review is void; continue to E2E verification and shipping without restarting it.","verifying":"Resume E2E verification and shipping from the active component phase.","incomplete":"Report the persisted incomplete reason, emit the INCOMPLETE terminal marker, and stop without entering Phase 3."}' \
    "$STATE_FILE" '["COMPLETE","INCOMPLETE"]'
fi
```

## Persist Arguments Block

```bash
source "<PLUGIN_ROOT>/lib/loop-state.sh"
initialize_workflow_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "issue_num" "$ISSUE_NUM" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "flags" "$FLAGS" "$WORKFLOW_STATE_PATH"
if [ -z "$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')" ]; then
  set_loop_field "$STATE_FILE" "original_repo_root" "$ORIGINAL_REPO_ROOT" '[]'
fi
if [ -z "$(get_loop_field "$STATE_FILE" "worktree_path" '[]')" ]; then
  set_loop_field "$STATE_FILE" "worktree_path" "$CURRENT_CHECKOUT_ROOT" '[]'
fi
if [ -z "$(get_loop_field "$STATE_FILE" "repo_slug" '[]')" ]; then
  set_loop_field "$STATE_FILE" "repo_slug" "$REPO_SLUG" '[]'
fi
if [ -z "$(get_loop_field "$STATE_FILE" "pr_number" "$WORKFLOW_STATE_PATH")" ]; then
  set_loop_field "$STATE_FILE" "pr_number" "" "$WORKFLOW_STATE_PATH"
fi
```

## Re-entry Check

```bash
source "<PLUGIN_ROOT>/lib/loop-state.sh"
if [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
  WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" '[]')
  PERSISTED_REPO_SLUG=$(get_loop_field "$STATE_FILE" "repo_slug" '[]')
  PERSISTED_ORIGINAL_REPO_ROOT=$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')
fi

if [ -n "$PHASE" ] && [ "$PHASE" != "implementing" ] && [ "$PHASE" != "incomplete" ]; then
  REGISTERED_WORKTREES=$(git -C "$ORIGINAL_REPO_ROOT" worktree list --porcelain | awk '/^worktree / { sub(/^worktree /, ""); print }')
  if [ "$PERSISTED_ORIGINAL_REPO_ROOT" != "$ORIGINAL_REPO_ROOT" ] ||
     [ -z "$WORKTREE_PATH" ] ||
     [ "${WORKTREE_PATH#/}" = "$WORKTREE_PATH" ] ||
     [ ! -d "$WORKTREE_PATH" ] ||
     ! printf '%s\n' "$REGISTERED_WORKTREES" | awk -v expected="$WORKTREE_PATH" '$0 == expected { found = 1 } END { exit found ? 0 : 1 }' ||
     [ -z "$PERSISTED_REPO_SLUG" ] ||
     [ "$PERSISTED_REPO_SLUG" != "$REPO_SLUG" ]; then
    WORKFLOW_REASON=start-issue-worktree-path-invalid
    set_loop_terminal_result "$STATE_FILE" "incomplete" "$WORKFLOW_REASON" "incomplete" "INCOMPLETE"
    echo "WORKFLOW_RESULT=INCOMPLETE"
    echo "WORKFLOW_REASON=$WORKFLOW_REASON"
    echo "<done>INCOMPLETE</done>"
    exit 1
  fi
  REPO_SLUG="$PERSISTED_REPO_SLUG"
fi
```

If `PHASE` is `implementing`, read the start-issue component phase before
resuming Phase 1. If it is `verifying`, read the E2E component phase before
resuming Phase 3. A persisted `reviewing` phase never resumes the prior review;
continue to Phase 3. A persisted `incomplete` phase reports its reason and
terminates without entering Phase 3. If `PHASE` is empty, continue to Phase 1.
