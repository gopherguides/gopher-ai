# Fix Cycle: Steps 3-9

## Step 3: Display and Categorize Comments

**Group A — Resolvable threads** (from `reviewThreads`): Track thread ID, file/line, body, author.

**Group B — Pending reviews** (`CHANGES_REQUESTED`): Track review body, author. Cannot be auto-resolved.

**Track unique reviewers** from both groups for Step 10.

### If no feedback found:

- **If `CURRENT_PHASE` is `fixing` AND `WATCH_MODE` is `true` AND bots detected:** Set phase to `watching`, skip to Step 12:
  ```bash
  SAFE_LOOP_NAME=$(echo "address-review-${RESOLVED_PR:-auto}" | sed 's/[^a-zA-Z0-9_-]/-/g')
  LOOP_STATE_FILE=".local/state/${SAFE_LOOP_NAME}.loop.local.json"
  if [ -f "$LOOP_STATE_FILE" ]; then
    source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
    set_loop_phase "$LOOP_STATE_FILE" "watching"
    echo "Phase set to: watching (post-fix-cycle path)"
  fi
  ```
- **If fresh run (no phase set):** PR already clean → `<done>COMPLETE</done>`.
- **If `WATCH_MODE` is `true` AND no bots:** → `<done>COMPLETE</done>`.
- **If `WATCH_MODE` is `false`:** → `<done>COMPLETE</done>`.

### If only pending reviews (no threads):

Address feedback, but note: "This PR has pending review feedback that cannot be auto-resolved. After pushing fixes, you'll need to request re-review from the reviewer."

---

## Step 4: Address Each Comment

**Set phase to `fixing`:**

```bash
SAFE_LOOP_NAME=$(echo "address-review-${RESOLVED_PR:-auto}" | sed 's/[^a-zA-Z0-9_-]/-/g')
LOOP_STATE_FILE=".local/state/${SAFE_LOOP_NAME}.loop.local.json"
if [ -f "$LOOP_STATE_FILE" ]; then
  source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
  set_loop_phase "$LOOP_STATE_FILE" "fixing"
fi
```

### Protect Pre-existing Target Changes

Before the first edit to each unique source or test path in this fix cycle, verify that the target path has no staged, unstaged, or untracked changes. Run this guard exactly once per path, before sequential work or agent dispatch:

```bash
TARGET_FILE="path/from-review-thread"
if [ -n "$(git status --porcelain -- "$TARGET_FILE")" ]; then
  echo "Error: $TARGET_FILE already has changes that are not owned by this review-fix cycle."
  exit 1
fi
```

If the guard fails, inspect the pre-existing diff, review request, and current
workflow-owned file list. State `Decision`, `Evidence`, and `Rationale`. Because
Git cannot distinguish those hunks from a new review fix, do not edit or stage
the path. Stop incomplete with
`WORKFLOW_REASON=unowned-review-target-changes` until the changes are committed,
stashed, or otherwise separated. Follow the caller's **Hard Invariant Failure**
procedure so the workflow cannot advance.

### Parallel Fix Dispatch (when 3+ comments target different files)

When there are 3 or more unresolved comments targeting **different files**, dispatch parallel Implementer subagents:

1. **Group comments by file** — comments in the same file are handled by one subagent
2. **Group by shared test files** — if two source files are in the same package and share a `_test.go`, they must be in the same group to avoid write conflicts
3. **For each file group**, delegate a fresh-context implementation worker
   through the active surface, selecting sonnet when the surface supports model
   choice, with:
   - "You are addressing PR review comments in `{FILE_PATH}`. Working directory: `{PROJECT_ROOT}`."
   - All comments for that file (reviewer text, line number, suggested change)
   - "Before editing, run the pre-existing target changes guard. For each comment: understand the request, locate the code, make the minimal fix, validate against feedback. Report: files changed, fixes applied, testability of each fix."
3. **Dispatch all file-group agents in parallel** using `run_in_background: true`
4. **Collect results** — proceed to Step 4.5 (test generation) with combined fix list

**Fall back to sequential processing** when fewer than 3 comments or all target the same file.

For each unresolved review comment (sequential mode, or when parallel dispatch is not used):

### 4a. Understand the Request
Determine what change is requested: code style, logic, docs, test, refactoring? Is it testable (alters observable behavior)?

### 4b. Locate the Code
Use file path and line number from the thread.

### 4c. Make the Fix
Make the **minimal change** that addresses the comment. Follow existing patterns.

### 4d. Validate Fix Against Feedback
1. Re-read the reviewer's comment
2. Compare your change against reviewer's intent
3. Check for completeness
4. Avoid mechanical edits that miss the underlying concern

### 4e. Track the Fix
Note: thread ID, what was fixed, brief explanation, testability (`testable`/`not-testable`), source file/function/package if testable, and every file modified by the fix. Maintain one explicit owned-files list for this fix cycle. Do not add files that were already modified before the cycle or changed for unrelated work.

## Step 4.5: Generate Tests for Testable Fixes

