---
argument-hint: "[PR-number]"
description: "Address PR review comments, make fixes, reply, and resolve"
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

**Usage:** `/address-review [PR-number]`

**Example:** `/address-review 123` or just `/address-review` on a PR branch

Ask the user: "No PR found for current branch. What PR number would you like to address?"

---

**If PR number is available (from `$ARGUMENTS` or auto-detected):**

## Security Validation

Validate input is numeric:
!if [ -n "$ARGUMENTS" ] && ! echo "$ARGUMENTS" | grep -qE '^[0-9]+$'; then echo "Error: PR number must be numeric"; exit 1; fi

## Loop Initialization

Initialize persistent loop to ensure work continues until complete:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "address-review-${ARGUMENTS:-auto}" "COMPLETE"`

## Context

- PR details: !`PR_NUM="${ARGUMENTS:-$(gh pr view --json number --jq '.number' 2>/dev/null)}"; gh pr view "$PR_NUM" --json title,state,body,headRefName,baseRefName 2>/dev/null || echo "PR not found"`
- Current branch: !`git branch --show-current`
- Default branch: !`git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main"`
- PR number: !`echo "${ARGUMENTS:-$(gh pr view --json number --jq '.number' 2>/dev/null)}"`

---

## Branch Protection

**CRITICAL:** Verify you are NOT on `main`, `master`, or the default branch.

If the current branch is `main`, `master`, or matches the default branch:
1. **STOP** - Do not make changes on the main branch
2. **Check out the PR branch first**:
   ```bash
   gh pr checkout "$PR_NUM"
   ```
3. Then continue with the workflow

---

## Step 1: Get PR Number

Set PR_NUM for use throughout:

```bash
PR_NUM="${ARGUMENTS:-$(gh pr view --json number --jq '.number')}"
echo "Working on PR #$PR_NUM"
```

---

## Known AI/Bot Reviewers

Track these reviewers for automatic re-review requests at the end:

| Bot Username | Re-review Trigger |
|--------------|-------------------|
| `codex`, `chatgpt-codex-connector` | `@codex review` (comment on PR) |
| `copilot` | Add via GitHub Reviewers dropdown |
| `coderabbitai` | `@coderabbitai review` (comment on PR) |
| `greptileai` | `@greptileai review` (comment on PR) |
| `github-actions[bot]` | N/A (CI bot, no re-review) |
| `dependabot[bot]` | N/A (dependency bot, no re-review) |

**To disable auto bot re-review:** Add to your project's CLAUDE.md:
```
## Bot Review Settings
DISABLE_BOT_REREVIEW=true
```

---

## Step 2: Check for Rebase

**CRITICAL: Always check if the PR branch needs rebasing before addressing review comments.**

Addressing comments on a stale branch wastes effort — files may have changed, conflicts may exist, and CI will run against outdated code. Rebase first, then address reviews.

### 2a. Verify we're on the PR branch

**Before any rebase operations, verify the current branch matches the PR's head branch:**

```bash
PR_BRANCH=$(gh pr view "$PR_NUM" --json headRefName --jq '.headRefName')
CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" != "$PR_BRANCH" ]; then
  echo "WARNING: Current branch ($CURRENT_BRANCH) differs from PR branch ($PR_BRANCH)"
  echo "Checking out PR branch..."
  gh pr checkout "$PR_NUM"
fi
```

**If the branches don't match:** Use `gh pr checkout "$PR_NUM"` to switch to the correct branch before proceeding. This prevents accidentally rebasing/force-pushing an unrelated branch.

### 2b. Determine base branch and check if behind

```bash
BASE_BRANCH=$(gh pr view "$PR_NUM" --json baseRefName --jq '.baseRefName')
echo "Base branch: $BASE_BRANCH"

git fetch origin "$BASE_BRANCH"

BEHIND=$(git rev-list --count "HEAD..origin/$BASE_BRANCH")
echo "Commits behind origin/$BASE_BRANCH: $BEHIND"
```

### 2c. If behind, rebase onto base branch

**If `$BEHIND` is greater than 0:**

1. Ensure working tree is clean before rebasing:
   ```bash
   if [ -n "$(git status --porcelain)" ]; then
     echo "ERROR: Working tree has uncommitted changes. Stash or commit before rebasing."
     exit 1
   fi
   ```
   **If dirty, STOP immediately.** Use AskUserQuestion to ask:
   > "Working tree has uncommitted changes. How would you like to proceed?"
   > - Stash changes (`git stash`)
   > - Commit changes first
   > - Abort and let me handle manually

   **Do not proceed to rebase until the working tree is clean.**

2. Perform the rebase:
   ```bash
   git rebase "origin/$BASE_BRANCH"
   ```

3. **If rebase conflicts occur:**
   - List conflicting files: `git diff --name-only --diff-filter=U`
   - Read each conflicting file and resolve conflicts intelligently:
     - Understand the intent of both sides
     - Preserve PR changes where they don't conflict with base
     - Accept base changes for unrelated updates
   - After resolving each file: `git add <file>`
   - Continue the rebase: `git rebase --continue`
   - If conflicts are too complex to resolve automatically, **STOP and ask the user** for guidance

