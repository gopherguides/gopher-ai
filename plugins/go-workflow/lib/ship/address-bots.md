# Ship — Phase 5: Address Bot Feedback (Step 12)

Loaded by `skills/ship/SKILL.md` Phase 5.

## 12a. Fetch and rebase against base branch

Before applying fixes, ensure the branch is up to date with the base to avoid conflicts:

```bash
git -C "$WORKTREE_PATH" fetch origin "$BASE_BRANCH"
git -C "$WORKTREE_PATH" rebase "origin/$BASE_BRANCH"
```

Resolve conflicts only when the correct resolution is evident and every
conflict is cleared. If any conflict remains, abort the rebase, then:

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=rebase-conflict
```

Follow the top-level **Hard Invariant Failure** procedure and stop before
applying review fixes.

## 12b. Apply address-review fixes

Pass ship's resolved ownership contract into address-review:

```bash
ADDRESS_REVIEW_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "address_review")
initialize_workflow_state "$STATE_FILE" "$ADDRESS_REVIEW_STATE_PATH"
CALLER_LOOP_STATE_FILE="$STATE_FILE"
CALLER_WORKFLOW_STATE_PATH="$WORKFLOW_STATE_PATH"
```

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/SKILL.md`, execute its argument
resolution and **Embedded Workflow Contract**, then follow **Steps 2–11 only**:

- **Skip Step 1** (loop init / PR checkout) — we're already on the branch; loop is owned by `$go-workflow:ship`
- **Skip Step 12** (bot watch) — `$go-workflow:ship` Step 11 owns that
- Do NOT create a second loop state file — all phases run under the `ship` loop

After address-review returns, clear the caller contract and route its structured
result before continuing:

```bash
WORKFLOW_STATE_PATH="$CALLER_WORKFLOW_STATE_PATH"
unset CALLER_LOOP_STATE_FILE CALLER_WORKFLOW_STATE_PATH
ADDRESS_REVIEW_RESULT=$(get_loop_field "$STATE_FILE" "result" "$ADDRESS_REVIEW_STATE_PATH")
ADDRESS_REVIEW_REASON=$(get_loop_field "$STATE_FILE" "reason" "$ADDRESS_REVIEW_STATE_PATH")
if [ "$ADDRESS_REVIEW_RESULT" != "complete" ]; then
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON="${ADDRESS_REVIEW_REASON:-address-review-incomplete}"
fi
```

If address-review did not return `complete`, follow the top-level **Hard
Invariant Failure** procedure and stop before Step 12c.

## 12c. Capture baseline BEFORE push, HEAD SHA AFTER push

**CRITICAL:** Capture `BOT_REVIEW_BASELINE` BEFORE pushing. Capturing after the push misses fast bot responses that arrive between push and timestamp:

```bash
BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
```

Then push the fixes. After pushing, capture HEAD SHA:

```bash
git -C "$WORKTREE_PATH" push
HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD)
echo "HEAD SHA captured: $HEAD_SHA"
```

Persist both values in the resolved ship workflow object:

```bash
set_loop_field "$STATE_FILE" "bot_review_baseline" "$BOT_REVIEW_BASELINE" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "head_sha" "$HEAD_SHA" "$WORKFLOW_STATE_PATH"
```

Return to Step 10 (ci-watch) — set phase to `ci-watch` and re-watch CI for the new HEAD SHA before checking bot approval again.
