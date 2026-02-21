---
argument-hint: "[PR-number] [--no-watch]"
description: "Address PR review comments, fix, and loop until bots approve (one-shot). Use --no-watch to exit after one fix cycle."
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

Extract `--no-watch` flag and PR number from `$ARGUMENTS`:

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

Store the parsed values:
- `WATCH_MODE`: `true` (default, one-shot) enables watch loop so AI fully completes the task; `false` exits after one fix cycle requiring manual re-runs
- `PR_ARG`: The PR number (may be empty for auto-detect)

## Security Validation

Validate input is numeric (using `PR_ARG` which has `--no-watch` stripped):
!if [ -n "$PR_ARG" ] && ! echo "$PR_ARG" | grep -qE '^[0-9]+$'; then echo "Error: PR number must be numeric"; exit 1; fi

## Resolve PR Number

Always resolve the PR number BEFORE loop initialization to ensure the loop state is PR-specific (not `address-review-auto` which could leak phase across different PRs):

```bash
RESOLVED_PR="${PR_ARG:-$(gh pr view --json number --jq '.number' 2>/dev/null || echo 'auto')}"
echo "Resolved PR: $RESOLVED_PR"
```

Store `RESOLVED_PR` for use in loop initialization and throughout the workflow.

## Loop Initialization

Initialize persistent loop with PR-specific name:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "address-review-${RESOLVED_PR:-auto}" "COMPLETE"`

## Re-entry Check

Before starting the fix cycle, check if we're resuming from a previous watching phase:

```bash
SAFE_LOOP_NAME=$(echo "address-review-${RESOLVED_PR:-auto}" | sed 's/[^a-zA-Z0-9_-]/-/g')
LOOP_STATE_FILE=".claude/${SAFE_LOOP_NAME}.loop.local.md"
CURRENT_PHASE=""
if [ -f "$LOOP_STATE_FILE" ]; then
  CURRENT_PHASE=$(grep '^phase:' "$LOOP_STATE_FILE" | sed 's/phase: *//' || true)
fi
echo "Current phase: ${CURRENT_PHASE:-<none>}"
```

**If `CURRENT_PHASE` is `watching` AND `WATCH_MODE` is `true`:** The fix cycle (Steps 1-11) already completed in a previous iteration. Restore `BOT_REVIEW_BASELINE` from the state file (persisted during Phase Transition) so timestamp checks use the original post-push baseline, not the current time:

```bash
BOT_REVIEW_BASELINE=""
if [ -f "$LOOP_STATE_FILE" ]; then
  BOT_REVIEW_BASELINE=$(grep '^bot_review_baseline:' "$LOOP_STATE_FILE" | sed 's/bot_review_baseline: *//' || true)
fi
if [ -z "$BOT_REVIEW_BASELINE" ]; then
  BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "Bot review baseline (fallback, not persisted): $BOT_REVIEW_BASELINE"
else
  echo "Bot review baseline (restored): $BOT_REVIEW_BASELINE"
fi
```

Do NOT re-run the fix cycle.

**If `CURRENT_PHASE` is `watching` AND `WATCH_MODE` is `false`:** Clear the stale phase explicitly so stop-hook doesn't route to Step 12:

```bash
if [ -f "$LOOP_STATE_FILE" ]; then
  sed -i '' "s/^phase: .*/phase: /" "$LOOP_STATE_FILE" 2>/dev/null || sed -i "s/^phase: .*/phase: /" "$LOOP_STATE_FILE"
  echo "Phase cleared (--no-watch mode)"