4. Force-push the rebased branch:
   ```bash
   git push --force-with-lease
   ```

5. Inform the user:
   > "Rebased branch onto latest `$BASE_BRANCH` ($BEHIND commits behind). Force-pushed updated branch."

**If `$BEHIND` is 0:** No rebase needed, skip Step 2d and continue directly to Step 3.

### 2d. Wait for CI after rebase (ONLY if rebased)

**IMPORTANT: Only execute this step if `$BEHIND > 0` and a rebase was performed in Step 2c.**

If no rebase was needed (`$BEHIND` was 0), skip this entire section and proceed to Step 3.

If a rebase was performed, wait for CI to pass before addressing comments. Review comments may reference lines that shifted during rebase.

**First, check if the repo has CI configured:**

```bash
if [ "$BEHIND" -gt 0 ]; then
  # Check if repo has workflow files
  REPO_ROOT=$(git rev-parse --show-toplevel)
  HAS_CI=$(find "$REPO_ROOT/.github/workflows" -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | head -1)

  if [ -z "$HAS_CI" ]; then
    echo "No CI workflows found — skipping CI wait"
  else
    echo "Waiting for CI after rebase..."
    for i in 1 2 3; do
      sleep 10
      if gh pr checks "$PR_NUM" --watch; then
        echo "CI passed"
        break
      fi
      if [ "$i" -eq 3 ]; then
        echo "ERROR: CI checks not passing after 3 attempts"
        exit 1
      fi
    done
  fi
fi
```

**If CI checks never pass or the loop exhausts retries (after a rebase):**
- **STOP immediately** — do not proceed to address review comments
- Analyze the CI failure output
- Fix the issue, commit, and push
- Re-run `gh pr checks "$PR_NUM" --watch` until all checks pass
- Only then continue to Step 3

**Do not proceed to address review comments until CI passes on the rebased branch.**

**If no CI workflows exist:** Proceed directly to Step 3 after rebase.

**If no rebase was needed:** Proceed directly to Step 3.

---

## Step 3: Fetch All Review Feedback

GitHub has two types of review feedback:
1. **Review threads** (line-specific comments) - CAN be auto-resolved via GraphQL
2. **Review comments** (general feedback from CHANGES_REQUESTED reviews) - CANNOT be auto-resolved, only the reviewer can approve

### 3a. Fetch review threads (resolvable)

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

### 3b. Fetch pending reviews (not auto-resolvable)

```bash
gh pr view "$PR_NUM" --json reviews --jq '.reviews[] | select(.state == "CHANGES_REQUESTED")'
```

---

## Step 4: Display and Categorize Comments

### Categorize feedback into two groups:

**Group A - Resolvable threads** (from GraphQL `reviewThreads`):
- Thread ID (needed for resolution later)
- File path and line number
- Comment body
- Author username (track for re-review in Step 11)
- These CAN be auto-resolved after fixing

**Group B - Pending reviews** (from `reviews` with `state: CHANGES_REQUESTED`):
- Review body/comments
- Author username (track for re-review in Step 11)
- These CANNOT be auto-resolved - the reviewer must approve

### Track unique reviewers

Build a list of unique reviewer usernames from both groups. Note which are bots vs humans (see "Known AI/Bot Reviewers" table above).

### If no feedback found:

If there are no unresolved threads AND no pending reviews:

```
<done>COMPLETE</done>
```

### If only pending reviews (no threads):

Address the feedback, but note to the user:
> "This PR has pending review feedback that cannot be auto-resolved. After pushing fixes, you'll need to request re-review from the reviewer."

---

## Step 5: Address Each Comment

For each unresolved review comment:

### 5a. Understand the Request

Read the comment carefully. Determine what change is being requested:
- Code style fix?
- Logic change?
- Documentation update?
- Test addition?
- Refactoring?

### 5b. Locate the Code

Use the file path and line number from the thread to find the relevant code:

```bash
# Read the file around the commented line
```

### 5c. Make the Fix

Edit the code to address the feedback. Follow these principles:
- Make the **minimal change** that addresses the comment
- Follow existing code patterns
- Don't introduce unrelated changes

### 5d. Validate Fix Against Feedback

After making each fix, verify it actually addresses what the reviewer asked for:

1. **Re-read the reviewer's comment** — what specifically did they request?
2. **Compare your change** — does it match the reviewer's intent, not just the literal words?
3. **Check for completeness** — did you address the full comment, or only part of it?
4. **Avoid mechanical edits** — a find-and-replace or surface-level change may not satisfy the underlying concern

If the fix doesn't match the reviewer's intent, revise before moving to the next comment.

### 5e. Track the Fix

Keep a mental note of:
- Thread ID
- What was fixed
- Brief explanation for the reply

---

## Step 6: Verify Fixes Locally

Before committing, run the full verification checklist. **All must pass before proceeding:**

