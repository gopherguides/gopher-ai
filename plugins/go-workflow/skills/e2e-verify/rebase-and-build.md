# Steps 1-2: Rebase and Build Verification

## Step 1: Rebase onto Base Branch

### 1a. Checkout PR Branch

Ensure we are on the correct PR branch before rebasing. This handles the case where `$go-workflow:e2e-verify 42` is run from a different branch:

```bash
if [ -z "${PR_NUM:-}" ]; then
  PR_JSON=$(github_current_pr) || {
    echo "Error: No open PR matches the current branch and HEAD"
    exit 1
  }
  PR_NUM=$(jq -er '.number' <<< "$PR_JSON")
else
  PR_JSON=$(github_pr "$PR_NUM") || {
    echo "Error: Could not read PR #$PR_NUM"
    exit 1
  }
fi

CURRENT_BRANCH=$(git branch --show-current)
PR_HEAD_BRANCH=$(jq -er '.head.ref' <<< "$PR_JSON")
PR_HEAD_SHA=$(jq -er '.head.sha' <<< "$PR_JSON")
EXPECTED_REMOTE_HEAD_SHA="$PR_HEAD_SHA"
PR_HEAD_OWNER_REPO=$(jq -er '.head.repo.full_name' <<< "$PR_JSON")
PR_HEAD_CLONE_URL=$(jq -er '.head.repo.clone_url' <<< "$PR_JSON")
LOCAL_HEAD_SHA=$(git rev-parse HEAD)
if [ "$CURRENT_BRANCH" != "$PR_HEAD_BRANCH" ] || [ "$LOCAL_HEAD_SHA" != "$PR_HEAD_SHA" ]; then
  if [ -n "$(git status --porcelain)" ]; then
    WORKFLOW_RESULT=INCOMPLETE
    WORKFLOW_REASON=dirty-worktree
    echo "WORKFLOW_RESULT=$WORKFLOW_RESULT"
    echo "WORKFLOW_REASON=$WORKFLOW_REASON"
    exit 1
  fi

  PR_HEAD_REMOTE=""
  for remote in $(git remote); do
    REMOTE_URL=$(git remote get-url "$remote")
    REMOTE_OWNER_REPO=$(echo "$REMOTE_URL" | sed 's|\.git$||' | sed -E 's|^https?://[^/]+/||' | sed -E 's|^ssh://[^/]+/||' | sed -E 's|^[^@]+@[^:]+:||')
    if [ "$REMOTE_OWNER_REPO" = "$PR_HEAD_OWNER_REPO" ]; then
      PR_HEAD_REMOTE="$remote"
      break
    fi
  done

  echo "Not on PR branch ($PR_HEAD_BRANCH) — checking out..."
  if [ -n "$PR_HEAD_REMOTE" ]; then
    PR_HEAD_FETCH_SOURCE="$PR_HEAD_REMOTE"
  else
    PR_HEAD_FETCH_SOURCE="$PR_HEAD_CLONE_URL"
  fi
  PR_HEAD_FETCH_REF="refs/e2e-verify/$PR_NUM/head"
  git fetch "$PR_HEAD_FETCH_SOURCE" "+refs/heads/${PR_HEAD_BRANCH}:${PR_HEAD_FETCH_REF}"
  FETCHED_HEAD_SHA=$(git rev-parse "$PR_HEAD_FETCH_REF")
  if [ "$FETCHED_HEAD_SHA" != "$PR_HEAD_SHA" ]; then
    WORKFLOW_RESULT=INCOMPLETE
    WORKFLOW_REASON=pr-head-shift
    echo "WORKFLOW_RESULT=$WORKFLOW_RESULT"
    echo "WORKFLOW_REASON=$WORKFLOW_REASON"
    exit 1
  fi

  LOCAL_PR_BRANCH="$PR_HEAD_BRANCH"
  if git show-ref --verify --quiet "refs/heads/$LOCAL_PR_BRANCH"; then
    LOCAL_BRANCH_SHA=$(git rev-parse "refs/heads/$LOCAL_PR_BRANCH")
    if [ "$LOCAL_BRANCH_SHA" != "$PR_HEAD_SHA" ]; then
      LOCAL_PR_BRANCH="e2e-verify-pr-$PR_NUM"
    fi
  fi
  if git show-ref --verify --quiet "refs/heads/$LOCAL_PR_BRANCH"; then
    LOCAL_BRANCH_SHA=$(git rev-parse "refs/heads/$LOCAL_PR_BRANCH")
    if [ "$LOCAL_BRANCH_SHA" != "$PR_HEAD_SHA" ]; then
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=local-pr-branch-diverged
      echo "WORKFLOW_RESULT=$WORKFLOW_RESULT"
      echo "WORKFLOW_REASON=$WORKFLOW_REASON"
      exit 1
    fi
    git checkout "$LOCAL_PR_BRANCH"
  else
    git checkout -b "$LOCAL_PR_BRANCH" "$PR_HEAD_FETCH_REF"
  fi
fi
```

A divergent local branch is preserved. The workflow uses a dedicated local PR
branch only when it points to the exact REST-declared head; otherwise it stops
without moving either existing branch.

### 1b. Detect Base Branch

