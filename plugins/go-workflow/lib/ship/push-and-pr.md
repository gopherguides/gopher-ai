# Ship — Phase 2: Push and PR Creation (Step 9)

Loaded by `skills/ship/SKILL.md` Phase 2.

## Step 9a — Push to remote

Detect the remote and branch from tracking config or PR metadata:

```bash
CURRENT_BRANCH=$(git branch --show-current)
BRANCH_REMOTE=$(git config "branch.$CURRENT_BRANCH.remote" 2>/dev/null || echo "origin")
PR_HEAD_BRANCH="$CURRENT_BRANCH"
if [ -n "$PR_NUM" ]; then
  if ! PR_JSON=$(github_pr "$PR_NUM"); then
    WORKFLOW_REASON="pr-metadata-api-error"
  fi
  PR_HEAD_BRANCH=$(jq -er '.head.ref' <<< "$PR_JSON")
fi
git push -u "$BRANCH_REMOTE" "HEAD:$PR_HEAD_BRANCH"
```

If PR metadata cannot be read, follow **Hard Invariant Failure** with
`WORKFLOW_REASON=pr-metadata-api-error` and stop before pushing.

## Step 9b — Ensure PR exists

After pushing, use the exact pushed head to discover an existing PR:

```bash
HEAD_SHA=$(git rev-parse HEAD)
if [ -z "$PR_NUM" ]; then
  if PR_JSON=$(github_current_pr "$PR_HEAD_BRANCH" "$HEAD_SHA"); then
    PR_NUM=$(jq -r '.number' <<< "$PR_JSON")
    BASE_BRANCH=$(jq -r '.base.ref' <<< "$PR_JSON")
  else
    PR_LOOKUP_STATUS=$?
    if [ "$PR_LOOKUP_STATUS" -ne 4 ]; then
      WORKFLOW_REASON="current-pr-api-error"
    fi
  fi
fi
```

Status 4 means no matching open PR exists. Any other lookup failure follows
**Hard Invariant Failure** with `WORKFLOW_REASON=current-pr-api-error`.

If `PR_NUM` remains empty:

1. Check for a PR template at `.github/pull_request_template.md` (also check `.github/PULL_REQUEST_TEMPLATE.md`, `docs/`, repo root)
2. If found, use its section structure
3. If not, use default: `## Summary` + `## Test Plan`
4. Generate conventional commit title from commits: `<type>(<scope>): <subject>`
5. Check branch name and commit messages for issue references
6. Create PR targeting the detected base branch:

```bash
gh pr create --base "$BASE_BRANCH" --title "<title>" --body "$(cat <<'EOF'
<filled-in template or default body>
EOF
)"
```

After creation, capture the exact-head PR and persist its number:

```bash
if ! PR_JSON=$(github_current_pr "$PR_HEAD_BRANCH" "$HEAD_SHA"); then
  WORKFLOW_REASON="created-pr-lookup-failed"
fi
PR_NUM=$(jq -er '.number' <<< "$PR_JSON")
```

If the created PR cannot be read, follow **Hard Invariant Failure** with
`WORKFLOW_REASON=created-pr-lookup-failed`. Persist `pr_number` in the state
file after a successful lookup.

## Step 9c — Capture HEAD SHA and bot review baseline

**CRITICAL: Capture immediately after push.**

```bash
echo "HEAD SHA captured: $HEAD_SHA"
BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Bot review baseline captured: $BOT_REVIEW_BASELINE"
```

Persist both `head_sha` and `bot_review_baseline` in the state file. The
baseline is captured here (before bots can post) so Step 11's bot-watch
window starts at the right moment.