fi
```

Continue with the full fix cycle. (`--no-watch` mode should not inherit watching phase from a prior run.)

**Otherwise:** Continue normally with the full flow below.

## Bot Registry

Reference table of known review bots. Used ONLY for matching against bots actually found on the PR — never for proactively contacting bots.

| Login | Approval Signal | Has Issues Signal | Re-review Trigger |
|---|---|---|---|
| `coderabbitai[bot]` | Formal `APPROVED` review state (requires `request_changes_workflow` in `.coderabbit.yaml`) | `CHANGES_REQUESTED` review with inline comments | `@coderabbitai full review` |
| `chatgpt-codex-connector[bot]` (mention as `@codex`) | Issue comment: `"Codex Review: Didn't find any major issues."` + 👍 reaction on trigger comment | `COMMENTED` review with inline P1/P2 badge comments | `@codex review` |
| `greptileai` | Greptile status check passes + no inline comments posted | Inline comments on specific file changes | `@greptileai` |
| `copilot-pull-request-review[bot]` | `COMMENTED` review with no inline file comments ("did not comment on any files") | `COMMENTED` review with inline suggestions | Re-request review button in PR sidebar _(no `@` mention trigger)_ |
| `claude[bot]` | `COMMENTED` review or issue comment: `"No issues found."` (or silent) | `COMMENTED` review with inline comments scored by confidence | `@claude` |

**How each bot signals it's done (detection logic):**

- **CodeRabbit**: Only bot that uses formal GitHub review states. Query latest review from `coderabbitai[bot]` — if `state == "APPROVED"` → done. This is the most reliable signal.
- **Codex**: Look for an issue comment from `chatgpt-codex-connector[bot]` containing `"Didn't find any major issues"`. Also reacts with 👍 on the `@codex review` trigger comment. If the bot posted `COMMENTED` reviews with P1/P2 inline comments, it still has issues. Eyes emoji (👀) on trigger comment means processing started (not done yet).
- **Greptile**: Uses a **status check** (not review states). Check `gh pr checks` for a Greptile check — if it passes and no new inline comments were posted, Greptile is satisfied.
- **Copilot**: Always posts `COMMENTED` reviews (never `APPROVED` or `CHANGES_REQUESTED`). If its review body says it "did not comment on any files" or has no inline comments → no issues found. Cannot be re-triggered via comment — must use the re-request review button in the GitHub PR sidebar.
- **Claude**: Posts `COMMENTED` reviews. If no inline comments above confidence threshold → "No issues found" or no review posted at all. Re-trigger via `@claude` mention.

**Ignore list:** `github-actions[bot]`, `dependabot[bot]`, `renovate[bot]`, `netlify[bot]`, `vercel[bot]` — these are CI/deploy bots, not reviewers.

## Context

- PR details: !`PR_NUM="${PR_ARG:-\`gh pr view --json number --jq '.number' 2>/dev/null\`}"; gh pr view "$PR_NUM" --json title,state,body,headRefName,baseRefName --jq '.' 2>/dev/null || echo "PR not found"`
- Current branch: !`git branch --show-current 2>&1 || echo "unknown"`
- Default branch: !`git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main"`
- PR number: !`echo "${PR_ARG:-\`gh pr view --json number --jq '.number' 2>/dev/null\`}"`

## Mode Banner and Bot Discovery

**Display mode banner based on `WATCH_MODE`:**

If `WATCH_MODE` is `true` (default):
```
🔄 Watch mode enabled (default) — will loop until all review bots approve.
   Tip: Use /address-review [PR] --no-watch to exit after one fix cycle.
```

If `WATCH_MODE` is `false`:
```
⏩ No-watch mode — will fix comments once and exit. You may need to re-run if bots leave new feedback.
```

**Discover review bots on this PR** (only when `WATCH_MODE` is `true`):

Query the PR for all unique comment/review authors and match against the bot registry:

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

Match the returned authors against the bot registry table above. For each match, note:
- The bot's login
- Its approval detection tier (1 or 2)
- Its re-review trigger command (if any)

Display the discovered bots:
- If bots found: `"Monitoring reviews from: codex, coderabbitai"` (list only matched bots)
- If no bots found: `"No review bots detected on this PR. Running one fix cycle."`
  - In this case, complete the full fix cycle including CI verification (Steps 1-11) but skip Step 12 (no bot re-review polling needed)

---

## Step 1: Checkout PR Branch and Rebase

**This is the FIRST thing you must do. Do NOT skip ahead to fetching review comments.**

### 1a. Get PR number and checkout

```bash
PR_NUM="${PR_ARG:-$(gh pr view --json number --jq '.number')}"
echo "Working on PR #$PR_NUM"
gh pr checkout "$PR_NUM"
```

This is idempotent (no-op if already on the right branch) and handles same-repo PRs, fork PRs, and branch tracking automatically. It also ensures you are NOT on `main` or `master`.

### 1b. Check if behind base branch and rebase

Identify the remote that points to the PR's base repository by matching the `owner/repo` path:

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
  echo "Error: No remote found pointing to the base repository ($BASE_OWNER_REPO)"
  echo "Please add a remote for the base repository and try again."
  exit 1
