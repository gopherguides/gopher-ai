# Complete Issue — Loop State Plumbing

Loaded by `SKILL.md` "Loop Initialization & Re-entry". Resolve the original
repository root before the start-issue transition and keep one absolute state
path for the entire workflow.

## Bootstrap Block

```bash
CURRENT_CHECKOUT_ROOT=$(git rev-parse --show-toplevel)
ORIGINAL_REPO_ROOT=$(git -C "$CURRENT_CHECKOUT_ROOT" worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print; exit}')
if [ -z "$ORIGINAL_REPO_ROOT" ] || [ "${ORIGINAL_REPO_ROOT#/}" = "$ORIGINAL_REPO_ROOT" ] || [ ! -d "$ORIGINAL_REPO_ROOT" ]; then
  echo "ERROR: Could not resolve the absolute original repository root."
  exit 1
fi
STATE_FILE="$ORIGINAL_REPO_ROOT/.local/state/complete-issue-${ISSUE_NUM}.loop.local.json"
REPO_SLUG=$(cd "$CURRENT_CHECKOUT_ROOT" && gh api "repos/{owner}/{repo}" --jq '.full_name')
if [ -f "$STATE_FILE" ] && [ -n "$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null)" ]; then
  echo "Re-entry detected — skipping setup-loop."
else
  "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "complete-issue-${ISSUE_NUM}" "COMPLETE" 100 "" \
    '{"implementing":"Resume start-issue implementation.","reviewing":"The prior in-session review is void; continue to E2E verification and shipping without restarting it.","verifying":"Resume E2E verification and shipping.","incomplete":"Report the persisted incomplete reason, emit the INCOMPLETE terminal marker, and stop without entering Phase 3."}' \
    "$STATE_FILE"
fi
```

## Persist Arguments Block

```bash
TMP="${STATE_FILE}.tmp"
jq --arg issue_num "$ISSUE_NUM" --arg flags "$FLAGS" --arg pr_number "" \
   --arg original_repo_root "$ORIGINAL_REPO_ROOT" --arg repo_slug "$REPO_SLUG" \
   '. + {issue_num: $issue_num, flags: $flags, pr_number: $pr_number, original_repo_root: $original_repo_root, repo_slug: $repo_slug}' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## Re-entry Check

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
if [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE"
  WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$STATE_FILE")
  REPO_SLUG=$(jq -r '.repo_slug // empty' "$STATE_FILE")
  PERSISTED_ORIGINAL_REPO_ROOT=$(jq -r '.original_repo_root // empty' "$STATE_FILE")
fi

if [ -n "$PHASE" ] && [ "$PHASE" != "implementing" ] && [ "$PHASE" != "incomplete" ]; then
  REGISTERED_WORKTREES=$(git -C "$ORIGINAL_REPO_ROOT" worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print}')
  if [ "$PERSISTED_ORIGINAL_REPO_ROOT" != "$ORIGINAL_REPO_ROOT" ] ||
     [ -z "$WORKTREE_PATH" ] ||
     [ "${WORKTREE_PATH#/}" = "$WORKTREE_PATH" ] ||
     [ ! -d "$WORKTREE_PATH" ] ||
     ! printf '%s\n' "$REGISTERED_WORKTREES" | awk -v expected="$WORKTREE_PATH" '$0 == expected {found=1} END {exit found ? 0 : 1}'; then
    WORKFLOW_REASON=start-issue-worktree-path-invalid
    TMP="${STATE_FILE}.tmp"
    jq --arg reason "$WORKFLOW_REASON" \
      '.workflow_result = "incomplete" | .workflow_reason = $reason | .phase = "incomplete" | .completion_promise = "INCOMPLETE"' \
      "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
    echo "WORKFLOW_RESULT=INCOMPLETE"
    echo "WORKFLOW_REASON=$WORKFLOW_REASON"
    echo "<done>INCOMPLETE</done>"
    exit 1
  fi
fi
```

If `PHASE` is set, recover state and skip to the corresponding phase listed in
the SKILL.md phase routing table. A persisted `reviewing` phase never resumes
the prior review; continue to Phase 3. A persisted `incomplete` phase reports
its reason and terminates without entering Phase 3. If `PHASE` is empty,
continue to Phase 1.
