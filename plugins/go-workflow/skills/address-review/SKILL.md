---
name: address-review
description: |
  Address PR review comments, fix reviewer feedback, and resolve review threads on GitHub
  pull requests. Use when the user wants to handle, fix, or respond to feedback left by
  human reviewers or review bots (CodeRabbit, Copilot, Greptile, Claude) on a PR. Covers
  fixing flagged issues, resolving unresolved threads, addressing CHANGES_REQUESTED reviews,
  and requesting re-review after fixes. Triggers for any mention of PR review comments,
  reviewer suggestions, review feedback, or unresolved review threads needing action.
  NOT for: creating new PRs, performing your own code review, general coding tasks, or
  closing/managing PRs without review context.
argument-hint: "[PR-number] [--no-watch]"
model: claude-opus-4-6
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "Task", "AskUserQuestion"]
---

# Address PR Review Comments

**If `$ARGUMENTS` is empty or not provided:**

Auto-detect PR from current branch:

```bash
gh pr view --json number --jq '.number' 2>/dev/null
```

If no PR found, display usage and ask:

**Usage:** `/address-review [PR-number] [--no-watch]`

**Example:** `/address-review 123` or just `/address-review` on a PR branch. Add `--no-watch` to exit after one fix cycle instead of watching for bot re-reviews.

Ask the user: "No PR found for current branch. What PR number would you like to address?"

---

**If PR number is available (from `$ARGUMENTS` or auto-detected):**

## Parse Arguments

```bash
WATCH_MODE=true
PR_ARG=""
for arg in $ARGUMENTS; do
  case "$arg" in
    --no-watch) WATCH_MODE=false ;;
    *) PR_ARG="$arg" ;;
  esac
done
echo "WATCH_MODE=$WATCH_MODE PR_ARG=$PR_ARG"
```

- `WATCH_MODE`: `true` (default) enables watch loop; `false` exits after one fix cycle. `PR_ARG`: The PR number (may be empty for auto-detect).

## Security Validation

!if [ -n "$PR_ARG" ] && ! echo "$PR_ARG" | grep -qE '^[0-9]+$'; then echo "Error: PR number must be numeric"; exit 1; fi

## Resolve PR Number

Always resolve BEFORE loop initialization to ensure PR-specific loop state:

```bash
RESOLVED_PR="${PR_ARG:-$(gh pr view --json number --jq '.number' 2>/dev/null || echo 'auto')}"
echo "Resolved PR: $RESOLVED_PR"
```

## Loop Initialization

!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "address-review-${RESOLVED_PR:-auto}" "COMPLETE"`

## Re-entry Check

Check if resuming from a previous watching phase:

```bash
SAFE_LOOP_NAME=$(echo "address-review-${RESOLVED_PR:-auto}" | sed 's/[^a-zA-Z0-9_-]/-/g')
LOOP_STATE_FILE=".claude/${SAFE_LOOP_NAME}.loop.local.md"
CURRENT_PHASE=""
if [ -f "$LOOP_STATE_FILE" ]; then
  CURRENT_PHASE=$(grep '^phase:' "$LOOP_STATE_FILE" | sed 's/phase: *//' || true)
fi
echo "Current phase: ${CURRENT_PHASE:-<none>}"
```

**If `CURRENT_PHASE` is `watching` AND `WATCH_MODE` is `true`:** Fix cycle already completed. Restore `BOT_REVIEW_BASELINE` from state file:

```bash
BOT_REVIEW_BASELINE=""
if [ -f "$LOOP_STATE_FILE" ]; then
  BOT_REVIEW_BASELINE=$(grep '^bot_review_baseline:' "$LOOP_STATE_FILE" | sed 's/bot_review_baseline: *//' || true)
fi
if [ -z "$BOT_REVIEW_BASELINE" ]; then
  BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "Bot review baseline (fallback): $BOT_REVIEW_BASELINE"
  if [ -f "$LOOP_STATE_FILE" ]; then
    sed -i '' "/^phase:/a\\
bot_review_baseline: $BOT_REVIEW_BASELINE" "$LOOP_STATE_FILE" 2>/dev/null || sed -i "/^phase:/a bot_review_baseline: $BOT_REVIEW_BASELINE" "$LOOP_STATE_FILE"
  fi
else
  echo "Bot review baseline (restored): $BOT_REVIEW_BASELINE"
fi
```

Do NOT re-run the fix cycle. Skip to watch loop (read `watch-loop.md`).

**If `CURRENT_PHASE` is `watching` AND `WATCH_MODE` is `false`:** Clear stale phase:

```bash
if [ -f "$LOOP_STATE_FILE" ]; then
  sed -i '' "s/^phase: .*/phase: /" "$LOOP_STATE_FILE" 2>/dev/null || sed -i "s/^phase: .*/phase: /" "$LOOP_STATE_FILE"
  echo "Phase cleared (--no-watch mode)"
