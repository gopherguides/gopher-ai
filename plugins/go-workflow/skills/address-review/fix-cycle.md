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

### Parallel Fix Dispatch (when 3+ comments target different files)

When there are 3 or more unresolved comments targeting **different files**, dispatch parallel Implementer subagents:

1. **Group comments by file** — comments in the same file are handled by one subagent
2. **Group by shared test files** — if two source files are in the same package and share a `_test.go`, they must be in the same group to avoid write conflicts
3. **For each file group**, dispatch an Agent subagent (sonnet) with:
   - "You are addressing PR review comments in `{FILE_PATH}`. Working directory: `{PROJECT_ROOT}`."
   - All comments for that file (reviewer text, line number, suggested change)
   - "For each comment: understand the request, locate the code, make the minimal fix, validate against feedback. Report: files changed, fixes applied, testability of each fix."
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
Note: thread ID, what was fixed, brief explanation, testability (`testable`/`not-testable`), source file/function/package if testable.

## Step 4.5: Generate Tests for Testable Fixes

Read `test-generation.md` for full test generation guidelines including testability rules, existing test detection, pattern matching, and test writing procedures.

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

```bash
git add -A
git commit -m "address review comments

- [brief summary of each fix]
- [tests added for testable fixes, if any]"
git push
```

**CRITICAL: Capture bot review baseline IMMEDIATELY after pushing:**

```bash
BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Bot review baseline captured: $BOT_REVIEW_BASELINE"
```

Store this value for all Step 12 bot checks. Do NOT recompute later.

---

## Step 7: Watch CI

```bash
gh pr checks "$PR_NUM" --watch
```

If "no checks reported" — retry up to 3 times with 10s delays:
```bash
for i in 1 2 3; do sleep 10 && gh pr checks "$PR_NUM" --watch && break; done
```

If still no checks after retries, verify CI workflow files exist (`find .github/workflows -name '*.yml' -o -name '*.yaml'`). If no workflow files exist, proceed — repo has no CI. If CI fails: analyze, fix, commit, push, re-watch. **Do not proceed until CI is green (or confirmed no CI configured).**

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
