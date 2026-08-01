# Step 1: Checkout PR Branch and Rebase

**Do NOT skip ahead to fetching review comments.**

## 1a. Load and validate PR head/base metadata

```bash
PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=pr-metadata-api-failure
}
PR_HEAD_BRANCH=$(jq -er '.head.ref' <<< "$PR_JSON") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=invalid-pr-head-metadata
}
PR_HEAD_SHA=$(jq -er '.head.sha' <<< "$PR_JSON") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=invalid-pr-head-metadata
}
PR_HEAD_OWNER_REPO=$(jq -er '.head.repo.full_name' <<< "$PR_JSON") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=missing-pr-head-repository
}
PR_HEAD_CLONE_URL=$(jq -er '.head.repo.clone_url' <<< "$PR_JSON") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=missing-pr-head-repository
}
PR_BASE_BRANCH=$(jq -er '.base.ref' <<< "$PR_JSON") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=invalid-pr-base-metadata
}
PR_BASE_OWNER_REPO=$(jq -er '.base.repo.full_name' <<< "$PR_JSON") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=invalid-pr-base-metadata
}
PR_BASE_CLONE_URL=$(jq -er '.base.repo.clone_url' <<< "$PR_JSON") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=invalid-pr-base-metadata
}
```

Any metadata failure is a top-level **Hard Invariant Failure**. Stop before
fetching, checkout, rebase, or push.

Protect all existing work before changing the checked-out branch:

```bash
if [ -n "$(git -C "$WORKTREE_PATH" status --porcelain)" ]; then
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=dirty-worktree
fi
```

If dirty, follow the top-level **Hard Invariant Failure** procedure. Do not
stash, discard, carry, or overwrite the existing changes.

## 1b. Resolve remotes, fetch the exact PR head, and checkout safely

```bash
PR_HEAD_REMOTE=""
PR_BASE_REMOTE=""
for remote in $(git -C "$WORKTREE_PATH" remote); do
  REMOTE_URL=$(git -C "$WORKTREE_PATH" remote get-url "$remote")
  REMOTE_OWNER_REPO=$(printf '%s\n' "$REMOTE_URL" | sed 's|\.git$||' | sed -E 's|^https?://[^/]+/||' | sed -E 's|^ssh://[^/]+/||' | sed -E 's|^[^@]+@[^:]+:||')
  if [ "$REMOTE_OWNER_REPO" = "$PR_HEAD_OWNER_REPO" ] && [ -z "$PR_HEAD_REMOTE" ]; then
    PR_HEAD_REMOTE="$remote"
  fi
  if [ "$REMOTE_OWNER_REPO" = "$PR_BASE_OWNER_REPO" ] && [ -z "$PR_BASE_REMOTE" ]; then
    PR_BASE_REMOTE="$remote"
  fi
done

PR_HEAD_FETCH_SOURCE="${PR_HEAD_REMOTE:-$PR_HEAD_CLONE_URL}"
PR_HEAD_PUSH_TARGET="${PR_HEAD_REMOTE:-$PR_HEAD_CLONE_URL}"
PR_BASE_FETCH_SOURCE="${PR_BASE_REMOTE:-$PR_BASE_CLONE_URL}"
PR_HEAD_FETCH_REF="refs/address-review/$PR_NUM/head"
PR_BASE_FETCH_REF="refs/address-review/$PR_NUM/base"

git -C "$WORKTREE_PATH" fetch "$PR_HEAD_FETCH_SOURCE" "+refs/heads/${PR_HEAD_BRANCH}:${PR_HEAD_FETCH_REF}"
FETCHED_HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse "$PR_HEAD_FETCH_REF")
if [ "$FETCHED_HEAD_SHA" != "$PR_HEAD_SHA" ]; then
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=pr-head-shift
fi
```

If the fetched SHA differs from REST metadata, follow the top-level **Hard
Invariant Failure** procedure and restart discovery. Never checkout stale PR
metadata.

