# Context, Mode Banner & Bot Discovery

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
