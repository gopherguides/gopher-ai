# Steps 1-2: Rebase and Build Verification

## Step 1: Rebase onto Base Branch

### 1a. Checkout PR Branch

Ensure we are on the correct PR branch before rebasing. This handles the case where `$go-workflow:e2e-verify 42` is run from a different branch:

```bash
if [ -z "${PR_NUM:-}" ]; then
  PR_JSON=$(cd "$WORKTREE_PATH" && github_current_pr) || {
    echo "Error: No open PR matches the current branch and HEAD"
    exit 1
  }
  PR_NUM=$(jq -er '.number' <<< "$PR_JSON")
else
  PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM") || {
    echo "Error: Could not read PR #$PR_NUM"
    exit 1
  }
fi

CURRENT_BRANCH=$(git -C "$WORKTREE_PATH" branch --show-current)
PR_HEAD_BRANCH=$(jq -er '.head.ref' <<< "$PR_JSON")
PR_HEAD_SHA=$(jq -er '.head.sha' <<< "$PR_JSON")
EXPECTED_REMOTE_HEAD_SHA="$PR_HEAD_SHA"
PR_HEAD_OWNER_REPO=$(jq -er '.head.repo.full_name' <<< "$PR_JSON")
PR_HEAD_CLONE_URL=$(jq -er '.head.repo.clone_url' <<< "$PR_JSON")
LOCAL_HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD)
if [ "$CURRENT_BRANCH" != "$PR_HEAD_BRANCH" ] || [ "$LOCAL_HEAD_SHA" != "$PR_HEAD_SHA" ]; then
  if [ -n "$(git -C "$WORKTREE_PATH" status --porcelain)" ]; then
    WORKFLOW_RESULT=INCOMPLETE
    WORKFLOW_REASON=dirty-worktree
    echo "WORKFLOW_RESULT=$WORKFLOW_RESULT"
    echo "WORKFLOW_REASON=$WORKFLOW_REASON"
    exit 1
  fi

  PR_HEAD_REMOTE=""
  for remote in $(git -C "$WORKTREE_PATH" remote); do
    REMOTE_URL=$(git -C "$WORKTREE_PATH" remote get-url "$remote")
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
  git -C "$WORKTREE_PATH" fetch "$PR_HEAD_FETCH_SOURCE" "+refs/heads/${PR_HEAD_BRANCH}:${PR_HEAD_FETCH_REF}"
  FETCHED_HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse "$PR_HEAD_FETCH_REF")
  if [ "$FETCHED_HEAD_SHA" != "$PR_HEAD_SHA" ]; then
    WORKFLOW_RESULT=INCOMPLETE
    WORKFLOW_REASON=pr-head-shift
    echo "WORKFLOW_RESULT=$WORKFLOW_RESULT"
    echo "WORKFLOW_REASON=$WORKFLOW_REASON"
    exit 1
  fi

  LOCAL_PR_BRANCH="$PR_HEAD_BRANCH"
  if git -C "$WORKTREE_PATH" show-ref --verify --quiet "refs/heads/$LOCAL_PR_BRANCH"; then
    LOCAL_BRANCH_SHA=$(git -C "$WORKTREE_PATH" rev-parse "refs/heads/$LOCAL_PR_BRANCH")
    if [ "$LOCAL_BRANCH_SHA" != "$PR_HEAD_SHA" ]; then
      LOCAL_PR_BRANCH="e2e-verify-pr-$PR_NUM"
    fi
  fi
  if git -C "$WORKTREE_PATH" show-ref --verify --quiet "refs/heads/$LOCAL_PR_BRANCH"; then
    LOCAL_BRANCH_SHA=$(git -C "$WORKTREE_PATH" rev-parse "refs/heads/$LOCAL_PR_BRANCH")
    if [ "$LOCAL_BRANCH_SHA" != "$PR_HEAD_SHA" ]; then
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=local-pr-branch-diverged
      echo "WORKFLOW_RESULT=$WORKFLOW_RESULT"
      echo "WORKFLOW_REASON=$WORKFLOW_REASON"
      exit 1
    fi
    git -C "$WORKTREE_PATH" checkout "$LOCAL_PR_BRANCH"
  else
    git -C "$WORKTREE_PATH" checkout -b "$LOCAL_PR_BRANCH" "$PR_HEAD_FETCH_REF"
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
for remote in $(git -C "$WORKTREE_PATH" remote); do
  REMOTE_URL=$(git -C "$WORKTREE_PATH" remote get-url "$remote")
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
git -C "$WORKTREE_PATH" fetch "$BASE_REMOTE" "$BASE_BRANCH"
BEHIND=$(git -C "$WORKTREE_PATH" rev-list --count "HEAD..${BASE_REMOTE}/${BASE_BRANCH}")
echo "Commits behind ${BASE_REMOTE}/${BASE_BRANCH}: $BEHIND"
```

