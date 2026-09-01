# Context, Mode Banner & Bot Discovery

## Context

Gather the PR context from the REST metadata already selected by the top-level
current-PR lookup:

```bash
PR_NUM="$RESOLVED_PR"
PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=pr-metadata-api-failure
}

jq '{
  number,
  title,
  state,
  body,
  headRefName: .head.ref,
  headSha: .head.sha,
  headRepository: .head.repo.full_name,
  baseRefName: .base.ref,
  baseRepository: .base.repo.full_name
}' <<< "$PR_JSON"
echo "Current branch: $(git -C "$WORKTREE_PATH" branch --show-current 2>/dev/null || echo unknown)"
echo "Default branch: $(jq -r '.base.ref' <<< "$PR_JSON")"
echo "PR number: $PR_NUM"
```

If REST metadata cannot be loaded, follow the top-level **Hard Invariant
Failure** procedure before checkout, feedback retrieval, edits, or pushes.

## Mode Banner and Bot Discovery

**Display mode banner:**

If `WATCH_MODE` is `true`: `🔄 Watch mode enabled (default) — will loop until all review bots approve. Tip: Use /address-review [PR] --no-watch to exit after one fix cycle.`

If `WATCH_MODE` is `false`: `⏩ No-watch mode — will fix comments once and exit.`

**Discover review bots** (only when `WATCH_MODE` is `true`):

```bash
OWNER=$(jq -er '.base.repo.owner.login' <<< "$PR_JSON")
REPO=$(jq -er '.base.repo.name' <<< "$PR_JSON")

FORMAL_REVIEWS=$(cd "$WORKTREE_PATH" && github_pr_reviews "$PR_NUM") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=review-api-failure
}
FORMAL_REVIEW_AUTHORS=$(jq -r '.[].user.login // empty' <<< "$FORMAL_REVIEWS")

ISSUE_COMMENT_PAGES=$(gh api --paginate --slurp "repos/$REPO_SLUG/issues/$PR_NUM/comments?per_page=100") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=issue-comment-api-failure
}
ISSUE_COMMENT_AUTHORS=$(jq -r '.[][] | .user.login // empty' <<< "$ISSUE_COMMENT_PAGES")

THREAD_RESULT=$(cd "$WORKTREE_PATH" && gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
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
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=review-thread-api-failure
}
THREAD_REVIEW_AUTHORS=$(jq -r '
  .data.repository.pullRequest.reviewThreads.nodes[]?.comments.nodes[]?.author.login // empty
' <<< "$THREAD_RESULT")

if printf '%s\n' "$ISSUE_COMMENT_AUTHORS" | grep -qx 'chatgpt-codex-connector\[bot\]'; then
  THREAD_REVIEW_AUTHORS=$(printf '%s\n' "$THREAD_REVIEW_AUTHORS" | sed 's/^chatgpt-codex-connector$/chatgpt-codex-connector[bot]/')
fi

BOT_AUTHORS=$(printf '%s\n%s\n%s\n' "$FORMAL_REVIEW_AUTHORS" "$ISSUE_COMMENT_AUTHORS" "$THREAD_REVIEW_AUTHORS" | jq -Rsc '
  split("\n") | map(select(length > 0)) | unique | .[]
')

echo "All unique authors on PR: $BOT_AUTHORS"
```

Treat a REST review, REST issue-comment, or GraphQL review-thread failure as a hard
invariant failure. Do not interpret missing API data as an empty reviewer list.

Match authors against the bot registry (read `bot-registry.md` for the full table). Display discovered bots or "No review bots detected on this PR." If no bots found: complete fix cycle (Steps 1-11) but skip Step 12.