fi
```

Continue with full fix cycle. **Otherwise:** Continue normally.

## Context

- PR details: !`PR_NUM="${PR_ARG:-\`gh pr view --json number --jq '.number' 2>/dev/null\`}"; gh pr view "$PR_NUM" --json title,state,body,headRefName,baseRefName --jq '.' 2>/dev/null || echo "PR not found"`
- Current branch: !`git branch --show-current 2>&1 || echo "unknown"`
- Default branch: !`git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main"`
- PR number: !`echo "${PR_ARG:-\`gh pr view --json number --jq '.number' 2>/dev/null\`}"`

## Mode Banner and Bot Discovery

**Display mode banner:**

If `WATCH_MODE` is `true`: `🔄 Watch mode enabled (default) — will loop until all review bots approve. Tip: Use /address-review [PR] --no-watch to exit after one fix cycle.`

If `WATCH_MODE` is `false`: `⏩ No-watch mode — will fix comments once and exit.`

**Discover review bots** (only when `WATCH_MODE` is `true`):

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')
PR_NUM="${PR_ARG:-$(gh pr view --json number --jq '.number')}"

BOT_AUTHORS=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviews(first: 100) {
          nodes {
            author { login }
            state
          }
        }
        reviewThreads(first: 100) {
          nodes {
            comments(first: 50) {
              nodes {
                author { login }
              }
            }
          }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq -r '
  [
    .data.repository.pullRequest.reviews.nodes[].author.login,
    .data.repository.pullRequest.reviewThreads.nodes[].comments.nodes[].author.login
  ] | unique | .[]
')

echo "All unique authors on PR: $BOT_AUTHORS"
```

Match authors against the bot registry (read `bot-registry.md` for the full table). Display discovered bots or "No review bots detected on this PR." If no bots found: complete fix cycle (Steps 1-11) but skip Step 12.

---

## Step 1: Checkout PR Branch and Rebase

**Do NOT skip ahead to fetching review comments.**

### 1a. Checkout

```bash
PR_NUM="${PR_ARG:-$(gh pr view --json number --jq '.number')}"
echo "Working on PR #$PR_NUM"
gh pr checkout "$PR_NUM"
```

Idempotent — handles same-repo PRs, fork PRs, and branch tracking.

### 1b. Check if behind base branch and rebase

```bash
BASE_BRANCH=$(gh pr view "$PR_NUM" --json baseRefName --jq '.baseRefName')
BASE_OWNER_REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')

BASE_REMOTE=""
for remote in $(git remote); do
  REMOTE_URL=$(git remote get-url "$remote")
  REMOTE_OWNER_REPO=$(echo "$REMOTE_URL" | sed 's|\.git$||' | sed -E 's|^https?://[^/]+/||' | sed -E 's|^ssh://[^/]+/||' | sed -E 's|^[^@]+@[^:]+:||')
  if [ "$REMOTE_OWNER_REPO" = "$BASE_OWNER_REPO" ]; then
    BASE_REMOTE="$remote"
    break
  fi
done

if [ -z "$BASE_REMOTE" ]; then
  echo "Error: No remote found pointing to base repository ($BASE_OWNER_REPO)"
  exit 1
fi

git fetch "$BASE_REMOTE" "$BASE_BRANCH"
BEHIND=$(git rev-list --count "HEAD..${BASE_REMOTE}/${BASE_BRANCH}")
echo "Commits behind ${BASE_REMOTE}/${BASE_BRANCH}: $BEHIND"
```

**If `$BEHIND` is 0:** Proceed to Step 2.

**If `$BEHIND` > 0:**
1. Check `git status --porcelain`. **If dirty, STOP** — ask user how to proceed.
2. `git rebase "${BASE_REMOTE}/${BASE_BRANCH}"` — resolve conflicts intelligently or ask user if too complex.
3. Force-push:
   ```bash
   PR_HEAD_BRANCH=$(gh pr view "$PR_NUM" --json headRefName --jq '.headRefName')
   BRANCH_REMOTE=$(git config "branch.$(git branch --show-current).remote")
   git push --force-with-lease "$BRANCH_REMOTE" "HEAD:$PR_HEAD_BRANCH"
   ```

### 1c. Wait for CI after rebase (only if rebased)

```bash
for i in 1 2 3 4 5; do sleep 10 && gh pr checks "$PR_NUM" --watch && break; done
```

Verify with `gh pr checks "$PR_NUM"`. Fix any failures before proceeding.

---

## Step 2: Fetch All Review Feedback

GitHub has two types: **review threads** (line-specific, auto-resolvable) and **review comments** (general CHANGES_REQUESTED, not auto-resolvable).

### 2a. Fetch review threads

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')

gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            path
            line
            comments(first: 50) {
              nodes {
                body
                author { login }
                createdAt
              }
            }
          }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM"
```

### 2b. Fetch pending reviews

```bash
gh pr view "$PR_NUM" --json reviews --jq '.reviews[] | select(.state == "CHANGES_REQUESTED")'
```

---

## Step 3: Display and Categorize Comments

**Group A — Resolvable threads** (from `reviewThreads`): Track thread ID, file/line, body, author.

**Group B — Pending reviews** (`CHANGES_REQUESTED`): Track review body, author. Cannot be auto-resolved.

**Track unique reviewers** from both groups for Step 10.

### If no feedback found:

- **If `CURRENT_PHASE` is `fixing` AND `WATCH_MODE` is `true` AND bots detected:** Set phase to `watching`, skip to Step 12:
  ```bash
  SAFE_LOOP_NAME=$(echo "address-review-${RESOLVED_PR:-auto}" | sed 's/[^a-zA-Z0-9_-]/-/g')
  LOOP_STATE_FILE=".claude/${SAFE_LOOP_NAME}.loop.local.md"
  if [ -f "$LOOP_STATE_FILE" ]; then
    if grep -q '^phase:' "$LOOP_STATE_FILE"; then
      sed -i '' "s/^phase: .*/phase: watching/" "$LOOP_STATE_FILE" 2>/dev/null || sed -i "s/^phase: .*/phase: watching/" "$LOOP_STATE_FILE"
    else
      sed -i '' "/^completion_promise:/a\\
  phase: watching" "$LOOP_STATE_FILE" 2>/dev/null || sed -i "/^completion_promise:/a phase: watching" "$LOOP_STATE_FILE"
    fi
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
LOOP_STATE_FILE=".claude/${SAFE_LOOP_NAME}.loop.local.md"
if [ -f "$LOOP_STATE_FILE" ]; then
  sed -i '' "s/^phase: .*/phase: fixing/" "$LOOP_STATE_FILE" 2>/dev/null || sed -i "s/^phase: .*/phase: fixing/" "$LOOP_STATE_FILE"
fi
```

For each unresolved review comment:

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

If CI fails: analyze, fix, commit, push, re-watch. **Do not proceed until CI is green.**

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

---

## Step 10: Request Re-review

Read `bot-registry.md` for the full re-review procedure (Steps 10a-10e) including bot detection, opt-out checks, and data-driven re-review triggering.

---

## Step 11: Verify Completion

Confirm all resolvable threads are resolved:

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')

gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes {
            isResolved
          }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq '.data.repository.pullRequest.reviewThreads.nodes | map(select(.isResolved == false)) | length'
```

Confirm CI is passing: `gh pr checks "$PR_NUM"`

---

## Step 12: Watch for Bot Re-review (Phase Transition + Watch Loop)

**Skip if `WATCH_MODE` is `false` or no review bots were detected.**

Read `watch-loop.md` for the complete Phase Transition logic, bot polling (12a-12d), quiet period detection, timeout handling, and re-trigger procedures.

---

## Completion Criteria

### With `--no-watch`:
Output `<done>COMPLETE</done>` when ALL are true:
1. PR branch rebased onto latest base branch (or already up to date)
2. All review feedback addressed with code changes
3. Each fix validated against reviewer's intent
4. Local verification passes (`go build`, `go test`, `golangci-lint`)
5. Changes committed and pushed
6. CI checks pass
7. Replies posted to each comment
8. All resolvable threads resolved via GraphQL
9. Re-review requested from actual reviewers (data-driven per `bot-registry.md`)

### Default (watch mode):
All above, PLUS:
10. All detected review bots signaled approval per Bot Registry
11. If no bots detected, skip Step 12 (fix cycle still completes fully)

**Note:** Pending reviews (CHANGES_REQUESTED) cannot be auto-resolved. Do NOT request review from bots that never reviewed this PR.

**When ALL criteria are met, output exactly:** `<done>COMPLETE</done>`

**Safety note:** If you've iterated 15+ times without success, document what's blocking and ask the user for guidance. Use extended thinking for complex analysis.

## Supporting Files

- `bot-registry.md` — Bot registry table, detection logic, and Step 10 re-review procedures
- `test-generation.md` — Step 4.5 test generation guidelines and testability rules
- `watch-loop.md` — Phase Transition logic and Step 12 watch loop procedures
