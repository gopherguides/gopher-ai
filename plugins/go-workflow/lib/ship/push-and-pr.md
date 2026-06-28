# Ship — Phase 2: Push and PR Creation (Step 9)

Loaded by `skills/ship/SKILL.md` Phase 2.

## Step 9a — Push to remote

Detect the remote and branch from tracking config or PR metadata:

```bash
BRANCH_REMOTE=$(git config "branch.$(git branch --show-current).remote" 2>/dev/null || echo "origin")
PR_HEAD_BRANCH=$(gh pr view --json headRefName --jq '.headRefName' 2>/dev/null || git branch --show-current)
git push -u "$BRANCH_REMOTE" "HEAD:$PR_HEAD_BRANCH"
```

## Step 9b — Ensure PR exists

If `PR_NUM` is empty:

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

Capture and persist the PR number:

```bash
PR_NUM=$(gh pr view --json number --jq '.number')
```

Persist `pr_number` in state file.

## Step 9c — Capture HEAD SHA and bot review baseline

**CRITICAL: Capture immediately after push.**

```bash
HEAD_SHA=$(git rev-parse HEAD)
echo "HEAD SHA captured: $HEAD_SHA"
BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Bot review baseline captured: $BOT_REVIEW_BASELINE"
```

Persist both `head_sha` and `bot_review_baseline` in the state file. The
baseline is captured here (before bots can post) so Step 11's bot-watch
window starts at the right moment.
