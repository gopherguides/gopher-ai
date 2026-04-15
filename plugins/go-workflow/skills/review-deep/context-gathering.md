# Context Gathering: PR Detection, Context Fetching, Diff Generation

This document details the full context gathering procedure for deep review.

## PR Context (when PR detected)

### Fetch PR Metadata

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')
REPO_FULL="$OWNER/$REPO"

PR_FULL=$(gh pr view "$PR_NUM" --json number,title,body,state,baseRefName,closingIssuesReferences,comments,reviews --jq '.' 2>/dev/null)
```

Display a brief summary:

```
**PR #<number>**: "<title>"
- State: <state>
- Base: <baseRefName>
- Comments: <count>
- Reviews: <count>
```

### Fetch Linked Issues

Extract issue numbers from `closingIssuesReferences` and fetch each:

```bash
ISSUE_NUMS=$(echo "$PR_FULL" | jq -r '.closingIssuesReferences[].number' 2>/dev/null)

for NUM in $ISSUE_NUMS; do
  echo "--- Issue #$NUM ---"
  gh issue view "$NUM" --json number,title,body,labels,comments --jq '.' 2>/dev/null
done
```

Display linked issues:

```
**Linked Issues:**
- Issue #<num>: "<title>" (<labels>)
```

### Fetch Review Threads (Unresolved)

Use GraphQL to fetch all review threads with nested comments:

```bash
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

Filter to unresolved threads and track:
- Thread ID
- File path and line number
- Comment bodies with authors
- Whether each appears addressed in the current diff

### Fetch Inline Review Comments

```bash
gh api "repos/$REPO_FULL/pulls/$PR_NUM/comments" --jq '.[] | {path, line, body, user: .user.login}' 2>/dev/null
```

### Fetch Pending Reviews

```bash
gh pr view "$PR_NUM" --json reviews --jq '.reviews[] | select(.state == "CHANGES_REQUESTED")' 2>/dev/null
```

---

## Issue-Only Context (when --issue N provided)

When the user provides `--issue N` without a PR:

```bash
gh issue view "$ISSUE_ARG" --json number,title,body,labels,comments --jq '.' 2>/dev/null
```

This provides requirement context for spec compliance checking without PR-specific data (no review threads, no inline comments).

---

## No Context (no PR, no issue)

When no PR is detected and no `--issue` flag provided:

- Skip all context fetching
- Proceed with diff-only review
- Spec compliance section is omitted from the review output
- Review comments status section is omitted

---

## Repo Guidelines

Auto-detect project guidelines for inclusion in the review:

```bash
if [ -f "AGENTS.md" ]; then
  echo "=== Repo Guidelines (AGENTS.md) ==="
  cat AGENTS.md
elif [ -f "CLAUDE.md" ]; then
  echo "=== Repo Guidelines (CLAUDE.md) ==="
  cat CLAUDE.md
fi
```

Include these guidelines as additional review criteria specific to the project.

---

## Bot Noise Filtering

Silently discard any PR comment or review comment that contains external service usage limit messages. These patterns indicate automated bot noise:

- "reached your Codex usage limits"
- "usage limits for code reviews"
- "see your limits"
- Quota warnings or rate limit notices

These are about external service web/API limits and have no bearing on the review. Never treat them as blockers.

---

## Size Guard

Before assembling the full context block, estimate the total size:

```bash
CONTEXT_SIZE=$(( ${#PR_BODY} + ${#ISSUE_BODIES} + ${#REVIEW_COMMENTS} + ${#INLINE_COMMENTS} ))
echo "Context size: ~$CONTEXT_SIZE characters"
```

**If combined context exceeds ~6000 characters**, use summary format to preserve context window:

### Full Format (context <= 6000 chars)

Include complete PR body, full issue bodies, all comments verbatim, all review thread bodies.

### Summary Format (context > 6000 chars)

- **PR body**: First 300 characters + "..."
- **Issue bodies**: First 150 characters each + "..."
- **PR comments**: Summarize key points (skip "LGTM", "+1", bot noise)
- **Review threads**: Include only unresolved threads, truncate bodies to 200 chars
- **Inline comments**: Include file:line + first 150 chars of body

The goal is to fit all context + the diff + review criteria within the model's effective working memory.
