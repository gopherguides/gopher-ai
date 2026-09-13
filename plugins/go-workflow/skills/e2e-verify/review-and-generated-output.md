# E2E Verify — Review and Generated Output

Loaded by `SKILL.md` Step 3 for `fix-and-verify` and `fix-and-ship`. Execute this complete procedure before browser testing.

## Step 3: Address Review (conditional)

**Only for modes: `fix-and-verify`, `fix-and-ship`** — for all others, skip to Step 4 or 5.

```bash
set_loop_phase "$STATE_FILE" "addressing" "$WORKFLOW_STATE_PATH"
ADDRESS_REVIEW_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "address_review")
initialize_workflow_state "$STATE_FILE" "$ADDRESS_REVIEW_STATE_PATH"
```

### Recover an Interrupted Generated-Output Transaction

Reconcile a persisted generated-output commit before invoking address-review.
This keeps an interrupted E2E-owned stage/commit/push from leaking into the
embedded workflow's empty-index contract:

```bash
GENERATED_PUSH_RECOVERED=false
if [ "${GENERATED_COMMIT_STATUS:-}" = "committing" ] ||
   [ "${GENERATED_COMMIT_STATUS:-}" = "push-pending" ]; then
  if [ "${GEN_NEW_FILES[0]+set}" != "set" ] || [ -z "${GENERATED_COMMIT_PARENT:-}" ]; then
    WORKFLOW_RESULT=INCOMPLETE
    WORKFLOW_REASON=generated-transaction-state-invalid
  else
    EXPECTED_GENERATED_PATHS_JSON=$(jq -cn '$ARGS.positional | sort' --args "${GEN_NEW_FILES[@]}")
    LOCAL_GENERATED_HEAD=$(git -C "$WORKTREE_PATH" rev-parse HEAD)
  fi

  if [ -z "${WORKFLOW_REASON:-}" ] && [ "$GENERATED_COMMIT_STATUS" = "committing" ]; then
    if [ "$LOCAL_GENERATED_HEAD" = "$GENERATED_COMMIT_PARENT" ]; then
      CACHED_GENERATED_FILES=()
      while IFS= read -r -d '' CACHED_GENERATED_FILE; do
        CACHED_GENERATED_FILES+=("$CACHED_GENERATED_FILE")
      done < <(git -C "$WORKTREE_PATH" diff --cached --name-only -z)
      if [ "${CACHED_GENERATED_FILES[0]+set}" = "set" ]; then
        CACHED_GENERATED_PATHS_JSON=$(jq -cn '$ARGS.positional | sort' --args "${CACHED_GENERATED_FILES[@]}")
      else
        CACHED_GENERATED_PATHS_JSON='[]'
      fi
      if [ "$CACHED_GENERATED_PATHS_JSON" != '[]' ] && [ "$CACHED_GENERATED_PATHS_JSON" != "$EXPECTED_GENERATED_PATHS_JSON" ]; then
        WORKFLOW_RESULT=INCOMPLETE
        WORKFLOW_REASON=generated-index-mismatch
      elif [ "$CACHED_GENERATED_PATHS_JSON" != '[]' ]; then
        git -C "$WORKTREE_PATH" restore --staged -- "${GEN_NEW_FILES[@]}"
      fi
      if [ -z "${WORKFLOW_REASON:-}" ]; then
        GENERATED_COMMIT_STATUS=""
        GENERATED_COMMIT_PARENT=""
        GENERATED_COMMIT_SHA=""
        set_loop_field "$STATE_FILE" "generated_commit_status" "" "$WORKFLOW_STATE_PATH"
        set_loop_field "$STATE_FILE" "generated_commit_parent" "" "$WORKFLOW_STATE_PATH"
        set_loop_field "$STATE_FILE" "generated_commit_sha" "" "$WORKFLOW_STATE_PATH"
      fi
    else
      RECOVERED_GENERATED_PARENT=$(git -C "$WORKTREE_PATH" rev-parse "${LOCAL_GENERATED_HEAD}^")
      RECOVERED_GENERATED_FILES=()
      while IFS= read -r -d '' RECOVERED_GENERATED_FILE; do
        RECOVERED_GENERATED_FILES+=("$RECOVERED_GENERATED_FILE")
      done < <(git -C "$WORKTREE_PATH" diff-tree --no-commit-id --name-only -r -z "$LOCAL_GENERATED_HEAD")
      RECOVERED_GENERATED_PATHS_JSON=$(jq -cn '$ARGS.positional | sort' --args "${RECOVERED_GENERATED_FILES[@]}")
      if [ "$RECOVERED_GENERATED_PARENT" != "$GENERATED_COMMIT_PARENT" ] ||
         [ "$RECOVERED_GENERATED_PATHS_JSON" != "$EXPECTED_GENERATED_PATHS_JSON" ]; then
        WORKFLOW_RESULT=INCOMPLETE
        WORKFLOW_REASON=generated-transaction-state-invalid
      else
        GENERATED_COMMIT_SHA="$LOCAL_GENERATED_HEAD"
        GENERATED_COMMIT_STATUS=push-pending
        set_loop_field "$STATE_FILE" "generated_commit_status" "push-pending" "$WORKFLOW_STATE_PATH"
        set_loop_field "$STATE_FILE" "generated_commit_sha" "$GENERATED_COMMIT_SHA" "$WORKFLOW_STATE_PATH"
      fi
    fi
  fi

  if [ -z "${WORKFLOW_REASON:-}" ] && [ "$GENERATED_COMMIT_STATUS" = "push-pending" ]; then
    GENERATED_PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM") || {
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=pr-metadata-api-failure
    }
    if [ -z "${WORKFLOW_REASON:-}" ]; then
      PUBLISHED_GENERATED_HEAD=$(jq -er '.head.sha' <<< "$GENERATED_PR_JSON") || {
        WORKFLOW_RESULT=INCOMPLETE
        WORKFLOW_REASON=invalid-pr-head-metadata
      }
      PR_HEAD_BRANCH=$(jq -er '.head.ref' <<< "$GENERATED_PR_JSON") || {
        WORKFLOW_RESULT=INCOMPLETE
        WORKFLOW_REASON=invalid-pr-head-metadata
      }
      PR_HEAD_OWNER_REPO=$(jq -er '.head.repo.full_name' <<< "$GENERATED_PR_JSON") || {
        WORKFLOW_RESULT=INCOMPLETE
        WORKFLOW_REASON=missing-pr-head-repository
      }
      PR_HEAD_CLONE_URL=$(jq -er '.head.repo.clone_url' <<< "$GENERATED_PR_JSON") || {
        WORKFLOW_RESULT=INCOMPLETE
        WORKFLOW_REASON=missing-pr-head-repository
      }
    fi
    if [ -z "${WORKFLOW_REASON:-}" ] &&
       { [ "$LOCAL_GENERATED_HEAD" != "$GENERATED_COMMIT_SHA" ] ||
         [ "$(git -C "$WORKTREE_PATH" rev-parse "${GENERATED_COMMIT_SHA}^")" != "$GENERATED_COMMIT_PARENT" ]; }; then
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=generated-transaction-state-invalid
    fi
    if [ -z "${WORKFLOW_REASON:-}" ]; then
      PENDING_GENERATED_FILES=()
      while IFS= read -r -d '' PENDING_GENERATED_FILE; do
        PENDING_GENERATED_FILES+=("$PENDING_GENERATED_FILE")
      done < <(git -C "$WORKTREE_PATH" diff-tree --no-commit-id --name-only -r -z "$GENERATED_COMMIT_SHA")
      PENDING_GENERATED_PATHS_JSON=$(jq -cn '$ARGS.positional | sort' --args "${PENDING_GENERATED_FILES[@]}")
      if [ "$PENDING_GENERATED_PATHS_JSON" != "$EXPECTED_GENERATED_PATHS_JSON" ]; then
        WORKFLOW_RESULT=INCOMPLETE
        WORKFLOW_REASON=generated-transaction-state-invalid
      fi
    fi
    if [ -z "${WORKFLOW_REASON:-}" ] && [ "$PUBLISHED_GENERATED_HEAD" = "$GENERATED_COMMIT_SHA" ]; then
      GENERATED_PUSH_RECOVERED=true
    elif [ -z "${WORKFLOW_REASON:-}" ] && [ "$PUBLISHED_GENERATED_HEAD" = "$GENERATED_COMMIT_PARENT" ]; then
      PR_HEAD_PUSH_TARGET=""
      for remote in $(git -C "$WORKTREE_PATH" remote); do
        REMOTE_URL=$(git -C "$WORKTREE_PATH" remote get-url "$remote")
        REMOTE_OWNER_REPO=$(printf '%s\n' "$REMOTE_URL" | sed 's|\.git$||' | sed -E 's|^https?://[^/]+/||' | sed -E 's|^ssh://[^/]+/||' | sed -E 's|^[^@]+@[^:]+:||')
        if [ "$REMOTE_OWNER_REPO" = "$PR_HEAD_OWNER_REPO" ]; then
          PR_HEAD_PUSH_TARGET="$remote"
          break
        fi
      done
      PR_HEAD_PUSH_TARGET="${PR_HEAD_PUSH_TARGET:-$PR_HEAD_CLONE_URL}"
      if git -C "$WORKTREE_PATH" push "$PR_HEAD_PUSH_TARGET" "HEAD:refs/heads/$PR_HEAD_BRANCH"; then
        PUBLISHED_GENERATED_HEAD=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM" | jq -er '.head.sha') || {
          WORKFLOW_RESULT=INCOMPLETE
          WORKFLOW_REASON=pr-metadata-api-failure
        }
        if [ "${PUBLISHED_GENERATED_HEAD:-}" = "$GENERATED_COMMIT_SHA" ]; then
          GENERATED_PUSH_RECOVERED=true
        else
          WORKFLOW_RESULT=INCOMPLETE
          WORKFLOW_REASON=pr-head-shift
        fi
      else
        WORKFLOW_RESULT=INCOMPLETE
        WORKFLOW_REASON=generated-push-failed
      fi
    elif [ -z "${WORKFLOW_REASON:-}" ]; then
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=pr-head-shift
    fi

    if [ "$GENERATED_PUSH_RECOVERED" = "true" ]; then
      PR_HEAD_SHA="$GENERATED_COMMIT_SHA"
      GENERATED_COMMIT_STATUS=""
      GENERATED_COMMIT_PARENT=""
      GENERATED_COMMIT_SHA=""
      set_loop_field "$STATE_FILE" "generated_commit_status" "" "$WORKFLOW_STATE_PATH"
      set_loop_field "$STATE_FILE" "generated_commit_parent" "" "$WORKFLOW_STATE_PATH"
      set_loop_field "$STATE_FILE" "generated_commit_sha" "" "$WORKFLOW_STATE_PATH"
    fi
  fi
fi
```