```bash
LOCAL_PR_BRANCH="$PR_HEAD_BRANCH"
if git -C "$WORKTREE_PATH" show-ref --verify --quiet "refs/heads/$LOCAL_PR_BRANCH"; then
  LOCAL_BRANCH_SHA=$(git -C "$WORKTREE_PATH" rev-parse "refs/heads/$LOCAL_PR_BRANCH")
  if [ "$LOCAL_BRANCH_SHA" != "$PR_HEAD_SHA" ]; then
    LOCAL_PR_BRANCH="address-review-pr-$PR_NUM"
  fi
fi

if git -C "$WORKTREE_PATH" show-ref --verify --quiet "refs/heads/$LOCAL_PR_BRANCH"; then
  LOCAL_BRANCH_SHA=$(git -C "$WORKTREE_PATH" rev-parse "refs/heads/$LOCAL_PR_BRANCH")
  if [ "$LOCAL_BRANCH_SHA" != "$PR_HEAD_SHA" ]; then
    WORKFLOW_RESULT=INCOMPLETE
    WORKFLOW_REASON=local-pr-branch-diverged
  else
    git -C "$WORKTREE_PATH" checkout "$LOCAL_PR_BRANCH"
  fi
else
  git -C "$WORKTREE_PATH" checkout -b "$LOCAL_PR_BRANCH" "$PR_HEAD_FETCH_REF"
fi
```

A divergent local head branch is preserved by using the dedicated PR branch.
If that dedicated branch also diverged, follow the top-level **Hard Invariant
Failure** procedure instead of resetting either branch.

## 1c. Check if behind base branch and rebase

```bash
git -C "$WORKTREE_PATH" fetch "$PR_BASE_FETCH_SOURCE" "+refs/heads/${PR_BASE_BRANCH}:${PR_BASE_FETCH_REF}"
BEHIND=$(git -C "$WORKTREE_PATH" rev-list --count "HEAD..${PR_BASE_FETCH_REF}")
echo "PR #$PR_NUM is $BEHIND commit(s) behind $PR_BASE_OWNER_REPO/$PR_BASE_BRANCH"
```

**If `$BEHIND` is 0:** Proceed to Step 2.

**If `$BEHIND` > 0:**

1. Re-check `git -C "$WORKTREE_PATH" status --porcelain`. If dirty, report
   `WORKFLOW_RESULT=INCOMPLETE` and `WORKFLOW_REASON=dirty-worktree`, follow the
   top-level **Hard Invariant Failure** procedure, and stop.
2. Run `git -C "$WORKTREE_PATH" rebase "$PR_BASE_FETCH_REF"`. Resolve conflicts only when the
   correct resolution is evident and every conflict is cleared. If any
   conflict remains, run `git -C "$WORKTREE_PATH" rebase --abort`, report
   `WORKFLOW_RESULT=INCOMPLETE` and `WORKFLOW_REASON=rebase-conflict`, then
   follow the top-level **Hard Invariant Failure** procedure and stop.
3. Force-push only to the REST-declared fork/head branch and pin the lease to
   the pre-rebase PR head:

   ```bash
   EXPECTED_REMOTE_HEAD_SHA="$PR_HEAD_SHA"
   PR_HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD)
   git -C "$WORKTREE_PATH" push --force-with-lease="refs/heads/${PR_HEAD_BRANCH}:${EXPECTED_REMOTE_HEAD_SHA}" \
     "$PR_HEAD_PUSH_TARGET" "HEAD:refs/heads/$PR_HEAD_BRANCH"
   PUBLISHED_HEAD_SHA=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM" | jq -er '.head.sha') || {
     WORKFLOW_RESULT=INCOMPLETE
     WORKFLOW_REASON=pr-metadata-api-failure
   }
   if [ "$PUBLISHED_HEAD_SHA" != "$PR_HEAD_SHA" ]; then
     WORKFLOW_RESULT=INCOMPLETE
     WORKFLOW_REASON=pr-head-shift
   fi
   ```

If push verification fails, follow the top-level **Hard Invariant Failure**
procedure.

## 1d. Wait for CI after rebase

Only after a rebase, watch checks pinned to the exact pushed head:

```bash
CHECK_STATUS=0
CHECKS_JSON=$(cd "$WORKTREE_PATH" && github_watch_pr_checks "$PR_NUM" "$PR_HEAD_SHA") || CHECK_STATUS=$?
case "$CHECK_STATUS" in
  0) printf '%s\n' "$CHECKS_JSON" | jq '.' ;;
  1) echo "CI failed after rebase. Analyze and fix every failure before proceeding." ;;
  2) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=checks-registration-timeout ;;
  3) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=checks-api-failure ;;
  4) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=pr-head-shift ;;
  *) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=checks-unknown-failure ;;
esac
```

For statuses 2-4 or an unknown status, follow the top-level **Hard Invariant
Failure** procedure. Registration timeout, API failure, and head shift are
non-success outcomes. Do not proceed until CI passes for `PR_HEAD_SHA`.
