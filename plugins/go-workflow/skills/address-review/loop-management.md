# Loop Initialization & Re-entry Check

## Loop Initialization

```bash
SAFE_LOOP_NAME=$(echo "address-review-${RESOLVED_PR:-auto}" | sed 's/[^a-zA-Z0-9_-]/-/g')
LOOP_STATE_FILE="${STATE_FILE:-$ORIGINAL_REPO_ROOT/.local/state/${SAFE_LOOP_NAME}.loop.local.json}"
if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
  echo "Embedded address-review is using the caller-owned loop state."
elif [ -f "$LOOP_STATE_FILE" ] && [ -n "$(jq -r '.phase // empty' "$LOOP_STATE_FILE" 2>/dev/null)" ]; then
  echo "Re-entry detected — skipping setup-loop."
else
  /bin/bash "<PLUGIN_ROOT>/scripts/setup-loop.sh" "address-review-${RESOLVED_PR:-auto}" "COMPLETE" "" "" '{}' \
    "$LOOP_STATE_FILE" '["COMPLETE","INCOMPLETE"]'
fi
initialize_workflow_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
if [ "$EMBEDDED_WORKFLOW" != "true" ]; then
  if [ -z "$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')" ]; then
    set_loop_field "$STATE_FILE" "original_repo_root" "$ORIGINAL_REPO_ROOT" '[]'
  fi
  if [ -z "$(get_loop_field "$STATE_FILE" "worktree_path" '[]')" ]; then
    set_loop_field "$STATE_FILE" "worktree_path" "$WORKTREE_PATH" '[]'
  fi
  if [ -z "$(get_loop_field "$STATE_FILE" "repo_slug" '[]')" ]; then
    set_loop_field "$STATE_FILE" "repo_slug" "$REPO_SLUG" '[]'
  fi
fi
```

## Re-entry Check

Check if resuming from a previous watching phase:

```bash
CURRENT_PHASE=""
if [ -f "$LOOP_STATE_FILE" ]; then
  source "<PLUGIN_ROOT>/lib/loop-state.sh"
  read_loop_state "$LOOP_STATE_FILE" "$WORKFLOW_STATE_PATH"
  CURRENT_PHASE="$PHASE"
fi

if [ "$EMBEDDED_WORKFLOW" = "true" ] || [ -n "$CURRENT_PHASE" ]; then
  PERSISTED_ORIGINAL_REPO_ROOT=$(get_loop_field "$LOOP_STATE_FILE" "original_repo_root" '[]')
  PERSISTED_WORKTREE_PATH=$(get_loop_field "$LOOP_STATE_FILE" "worktree_path" '[]')
  PERSISTED_REPO_SLUG=$(get_loop_field "$LOOP_STATE_FILE" "repo_slug" '[]')
  REGISTERED_WORKTREES=$(git -C "$RESOLVED_ORIGINAL_REPO_ROOT" worktree list --porcelain | awk '/^worktree / { sub(/^worktree /, ""); print }')
  if [ "$PERSISTED_ORIGINAL_REPO_ROOT" != "$RESOLVED_ORIGINAL_REPO_ROOT" ] ||
     [ -z "$PERSISTED_WORKTREE_PATH" ] ||
     [ "${PERSISTED_WORKTREE_PATH#/}" = "$PERSISTED_WORKTREE_PATH" ] ||
     [ ! -d "$PERSISTED_WORKTREE_PATH" ] ||
     ! printf '%s\n' "$REGISTERED_WORKTREES" | awk -v path="$PERSISTED_WORKTREE_PATH" '$0 == path { found = 1 } END { exit !found }' ||
     [ -z "$PERSISTED_REPO_SLUG" ] ||
     [ "$PERSISTED_REPO_SLUG" != "$CURRENT_REPO_SLUG" ]; then
    WORKFLOW_REASON=address-review-worktree-path-invalid
    if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
      set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "incomplete" "$WORKFLOW_REASON" "incomplete"
      echo "ADDRESS_REVIEW_RESULT=incomplete"
      echo "ADDRESS_REVIEW_REASON=$WORKFLOW_REASON"
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
echo "Current phase: ${CURRENT_PHASE:-<none>}"
```

**If `CURRENT_PHASE` is `watching` AND `WATCH_MODE` is `true`:** Fix cycle already completed. Restore `BOT_REVIEW_BASELINE` from state file:

```bash
BOT_REVIEW_BASELINE=""
if [ -f "$LOOP_STATE_FILE" ]; then
  BOT_REVIEW_BASELINE=$(get_loop_field "$LOOP_STATE_FILE" "bot_review_baseline" "$WORKFLOW_STATE_PATH")
fi
if [ -z "$BOT_REVIEW_BASELINE" ]; then
  BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "Bot review baseline (fallback): $BOT_REVIEW_BASELINE"
  if [ -f "$LOOP_STATE_FILE" ]; then
    set_loop_field "$LOOP_STATE_FILE" "bot_review_baseline" "$BOT_REVIEW_BASELINE" "$WORKFLOW_STATE_PATH"
  fi
else
  echo "Bot review baseline (restored): $BOT_REVIEW_BASELINE"
fi
```

Do NOT re-run the fix cycle. Skip to watch loop (read `watch-loop.md`).

**If `CURRENT_PHASE` is `watching` AND `WATCH_MODE` is `false`:** Clear stale phase:

```bash
if [ -f "$LOOP_STATE_FILE" ]; then
  set_loop_phase "$LOOP_STATE_FILE" "" "$WORKFLOW_STATE_PATH"
  echo "Phase cleared (--no-watch mode)"
fi
```

Continue with full fix cycle. **Otherwise:** Continue normally.