If this block sets `WORKFLOW_REASON`, follow **Hard Invariant Failure** and
stop. If `GENERATED_PUSH_RECOVERED=true`, skip the embedded address-review,
generation refresh, and generated commit subsections, then continue at
**Re-verify after fixes**. Otherwise continue below.

Before executing address-review, set its caller contract:

```bash
CALLER_LOOP_STATE_FILE="$STATE_FILE"
CALLER_WORKFLOW_STATE_PATH="$WORKFLOW_STATE_PATH"
```

Read `<PLUGIN_ROOT>/skills/address-review/SKILL.md`, execute its argument
resolution and **Embedded Workflow Contract**, then follow **Steps 2-11 only**:

- **Skip Step 1** (checkout/rebase) — already done in Steps 1-2 above
- **Skip standalone loop initialization** — the embedded contract resolves the
  address-review component in this caller-owned file
- **Skip Step 12** (watch loop) — not applicable in e2e-verify context
- Do NOT create a second loop state file — all phases are managed under the e2e-verify loop

After address-review returns, clear the caller variables and route its
structured component result before continuing with E2E-owned generated output:

```bash
WORKFLOW_STATE_PATH="$CALLER_WORKFLOW_STATE_PATH"
unset CALLER_LOOP_STATE_FILE CALLER_WORKFLOW_STATE_PATH
ADDRESS_REVIEW_RESULT=$(get_loop_field "$STATE_FILE" "result" "$ADDRESS_REVIEW_STATE_PATH")
ADDRESS_REVIEW_REASON=$(get_loop_field "$STATE_FILE" "reason" "$ADDRESS_REVIEW_STATE_PATH")
if [ "$ADDRESS_REVIEW_RESULT" != "complete" ]; then
  WORKFLOW_REASON="${ADDRESS_REVIEW_REASON:-address-review-incomplete}"
  WORKFLOW_RESULT=INCOMPLETE
fi
```

