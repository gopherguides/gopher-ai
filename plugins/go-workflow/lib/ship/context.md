# Ship Context Discovery

Loaded by `skills/ship/SKILL.md` Step 3. Execute the complete procedure before prerequisite checks or local review.

## 3. Detect Context

```bash
CURRENT_BRANCH=$(git -C "$WORKTREE_PATH" branch --show-current)
LOCAL_HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD)

if PR_JSON=$(cd "$WORKTREE_PATH" && github_current_pr "$CURRENT_BRANCH" "$LOCAL_HEAD_SHA"); then
  PR_NUM=$(echo "$PR_JSON" | jq -r '.number')
  BASE_BRANCH=$(echo "$PR_JSON" | jq -r '.base.ref')
  echo "PR #$PR_NUM targets: $BASE_BRANCH"
else
  PR_LOOKUP_STATUS=$?
  if [ "$PR_LOOKUP_STATUS" -ne 4 ]; then
    WORKFLOW_REASON="current-pr-api-error"
  fi
  BASE_BRANCH=$(gh api "repos/$REPO_SLUG" --jq '.default_branch')
  PR_NUM=""
  echo "No PR found. Base: $BASE_BRANCH"
fi
```

An empty exact-head lookup returns status 4 and means no PR exists yet. Any
other lookup failure sets `WORKFLOW_REASON=current-pr-api-error`; follow
**Hard Invariant Failure** and stop rather than treating an API failure as no
PR.

**CRITICAL:** If `CURRENT_BRANCH == BASE_BRANCH`, set
`WORKFLOW_REASON=default-branch`, follow **Hard Invariant Failure**, and stop.
Do not ship from the default branch.

If `git -C "$WORKTREE_PATH" status --porcelain` shows uncommitted changes, resolve a
**driver-resolvable gate**. Inspect the diff, staged state, original request,
and workflow-owned file list:

- Include and commit changes only when they are unambiguously in scope and have
  fresh validation evidence.
- Preserve unrelated changes and ship only committed `HEAD` when later steps
  cannot overwrite or stage them.
- If ownership is ambiguous or safe isolation is impossible, stop incomplete
  with `WORKFLOW_REASON=unowned-worktree-changes`.

State `Decision`, `Evidence`, and `Rationale`; do not request input for this
technical ownership decision.

Persist the detected context in the resolved ship workflow object:

```bash
set_loop_field "$STATE_FILE" "base_branch" "$BASE_BRANCH" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "pr_number" "$PR_NUM" "$WORKFLOW_STATE_PATH"
```
