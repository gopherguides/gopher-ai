# Ship — Phase 4: Bot Discovery and Watch (Step 11)

Loaded by `commands/ship.md` Phase 4.

## 11a. Discover review bots

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/bot-registry.md` for the bot registry table.

Query **all** author sources — formal reviews, review thread comments, AND top-level PR comments — since some bots (e.g., Claude) signal via ordinary PR comments:

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')

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
        comments(first: 100) {
          nodes {
            author { login }
          }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq -r '
  [
    .data.repository.pullRequest.reviews.nodes[].author.login,
    .data.repository.pullRequest.reviewThreads.nodes[].comments.nodes[].author.login,
    .data.repository.pullRequest.comments.nodes[].author.login
  ] | unique | .[]
')
```

Also check PR status checks for bots that signal via commit statuses (e.g., Greptile):

```bash
CHECK_BOTS=$(gh pr checks "$PR_NUM" --json name 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)
```

Match both `BOT_AUTHORS` and `CHECK_BOTS` against the bot registry.

## No bots detected yet

This may be because async bots haven't posted their first review. If `BOT_REVIEW_BASELINE` was captured less than 2 minutes ago, ask via `AskUserQuestion`:

> "No review bots detected yet. The push was recent — bots may still be starting. Wait for bots to respond, or proceed to merge without bot review?"

If the user chooses to wait, poll up to 3 times (30s apart). If still no bots after retries → proceed to Step 13 (merging).

## Persist discovered bots

Store as a comma-separated list:

```bash
# e.g., discovered_bots: chatgpt-codex-connector[bot],coderabbitai[bot]
TMP="$STATE_FILE.tmp"
jq --arg bots "$DISCOVERED_BOTS_CSV" '.discovered_bots = $bots' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## 11b. Poll for bot approval

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/watch-loop.md` and follow Steps 12a-12d. Outcomes:

- **All bots approved** → proceed to Step 13 (merging)
- **New comments / `CHANGES_REQUESTED`** → go to Step 12 (address feedback)
- **Timeout (5 min)** → ask the user via `AskUserQuestion` what to do