fi

git fetch "$BASE_REMOTE" "$BASE_BRANCH"
BEHIND=$(git rev-list --count "HEAD..${BASE_REMOTE}/${BASE_BRANCH}")
echo "Commits behind ${BASE_REMOTE}/${BASE_BRANCH}: $BEHIND"
```

**If `$BEHIND` is 0:** No rebase needed, proceed to Step 2.

**If `$BEHIND` is greater than 0:**

1. Check working tree is clean:
   ```bash
   git status --porcelain
   ```
   **If dirty, STOP.** Use AskUserQuestion to ask how to proceed (stash, commit, or abort). Do not rebase until the working tree is clean.

2. Rebase onto base branch:
   ```bash
   git rebase "${BASE_REMOTE}/${BASE_BRANCH}"
   ```

3. **If rebase conflicts occur:**
   - Read each conflicting file and resolve intelligently
   - After resolving each file: `git add <file>`
   - Continue: `git rebase --continue`
   - If too complex, **STOP and ask the user**

4. Force-push the rebased branch to the PR's head branch:
   ```bash
   PR_HEAD_BRANCH=$(gh pr view "$PR_NUM" --json headRefName --jq '.headRefName')
   BRANCH_REMOTE=$(git config "branch.$(git branch --show-current).remote")
   git push --force-with-lease "$BRANCH_REMOTE" "HEAD:$PR_HEAD_BRANCH"
   ```
   Note: After `gh pr checkout`, the branch's remote is correctly configured (fork remote for fork PRs, `origin` for same-repo PRs). We push to the explicit PR head branch name to handle cases where the local branch was renamed.

5. Inform the user of the rebase.

### 1c. Wait for CI after rebase

**Only run this if a rebase was performed in 1b.**

Wait for CI checks to pass (handles both GitHub Actions and external CI providers):

```bash
for i in 1 2 3 4 5; do sleep 10 && gh pr checks "$PR_NUM" --watch && break; done
```

**After the loop, verify CI status:**

```bash
gh pr checks "$PR_NUM"
```

- If all checks show `pass`: Proceed to Step 2.
- If any checks show `fail`: Analyze the failure, fix, commit, push, and re-watch until green.
- If "no checks reported" after 5 retries: The repo may not have CI configured. Proceed with caution, but note this to the user.

**Do not proceed to Step 2 until all CI checks pass (or confirmed no CI is configured).**

---

## Step 2: Fetch All Review Feedback

GitHub has two types of review feedback:
1. **Review threads** (line-specific comments) - CAN be auto-resolved via GraphQL
2. **Review comments** (general feedback from CHANGES_REQUESTED reviews) - CANNOT be auto-resolved, only the reviewer can approve

### 2a. Fetch review threads (resolvable)

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

### 2b. Fetch pending reviews (not auto-resolvable)

```bash
gh pr view "$PR_NUM" --json reviews --jq '.reviews[] | select(.state == "CHANGES_REQUESTED")'
```

---

## Step 3: Display and Categorize Comments

### Categorize feedback into two groups:

**Group A - Resolvable threads** (from GraphQL `reviewThreads`):
- Thread ID (needed for resolution later)
- File path and line number
- Comment body
- Author username (track for re-review in Step 10)
- These CAN be auto-resolved after fixing

**Group B - Pending reviews** (from `reviews` with `state: CHANGES_REQUESTED`):
- Review body/comments
- Author username (track for re-review in Step 10)
- These CANNOT be auto-resolved - the reviewer must approve

### Track unique reviewers

Build a list of unique reviewer usernames from both groups (only reviewers who actually left feedback on THIS PR). This list drives Step 10 — only these reviewers will be contacted for re-review.

### If no feedback found:

If there are no unresolved threads AND no pending reviews:

- **If `CURRENT_PHASE` is `fixing` AND `WATCH_MODE` is `true` AND bots were detected:** A fix cycle ran (we pushed changes) but bots haven't re-reviewed yet. Set phase to `watching` and skip to Step 12.
- **If `CURRENT_PHASE` is empty/unset (fresh run):** The PR is already clean — no fixes were needed and no push occurred. Bots have nothing new to review. Output `<done>COMPLETE</done>`.
- **If `WATCH_MODE` is `true` AND no bots detected:** No feedback and nothing to watch for → output `<done>COMPLETE</done>`.
- **If `WATCH_MODE` is `false`:** No feedback to address → output `<done>COMPLETE</done>`.

**Phase set code for post-fix-cycle "no feedback" path (only when `CURRENT_PHASE` is `fixing`):**

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

Note: `BOT_REVIEW_BASELINE` should already be set from Step 6 in this path since a fix cycle ran.

### If only pending reviews (no threads):

Address the feedback, but note to the user:
> "This PR has pending review feedback that cannot be auto-resolved. After pushing fixes, you'll need to request re-review from the reviewer."

---

## Step 4: Address Each Comment

For each unresolved review comment:

### 4a. Understand the Request

Read the comment carefully. Determine what change is being requested:
- Code style fix?
- Logic change?
- Documentation update?
- Test addition?
- Refactoring?

### 4b. Locate the Code

Use the file path and line number from the thread to find the relevant code:

```bash
# Read the file around the commented line
```

### 4c. Make the Fix

Edit the code to address the feedback. Follow these principles:
- Make the **minimal change** that addresses the comment
- Follow existing code patterns
- Don't introduce unrelated changes

### 4d. Validate Fix Against Feedback

After making each fix, verify it actually addresses what the reviewer asked for:

1. **Re-read the reviewer's comment** — what specifically did they request?
2. **Compare your change** — does it match the reviewer's intent, not just the literal words?
3. **Check for completeness** — did you address the full comment, or only part of it?
4. **Avoid mechanical edits** — a find-and-replace or surface-level change may not satisfy the underlying concern

If the fix doesn't match the reviewer's intent, revise before moving to the next comment.

### 4e. Track the Fix

Keep a mental note of:
- Thread ID
- What was fixed
- Brief explanation for the reply

---

## Step 5: Verify Fixes Locally

Before committing, run the full verification checklist. **All must pass before proceeding:**

- **Build**: `go build ./...` — confirm compilation succeeds
- **All tests**: `go test ./...` — confirm ALL tests pass (not just changed code)
- **Lint**: `golangci-lint run` (if available) — confirm no lint issues
- **Build logs**: If a dev server is running (Air, Vite, Webpack, etc.), check its log output for errors

If any step fails, fix the issue and re-run until all green. This catches problems locally before pushing, avoiding CI round-trip delays.

---

## Step 6: Commit and Push All Fixes

After verification passes, bundle changes into a single commit:

```bash
git add -A
git commit -m "address review comments

