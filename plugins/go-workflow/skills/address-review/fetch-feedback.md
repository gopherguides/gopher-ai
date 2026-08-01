# Step 2: Fetch All Review Feedback

GitHub has two types: **review threads** (line-specific, auto-resolvable) and **review comments** (general CHANGES_REQUESTED, not auto-resolvable).

## 2a. Fetch review threads

```bash
PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=pr-metadata-api-failure
}
OWNER=$(jq -er '.base.repo.owner.login' <<< "$PR_JSON")
REPO=$(jq -er '.base.repo.name' <<< "$PR_JSON")

(cd "$WORKTREE_PATH" && gh api graphql -f query='
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
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM")
```

## 2b. Fetch pending formal reviews

```bash
FORMAL_REVIEWS=$(cd "$WORKTREE_PATH" && github_pr_reviews "$PR_NUM") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=review-api-failure
}

jq '[
  .[]
  | select(.state == "CHANGES_REQUESTED")
  | {
      id,
      body,
      author: .user.login,
      submittedAt: .submitted_at,
      commitId: .commit_id
    }
]' <<< "$FORMAL_REVIEWS"
```

If the REST review request fails, follow the top-level **Hard Invariant
Failure** procedure. Missing review data is not equivalent to no pending
feedback.
