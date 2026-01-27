---
argument-hint: "[PR-number]"
description: "Address PR review comments, make fixes, reply, and resolve"
model: claude-opus-4-5-20251101
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
- Author
- These CAN be auto-resolved after fixing

**Group B - Pending reviews** (from `reviews` with `state: CHANGES_REQUESTED`):
- Review body/comments
- Author
- These CANNOT be auto-resolved - the reviewer must approve

### If no feedback found:

If there are no unresolved threads AND no pending reviews:

```
<done>COMPLETE</done>
```

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

### 4d. Track the Fix

Keep a mental note of:
- Thread ID
- What was fixed
- Brief explanation for the reply

---

## Step 5: Commit and Push All Fixes

After addressing all comments, bundle changes into a single commit:

```bash
git add -A
git commit -m "address review comments

- [brief summary of each fix]"
git push
```

---

## Step 6: Watch CI

After pushing, watch CI and fix any failures:

```bash
gh pr checks "$PR_NUM" --watch
```

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

**Do not proceed to Step 7 until all CI checks pass.**

---

## Step 7: Reply to Each Comment

For each addressed comment, post a reply explaining the fix:

```bash
gh pr comment "$PR_NUM" --body "Fixed in latest commit: [brief explanation of what was changed]"
```

**Reply guidelines:**
- Keep replies brief and professional
- Reference the specific change made
- Don't be defensive or argumentative

---

## Step 8: Resolve Review Threads (Group A only)

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

## Step 9: Request Re-review (if pending reviews exist)

If there were pending reviews (Group B - CHANGES_REQUESTED), request re-review from those reviewers:

```bash
gh pr edit "$PR_NUM" --add-reviewer "REVIEWER_USERNAME"
```

Inform the user:
> "Requested re-review from [reviewer]. They will need to approve the PR to dismiss their CHANGES_REQUESTED status."

---

## Step 10: Verify Completion

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

1. All review feedback (threads AND pending reviews) has been addressed with code changes
2. Changes are committed and pushed
3. CI checks pass (`gh pr checks` shows all green)
4. Replies have been posted to each comment
5. All resolvable review threads (Group A) are resolved via GraphQL
6. Re-review requested from reviewers who left CHANGES_REQUESTED (Group B)

**Note:** Pending reviews (CHANGES_REQUESTED) cannot be auto-resolved. After requesting re-review, the reviewer must approve. This is expected behavior.

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.

Use extended thinking for complex analysis.
