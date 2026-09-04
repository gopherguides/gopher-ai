# Bot Registry & Re-review Logic

## Bot Registry

Reference table of known review bots. Used ONLY for matching against bots actually found on the PR — never for proactively contacting bots. **CRITICAL: Most PRs have ZERO bots. If Bot Discovery found no bots, ignore this entire table. Never trigger a bot that has not already reviewed this PR.**

| Login | Approval Signal | Has Issues Signal | Re-review Trigger |
|---|---|---|---|
| `chatgpt-codex-connector[bot]` | Connector-authored `+1` reaction on the current-head `codex-pull-request-review-summary`, or a separate connector-authored clean-result comment with matching `Reviewed commit:` evidence; either requires no unresolved inline comments from the connector | Current-head summary has unresolved inline comments from the connector | `@codex review` |
| `coderabbitai[bot]` | Formal `APPROVED` review state (requires `request_changes_workflow` in `.coderabbit.yaml`) | `CHANGES_REQUESTED` review with inline comments | `@coderabbitai full review` |
| `greptileai` | Greptile status check passes + no inline comments posted | Inline comments on specific file changes | `@greptileai` |
| `copilot-pull-request-review[bot]` | `COMMENTED` review with no inline file comments ("did not comment on any files") | `COMMENTED` review with inline suggestions | Re-request review button in PR sidebar _(no `@` mention trigger)_ |
| `claude[bot]` | `COMMENTED` review or issue comment: `"No issues found."` (or silent) | `COMMENTED` review with inline comments scored by confidence | `@claude` |

## Bot Detection Logic

- **Codex connector**: Only when discovered as `chatgpt-codex-connector[bot]`,
  select its newest REST issue comment containing
  `codex-pull-request-review-summary`. Confirm the commit displayed in that
  summary is the prefix of `PR_HEAD_SHA`, then load
  `repos/$REPO_SLUG/issues/comments/$COMMENT_ID/reactions`. A
  connector-authored `+1` reaction on that current-head summary is one approval
  signal. Select the newest connector-authored issue comment containing
  `Didn't find any major issues` independently from the persistent summary,
  allowing either a straight or curly apostrophe.
  That clean-result comment is a second approval signal only when it contains
  `Reviewed commit:` or `**Reviewed commit:**` followed by a commit prefix
  matching `PR_HEAD_SHA`.
  Either signal counts as current-head approval only when the connector has no
  unresolved inline comments. Unresolved connector inline comments are
  actionable findings. A running summary, a clean-result comment without
  matching reviewed-commit evidence, or a signal for another commit is pending
  or stale and cannot satisfy approval. Re-trigger with `@codex review`.

Evaluate the two approval forms independently, then apply the shared
current-head and unresolved-thread requirements:

```bash
CODEX_SUMMARY_COMMIT=$(sed -n 's/.*`\([0-9a-fA-F]\{7,40\}\)`.*/\1/p' <<< "$CODEX_SUMMARY_BODY" | head -1)
CODEX_REACTION_APPROVED=false
if [ -n "$CODEX_SUMMARY_COMMIT" ] && [[ "$PR_HEAD_SHA" == "$CODEX_SUMMARY_COMMIT"* ]] &&
   jq -e 'any(.[]; .content == "+1" and .user.login == "chatgpt-codex-connector[bot]")' <<< "$CODEX_REACTIONS" >/dev/null; then
  CODEX_REACTION_APPROVED=true
fi

CODEX_CLEAN_RESULT_COMMENT=$(jq -c '[
  .[]
  | select(.user.login == "chatgpt-codex-connector[bot]")
  | select((.body | contains("codex-pull-request-review-summary")) | not)
  | select(.body | test("Didn[\u0027’]t find any major issues"))
] | sort_by(.created_at) | last // empty' <<< "$ISSUE_COMMENTS")
CODEX_CLEAN_RESULT_BODY=$(jq -r '.body // empty' <<< "$CODEX_CLEAN_RESULT_COMMENT")
CODEX_REVIEWED_COMMIT=$(sed -n 's/.*Reviewed commit:\*\{0,2\}[[:space:]]*`\{0,1\}\([0-9a-fA-F]\{7,40\}\).*/\1/p' <<< "$CODEX_CLEAN_RESULT_BODY" | head -1)
CODEX_CLEAN_RESULT_APPROVED=false
if [ -n "$CODEX_REVIEWED_COMMIT" ] && [[ "$PR_HEAD_SHA" == "$CODEX_REVIEWED_COMMIT"* ]]; then
  CODEX_CLEAN_RESULT_APPROVED=true
fi
CODEX_UNRESOLVED_THREADS=$(jq '[
  .data.repository.pullRequest.reviewThreads.nodes[]?
  | select(.isResolved == false)
  | select(any(.comments.nodes[]?; .author.login == "chatgpt-codex-connector"))
] | length' <<< "$THREAD_RESULT")

if [ "$CODEX_UNRESOLVED_THREADS" -eq 0 ] &&
   { [ "$CODEX_REACTION_APPROVED" = true ] || [ "$CODEX_CLEAN_RESULT_APPROVED" = true ]; }; then
  echo "Codex connector approved the current head"
