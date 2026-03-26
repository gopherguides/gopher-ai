# Step 1: Checkout PR Branch and Rebase

**Do NOT skip ahead to fetching review comments.**

## 1a. Checkout

```bash
PR_NUM="${PR_ARG:-$(gh pr view --json number --jq '.number')}"
echo "Working on PR #$PR_NUM"
gh pr checkout "$PR_NUM"
```

Idempotent — handles same-repo PRs, fork PRs, and branch tracking.

## 1b. Check if behind base branch and rebase

```bash
BASE_BRANCH=$(gh pr view "$PR_NUM" --json baseRefName --jq '.baseRefName')
BASE_OWNER_REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')

BASE_REMOTE=""
for remote in $(git remote); do
  REMOTE_URL=$(git remote get-url "$remote")
  REMOTE_OWNER_REPO=$(echo "$REMOTE_URL" | sed 's|\.git$||' | sed -E 's|^https?://[^/]+/||' | sed -E 's|^ssh://[^/]+/||' | sed -E 's|^[^@]+@[^:]+:||')
  if [ "$REMOTE_OWNER_REPO" = "$BASE_OWNER_REPO" ]; then
    BASE_REMOTE="$remote"
    break
  fi
done

if [ -z "$BASE_REMOTE" ]; then
  echo "Error: No remote found pointing to base repository ($BASE_OWNER_REPO)"
  exit 1
fi

git fetch "$BASE_REMOTE" "$BASE_BRANCH"
BEHIND=$(git rev-list --count "HEAD..${BASE_REMOTE}/${BASE_BRANCH}")
echo "Commits behind ${BASE_REMOTE}/${BASE_BRANCH}: $BEHIND"
```

**If `$BEHIND` is 0:** Proceed to Step 2.

**If `$BEHIND` > 0:**
1. Check `git status --porcelain`. **If dirty, STOP** — ask user how to proceed.
2. `git rebase "${BASE_REMOTE}/${BASE_BRANCH}"` — resolve conflicts intelligently or ask user if too complex.
3. Force-push:
   ```bash
   PR_HEAD_BRANCH=$(gh pr view "$PR_NUM" --json headRefName --jq '.headRefName')
   BRANCH_REMOTE=$(git config "branch.$(git branch --show-current).remote")
   git push --force-with-lease "$BRANCH_REMOTE" "HEAD:$PR_HEAD_BRANCH"
   ```

## 1c. Wait for CI after rebase (only if rebased)

```bash
for i in 1 2 3 4 5; do sleep 10 && gh pr checks "$PR_NUM" --watch && break; done
```

Verify with `gh pr checks "$PR_NUM"`. Fix any failures before proceeding.