- **Build**: `go build ./...` — confirm compilation succeeds
- **All tests**: `go test ./...` — confirm ALL tests pass (not just changed code)
- **Lint**: `golangci-lint run` (if available) — confirm no lint issues
- **Build logs**: If a dev server is running (Air, Vite, Webpack, etc.), check its log output for errors

If any step fails, fix the issue and re-run until all green. This catches problems locally before pushing, avoiding CI round-trip delays.

---

## Step 7: Commit and Push All Fixes

After verification passes, bundle changes into a single commit:

```bash
git add -A
git commit -m "address review comments

- [brief summary of each fix]"
git push
```

---

## Step 8: Watch CI

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

**Do not proceed to Step 9 until all CI checks pass.**

---

## Step 9: Reply to Each Comment

For each addressed comment, post a reply explaining the fix:

```bash
gh pr comment "$PR_NUM" --body "Fixed in latest commit: [brief explanation of what was changed]"
```

**Reply guidelines:**
- Keep replies brief and professional
- Reference the specific change made
- Don't be defensive or argumentative

---

## Step 10: Resolve Review Threads (Group A only)

**CRITICAL:** Only resolve threads after CI passes and fixes are pushed.

**This only applies to line-specific review threads (Group A).** Pending reviews (Group B) cannot be auto-resolved.

For each thread ID collected in Step 4 (Group A), resolve it via GraphQL:

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

## Step 11: Request Re-review

After all fixes are committed and CI passes, request re-review from reviewers.

### 11a. Check for opt-out flag

Before requesting bot re-reviews, check if the project has opted out. Use the repo root to find the project's CLAUDE.md (handles running from subdirectories):

```bash
# Find repo root and check for DISABLE_BOT_REREVIEW=true
REPO_ROOT=$(git rev-parse --show-toplevel)
if [ -f "$REPO_ROOT/CLAUDE.md" ] && grep -q "DISABLE_BOT_REREVIEW=true" "$REPO_ROOT/CLAUDE.md"; then
  echo "Bot re-review disabled by project settings"
fi
```

**If `DISABLE_BOT_REREVIEW=true` is found:** Skip step 11c (bot re-reviews) entirely. Only request re-review from human reviewers.

**If not found or file doesn't exist:** Proceed with bot re-reviews.

### 11b. Identify reviewer types

From the reviewers collected in Step 4, categorize them:

**Bot reviewers** (trigger via PR comment):
- `codex`, `chatgpt-codex-connector` → `@codex review`
- `coderabbitai` → `@coderabbitai review`
- `greptileai` → `@greptileai review`

**Human reviewers** (trigger via GitHub API):
- All other reviewers → `gh pr edit --add-reviewer`

**Skip these bots** (no re-review needed):
- `github-actions[bot]`, `dependabot[bot]`, `renovate[bot]`

### 11c. Request re-review from bot reviewers

**Skip this step if `DISABLE_BOT_REREVIEW=true` was found in step 11a.**

**Before requesting bot re-reviews, inform the user:**

> 🤖 **Auto-requesting re-review from bot reviewers:** [list bots]
>
> This is automatic. To disable, add to your project's CLAUDE.md:
> ```
> ## Bot Review Settings
> DISABLE_BOT_REREVIEW=true
> ```

For each bot reviewer that left feedback, post a single comment requesting re-review:

```bash
# Example for Codex:
gh pr comment "$PR_NUM" --body "@codex review"

# Example for CodeRabbit:
gh pr comment "$PR_NUM" --body "@coderabbitai review"

# Example for Greptile:
gh pr comment "$PR_NUM" --body "@greptileai review"
```

**Important:** Only post ONE comment per bot, even if the bot left multiple comments.

### 11d. Request re-review from human reviewers

For human reviewers who left CHANGES_REQUESTED:

```bash
gh pr edit "$PR_NUM" --add-reviewer "REVIEWER_USERNAME"
```

### 11e. Inform the user

After requesting re-reviews:
> "Requested re-review from: [list of reviewers]. Bot reviewers will automatically review the updated code. Human reviewers will need to manually approve."

---

## Step 12: Verify Completion

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

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. PR branch is rebased onto latest base branch (or was already up to date)
2. All review feedback (threads AND pending reviews) has been addressed with code changes
3. Each fix has been validated against the reviewer's intent (not just mechanical edits)
4. Local verification passes (`go build`, `go test`, `golangci-lint`)
5. Changes are committed and pushed
6. CI checks pass (`gh pr checks` shows all green)
7. Replies have been posted to each comment
8. All resolvable review threads (Group A) are resolved via GraphQL
9. Re-review requested from all reviewers:
   - Bot reviewers: via `@bot review` comment (one per bot)
   - Human reviewers: via `gh pr edit --add-reviewer`

**Note:** Pending reviews (CHANGES_REQUESTED) cannot be auto-resolved. Bot reviewers will automatically re-review. Human reviewers will need to manually approve.

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.

Use extended thinking for complex analysis.
