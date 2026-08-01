# Ship — Phase 4: Bot Discovery and Watch (Step 11)

Loaded by `skills/ship/SKILL.md` Phase 4.

## 11a. Discover review bots

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/bot-registry.md` for the bot registry table.

Query all author sources. Formal reviews and top-level PR comments have REST
endpoints. Review-thread comments remain the GraphQL exception because REST
cannot discover review threads.

```bash
if ! FORMAL_REVIEWS=$(cd "$WORKTREE_PATH" && github_pr_reviews "$PR_NUM"); then
  WORKFLOW_REASON="bot-reviews-api-error"
fi
FORMAL_REVIEW_AUTHORS=$(jq -r '.[].user.login // empty' <<< "$FORMAL_REVIEWS")

if ! ISSUE_COMMENT_PAGES=$(gh api --paginate --slurp "repos/$REPO_SLUG/issues/$PR_NUM/comments?per_page=100"); then
  WORKFLOW_REASON="bot-comments-api-error"
fi
TOP_LEVEL_COMMENT_AUTHORS=$(jq -r '.[][]?.user.login // empty' <<< "$ISSUE_COMMENT_PAGES")

if ! REPOSITORY=$(gh api "repos/$REPO_SLUG"); then
  WORKFLOW_REASON="repository-api-error"
fi
OWNER=$(jq -er '.owner.login' <<< "$REPOSITORY")
REPO=$(jq -er '.name' <<< "$REPOSITORY")

if ! THREAD_COMMENT_AUTHORS=$(cd "$WORKTREE_PATH" && gh api graphql -f query='
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
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq -r '
  .data.repository.pullRequest.reviewThreads.nodes[]?.comments.nodes[]?.author.login // empty
'); then
  WORKFLOW_REASON="review-threads-api-error"
fi

BOT_AUTHORS=$(jq -rn \
  --arg formal "$FORMAL_REVIEW_AUTHORS" \
  --arg threads "$THREAD_COMMENT_AUTHORS" \
  --arg top "$TOP_LEVEL_COMMENT_AUTHORS" '
    [$formal, $threads, $top]
    | map(split("\n")[])
    | map(select(length > 0))
    | unique[]
  ')
```

Each failed API call follows **Hard Invariant Failure** with its supplied
`WORKFLOW_REASON`; do not interpret missing source data as no configured bot.

Also inspect the exact pushed head for bots that signal only through a check run
or commit status, such as Greptile:

```bash
if ! CHECK_SNAPSHOT=$(cd "$WORKTREE_PATH" && github_check_snapshot "$HEAD_SHA"); then
  WORKFLOW_REASON="bot-checks-api-error"
fi
if ! PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM"); then
  WORKFLOW_REASON="bot-pr-api-error"
fi
CURRENT_PR_HEAD=$(jq -er '.head.sha' <<< "$PR_JSON")
if [ "$CURRENT_PR_HEAD" != "$HEAD_SHA" ]; then
  WORKFLOW_REASON="bot-watch-head-shift"
fi
CHECK_BOTS=$(jq -r '.items[].name' <<< "$CHECK_SNAPSHOT")
```

An API failure follows **Hard Invariant Failure**. A head shift returns to Step
10d recovery and never counts the old snapshot as approval. An empty snapshot
does not satisfy bot approval; it contributes no status-only bot and continues
through the bounded discovery policy below.

Match both `BOT_AUTHORS` and `CHECK_BOTS` against the bot registry.

## No bots detected yet

This may be because async bots have not posted their first review. Resolve this
as a **driver-resolvable gate**:

1. If `BOT_REVIEW_BASELINE` is less than 2 minutes old, wait until the baseline
   is at least 2 minutes old, polling every 30 seconds.
2. Poll up to 3 additional times at 30-second intervals.
3. If no registered bot appears, state `Decision`, `Evidence`, and `Rationale`,
   record that no review bot is configured for this PR, and proceed to Step 13.

Do not request input for this bounded observation.

## Persist discovered bots

Store as a comma-separated list:

```bash
# e.g., discovered_bots: chatgpt-codex-connector[bot],coderabbitai[bot]
set_loop_field "$STATE_FILE" "discovered_bots" "$DISCOVERED_BOTS_CSV" "$WORKFLOW_STATE_PATH"
```

## 11b. Poll for bot approval

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/watch-loop.md` and follow Steps 12a-12d. Outcomes:

- **All bots approved** → proceed to Step 13 (merging)
- **New comments / `CHANGES_REQUESTED`** → go to Step 12 (address feedback)
- **Timeout (5 min)** → apply the deterministic re-trigger or incomplete
  outcome from `watch-loop.md`
