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

## Step 2: Check for Rebase

**Always check if the PR branch needs rebasing before addressing review comments.** Addressing comments on a stale branch wastes effort — files may have changed, conflicts may exist, and CI will run against outdated code.

### 2a. Ensure we're on the PR branch

Always run `gh pr checkout` to guarantee we're on the correct branch. This is idempotent (no-op if already on the right branch) and handles same-repo PRs, fork PRs, and branch tracking automatically:

```bash
gh pr checkout "$PR_NUM"
```

### 2b. Check if behind and rebase if needed

First, identify the remote that points to the PR's base repository by matching the `owner/repo` path:

```bash
BASE_BRANCH=$(gh pr view "$PR_NUM" --json baseRefName --jq '.baseRefName')

# Extract owner/repo from gh repo view (always returns https://github.com/owner/repo)
BASE_OWNER_REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')

# Find a remote that points to the same owner/repo
# Handles: https://, git@host:, ssh://git@host/ formats and .git suffix
BASE_REMOTE=""
for remote in $(git remote); do
  REMOTE_URL=$(git remote get-url "$remote")
  # Extract owner/repo from any URL format
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

**If `$BEHIND` is 0:** No rebase needed, skip to Step 3.

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
   # Get the PR's actual head branch name (may differ from local branch name)
   PR_HEAD_BRANCH=$(gh pr view "$PR_NUM" --json headRefName --jq '.headRefName')
   BRANCH_REMOTE=$(git config "branch.$(git branch --show-current).remote")
   git push --force-with-lease "$BRANCH_REMOTE" "HEAD:$PR_HEAD_BRANCH"
   ```
   Note: After `gh pr checkout`, the branch's remote is correctly configured (fork remote for fork PRs, `origin` for same-repo PRs). We push to the explicit PR head branch name to handle cases where the local branch was renamed.

5. Inform the user of the rebase.

### 2c. Wait for CI after rebase

**Only run this if a rebase was performed in 2b.**

Wait for CI checks to pass (handles both GitHub Actions and external CI providers):

```bash
for i in 1 2 3 4 5; do sleep 10 && gh pr checks "$PR_NUM" --watch && break; done
```

**After the loop, verify CI status:**

```bash
gh pr checks "$PR_NUM"
```

- If all checks show `pass`: Proceed to Step 3.
- If any checks show `fail`: Analyze the failure, fix, commit, push, and re-watch until green.
- If "no checks reported" after 5 retries: The repo may not have CI configured. Proceed with caution, but note this to the user.

**Do not proceed to Step 3 until all CI checks pass (or confirmed no CI is configured).**

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

Build a list of unique reviewer usernames from both groups (only reviewers who actually left feedback on THIS PR). This list drives Step 11 — only these reviewers will be contacted for re-review.

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

## Step 11: Request Re-review From Actual Reviewers Only

**CRITICAL: Only request re-review from reviewers who actually left feedback on this PR (collected in Step 4). Do NOT request review from bots or services that never reviewed this PR. If a bot like codex, coderabbitai, or greptileai is not in the reviewer list from Step 4, do NOT contact them.**

### 11a. Check the reviewer list from Step 4

Look at the unique reviewers you collected in Step 4. If the list is empty (no reviewers left feedback), skip this entire step.

### 11b. Check for bot re-review opt-out

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
if [ -f "$REPO_ROOT/CLAUDE.md" ] && grep -q "DISABLE_BOT_REREVIEW=true" "$REPO_ROOT/CLAUDE.md"; then
  echo "Bot re-review disabled by project settings"
fi
```

**If `DISABLE_BOT_REREVIEW=true` is found:** Skip bot re-reviews. Only request re-review from human reviewers.

### 11c. Request re-review from bot reviewers who left feedback

**Only do this for bots that appear in your Step 4 reviewer list.** If none of these bots reviewed the PR, skip this sub-step entirely.

Known bot re-review triggers (use ONLY if the bot is in your reviewer list):
- `codex` or `chatgpt-codex-connector` → `gh pr comment "$PR_NUM" --body "@codex review"`
- `coderabbitai` → `gh pr comment "$PR_NUM" --body "@coderabbitai review"`
- `greptileai` → `gh pr comment "$PR_NUM" --body "@greptileai review"`

Ignore CI/dependency bots (`github-actions[bot]`, `dependabot[bot]`, `renovate[bot]`) — they don't do re-reviews.

### 11d. Request re-review from human reviewers who left feedback

For human reviewers from your Step 4 list who left CHANGES_REQUESTED:

```bash
gh pr edit "$PR_NUM" --add-reviewer "REVIEWER_USERNAME"
```

### 11e. Inform the user

After requesting re-reviews, list who was contacted and why. If no re-reviews were requested, say so.

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
9. Re-review requested from reviewers who actually left feedback on this PR (from Step 4 list only):
   - Bot reviewers that left feedback: via `@bot review` comment (one per bot)
   - Human reviewers that left feedback: via `gh pr edit --add-reviewer`
   - If no bots reviewed, no bot re-review comments were posted

**Note:** Pending reviews (CHANGES_REQUESTED) cannot be auto-resolved. Do NOT request review from bots or services that never reviewed this PR.

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.

Use extended thinking for complex analysis.