If address-review returned an incomplete result, follow **Hard Invariant
Failure** before performing any generated-output operation.

Address-review owns its exact review-fix commit and push. After Steps 2-11
return, require an empty index before handling the generated paths retained by
E2E:

### Require Empty Index After Review

```bash
if ! git -C "$WORKTREE_PATH" diff --cached --quiet; then
  echo "Error: Address-review returned with staged changes that E2E does not own."
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=unexpected-staged-changes
fi
```

If `WORKFLOW_REASON=unexpected-staged-changes`, follow **Hard Invariant
Failure** and stop before staging or verification.

### Refresh Generated Output After Review

Review fixes can change generator inputs. In both fix modes, rerun the selected
generation target after address-review returns, then replace `GEN_NEW_FILES`
with the exact post-review generated path set while still leaving the index
empty:

```bash
if [ -n "${GEN_TARGET:-}" ]; then
  if ! (cd "$WORKTREE_PATH" && make "$GEN_TARGET") 2>&1; then
    WORKFLOW_RESULT=INCOMPLETE
    WORKFLOW_REASON=generation-failed
  else
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
    GEN_NEW_FILES=()
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
          GEN_NEW_FILES+=("$GENERATED_FILE")
        fi
      done
    fi
  fi
fi
```

If `WORKFLOW_REASON=generation-failed`, follow **Hard Invariant Failure** and
stop before staging or verification.

