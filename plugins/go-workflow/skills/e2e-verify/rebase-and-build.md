# Steps 1-2: Rebase and Build Verification

## Step 1: Rebase onto Base Branch

### 1a. Checkout PR Branch

Ensure we are on the correct PR branch before rebasing. This handles the case where `/e2e-verify 42` is run from a different branch:

```bash
PR_NUM="${PR_NUM:-$(gh pr view --json number --jq '.number' 2>/dev/null)}"
CURRENT_BRANCH=$(git branch --show-current)
PR_HEAD_BRANCH=$(gh pr view "$PR_NUM" --json headRefName --jq '.headRefName' 2>/dev/null)
if [ "$CURRENT_BRANCH" != "$PR_HEAD_BRANCH" ]; then
  echo "Not on PR branch ($PR_HEAD_BRANCH) — checking out..."
  gh pr checkout "$PR_NUM"
fi
```

### 1b. Detect Base Branch

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

echo "PR #$PR_NUM targets $BASE_REMOTE/$BASE_BRANCH"
```

### 1c. Fetch and Rebase

```bash
git fetch "$BASE_REMOTE" "$BASE_BRANCH"
BEHIND=$(git rev-list --count "HEAD..${BASE_REMOTE}/${BASE_BRANCH}")
echo "Commits behind ${BASE_REMOTE}/${BASE_BRANCH}: $BEHIND"
```

**If `$BEHIND` is 0:** Skip rebase, proceed to Step 2.

**If `$BEHIND` > 0:**
1. Check `git status --porcelain`. **If dirty, STOP** — ask user how to proceed.
2. `git rebase "${BASE_REMOTE}/${BASE_BRANCH}"` — if conflicts arise, abort and ask user.
3. Force-push:
   ```bash
   PR_HEAD_BRANCH=$(gh pr view "$PR_NUM" --json headRefName --jq '.headRefName')
   BRANCH_REMOTE=$(git config "branch.$(git branch --show-current).remote")
   git push --force-with-lease "$BRANCH_REMOTE" "HEAD:$PR_HEAD_BRANCH"
   ```

### 1d. Wait for CI After Rebase (only if rebased)

```bash
for i in 1 2 3 4 5; do sleep 10 && gh pr checks "$PR_NUM" --watch && break; done
```

Verify with `gh pr checks "$PR_NUM"`. Fix any failures before proceeding.

---

## Step 2: Build Verification

### 2a. Code Generation (if applicable)

```bash
if [ -f Makefile ]; then
  GEN_TARGET=$(make -qp 2>/dev/null | awk -F: '/^[a-zA-Z0-9_-]+:/ {print $1}' \
    | grep -E '^(generate|gen|codegen|sqlc|proto|templ)$' | head -1 || true)
  if [ -n "$GEN_TARGET" ]; then
    GEN_SNAPSHOT=$(printf '%s\n%s' "$(git diff --name-only)" "$(git ls-files --others --exclude-standard)" | sed '/^$/d' | sort -u)
    echo "Running make $GEN_TARGET..."
    if ! make "$GEN_TARGET" 2>&1; then
      echo "WARNING: make $GEN_TARGET failed (tooling may not be installed). Skipping codegen check."
      GEN_TARGET=""
    fi
  fi
fi
```

Check for generated file drift:

```bash
if [ -n "$GEN_TARGET" ]; then
  GEN_MODIFIED=$(git diff --name-only)
  GEN_UNTRACKED=$(git ls-files --others --exclude-standard)
  GEN_ALL=$(printf '%s\n%s' "$GEN_MODIFIED" "$GEN_UNTRACKED" | sed '/^$/d' | sort -u)
  if [ -n "$GEN_SNAPSHOT" ]; then
    GEN_NEW=$(comm -13 <(echo "$GEN_SNAPSHOT" | sort) <(echo "$GEN_ALL" | sort))
  else
    GEN_NEW="$GEN_ALL"
  fi
  if [ -n "$GEN_NEW" ]; then
    echo "Generated code is stale. Files changed after generation:"
    echo "$GEN_NEW"
    echo "Staging regenerated files..."
    echo "$GEN_NEW" | xargs git add
  fi
fi
```

### 2b. Build and Test

```bash
go build ./...
go test ./...
golangci-lint run 2>/dev/null || true
```

### 2c. Dev Server Logs (if running)

If Air or another dev server is running, check `tmp/logs/api.log` or similar for build errors:

```bash
if [ -f tmp/logs/api.log ]; then
  tail -20 tmp/logs/api.log | grep -iE 'error|fatal|panic' || echo "No errors in dev server logs"
fi
```

### 2d. Check for Unexpected Diffs

```bash
git diff --stat
```

If unexpected changes appear after generation, investigate before proceeding.

**Set `BUILD_RESULT`** to `pass` or `fail` based on the above checks. If any blocking check fails (build or test), report and stop — do not proceed to E2E testing with a broken build.
