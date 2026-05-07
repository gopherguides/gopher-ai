# Ship — Phase 6: Merge (Step 13)

Loaded by `commands/ship.md` Phase 6. Owns the final-checks block, merge
strategy detection, mergeStateStatus decision tree, and summary rendering.

**CRITICAL: NEVER use `--admin` flag. NEVER use any flag/method that bypasses branch protection.** If the merge fails due to protection, STOP and inform the user — do NOT retry with elevated privileges.

## 13a. Final checks

1. Verify CI is green (skip if `has_ci=false` in state file): `gh pr checks "$PR_NUM"`

2. Check for unresolved review threads:

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')
UNRESOLVED=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes { isResolved }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length')
```

3. Check for **active** human `CHANGES_REQUESTED` (latest review per human, excluding bots):

```bash
BLOCKING_HUMANS=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        latestReviews(first: 50) {
          nodes {
            author { login }
            state
          }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq '[.data.repository.pullRequest.latestReviews.nodes[] | select(.state == "CHANGES_REQUESTED") | select(.author.login | test("\\[bot\\]$") | not)] | length')
```

If unresolved threads OR active human `CHANGES_REQUESTED` exist, inform the user and ask how to proceed.

## 13b. `--no-merge` early exit

If `NO_MERGE=true`:

- Display the summary (see 13f)
- Output `<done>SHIPPED</done>`
- Stop here

## 13c. Auto-detect merge strategy

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')
MERGE_SETTINGS=$(gh api "repos/$OWNER/$REPO" --jq '{merge: .allow_merge_commit, squash: .allow_squash_merge, rebase: .allow_rebase_merge}' 2>/dev/null || echo '{}')

MERGE_FLAG="--merge"
if echo "$MERGE_SETTINGS" | jq -e '.merge == true' >/dev/null 2>&1; then
  MERGE_FLAG="--merge"
elif echo "$MERGE_SETTINGS" | jq -e '.squash == true' >/dev/null 2>&1; then
  MERGE_FLAG="--squash"
elif echo "$MERGE_SETTINGS" | jq -e '.rebase == true' >/dev/null 2>&1; then
  MERGE_FLAG="--rebase"
fi
```

Prefer merge > squash > rebase (matches GitHub's default fallback chain).

## 13d. Branch protection mergeability check

Query GitHub's mergeability status:

```bash
MERGE_STATE=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        mergeStateStatus
        mergeable
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" --jq '.data.repository.pullRequest')

MERGEABLE=$(echo "$MERGE_STATE" | jq -r '.mergeable')
STATE_STATUS=$(echo "$MERGE_STATE" | jq -r '.mergeStateStatus')

# Check if repo uses a merge queue (URL-encode branch name for slash-containing branches)
ENCODED_BRANCH=$(printf '%s' "$BASE_BRANCH" | jq -sRr @uri)
HAS_MERGE_QUEUE=$(gh api "repos/$OWNER/$REPO/rules/branches/$ENCODED_BRANCH" 2>/dev/null | jq '[.[] | select(.type == "merge_queue")] | length > 0' 2>/dev/null || echo "false")
```

GitHub computes mergeability asynchronously — `UNKNOWN` is a transient state after pushes or check completions.

### Decision tree (strict — do not invent reasons to merge for unhandled states)

| `MERGEABLE` | `STATE_STATUS` | Action |
|-------------|----------------|--------|
| any | `UNKNOWN` | Retry up to 6 times (5s apart). If still `UNKNOWN`, `AskUserQuestion`. |
| `UNKNOWN` | any | Same retry-then-ask. |
| `CONFLICTING` | any | **STOP.** "PR has merge conflicts. Resolve before merging." Cleanup, do NOT output `<done>`. |
| any | `BLOCKED` (with `HAS_MERGE_QUEUE=true`) | Proceed — `gh pr merge` will enqueue. |
| any | `BLOCKED` (no merge queue) | **STOP immediately.** "Branch protection requirements not met (status: BLOCKED). Cannot merge." Cleanup, no `<done>`. |
| any | `CLEAN` or `HAS_HOOKS` | Proceed — all checks passed and requirements satisfied. |
| `MERGEABLE` | `BEHIND` | Proceed. `BEHIND` only means base moved forward; GitHub still allows merging unless the repo requires up-to-date branches (caught by 13e on failure). |
| `MERGEABLE` | `UNSTABLE` | Proceed. Non-required checks failed but branch protection is satisfied. Caught by 13e on failure. |
| any | other (`DIRTY`, `DRAFT`, etc.) | **STOP immediately.** "PR is not ready to merge (mergeStateStatus: {STATE_STATUS}). Resolve before merging." Cleanup, no `<done>`. |

**STOP cleanup snippet** (for the STOP cases):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" "ship"
```

## 13e. Merge the PR

For merge-queue repos, omit the strategy flag — `gh pr merge` will enqueue automatically:

```bash
if [ "$HAS_MERGE_QUEUE" = "true" ]; then
  gh pr merge "$PR_NUM" --delete-branch
else
  gh pr merge "$PR_NUM" $MERGE_FLAG --delete-branch
fi
```

If the merge command fails (non-zero exit code):

- Do NOT retry with `--admin` or any other bypass flag
- Display the error output
- Run cleanup: `"${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" "ship"`
- Do NOT output `<done>SHIPPED</done>`
- Stop and let the user resolve the blocker

## 13f. Display summary

Read coverage and e2e results. Coverage may have skipped (e.g., all changed files were `package main`); in that case `coverage_skip_reason` is set and `coverage_result` is empty. Render a textual reason instead of `<COV_RESULT>%`:

```bash
COV_RESULT=$(jq -r '.coverage_result // ""' ".local/state/ship.loop.local.json")
COV_SKIP_REASON=$(jq -r '.coverage_skip_reason // ""' ".local/state/ship.loop.local.json")
COV_THRESHOLD=$(jq -r '.coverage_threshold // "60"' ".local/state/ship.loop.local.json")
TESTS_GEN=$(jq -r '.coverage_tests_generated // 0' ".local/state/ship.loop.local.json")
E2E_ATTEMPTED=$(jq -r '.e2e_attempted // ""' ".local/state/ship.loop.local.json")
E2E_RESULT=$(jq -r '.e2e_result // "skipped"' ".local/state/ship.loop.local.json")
E2E_PAGES=$(jq -r '.e2e_pages_tested // 0' ".local/state/ship.loop.local.json")

# Coverage line: prefer skip_reason when present, then numeric value, else "skipped".
if [ -n "$COV_SKIP_REASON" ]; then
  case "$COV_SKIP_REASON" in
    all-main) COV_LINE="skipped — all changed files are \`package main\`" ;;
    *)        COV_LINE="skipped — $COV_SKIP_REASON" ;;
  esac
elif [ -n "$COV_RESULT" ]; then
  COV_LINE="${COV_RESULT}% (threshold: ${COV_THRESHOLD}%)"
else
  COV_LINE="skipped"
fi
```

```
## Ship Complete

- **PR:** #<PR_NUM>
- **LLM:** <llm>
- **Review passes:** <n>
- **Findings addressed:** <n>
- **Coverage (changed files):** <COV_LINE>
- **Tests generated:** <TESTS_GEN>
- **E2E tests:** <E2E_PAGES> pages tested, <E2E_RESULT> — or "skipped — no web components" / "skipped — MCP unavailable"
- **CI:** green
- **Bot approvals:** <list or "none required">
- **Merge strategy:** <merge|squash|rebase>
- **Merged:** yes (or "skipped — --no-merge")
```

Output `<done>SHIPPED</done>`.