### Commit E2E-Owned Generated Output

Stage and commit only the refreshed generated path set owned by E2E, then push
before post-fix verification:

```bash
if ! git -C "$WORKTREE_PATH" diff --cached --quiet; then
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=generator-staged-changes
fi
if [ "${GEN_NEW_FILES[0]+set}" = "set" ] && [ -z "${WORKFLOW_REASON:-}" ]; then
  if [ -z "${WORKFLOW_REASON:-}" ]; then
    GENERATED_PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM") || {
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=pr-metadata-api-failure
    }
  fi
  if [ -z "${WORKFLOW_REASON:-}" ]; then
    EXPECTED_REMOTE_HEAD_SHA=$(jq -er '.head.sha' <<< "$GENERATED_PR_JSON") || {
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=invalid-pr-head-metadata
    }
    PR_HEAD_BRANCH=$(jq -er '.head.ref' <<< "$GENERATED_PR_JSON") || {
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=invalid-pr-head-metadata
    }
    PR_HEAD_OWNER_REPO=$(jq -er '.head.repo.full_name' <<< "$GENERATED_PR_JSON") || {
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=missing-pr-head-repository
    }
    PR_HEAD_CLONE_URL=$(jq -er '.head.repo.clone_url' <<< "$GENERATED_PR_JSON") || {
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=missing-pr-head-repository
    }
  fi
  if [ -z "${WORKFLOW_REASON:-}" ]; then
    PR_HEAD_PUSH_TARGET=""
    for remote in $(git -C "$WORKTREE_PATH" remote); do
      REMOTE_URL=$(git -C "$WORKTREE_PATH" remote get-url "$remote")
      REMOTE_OWNER_REPO=$(printf '%s\n' "$REMOTE_URL" | sed 's|\.git$||' | sed -E 's|^https?://[^/]+/||' | sed -E 's|^ssh://[^/]+/||' | sed -E 's|^[^@]+@[^:]+:||')
      if [ "$REMOTE_OWNER_REPO" = "$PR_HEAD_OWNER_REPO" ]; then
        PR_HEAD_PUSH_TARGET="$remote"
        break
      fi
    done
    PR_HEAD_PUSH_TARGET="${PR_HEAD_PUSH_TARGET:-$PR_HEAD_CLONE_URL}"
    if [ "$(git -C "$WORKTREE_PATH" rev-parse HEAD)" != "$EXPECTED_REMOTE_HEAD_SHA" ]; then
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=pr-head-shift
    fi
  fi
  if [ -z "${WORKFLOW_REASON:-}" ]; then
    GENERATED_COMMIT_STATUS=committing
    GENERATED_COMMIT_PARENT="$EXPECTED_REMOTE_HEAD_SHA"
    GENERATED_COMMIT_SHA=""
    if [ -n "${STATE_FILE:-}" ] && [ -f "$STATE_FILE" ]; then
      set_loop_field "$STATE_FILE" "generated_commit_status" "committing" "$WORKFLOW_STATE_PATH"
      set_loop_field "$STATE_FILE" "generated_commit_parent" "$GENERATED_COMMIT_PARENT" "$WORKFLOW_STATE_PATH"
      set_loop_field "$STATE_FILE" "generated_commit_sha" "" "$WORKFLOW_STATE_PATH"
    fi
    if ! git -C "$WORKTREE_PATH" add -- "${GEN_NEW_FILES[@]}"; then
      git -C "$WORKTREE_PATH" restore --staged -- "${GEN_NEW_FILES[@]}" 2>/dev/null || true
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=generated-staging-failed
    elif git -C "$WORKTREE_PATH" diff --cached --quiet; then
      echo "Error: Retained generated paths produced no staged changes."
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=generated-output-missing
    else
      EXPECTED_GENERATED_PATHS_JSON=$(jq -cn '$ARGS.positional | sort' --args "${GEN_NEW_FILES[@]}")
      CACHED_GENERATED_FILES=()
      while IFS= read -r -d '' CACHED_GENERATED_FILE; do
        CACHED_GENERATED_FILES+=("$CACHED_GENERATED_FILE")
      done < <(git -C "$WORKTREE_PATH" diff --cached --name-only -z)
      CACHED_GENERATED_PATHS_JSON=$(jq -cn '$ARGS.positional | sort' --args "${CACHED_GENERATED_FILES[@]}")
      if [ "$CACHED_GENERATED_PATHS_JSON" != "$EXPECTED_GENERATED_PATHS_JSON" ]; then
        git -C "$WORKTREE_PATH" restore --staged -- "${GEN_NEW_FILES[@]}"
        WORKFLOW_RESULT=INCOMPLETE
        WORKFLOW_REASON=generated-index-mismatch
      fi
    fi
  fi
  if [ -z "${WORKFLOW_REASON:-}" ]; then
    if ! git -C "$WORKTREE_PATH" commit -m "chore: refresh generated output"; then
      git -C "$WORKTREE_PATH" restore --staged -- "${GEN_NEW_FILES[@]}" 2>/dev/null || true
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=generated-commit-failed
    else
      GENERATED_COMMIT_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD)
      GENERATED_COMMIT_STATUS=push-pending
      if [ -n "${STATE_FILE:-}" ] && [ -f "$STATE_FILE" ]; then
        set_loop_field "$STATE_FILE" "generated_commit_status" "push-pending" "$WORKFLOW_STATE_PATH"
        set_loop_field "$STATE_FILE" "generated_commit_sha" "$GENERATED_COMMIT_SHA" "$WORKFLOW_STATE_PATH"
      fi
    fi
  fi
  if [ -z "${WORKFLOW_REASON:-}" ]; then
    if ! git -C "$WORKTREE_PATH" push "$PR_HEAD_PUSH_TARGET" "HEAD:refs/heads/$PR_HEAD_BRANCH"; then
      WORKFLOW_RESULT=INCOMPLETE
      WORKFLOW_REASON=generated-push-failed
    else
      PR_HEAD_SHA="$GENERATED_COMMIT_SHA"
      PUBLISHED_HEAD_SHA=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM" | jq -er '.head.sha') || {
        WORKFLOW_RESULT=INCOMPLETE
        WORKFLOW_REASON=pr-metadata-api-failure
      }
      if [ "${PUBLISHED_HEAD_SHA:-}" != "$PR_HEAD_SHA" ]; then
        WORKFLOW_RESULT=INCOMPLETE
        WORKFLOW_REASON=pr-head-shift
      else
        GENERATED_COMMIT_STATUS=""
        GENERATED_COMMIT_PARENT=""
        GENERATED_COMMIT_SHA=""
        if [ -n "${STATE_FILE:-}" ] && [ -f "$STATE_FILE" ]; then
          set_loop_field "$STATE_FILE" "generated_commit_status" "" "$WORKFLOW_STATE_PATH"
          set_loop_field "$STATE_FILE" "generated_commit_parent" "" "$WORKFLOW_STATE_PATH"
          set_loop_field "$STATE_FILE" "generated_commit_sha" "" "$WORKFLOW_STATE_PATH"
        fi
      fi
    fi
  fi
fi
```