- [brief summary of each fix]"
git push
```

**CRITICAL: Capture the bot review baseline timestamp IMMEDIATELY after pushing.** This is the reference point for detecting post-push bot reviews. Capturing it now (right after push) ensures that bots reviewing during CI/Steps 7-11 are correctly detected as post-push reviews.

```bash
BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Bot review baseline captured: $BOT_REVIEW_BASELINE"
```

Store this value and use it in all Step 12a bot checks. Do NOT recompute it later.

---

## Step 7: Watch CI

After pushing, watch CI and fix any failures:

```bash
gh pr checks "$PR_NUM" --watch
```

### If "no checks reported":

CI takes time to register after a push. **Wait 10 seconds and retry, up to 3 times**, before concluding there are no checks:

```bash
for i in 1 2 3; do sleep 10 && gh pr checks "$PR_NUM" --watch && break; done
```

If still no checks after retries, verify the repo actually has CI workflow files:

```bash
find .github/workflows -maxdepth 1 -name '*.yml' -o -name '*.yaml' 2>/dev/null | head -1 | grep -q . || echo "No workflow files found"
```

Only conclude there are no CI checks if no `.yml`/`.yaml` workflow files exist. If workflow files exist, the checks are likely still propagating — wait longer and retry.

### If CI fails:

1. Get failure details:
   ```bash
   gh pr checks "$PR_NUM" --json name,state,description
   ```

2. Analyze the failure (test errors, lint issues, build failures)

3. Fix the issue

4. Commit and push:
   ```bash
   git add -A
   git commit -m "fix: address CI failure"
   git push
   ```

5. Return to watching CI:
   ```bash
   gh pr checks "$PR_NUM" --watch
   ```

**Do not proceed to Step 8 until all CI checks pass.**

---

## Step 8: Reply to Each Comment

For each addressed comment, post a reply explaining the fix:

```bash
gh pr comment "$PR_NUM" --body "Fixed in latest commit: [brief explanation of what was changed]"
```

**Reply guidelines:**
- Keep replies brief and professional
- Reference the specific change made
- Don't be defensive or argumentative

---

## Step 9: Resolve Review Threads (Group A only)

**CRITICAL:** Only resolve threads after CI passes and fixes are pushed.

**This only applies to line-specific review threads (Group A).** Pending reviews (Group B) cannot be auto-resolved.

For each thread ID collected in Step 3 (Group A), resolve it via GraphQL:

```bash
gh api graphql -f query='
  mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) {
      thread { isResolved }
    }
  }