```bash
BASE_BRANCH=$(jq -er '.base.ref' <<< "$PR_JSON")
BASE_OWNER_REPO=$(jq -er '.base.repo.full_name' <<< "$PR_JSON")

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
1. Check `git status --porcelain`. If dirty, report
   `WORKFLOW_RESULT=INCOMPLETE` and `WORKFLOW_REASON=dirty-worktree`, follow the
   top-level **Hard Invariant Failure** procedure, and stop.
2. Run `git rebase "${BASE_REMOTE}/${BASE_BRANCH}"`. Resolve conflicts only
   when the correct resolution is evident and every conflict is cleared. If
   any conflict remains, run `git rebase --abort`, report
   `WORKFLOW_RESULT=INCOMPLETE` and `WORKFLOW_REASON=rebase-conflict`, then
   follow the top-level **Hard Invariant Failure** procedure and stop.
3. Force-push:
   ```bash
   PR_JSON=$(github_pr "$PR_NUM") || {
     echo "Error: Could not refresh PR #$PR_NUM before push"
     exit 1
   }
   PR_HEAD_BRANCH=$(jq -er '.head.ref' <<< "$PR_JSON")
   PR_HEAD_SHA=$(jq -er '.head.sha' <<< "$PR_JSON")
   if [ "$PR_HEAD_SHA" != "$EXPECTED_REMOTE_HEAD_SHA" ]; then
     WORKFLOW_RESULT=INCOMPLETE
     WORKFLOW_REASON=pr-head-shift
     echo "WORKFLOW_RESULT=$WORKFLOW_RESULT"
     echo "WORKFLOW_REASON=$WORKFLOW_REASON"
     exit 1
   fi
   PR_HEAD_OWNER_REPO=$(jq -er '.head.repo.full_name' <<< "$PR_JSON")
   PR_HEAD_CLONE_URL=$(jq -er '.head.repo.clone_url' <<< "$PR_JSON")
   PR_HEAD_TARGET=""
   for remote in $(git remote); do
     REMOTE_URL=$(git remote get-url "$remote")
     REMOTE_OWNER_REPO=$(echo "$REMOTE_URL" | sed 's|\.git$||' | sed -E 's|^https?://[^/]+/||' | sed -E 's|^ssh://[^/]+/||' | sed -E 's|^[^@]+@[^:]+:||')
     if [ "$REMOTE_OWNER_REPO" = "$PR_HEAD_OWNER_REPO" ]; then
       PR_HEAD_TARGET="$remote"
       break
     fi
   done
   PR_HEAD_TARGET="${PR_HEAD_TARGET:-$PR_HEAD_CLONE_URL}"
   git push --force-with-lease="refs/heads/$PR_HEAD_BRANCH:$EXPECTED_REMOTE_HEAD_SHA" "$PR_HEAD_TARGET" "HEAD:refs/heads/$PR_HEAD_BRANCH"
   PUBLISHED_PR_JSON=$(github_pr "$PR_NUM") || {
     echo "Error: Could not verify PR #$PR_NUM after push"
     exit 1
   }
   PUBLISHED_HEAD_SHA=$(jq -er '.head.sha' <<< "$PUBLISHED_PR_JSON")
   LOCAL_REBASED_HEAD_SHA=$(git rev-parse HEAD)
   if [ "$PUBLISHED_HEAD_SHA" != "$LOCAL_REBASED_HEAD_SHA" ]; then
     WORKFLOW_RESULT=INCOMPLETE
     WORKFLOW_REASON=pr-head-shift
     echo "WORKFLOW_RESULT=$WORKFLOW_RESULT"
     echo "WORKFLOW_REASON=$WORKFLOW_REASON"
     exit 1
   fi
   ```

### 1d. Wait for CI After Rebase (only if rebased)

```bash
HEAD_SHA=$(git rev-parse HEAD)
CHECKS_STATUS=0
CHECKS_SNAPSHOT=$(github_watch_pr_checks "$PR_NUM" "$HEAD_SHA") || CHECKS_STATUS=$?
if [ "$CHECKS_STATUS" -ne 0 ]; then
  case "$CHECKS_STATUS" in
    "$GITHUB_CHECKS_FAILED") WORKFLOW_REASON=ci-checks-failed ;;
    "$GITHUB_CHECKS_REGISTRATION_TIMEOUT") WORKFLOW_REASON=ci-registration-timeout ;;
    "$GITHUB_CHECKS_API_ERROR") WORKFLOW_REASON=ci-api-failed ;;
    "$GITHUB_CHECKS_HEAD_SHIFT") WORKFLOW_REASON=pr-head-shift ;;
    *) WORKFLOW_REASON=ci-watch-failed ;;
  esac
  WORKFLOW_RESULT=INCOMPLETE
  echo "WORKFLOW_RESULT=$WORKFLOW_RESULT"
  echo "WORKFLOW_REASON=$WORKFLOW_REASON"
  exit 1
fi
jq -r '.items[] | "\(.name): \(.state)"' <<< "$CHECKS_SNAPSHOT"
```

Registration timeout, API failure, check failure, or a PR head shift is a
non-success result. Follow the top-level **Hard Invariant Failure** procedure
and stop before build or E2E testing.

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
      BUILD_RESULT="fail"
      WORKFLOW_REASON="generation-failed"
    fi
  fi
fi
```

If `WORKFLOW_REASON=generation-failed`, report:

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=generation-failed
```

Follow the top-level **Hard Invariant Failure** procedure and stop before build
or E2E testing.

Check for generated file drift:

```bash
if [ -n "$GEN_TARGET" ] && [ -z "${WORKFLOW_REASON:-}" ]; then
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
BUILD_RESULT=pass
if ! go build ./...; then
  BUILD_RESULT=fail
elif ! go test ./...; then
  BUILD_RESULT=fail
elif command -v golangci-lint >/dev/null 2>&1 && ! golangci-lint run; then
  BUILD_RESULT=fail
fi
```

If `BUILD_RESULT=fail`, report:

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=verification-failed
```

Follow the top-level **Hard Invariant Failure** procedure and stop. Never
continue to browser E2E with failed generation, build, tests, or configured
lint.

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

`BUILD_RESULT` is authoritative for the persisted result. Only `pass` may
advance to E2E testing.