If this block sets `WORKFLOW_REASON`, follow **Hard Invariant Failure** and stop
before post-fix verification. Never stage generated paths when the PR metadata
cannot be read or the local parent is not the exact published PR head.

### Re-verify after fixes

**CRITICAL:** Step 3 modified code, so re-run build verification before E2E:

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

If `BUILD_RESULT=fail`, report `WORKFLOW_RESULT=INCOMPLETE` and
`WORKFLOW_REASON=verification-failed`, follow **Hard Invariant Failure**, and
stop. Fix the failure before rerunning.

### Verify the Final Published Head

After post-fix local verification, capture the final published head and repeat
address-review Step 11. The CI result and unresolved-thread count must apply to
this exact head, including any E2E-owned generated-output commit:

```bash
FINAL_REVIEW_HEAD=$(git -C "$WORKTREE_PATH" rev-parse HEAD)
FINAL_PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=pr-metadata-api-failure
}
if [ -z "${WORKFLOW_REASON:-}" ]; then
  PUBLISHED_FINAL_REVIEW_HEAD=$(jq -er '.head.sha' <<< "$FINAL_PR_JSON") || {
    WORKFLOW_RESULT=INCOMPLETE
    WORKFLOW_REASON=invalid-pr-head-metadata
  }
fi
if [ -z "${WORKFLOW_REASON:-}" ] && [ "$PUBLISHED_FINAL_REVIEW_HEAD" != "$FINAL_REVIEW_HEAD" ]; then
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=pr-head-shift
fi
EXPECTED_REVIEW_HEAD="$FINAL_REVIEW_HEAD"
```

If this block sets `WORKFLOW_REASON`, follow **Hard Invariant Failure** and stop.
Otherwise, read `<PLUGIN_ROOT>/skills/address-review/SKILL.md` and
repeat **Step 11 only** before proceeding to E2E testing. Do not proceed until
CI is green and the unresolved-thread count is zero for the exact local and
published final head. Step 11 must retain `EXPECTED_REVIEW_HEAD` and reject any
PR head change observed by its fresh metadata read.

---