fi
```
- **CodeRabbit**: Only bot that uses formal GitHub review states. Use `github_pr_reviews "$PR_NUM"`, select the newest `coderabbitai[bot]` review by `submitted_at`, and treat `APPROVED` as done.
- **Greptile**: Uses a **status check** (not review states). Use `github_check_snapshot "$PR_HEAD_SHA"`; a successful Greptile item plus no new inline comments means Greptile is satisfied.
- **Copilot**: Always posts `COMMENTED` formal reviews (never `APPROVED` or `CHANGES_REQUESTED`). Inspect its REST formal reviews. If its newest body says it "did not comment on any files" or has no inline comments, it found no issues. It cannot be re-triggered via comment; use the re-request review button in the GitHub PR sidebar.
- **Claude**: Posts `COMMENTED` formal reviews or REST issue comments. If no inline comments above confidence threshold, its signal is "No issues found" or no review. Re-trigger via `@claude` mention.

**Ignore list:** `github-actions[bot]`, `dependabot[bot]`, `renovate[bot]`, `netlify[bot]`, `vercel[bot]` — these are CI/deploy bots, not reviewers.

## Step 10: Request Re-review From Actual Reviewers Only (Data-Driven)

**CRITICAL: This step is entirely data-driven. You iterate the reviewer list from Step 3 and look up trigger commands in the Bot Registry. You NEVER iterate the Bot Registry to find bots to contact.**

### 10a. Query actual reviewers from the PR

Fetch the current list of unique authors who left reviews or thread comments on this PR:

```bash
PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=pr-metadata-api-failure
}
OWNER=$(jq -er '.base.repo.owner.login' <<< "$PR_JSON")
REPO=$(jq -er '.base.repo.name' <<< "$PR_JSON")

FORMAL_REVIEWS=$(cd "$WORKTREE_PATH" && github_pr_reviews "$PR_NUM") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=review-api-failure
}
FORMAL_REVIEWERS=$(jq -r '.[].user.login // empty' <<< "$FORMAL_REVIEWS")

ISSUE_COMMENT_PAGES=$(gh api --paginate --slurp "repos/$REPO_SLUG/issues/$PR_NUM/comments?per_page=100") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=issue-comment-api-failure
}
ISSUE_COMMENT_REVIEWERS=$(jq -r '.[][] | .user.login // empty' <<< "$ISSUE_COMMENT_PAGES")

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
THREAD_REVIEWERS=$(jq -r '
  .data.repository.pullRequest.reviewThreads.nodes[]?.comments.nodes[]?.author.login // empty
' <<< "$THREAD_RESULT")

if printf '%s\n' "$ISSUE_COMMENT_REVIEWERS" | grep -qx 'chatgpt-codex-connector\[bot\]'; then
  THREAD_REVIEWERS=$(printf '%s\n' "$THREAD_REVIEWERS" | sed 's/^chatgpt-codex-connector$/chatgpt-codex-connector[bot]/')
fi

ACTUAL_REVIEWERS=$(printf '%s\n%s\n%s\n' "$FORMAL_REVIEWERS" "$ISSUE_COMMENT_REVIEWERS" "$THREAD_REVIEWERS" | jq -Rsc '
  split("\n") | map(select(length > 0)) | unique | .[]
')

echo "Actual reviewers on PR: $ACTUAL_REVIEWERS"
```

If PR metadata, formal reviews, issue comments, or review threads cannot be loaded, follow the
top-level **Hard Invariant Failure** procedure. An API failure must not produce
an empty reviewer set.

Cross-reference this list with the Step 3 reviewer list. When the canonical
Codex issue-comment author was discovered, treat its GraphQL thread alias
`chatgpt-codex-connector` as `chatgpt-codex-connector[bot]` in both lists.
Only proceed with reviewers that appear in both normalized lists.

If the reviewer list is empty (no reviewers left feedback), skip this entire step.

### 10b. Check for bot re-review opt-out

```bash
REPO_ROOT=$(git -C "$WORKTREE_PATH" rev-parse --show-toplevel)
if [ -f "$REPO_ROOT/CLAUDE.md" ] && grep -q "DISABLE_BOT_REREVIEW=true" "$REPO_ROOT/CLAUDE.md"; then
  echo "Bot re-review disabled by project settings"
fi
```

**If `DISABLE_BOT_REREVIEW=true` is found:** Skip bot re-reviews. Only request re-review from human reviewers.

### 10c. Request re-review from bot reviewers (data-driven lookup)

**FORBIDDEN: Do NOT post trigger commands for bots that are not in the Step 3 reviewer list. If a bot never reviewed this PR, triggering it posts spam on the repository.**

**For each reviewer in the actual reviewer list from 10a:**

1. Check if the login matches any entry in the Bot Registry table above
2. If it matches AND has a re-review trigger command → post the trigger:
   ```bash
   gh pr comment "$PR_NUM" --repo "$REPO_SLUG" --body "<trigger command from registry>"
   ```
3. If it matches but has no trigger command (e.g., `copilot-pull-request-review[bot]`) → skip, log: "Skipping <login>: no re-trigger mechanism available"
4. If it's on the ignore list (`github-actions[bot]`, `dependabot[bot]`, etc.) → skip silently
5. If it doesn't match any registry entry and looks like a bot (contains `[bot]` or `bot` suffix) → skip, log: "Skipping unknown bot <login>: no trigger command known"

For `chatgpt-codex-connector[bot]`, this lookup produces `@codex review` only
when discovered in the actual reviewer list and the Step 3 feedback list.

**Never iterate the Bot Registry to find bots. Always iterate actual reviewers and look up triggers.**

### 10d. Request re-review from human reviewers who left feedback

For human reviewers from your Step 3 list who left CHANGES_REQUESTED:

```bash
jq -cn --arg reviewer "REVIEWER_USERNAME" '{reviewers: [$reviewer]}' |
  gh api --method POST "repos/$REPO_SLUG/pulls/$PR_NUM/requested_reviewers" --input -
```

### 10e. Inform the user

After requesting re-reviews, list who was contacted and why. If no re-reviews were requested, say so.