' -f threadId="THREAD_ID_HERE"
```

**Repeat for each unresolved thread.**

---

## Step 10: Request Re-review From Actual Reviewers Only (Data-Driven)

**CRITICAL: This step is entirely data-driven. You iterate the reviewer list from Step 3 and look up trigger commands in the Bot Registry. You NEVER iterate the Bot Registry to find bots to contact.**

### 10a. Query actual reviewers from the PR

Fetch the current list of unique authors who left reviews or thread comments on this PR:

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')

ACTUAL_REVIEWERS=$(gh api graphql -f query='
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

echo "Actual reviewers on PR: $ACTUAL_REVIEWERS"
```

Cross-reference this list with the Step 3 reviewer list. Only proceed with reviewers that appear in BOTH.

If the reviewer list is empty (no reviewers left feedback), skip this entire step.

### 10b. Check for bot re-review opt-out

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
if [ -f "$REPO_ROOT/CLAUDE.md" ] && grep -q "DISABLE_BOT_REREVIEW=true" "$REPO_ROOT/CLAUDE.md"; then
  echo "Bot re-review disabled by project settings"
fi
```

**If `DISABLE_BOT_REREVIEW=true` is found:** Skip bot re-reviews. Only request re-review from human reviewers.

### 10c. Request re-review from bot reviewers (data-driven lookup)

**For each reviewer in the actual reviewer list from 10a:**

1. Check if the login matches any entry in the Bot Registry table (from the "Bot Registry" section above)
2. If it matches AND has a re-review trigger command → post the trigger:
   ```bash
   gh pr comment "$PR_NUM" --body "<trigger command from registry>"
   ```
3. If it matches but has no trigger command (e.g., `copilot-pull-request-review[bot]`) → skip, log: "Skipping <login>: no re-trigger mechanism available"
4. If it's on the ignore list (`github-actions[bot]`, `dependabot[bot]`, etc.) → skip silently
5. If it doesn't match any registry entry and looks like a bot (contains `[bot]` or `bot` suffix) → skip, log: "Skipping unknown bot <login>: no trigger command known"

**Never iterate the Bot Registry to find bots. Always iterate actual reviewers and look up triggers.**

### 10d. Request re-review from human reviewers who left feedback

For human reviewers from your Step 3 list who left CHANGES_REQUESTED:

```bash
gh pr edit "$PR_NUM" --add-reviewer "REVIEWER_USERNAME"
```

### 10e. Inform the user

After requesting re-reviews, list who was contacted and why. If no re-reviews were requested, say so.

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

If count is 0, all threads are resolved.

Confirm CI is passing:

```bash
gh pr checks "$PR_NUM"
```

---

## Phase Transition

Before entering the watch loop, update the loop state phase so that any stop-hook re-entry resumes at Step 12 instead of restarting the fix cycle:

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
  echo "Phase set to: watching"
fi
```

**Note:** `BOT_REVIEW_BASELINE` should already be set from Step 6 (right after the push). If for some reason it wasn't captured earlier (e.g., re-entry after context loss), capture it now as a fallback.

**CRITICAL: Persist the baseline in the state file** so it survives context-loss re-entry:

