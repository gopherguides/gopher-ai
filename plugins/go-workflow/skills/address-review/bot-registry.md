# Bot Registry & Re-review Logic

## Bot Registry

Reference table of known review bots. Used ONLY for matching against bots actually found on the PR — never for proactively contacting bots. **CRITICAL: Most PRs have ZERO bots. If Bot Discovery found no bots, ignore this entire table. Never trigger a bot that has not already reviewed this PR.**

| Login | Approval Signal | Has Issues Signal | Re-review Trigger |
|---|---|---|---|
| `coderabbitai[bot]` | Formal `APPROVED` review state (requires `request_changes_workflow` in `.coderabbit.yaml`) | `CHANGES_REQUESTED` review with inline comments | `@coderabbitai full review` |
| `greptileai` | Greptile status check passes + no inline comments posted | Inline comments on specific file changes | `@greptileai` |
| `copilot-pull-request-review[bot]` | `COMMENTED` review with no inline file comments ("did not comment on any files") | `COMMENTED` review with inline suggestions | Re-request review button in PR sidebar _(no `@` mention trigger)_ |
| `claude[bot]` | `COMMENTED` review or issue comment: `"No issues found."` (or silent) | `COMMENTED` review with inline comments scored by confidence | `@claude` |

## Bot Detection Logic

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

ACTUAL_REVIEWERS=$(printf '%s\n%s\n' "$FORMAL_REVIEWERS" "$THREAD_REVIEWERS" | jq -Rsc '
  split("\n") | map(select(length > 0)) | unique | .[]
')

echo "Actual reviewers on PR: $ACTUAL_REVIEWERS"
```

If PR metadata, formal reviews, or review threads cannot be loaded, follow the
top-level **Hard Invariant Failure** procedure. An API failure must not produce
an empty reviewer set.

Cross-reference this list with the Step 3 reviewer list. Only proceed with reviewers that appear in BOTH.

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

**Never iterate the Bot Registry to find bots. Always iterate actual reviewers and look up triggers.**

### 10d. Request re-review from human reviewers who left feedback

For human reviewers from your Step 3 list who left CHANGES_REQUESTED:

```bash
jq -cn --arg reviewer "REVIEWER_USERNAME" '{reviewers: [$reviewer]}' |
  gh api --method POST "repos/$REPO_SLUG/pulls/$PR_NUM/requested_reviewers" --input -
```

### 10e. Inform the user

After requesting re-reviews, list who was contacted and why. If no re-reviews were requested, say so.
