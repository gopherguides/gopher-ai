# Ship Re-entry and Invariant Handling

Loaded by `skills/ship/SKILL.md` after state bootstrap and argument persistence. Execute every applicable section before context discovery.

## Hard Invariant Failure

When this skill or a supporting file says to stop incomplete, set the supplied
reason code as `WORKFLOW_REASON`, then persist the machine-readable outcome:

```bash
WORKFLOW_REASON="${WORKFLOW_REASON:?workflow reason is required}"
if [ "$SHIP_EMBEDDED" = "true" ]; then
  set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "incomplete" "$WORKFLOW_REASON" "incomplete"
  echo "WORKFLOW_RESULT=INCOMPLETE"
  echo "WORKFLOW_REASON=$WORKFLOW_REASON"
else
  set_loop_terminal_result "$STATE_FILE" "incomplete" "$WORKFLOW_REASON" "incomplete" "INCOMPLETE"
  echo "WORKFLOW_RESULT=INCOMPLETE"
  echo "WORKFLOW_REASON=$WORKFLOW_REASON"
  echo "<done>INCOMPLETE</done>"
fi
```

Stop the ship workflow after this block. Embedded ship returns the structured
result to its caller without changing caller-owned terminal fields or emitting
a marker. Standalone ship emits its allowlisted `INCOMPLETE` marker. Never ask
for permission to bypass the invariant and never output `SHIPPED` on this path.

## 2. Re-entry Check

```bash
[ -f "$STATE_FILE" ] && read_loop_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" '[]')
REPO_SLUG=$(get_loop_field "$STATE_FILE" "repo_slug" '[]')
```

If `PHASE` is set (non-empty), this is a stop-hook re-entry. Restore every Step
1 field through `get_loop_field "$STATE_FILE" "<field>"
"$WORKFLOW_STATE_PATH"`. If `review_clean == "true"`, set
`REVIEW_CLEAN=true` to preserve the clean-review fast path. Never read the
physical root directly because embedded ship owns only its child object.

Ignore legacy `use_agent_review` state; it never authorizes delegation.
A persisted `llm=fable` with `llm_explicit!=true` is an obsolete automatic
selection: reset `llm` to `codex` and apply current prerequisite policy before
any new review. Restore `REVIEW_RESULT` from `review_result` so a skipped
review resumes verification without running a reviewer.

An in-session review is never resumable. If `PHASE == "reviewing"` on
re-entry, the reviewer from the earlier session no longer exists. Do not wait
for it and do not dispatch a replacement. Follow **Expired review recovery**
below.

Then jump to the matching phase:

| Phase | Step |
|-------|------|
| `reviewing` | Expired review recovery, then Step 9 (Phase 2) |
| `review-required` | Step 5 (Phase 1) |
| `fixing` | Step 6 (Phase 1) |
| `verifying` | Step 7 (Phase 1) |
| `coverage-check` | Step 7.5 (Phase 1) |
| `e2e-testing` | Step 7.6 (Phase 1) |
| `pushing` | Step 9 (Phase 2) |
| `ci-watch` | Step 10 (Phase 3) |
| `bot-watching` | Step 11 (Phase 4) |
| `addressing` | Step 12 (Phase 5) |
| `merging` | Step 13 (Phase 6) |

If `PHASE` is empty/unset → fresh start. Continue to Step 3.

`review-required` is a durable request to start one review, used when CI
detects that the PR head changed. Step 5 immediately changes it to
`reviewing` before dispatch. This keeps a review that has not started distinct
from an in-flight review that expired at a session boundary.

### Expired review recovery

This path is for a successor session only. Treat the earlier review as void and
make the validated work durable before doing anything else:

1. Persist `review_result="void"` and
   `review_skip_reason="session-boundary"`. Never reuse a prior agent handle or
   review output.
2. If the index contains validated staged changes, inspect the staged diff and
   commit exactly those files with a conventional message that describes the
   change. Do not label this commit as review findings.
3. Set the phase to `pushing`, push every local commit, and ensure a non-draft
   PR exists via Step 9. Do all three in the same session before yielding.

If there is no staged diff, continue with the existing local commits. Unstaged
or untracked files were not part of the validated index; leave them untouched
and report them after the PR is open.
