# Loop Initialization & Re-entry Check

## Loop Initialization and Re-entry Check

```bash
SAFE_LOOP_NAME=$(echo "address-review-${RESOLVED_PR:-auto}" | sed 's/[^a-zA-Z0-9_-]/-/g')
LOOP_STATE_FILE="${STATE_FILE:-$ORIGINAL_REPO_ROOT/.local/state/${SAFE_LOOP_NAME}.loop.local.json}"
CURRENT_PHASE=""
if [ -f "$LOOP_STATE_FILE" ]; then
  CURRENT_PHASE=$(jq -r '.phase // empty' "$LOOP_STATE_FILE" 2>/dev/null || true)
fi

if [ -n "$CURRENT_PHASE" ]; then
  PERSISTED_ORIGINAL_REPO_ROOT=$(jq -r '.original_repo_root // empty' "$LOOP_STATE_FILE" 2>/dev/null || true)
  PERSISTED_WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$LOOP_STATE_FILE" 2>/dev/null || true)
  PERSISTED_REPO_SLUG=$(jq -r '.repo_slug // empty' "$LOOP_STATE_FILE" 2>/dev/null || true)
  REGISTERED_WORKTREES=$(git -C "$ORIGINAL_REPO_ROOT" worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print}')
  if [ "$PERSISTED_ORIGINAL_REPO_ROOT" != "$ORIGINAL_REPO_ROOT" ] ||
     [ -z "$PERSISTED_WORKTREE_PATH" ] ||
     [ "${PERSISTED_WORKTREE_PATH#/}" = "$PERSISTED_WORKTREE_PATH" ] ||
     [ ! -d "$PERSISTED_WORKTREE_PATH" ] ||
     ! printf '%s\n' "$REGISTERED_WORKTREES" | awk -v path="$PERSISTED_WORKTREE_PATH" '$0 == path { found = 1 } END { exit !found }' ||
     [ "$PERSISTED_REPO_SLUG" != "$CURRENT_REPO_SLUG" ]; then
    TMP="${LOOP_STATE_FILE}.tmp"
    jq '.workflow_result = "incomplete" | .workflow_reason = "address-review-worktree-path-invalid" | .phase = "incomplete" | .completion_promise = "INCOMPLETE"' "$LOOP_STATE_FILE" > "$TMP" && mv "$TMP" "$LOOP_STATE_FILE"
    echo "WORKFLOW_RESULT=INCOMPLETE"
    echo "WORKFLOW_REASON=address-review-worktree-path-invalid"
    echo "<done>INCOMPLETE</done>"
    exit 1
  fi
  WORKTREE_PATH="$PERSISTED_WORKTREE_PATH"
  REPO_SLUG="$PERSISTED_REPO_SLUG"
else
  "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "address-review-${RESOLVED_PR:-auto}" "COMPLETE" "" "" '{}' "$LOOP_STATE_FILE"
  TMP="${LOOP_STATE_FILE}.tmp"
  jq --arg original_repo_root "$ORIGINAL_REPO_ROOT" --arg worktree_path "$WORKTREE_PATH" --arg repo_slug "$REPO_SLUG" \
    '. + {original_repo_root: $original_repo_root, worktree_path: $worktree_path, repo_slug: $repo_slug}' \
    "$LOOP_STATE_FILE" > "$TMP" && mv "$TMP" "$LOOP_STATE_FILE"
fi
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
echo "Current phase: ${CURRENT_PHASE:-<none>}"
```

**If `CURRENT_PHASE` is `watching` AND `WATCH_MODE` is `true`:** Fix cycle already completed. Restore `BOT_REVIEW_BASELINE` from state file:

```bash
BOT_REVIEW_BASELINE=""
if [ -f "$LOOP_STATE_FILE" ]; then
  BOT_REVIEW_BASELINE=$(jq -r '.bot_review_baseline // empty' "$LOOP_STATE_FILE" 2>/dev/null || true)
fi
if [ -z "$BOT_REVIEW_BASELINE" ]; then
  BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "Bot review baseline (fallback): $BOT_REVIEW_BASELINE"
  if [ -f "$LOOP_STATE_FILE" ]; then
    set_loop_field "$LOOP_STATE_FILE" "bot_review_baseline" "$BOT_REVIEW_BASELINE"
  fi
else
  echo "Bot review baseline (restored): $BOT_REVIEW_BASELINE"
fi
```

Do NOT re-run the fix cycle. Skip to watch loop (read `watch-loop.md`).

**If `CURRENT_PHASE` is `watching` AND `WATCH_MODE` is `false`:** Clear stale phase:

```bash
if [ -f "$LOOP_STATE_FILE" ]; then
  set_loop_phase "$LOOP_STATE_FILE" ""
  echo "Phase cleared (--no-watch mode)"
fi
```

Continue with full fix cycle. **Otherwise:** Continue normally.