**If `$BEHIND` is 0:** Skip rebase, proceed to Step 2.

**If `$BEHIND` > 0:**
1. Check `git -C "$WORKTREE_PATH" status --porcelain`. If dirty, report
   `WORKFLOW_RESULT=INCOMPLETE` and `WORKFLOW_REASON=dirty-worktree`, follow the
   top-level **Hard Invariant Failure** procedure, and stop.
2. Run `git -C "$WORKTREE_PATH" rebase "${BASE_REMOTE}/${BASE_BRANCH}"`. Resolve conflicts only
   when the correct resolution is evident and every conflict is cleared. If
   any conflict remains, run `git -C "$WORKTREE_PATH" rebase --abort`, report
   `WORKFLOW_RESULT=INCOMPLETE` and `WORKFLOW_REASON=rebase-conflict`, then
   follow the top-level **Hard Invariant Failure** procedure and stop.
3. Force-push:
   ```bash
   PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM") || {
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
   for remote in $(git -C "$WORKTREE_PATH" remote); do
     REMOTE_URL=$(git -C "$WORKTREE_PATH" remote get-url "$remote")
     REMOTE_OWNER_REPO=$(echo "$REMOTE_URL" | sed 's|\.git$||' | sed -E 's|^https?://[^/]+/||' | sed -E 's|^ssh://[^/]+/||' | sed -E 's|^[^@]+@[^:]+:||')
     if [ "$REMOTE_OWNER_REPO" = "$PR_HEAD_OWNER_REPO" ]; then
       PR_HEAD_TARGET="$remote"
       break
     fi
   done
   PR_HEAD_TARGET="${PR_HEAD_TARGET:-$PR_HEAD_CLONE_URL}"
   git -C "$WORKTREE_PATH" push --force-with-lease="refs/heads/$PR_HEAD_BRANCH:$EXPECTED_REMOTE_HEAD_SHA" "$PR_HEAD_TARGET" "HEAD:refs/heads/$PR_HEAD_BRANCH"
   PUBLISHED_PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM") || {
     echo "Error: Could not verify PR #$PR_NUM after push"
     exit 1
   }
   PUBLISHED_HEAD_SHA=$(jq -er '.head.sha' <<< "$PUBLISHED_PR_JSON")
   LOCAL_REBASED_HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD)
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
HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD)
CHECKS_STATUS=0
CHECKS_SNAPSHOT=$(cd "$WORKTREE_PATH" && github_watch_pr_checks "$PR_NUM" "$HEAD_SHA") || CHECKS_STATUS=$?
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
if ! declare -p GEN_NEW_FILES >/dev/null 2>&1; then
  GEN_NEW_FILES=()
fi
if [ -f "$WORKTREE_PATH/Makefile" ]; then
  if [ -z "${GEN_TARGET:-}" ]; then
    GEN_TARGET=$( (cd "$WORKTREE_PATH" && make -qp 2>/dev/null) | awk -F: '/^[a-zA-Z0-9_-]+:/ {print $1}' \
      | grep -E '^(generate|gen|codegen|sqlc|proto|templ)$' | head -1 || true)
    if [ -n "$GEN_TARGET" ]; then
      GEN_SNAPSHOT_FILES=()
      while IFS= read -r -d '' SNAPSHOT_FILE; do
        SNAPSHOT_ALREADY_PRESENT=false
        if [ "${GEN_SNAPSHOT_FILES[0]+set}" = "set" ]; then
          for EXISTING_SNAPSHOT_FILE in "${GEN_SNAPSHOT_FILES[@]}"; do
            if [ "$EXISTING_SNAPSHOT_FILE" = "$SNAPSHOT_FILE" ]; then
              SNAPSHOT_ALREADY_PRESENT=true
              break
            fi
          done
        fi
        if [ "$SNAPSHOT_ALREADY_PRESENT" = "false" ]; then
          GEN_SNAPSHOT_FILES+=("$SNAPSHOT_FILE")
        fi
      done < <(git -C "$WORKTREE_PATH" diff --name-only -z; git -C "$WORKTREE_PATH" ls-files --others --exclude-standard -z)
      if [ "${GEN_SNAPSHOT_FILES[0]+set}" = "set" ]; then
        GENERATION_SNAPSHOT_JSON=$(jq -cn '$ARGS.positional' --args "${GEN_SNAPSHOT_FILES[@]}")
      else
        GENERATION_SNAPSHOT_JSON='[]'
      fi
      if [ -n "${STATE_FILE:-}" ] && [ -f "$STATE_FILE" ]; then
        TMP="${STATE_FILE}.tmp"
        jq --arg generation_target "$GEN_TARGET" --argjson generation_snapshot "$GENERATION_SNAPSHOT_JSON" \
          '.generation_target = $generation_target | .generation_snapshot = $generation_snapshot' \
          "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
      fi
    fi
  fi
  if [ -n "$GEN_TARGET" ]; then
    echo "Running make $GEN_TARGET..."
    if ! (cd "$WORKTREE_PATH" && make "$GEN_TARGET") 2>&1; then
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
  GEN_ALL_FILES=()
  while IFS= read -r -d '' GENERATED_FILE; do
    GENERATED_ALREADY_PRESENT=false
    if [ "${GEN_ALL_FILES[0]+set}" = "set" ]; then
      for EXISTING_GENERATED_FILE in "${GEN_ALL_FILES[@]}"; do
        if [ "$EXISTING_GENERATED_FILE" = "$GENERATED_FILE" ]; then
          GENERATED_ALREADY_PRESENT=true
          break
        fi
      done
    fi
    if [ "$GENERATED_ALREADY_PRESENT" = "false" ]; then
      GEN_ALL_FILES+=("$GENERATED_FILE")
    fi
  done < <(git -C "$WORKTREE_PATH" diff --name-only -z; git -C "$WORKTREE_PATH" ls-files --others --exclude-standard -z)
  if [ "${GEN_ALL_FILES[0]+set}" = "set" ]; then
    for GENERATED_FILE in "${GEN_ALL_FILES[@]}"; do
      GENERATED_IN_SNAPSHOT=false
      if [ "${GEN_SNAPSHOT_FILES[0]+set}" = "set" ]; then
        for SNAPSHOT_FILE in "${GEN_SNAPSHOT_FILES[@]}"; do
          if [ "$SNAPSHOT_FILE" = "$GENERATED_FILE" ]; then
            GENERATED_IN_SNAPSHOT=true
            break
          fi
        done
      fi
      if [ "$GENERATED_IN_SNAPSHOT" = "false" ]; then
        GENERATED_ALREADY_OWNED=false
        if [ "${GEN_NEW_FILES[0]+set}" = "set" ]; then
          for OWNED_GENERATED_FILE in "${GEN_NEW_FILES[@]}"; do
            if [ "$OWNED_GENERATED_FILE" = "$GENERATED_FILE" ]; then
              GENERATED_ALREADY_OWNED=true
              break
            fi
          done
        fi
        if [ "$GENERATED_ALREADY_OWNED" = "false" ]; then
          GEN_NEW_FILES+=("$GENERATED_FILE")
        fi
      fi
    done
  fi
  if [ "${GEN_NEW_FILES[0]+set}" = "set" ]; then
    echo "Generated code is stale. E2E-owned paths:"
    printf '%s\n' "${GEN_NEW_FILES[@]}"
    echo "Keep the generated paths unstaged until the E2E-owned commit."
  fi
  if [ -n "${STATE_FILE:-}" ] && [ -f "$STATE_FILE" ]; then
    if [ "${GEN_NEW_FILES[0]+set}" = "set" ]; then
      GENERATED_FILES_JSON=$(jq -cn '$ARGS.positional' --args "${GEN_NEW_FILES[@]}")
    else
      GENERATED_FILES_JSON='[]'
    fi
    TMP="${STATE_FILE}.tmp"
    if [ "${GEN_SNAPSHOT_FILES[0]+set}" = "set" ]; then
      GENERATION_SNAPSHOT_JSON=$(jq -cn '$ARGS.positional' --args "${GEN_SNAPSHOT_FILES[@]}")
    else
      GENERATION_SNAPSHOT_JSON='[]'
    fi
    jq --arg generation_target "$GEN_TARGET" --argjson generation_snapshot "$GENERATION_SNAPSHOT_JSON" \
      --argjson generated_files "$GENERATED_FILES_JSON" \
      '.generation_target = $generation_target | .generation_snapshot = $generation_snapshot | .generated_files = $generated_files' \
      "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
  fi
fi
```

### 2b. Build and Test

```bash
BUILD_RESULT=pass
if ! go -C "$WORKTREE_PATH" build ./...; then
  BUILD_RESULT=fail
elif ! go -C "$WORKTREE_PATH" test ./...; then
  BUILD_RESULT=fail
elif command -v golangci-lint >/dev/null 2>&1 && ! (cd "$WORKTREE_PATH" && golangci-lint run); then
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
if [ -f "$WORKTREE_PATH/tmp/logs/api.log" ]; then
  tail -20 "$WORKTREE_PATH/tmp/logs/api.log" | grep -iE 'error|fatal|panic' || echo "No errors in dev server logs"
fi
```

### 2d. Check for Unexpected Diffs

```bash
git -C "$WORKTREE_PATH" diff --stat
```

If unexpected changes appear after generation, investigate before proceeding.

`BUILD_RESULT` is authoritative for the persisted result. Only `pass` may
advance to E2E testing.