Read `test-generation.md` for full test generation guidelines including testability rules, existing test detection, pattern matching, and test writing procedures. Run the pre-existing target changes guard before modifying an existing test path, then add every generated or modified test file to the owned-files list.

---

## Step 5: Verify Fixes Locally

**All must pass before proceeding:**
- `go build ./...`
- `go test ./...`
- `golangci-lint run` (if available)
- Check dev server logs for errors if applicable

Fix any failures and re-run until all green.

---

## Step 6: Commit and Push

Stage only files modified during this fix cycle. Build `OWNED_FILES` from the paths tracked in Steps 4 and 4.5, inspect `git status --short`, and exclude every pre-existing or unrelated change. Start from an empty index so an earlier staged change cannot enter the review-fix commit.

```bash
PR_JSON=$(github_pr "$PR_NUM") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=pr-metadata-api-failure
}
EXPECTED_REMOTE_HEAD_SHA=$(jq -er '.head.sha' <<< "$PR_JSON") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=invalid-pr-head-metadata
}
PR_HEAD_BRANCH=$(jq -er '.head.ref' <<< "$PR_JSON") || {
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
PR_HEAD_PUSH_TARGET=""
for remote in $(git remote); do
  REMOTE_URL=$(git remote get-url "$remote")
  REMOTE_OWNER_REPO=$(printf '%s\n' "$REMOTE_URL" | sed 's|\.git$||' | sed -E 's|^https?://[^/]+/||' | sed -E 's|^ssh://[^/]+/||' | sed -E 's|^[^@]+@[^:]+:||')
  if [ "$REMOTE_OWNER_REPO" = "$PR_HEAD_OWNER_REPO" ]; then
    PR_HEAD_PUSH_TARGET="$remote"
    break
  fi
done
PR_HEAD_PUSH_TARGET="${PR_HEAD_PUSH_TARGET:-$PR_HEAD_CLONE_URL}"
if [ "$(git rev-parse HEAD)" != "$EXPECTED_REMOTE_HEAD_SHA" ]; then
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=pr-head-shift
fi

if ! git diff --cached --quiet; then
  echo "Error: Pre-existing staged changes must be committed or unstaged before address-review can commit."
  exit 1
fi

OWNED_FILES=(
  "path/to/fixed-file.go"
  "path/to/generated_test.go"
)
git add -- "${OWNED_FILES[@]}"

if ! git diff --cached --quiet; then
  git commit -m "address review comments

- [brief summary of each fix]
- [tests added for testable fixes, if any]"
else
  echo "No owned review-fix changes to commit."
fi
git push "$PR_HEAD_PUSH_TARGET" "HEAD:refs/heads/$PR_HEAD_BRANCH"
PR_HEAD_SHA=$(git rev-parse HEAD)
PUBLISHED_HEAD_SHA=$(github_pr "$PR_NUM" | jq -er '.head.sha') || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=pr-metadata-api-failure
}
if [ "$PUBLISHED_HEAD_SHA" != "$PR_HEAD_SHA" ]; then
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=pr-head-shift
fi
```

Any PR metadata failure or head shift is a top-level **Hard Invariant
Failure**. Stop without pushing when the local parent no longer matches the PR
head, and stop without claiming success when the published head cannot be
verified. The push target is re-derived here so nested callers and watch-mode
re-entry do not depend on checkout-phase shell state.

**CRITICAL: Capture bot review baseline IMMEDIATELY after pushing:**

```bash
BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Bot review baseline captured: $BOT_REVIEW_BASELINE"
```

Store this value for all Step 12 bot checks. Do NOT recompute later.

---

## Step 7: Watch CI

```bash
CHECK_STATUS=0
CHECKS_JSON=$(github_watch_pr_checks "$PR_NUM" "$PR_HEAD_SHA") || CHECK_STATUS=$?
case "$CHECK_STATUS" in
  0) printf '%s\n' "$CHECKS_JSON" | jq '.' ;;
  1) echo "CI failed. Analyze and fix every failing check, then commit, push, update PR_HEAD_SHA, and re-watch." ;;
  2) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=checks-registration-timeout ;;
  3) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=checks-api-failure ;;
  4) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=pr-head-shift ;;
  *) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=checks-unknown-failure ;;
esac
```

For statuses 2-4 or an unknown status, follow the top-level **Hard Invariant
Failure** procedure. Registration timeout, API failure, and head shift are
non-success outcomes. If CI fails, analyze, fix, commit, push, update the exact
head SHA, and re-watch. **Do not proceed until CI is green for
`PR_HEAD_SHA`.**

---

## Step 8: Reply to Each Comment

```bash
gh pr comment "$PR_NUM" --body "Fixed in latest commit: [brief explanation]"
```

Keep replies brief and professional.

---

## Step 9: Resolve Review Threads (Group A only)

**Only resolve after CI passes and fixes are pushed.** Only for line-specific threads (Group A).

```bash
gh api graphql -f query='
  mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) {
      thread { isResolved }
    }
  }
' -f threadId="THREAD_ID_HERE"
```

Repeat for each unresolved thread.
