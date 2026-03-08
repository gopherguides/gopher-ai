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

- **CodeRabbit**: Only bot that uses formal GitHub review states. Query latest review from `coderabbitai[bot]` — if `state == "APPROVED"` → done. This is the most reliable signal.
- **Greptile**: Uses a **status check** (not review states). Check `gh pr checks` for a Greptile check — if it passes and no new inline comments were posted, Greptile is satisfied.
- **Copilot**: Always posts `COMMENTED` reviews (never `APPROVED` or `CHANGES_REQUESTED`). If its review body says it "did not comment on any files" or has no inline comments → no issues found. Cannot be re-triggered via comment — must use the re-request review button in the GitHub PR sidebar.
- **Claude**: Posts `COMMENTED` reviews. If no inline comments above confidence threshold → "No issues found" or no review posted at all. Re-trigger via `@claude` mention.

**Ignore list:** `github-actions[bot]`, `dependabot[bot]`, `renovate[bot]`, `netlify[bot]`, `vercel[bot]` — these are CI/deploy bots, not reviewers.

## Step 10: Request Re-review From Actual Reviewers Only (Data-Driven)

**CRITICAL: This step is entirely data-driven. You iterate the reviewer list from Step 3 and look up trigger commands in the Bot Registry. You NEVER iterate the Bot Registry to find bots to contact.**

### 10a. Query actual reviewers from the PR

Fetch the current list of unique authors who left reviews or thread comments on this PR:

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')

ACTUAL_REVIEWERS=$(gh api graphql -f query='
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

echo "Actual reviewers on PR: $ACTUAL_REVIEWERS"
```

Cross-reference this list with the Step 3 reviewer list. Only proceed with reviewers that appear in BOTH.

If the reviewer list is empty (no reviewers left feedback), skip this entire step.

### 10b. Check for bot re-review opt-out

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
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
   gh pr comment "$PR_NUM" --body "<trigger command from registry>"
   ```
3. If it matches but has no trigger command (e.g., `copilot-pull-request-review[bot]`) → skip, log: "Skipping <login>: no re-trigger mechanism available"
4. If it's on the ignore list (`github-actions[bot]`, `dependabot[bot]`, etc.) → skip silently
5. If it doesn't match any registry entry and looks like a bot (contains `[bot]` or `bot` suffix) → skip, log: "Skipping unknown bot <login>: no trigger command known"

**Never iterate the Bot Registry to find bots. Always iterate actual reviewers and look up triggers.**

### 10d. Request re-review from human reviewers who left feedback

For human reviewers from your Step 3 list who left CHANGES_REQUESTED:

```bash
gh pr edit "$PR_NUM" --add-reviewer "REVIEWER_USERNAME"
```

### 10e. Inform the user

After requesting re-reviews, list who was contacted and why. If no re-reviews were requested, say so.