```bash
if [ -z "$BOT_REVIEW_BASELINE" ]; then
  BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "Bot review baseline captured (fallback): $BOT_REVIEW_BASELINE"
fi

# Persist baseline in state file for re-entry
if [ -f "$LOOP_STATE_FILE" ]; then
  if grep -q '^bot_review_baseline:' "$LOOP_STATE_FILE"; then
    sed -i '' "s/^bot_review_baseline: .*/bot_review_baseline: $BOT_REVIEW_BASELINE/" "$LOOP_STATE_FILE" 2>/dev/null || sed -i "s/^bot_review_baseline: .*/bot_review_baseline: $BOT_REVIEW_BASELINE/" "$LOOP_STATE_FILE"
  else
    sed -i '' "/^phase:/a\\
bot_review_baseline: $BOT_REVIEW_BASELINE" "$LOOP_STATE_FILE" 2>/dev/null || sed -i "/^phase:/a bot_review_baseline: $BOT_REVIEW_BASELINE" "$LOOP_STATE_FILE"
  fi
  echo "Bot review baseline persisted: $BOT_REVIEW_BASELINE"
fi
```

---

## Step 12: Watch for Bot Re-review (default, skipped with --no-watch)

**Skip this entire step if `WATCH_MODE` is `false` or no review bots were detected in the Bot Discovery step.**

### 12a. Check if all bots have approved

For each bot discovered in the Bot Discovery step, check approval using the bot-specific detection logic from the Bot Registry:

**CodeRabbit (`coderabbitai[bot]`):** Query latest review state:

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')

gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviews(last: 100) {
          nodes {
            author { login }
            state
          }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq -r '
  [.data.repository.pullRequest.reviews.nodes[] | select(.author.login == "coderabbitai[bot]")] | last | .state
'
```

If result is `APPROVED` → done. If `CHANGES_REQUESTED` → still has issues.

**Codex (`chatgpt-codex-connector[bot]`):** Check for the "all clear" issue comment:

```bash
gh api "repos/$OWNER/$REPO/issues/$PR_NUM/comments" --jq '
  [.[] | select(.user.login == "chatgpt-codex-connector[bot]")] | last | .body
'
```

If the latest comment body contains `"Didn't find any major issues"` → done. If the bot posted `COMMENTED` reviews with P1/P2 inline comments after the last push → still has issues. Also check: if the `@codex review` trigger comment has a 👀 (eyes) reaction but no 👍 (thumbs up) yet, the bot is still processing.

**Greptile (`greptileai`):** Check status check result:

```bash
gh pr checks "$PR_NUM" --json name,state | jq '.[] | select(.name | test("greptile"; "i"))'
```

If the Greptile check shows `pass` AND no new inline comments were posted since last push → done.

**Copilot (`copilot-pull-request-review[bot]`):** Timestamp-based check — verify the bot posted a NEW review AFTER the baseline captured in Phase Transition:

```bash
# Use BOT_REVIEW_BASELINE captured in Phase Transition (do NOT recompute here).
# This ensures the baseline stays fixed across polling iterations.
echo "Using bot review baseline: $BOT_REVIEW_BASELINE"

COPILOT_STATUS=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviews(last: 100) {
          nodes {
            author { login }
            createdAt
          }
        }
        reviewThreads(first: 100) {
          nodes {
            isResolved
            comments(first: 1) {
              nodes {
                author { login }
                createdAt
              }
            }
          }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq --arg push "$BOT_REVIEW_BASELINE" --arg bot "copilot-pull-request-review[bot]" '
  {
    has_post_push_review: ([.data.repository.pullRequest.reviews.nodes[] | select(.author.login == $bot and .createdAt > $push)] | length > 0),
    unresolved_threads: [.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | select(.comments.nodes[0].author.login == $bot and .comments.nodes[0].createdAt > $push)] | length
  }
')
echo "Copilot status: $COPILOT_STATUS"
```

Interpret the result:
- `has_post_push_review: true` AND `unresolved_threads: 0` → bot re-reviewed and approved (done)
- `has_post_push_review: true` AND `unresolved_threads > 0` → bot re-reviewed and found new issues (not done)
- `has_post_push_review: false` → bot hasn't re-reviewed yet (not done, keep waiting)

Note: Copilot cannot be re-triggered via comment (see 12d).

**Claude (`claude[bot]`):** Same timestamp-based check as Copilot but for `claude[bot]`:
- Use `BOT_REVIEW_BASELINE` captured in Phase Transition (do NOT recompute)
- Check if `claude[bot]` posted a NEW review AFTER that baseline
- If post-push review exists with 0 new unresolved threads → done
- If no post-push review → hasn't re-reviewed yet (keep waiting)

**If ALL detected bots are done → output `<done>COMPLETE</done>` and stop.**

### 12b. Wait for bot re-review (quiet period detection)

If any bot hasn't approved yet:

1. **Record baseline:** Get the current count of reviews + thread comments per pending bot.

2. **Poll every 15 seconds:**
   ```bash
   sleep 15
   ```
   Then re-query review/comment counts via the same GraphQL queries.

3. **Quiet period detection:**
   - If counts changed since last poll → reset quiet timer, bot is still posting. Keep polling.
   - If counts are stable for 2 consecutive polls (30 seconds of no new activity) → bot has finished posting. Proceed to 12c.

4. **Timeout:** If 5 minutes pass with no new activity from any bot AND bots haven't approved:
   - Use `AskUserQuestion` to ask: "Bots haven't responded after 5 minutes. Would you like to keep waiting, re-trigger bot reviews, or exit?"
   - If "keep waiting" → reset timeout, continue polling
   - If "re-trigger" → go to 12d
   - If "exit" → output `<done>COMPLETE</done>`

### 12c. New comments found — loop back to Step 2

After the quiet period ends and new unresolved comments/threads exist:

**First, clear the `watching` phase** so stop-hook re-entry runs the fix cycle instead of skipping to Step 12:

```bash
SAFE_LOOP_NAME=$(echo "address-review-${RESOLVED_PR:-auto}" | sed 's/[^a-zA-Z0-9_-]/-/g')
LOOP_STATE_FILE=".claude/${SAFE_LOOP_NAME}.loop.local.md"
if [ -f "$LOOP_STATE_FILE" ]; then
  sed -i '' "s/^phase: .*/phase: fixing/" "$LOOP_STATE_FILE" 2>/dev/null || sed -i "s/^phase: .*/phase: fixing/" "$LOOP_STATE_FILE"
  echo "Phase reset to: fixing (new bot feedback detected)"
fi
```

Then:

1. Re-fetch all review feedback (Step 2) but **only address NEW unresolved comments** from bots. Already-resolved threads stay resolved.
2. Loop back through Steps 2-11 for the new feedback only.
3. After completing the fix cycle, return to Step 12a to re-check approval status (the Phase Transition section will set phase back to `watching`).

### 12d. No new comments but bot hasn't approved — re-trigger

If a bot's quiet period ended with no new comments but it still hasn't approved:

1. Look up the bot's re-review trigger command from the Bot Registry.
2. If a trigger exists → post it:
   ```bash
   gh pr comment "$PR_NUM" --body "<trigger command>"
   ```
3. **Max 3 re-trigger attempts per bot.** Track the count.
4. If 3 attempts exhausted → use `AskUserQuestion`: "Bot <login> hasn't approved after 3 re-trigger attempts. Keep trying, skip this bot, or exit?"
5. After re-triggering → return to 12b to wait again.

---

## Completion Criteria

### With `--no-watch` (single fix cycle, no watch loop):

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. PR branch is rebased onto latest base branch (or was already up to date)
2. All review feedback (threads AND pending reviews) has been addressed with code changes
3. Each fix has been validated against the reviewer's intent (not just mechanical edits)
4. Local verification passes (`go build`, `go test`, `golangci-lint`)
5. Changes are committed and pushed
6. CI checks pass (`gh pr checks` shows all green)
7. Replies have been posted to each comment
8. All resolvable review threads (Group A) are resolved via GraphQL
9. Re-review requested from reviewers who actually left feedback on this PR (data-driven from Step 10):
   - Bot reviewers that left feedback: via trigger command from Bot Registry (one per bot)
   - Human reviewers that left feedback: via `gh pr edit --add-reviewer`
   - If no bots reviewed, no bot re-review comments were posted

### Default (watch mode):

All conditions from `--no-watch` above, PLUS:

10. All detected review bots have signaled approval (per their bot-specific detection from Step 12a):
    - CodeRabbit: latest review state is `APPROVED`
    - Codex: latest issue comment contains "Didn't find any major issues"
    - Greptile: status check passes with no new inline comments
    - Copilot/Claude: no unresolved threads from the bot
11. If no review bots were detected, watch mode still completes the full fix cycle including CI verification (Steps 1-11) but skips Step 12 (no bot re-review polling needed)

**Note:** Pending reviews (CHANGES_REQUESTED) cannot be auto-resolved. Do NOT request review from bots or services that never reviewed this PR.

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.

Use extended thinking for complex analysis.
