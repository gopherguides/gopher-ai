# Address-Review Completion Check

Loaded by `skills/address-review/SKILL.md` Step 11 and directly reusable by embedded consumers. Execute every check against the expected published head.

## Step 11: Verify Completion

Confirm all resolvable threads are resolved and CI is passing:

```bash
PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=pr-metadata-api-failure
}
if [ -z "${WORKFLOW_REASON:-}" ]; then
  PR_HEAD_SHA=$(jq -er '.head.sha' <<< "$PR_JSON") || {
    WORKFLOW_RESULT=INCOMPLETE
    WORKFLOW_REASON=invalid-pr-metadata
  }
fi
if [ -z "${WORKFLOW_REASON:-}" ]; then
  REVIEW_HEAD_EXPECTATION="${EXPECTED_REVIEW_HEAD:-$(git -C "$WORKTREE_PATH" rev-parse HEAD)}"
fi
if [ -z "${WORKFLOW_REASON:-}" ] &&
   [ "$PR_HEAD_SHA" != "$REVIEW_HEAD_EXPECTATION" ]; then
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=pr-head-shift
fi
if [ -z "${WORKFLOW_REASON:-}" ]; then
  OWNER=$(jq -er '.base.repo.owner.login' <<< "$PR_JSON")
  REPO=$(jq -er '.base.repo.name' <<< "$PR_JSON")

  (cd "$WORKTREE_PATH" && gh api graphql -f query='
    query($owner: String!, $repo: String!, $pr: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100) {
            nodes { isResolved }
          }
        }
      }
    }
  ' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM") | jq '.data.repository.pullRequest.reviewThreads.nodes | map(select(.isResolved == false)) | length'
fi
```

Pin completion checks to the exact published PR head:

```bash
if [ -z "${WORKFLOW_REASON:-}" ]; then
  CHECK_STATUS=0
  CHECKS_JSON=$(cd "$WORKTREE_PATH" && github_watch_pr_checks "$PR_NUM" "$PR_HEAD_SHA") || CHECK_STATUS=$?
  case "$CHECK_STATUS" in
    0) printf '%s\n' "$CHECKS_JSON" | jq '.' ;;
    1) echo "CI failed. Return to the fix cycle and do not claim completion." ;;
    2) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=checks-registration-timeout ;;
    3) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=checks-api-failure ;;
    4) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=pr-head-shift ;;
    *) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=checks-unknown-failure ;;
  esac
fi
```

For metadata failures, an `EXPECTED_REVIEW_HEAD` mismatch, statuses 2-4, or an
unknown status, follow **Hard Invariant Failure**. A registration timeout, API
failure, or PR head shift is never a successful CI result.

---

## Embedded Consumer Contract

When ship, e2e-verify, or another workflow executes Steps 2-11, return control
to the caller after Step 11 and emit no terminal marker. The caller remains the
top-level owner of its later verification, posting, merge, and completion
gates.

On the no-feedback path, return `REVIEW_CLEAN=true` and persist
`review_clean=true` to the caller's `STATE_FILE` when available. Embedded
consumers skip the inapplicable edit, commit, reply, resolution, and re-review
steps, but still execute Step 5 local verification, Step 7 CI, and Step 11
completion verification before regaining control.

---

## Completion Criteria

The standalone address-review owns its final marker only after Step 11 and all
applicable completion criteria pass. Embedded consumers follow the contract
above instead.

### With `--no-watch`:
Output `<done>COMPLETE</done>` when: branch rebased; local verification passes;
CI is green; Step 11 confirms no unresolved threads; and, when feedback was
found, all feedback is addressed, fixes are validated and pushed, replies are
posted, threads are resolved, and re-review is requested. A clean review skips
only those feedback-specific actions.

### Default (watch mode):
All above, PLUS all detected review bots signaled approval per `bot-registry.md`.

When all criteria are met:

```bash
if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
  set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "complete" "" "completed"
  echo "ADDRESS_REVIEW_RESULT=complete"
else
  set_loop_terminal_result "$STATE_FILE" "complete" "" "completed" "COMPLETE"
  echo "<done>COMPLETE</done>"
fi
```

If the user exits or skips a bot before all detected bots approve, follow the
**Incomplete Approval Outcome** procedure in `watch-loop.md`. Persist
`approval_result` and `approval_reason`; standalone address-review emits its
allowlisted `INCOMPLETE` marker while embedded address-review returns its
structured failure without a marker.

**Safety:** If 15+ iterations complete without success, document the blocking
evidence and stop incomplete. Do not bypass review or approval criteria.
