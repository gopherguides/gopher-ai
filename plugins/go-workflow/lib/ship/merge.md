# Ship — Phase 6: Merge (Step 13)

Loaded by `skills/ship/SKILL.md` Phase 6. Owns the final-checks block, merge
strategy detection, REST mergeability decision tree, and summary rendering.

**CRITICAL: NEVER use `--admin` flag. NEVER use any flag/method that bypasses branch protection.** If the merge fails due to protection, STOP and inform the user — do NOT retry with elevated privileges.

## 13a. Final checks

1. Verify CI is green for the exact expected head, unless `has_ci=false` in the
   state file:

```bash
HAS_CI=$(get_loop_field "$STATE_FILE" "has_ci" "$WORKFLOW_STATE_PATH")
HEAD_SHA=$(get_loop_field "$STATE_FILE" "head_sha" "$WORKFLOW_STATE_PATH")
if [ "$HAS_CI" = "true" ]; then
  if [ -z "$HEAD_SHA" ]; then
    WORKFLOW_REASON="ci-head-missing"
  elif ! FINAL_PR=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM"); then
    WORKFLOW_REASON="ci-pr-api-error"
  elif [ "$(jq -er '.head.sha' <<< "$FINAL_PR")" != "$HEAD_SHA" ]; then
    WORKFLOW_REASON="ci-head-shift"
  elif ! FINAL_CHECKS=$(cd "$WORKTREE_PATH" && github_check_snapshot "$HEAD_SHA"); then
    WORKFLOW_REASON="ci-api-error"
  elif [ "$(jq '.items | length' <<< "$FINAL_CHECKS")" -eq 0 ]; then
    WORKFLOW_REASON="ci-checks-not-registered"
  elif [ "$(jq '[.items[] | select(.terminal == false)] | length' <<< "$FINAL_CHECKS")" -gt 0 ]; then
    WORKFLOW_REASON="ci-not-complete"
  elif [ "$(jq '[.items[] | select(.terminal and (.successful | not))] | length' <<< "$FINAL_CHECKS")" -gt 0 ]; then
    WORKFLOW_REASON="ci-not-green"
  fi
fi
```

Any reason set by this block follows **Hard Invariant Failure**. Missing check
registration, API failure, and a shifted PR head never count as green CI.

2. Check for unresolved review threads:

```bash
REPOSITORY=$(gh api "repos/$REPO_SLUG")
OWNER=$(jq -er '.owner.login' <<< "$REPOSITORY")
REPO=$(jq -er '.name' <<< "$REPOSITORY")
UNRESOLVED=$(cd "$WORKTREE_PATH" && gh api graphql -f query='
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

3. Check for **active** human `CHANGES_REQUESTED` by computing the latest REST
review per human:

```bash
if ! FORMAL_REVIEWS=$(cd "$WORKTREE_PATH" && github_pr_reviews "$PR_NUM"); then
  WORKFLOW_REASON="reviews-api-error"
fi
BLOCKING_HUMANS=$(jq '
  [
    .[]
    | select(.user.type == "User")
    | select(.user.login | test("\\[bot\\]$"; "i") | not)
    | {
        login: .user.login,
        state: .state,
        submitted_at: (.submitted_at // ""),
        id: .id
      }
  ]
  | sort_by([.login, .submitted_at, .id])
  | group_by(.login)
  | map(last)
  | [.[] | select(.state == "CHANGES_REQUESTED")]
  | length
' <<< "$FORMAL_REVIEWS")
```

If the review list cannot be read, follow **Hard Invariant Failure** with
`WORKFLOW_REASON=reviews-api-error`.

If unresolved threads exist, do not merge:

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=unresolved-review-threads
```

If active human `CHANGES_REQUESTED` exists, do not merge:

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=human-changes-requested
```

For either condition, follow the top-level **Hard Invariant Failure** procedure
and stop. Review requirements cannot be waived by a driver.

4. Check the local E2E gate recorded during Phase 1. A UI-visible diff that did
   not complete browser E2E must stop here even if CI is green:

```bash
E2E_REQUIRED=$(get_loop_field "$STATE_FILE" "e2e_required" "$WORKFLOW_STATE_PATH")
E2E_RESULT=$(get_loop_field "$STATE_FILE" "e2e_result" "$WORKFLOW_STATE_PATH")
E2E_SKIP_REASON=$(get_loop_field "$STATE_FILE" "e2e_skip_reason" "$WORKFLOW_STATE_PATH")
E2E_PAGES=$(get_loop_field "$STATE_FILE" "e2e_pages_tested" "$WORKFLOW_STATE_PATH")
E2E_REQUIRED="${E2E_REQUIRED:-false}"
E2E_RESULT="${E2E_RESULT:-skipped}"
E2E_PAGES="${E2E_PAGES:-0}"

if [ "$E2E_REQUIRED" = "true" ] && [ "$E2E_RESULT" != "passed" ]; then
  echo "E2E PREREQUISITE MISSING - UI-visible diff has no passing browser E2E result."
  echo "E2E status: ${E2E_RESULT}; reason: ${E2E_SKIP_REASON:-unknown}; pages tested: ${E2E_PAGES}"
  echo "No merge. Start the dev server or fix E2E, then re-run \$go-workflow:ship."
  WORKFLOW_REASON="required-e2e-not-passed"
fi
```

This is a backstop for re-entry and manual phase jumps. Do not prompt to merge
when `e2e_result` is `blocked`; follow the top-level **Hard Invariant Failure**
procedure and stop with `WORKFLOW_REASON=required-e2e-not-passed`.

## 13b. `--no-merge` early exit

If `NO_MERGE=true`:

- Display the summary (see 13f)
- Continue to Step 13g so embedded ship returns a structured result and
  standalone ship emits its terminal marker

## 13c. Auto-detect merge strategy

```bash
if ! REPOSITORY=$(gh api "repos/$REPO_SLUG"); then
  WORKFLOW_REASON="repository-api-error"
fi
OWNER=$(jq -er '.owner.login' <<< "$REPOSITORY")
REPO=$(jq -er '.name' <<< "$REPOSITORY")
MERGE_SETTINGS=$(jq '{merge: .allow_merge_commit, squash: .allow_squash_merge, rebase: .allow_rebase_merge}' <<< "$REPOSITORY")

MERGE_METHOD="${SHIP_MERGE_STRATEGY:-}"
if [ -n "$MERGE_METHOD" ]; then
  case "$MERGE_METHOD" in
    merge|squash|rebase) ;;
    *)
      echo "Invalid SHIP_MERGE_STRATEGY '$MERGE_METHOD'. Expected merge, squash, or rebase."
      if [ "${SHIP_EMBEDDED:-false}" = "true" ]; then
        set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "incomplete" "invalid-merge-strategy" "incomplete"
      else
        set_loop_terminal_result "$STATE_FILE" "incomplete" "invalid-merge-strategy" "incomplete" "INCOMPLETE"
        echo "WORKFLOW_RESULT=INCOMPLETE"
        echo "WORKFLOW_REASON=invalid-merge-strategy"
        echo "<done>INCOMPLETE</done>"
      fi
      exit 1
      ;;
  esac

  if ! echo "$MERGE_SETTINGS" | jq -e --arg method "$MERGE_METHOD" '.[$method] == true' >/dev/null 2>&1; then
    echo "Configured merge strategy '$MERGE_METHOD' is not allowed by $OWNER/$REPO."
    if [ "${SHIP_EMBEDDED:-false}" = "true" ]; then
      set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "incomplete" "merge-strategy-not-allowed" "incomplete"
    else
      set_loop_terminal_result "$STATE_FILE" "incomplete" "merge-strategy-not-allowed" "incomplete" "INCOMPLETE"
      echo "WORKFLOW_RESULT=INCOMPLETE"
      echo "WORKFLOW_REASON=merge-strategy-not-allowed"
      echo "<done>INCOMPLETE</done>"
    fi
    exit 1
  fi
elif echo "$MERGE_SETTINGS" | jq -e '.squash == true' >/dev/null 2>&1; then
  MERGE_METHOD="squash"
elif echo "$MERGE_SETTINGS" | jq -e '.rebase == true' >/dev/null 2>&1; then
  MERGE_METHOD="rebase"
elif echo "$MERGE_SETTINGS" | jq -e '.merge == true' >/dev/null 2>&1; then
  MERGE_METHOD="merge"
else
  echo "No allowed merge strategy is configured for $OWNER/$REPO."
  if [ "${SHIP_EMBEDDED:-false}" = "true" ]; then
    set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "incomplete" "merge-strategy-unavailable" "incomplete"
  else
    set_loop_terminal_result "$STATE_FILE" "incomplete" "merge-strategy-unavailable" "incomplete" "INCOMPLETE"
    echo "WORKFLOW_RESULT=INCOMPLETE"
    echo "WORKFLOW_REASON=merge-strategy-unavailable"
    echo "<done>INCOMPLETE</done>"
  fi
  exit 1
fi

MERGE_FLAG="--$MERGE_METHOD"
```

If repository metadata cannot be read, follow **Hard Invariant Failure** with
`WORKFLOW_REASON=repository-api-error` before selecting a merge strategy.

`SHIP_MERGE_STRATEGY` is the explicit per-project policy and must be `merge`,
`squash`, or `rebase`. Ship uses it exactly when the repository allows it and
stops with an error otherwise. Without an explicit policy, prefer squash >
rebase > merge.

## 13d. Branch protection mergeability check

GitHub computes REST mergeability asynchronously. Retry a bounded number of
times while `.mergeable` is null or `.mergeable_state` is missing/unknown, and
pin every read to `HEAD_SHA`:

```bash
MERGEABLE="null"
STATE_STATUS="unknown"
for ATTEMPT in $(seq 1 6); do
  if ! MERGE_STATE=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM"); then
    WORKFLOW_REASON="mergeability-api-error"
    break
  fi
  if [ "$(jq -er '.head.sha' <<< "$MERGE_STATE")" != "$HEAD_SHA" ]; then
    WORKFLOW_REASON="merge-head-shift"
    break
  fi
  MERGEABLE=$(jq -r 'if .mergeable == null then "null" else .mergeable end' <<< "$MERGE_STATE")
  STATE_STATUS=$(jq -r '(.mergeable_state // "unknown") | ascii_downcase' <<< "$MERGE_STATE")
  if [ "$MERGEABLE" != "null" ] && [ "$STATE_STATUS" != "unknown" ]; then
    break
  fi
  if [ "$ATTEMPT" -lt 6 ]; then
    sleep 5
  fi
done

if [ -z "${WORKFLOW_REASON:-}" ] && { [ "$MERGEABLE" = "null" ] || [ "$STATE_STATUS" = "unknown" ]; }; then
  WORKFLOW_REASON="mergeability-unknown"
fi

ENCODED_BRANCH=$(printf '%s' "$BASE_BRANCH" | jq -sRr @uri)
if ! BRANCH_RULES=$(gh api "repos/$REPO_SLUG/rules/branches/$ENCODED_BRANCH"); then
  WORKFLOW_REASON="merge-queue-api-error"
else
  HAS_MERGE_QUEUE=$(jq '[.[] | select(.type == "merge_queue")] | length > 0' <<< "$BRANCH_RULES")
fi
```

If this block sets `WORKFLOW_REASON`, follow **Hard Invariant Failure** before
evaluating the table.

### Decision tree (strict — do not invent reasons to merge for unhandled states)

| `MERGEABLE` | `STATE_STATUS` | Action |
|-------------|----------------|--------|
| `false` | any | **STOP.** Set `WORKFLOW_REASON=merge-conflict`. |
| any | `dirty` | **STOP.** Set `WORKFLOW_REASON=merge-conflict`. |
| any | `blocked` with `HAS_MERGE_QUEUE=true` | Proceed to required queue enqueueing. |
| any | `blocked` without a merge queue | **STOP.** Set `WORKFLOW_REASON=branch-protection-blocked`. |
| `true` | `clean` or `has_hooks` | Proceed. |
| `true` | `behind` | Proceed; the SHA-pinned merge endpoint enforces current server policy. |
| `true` | `unstable` | **STOP.** Set `WORKFLOW_REASON=mergeability-unstable`. |
| any | other | **STOP.** Set `WORKFLOW_REASON=pr-not-ready`. |

For every STOP row:

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=<reason from the table>
```

Follow the top-level **Hard Invariant Failure** procedure. Do not prompt for a
bypass and do not output `<done>SHIPPED</done>`.

## 13e. Merge the PR

The CLI call below is the required merge-queue exception because GitHub has no
REST enqueue endpoint. Ordinary merges use the SHA-pinned REST endpoint and
validate its `.merged` result.

```bash
if [ "$HAS_MERGE_QUEUE" = "true" ]; then
  gh pr merge "$PR_NUM" --repo "$REPO_SLUG" --delete-branch
else
  if ! MERGE_RESULT=$(gh api --method PUT "repos/$REPO_SLUG/pulls/$PR_NUM/merge" \
    -f merge_method="$MERGE_METHOD" \
    -f sha="$HEAD_SHA"); then
    WORKFLOW_REASON="merge-command-failed"
  elif ! jq -e '.merged == true' <<< "$MERGE_RESULT" >/dev/null; then
    jq -r '.message // "GitHub did not merge the pull request"' <<< "$MERGE_RESULT" >&2
    WORKFLOW_REASON="merge-command-failed"
  fi
fi
```

If the merge command fails (non-zero exit code):

- Do NOT retry with `--admin` or any other bypass flag
- Display the error output
- Set `WORKFLOW_REASON=merge-command-failed`
- Follow the top-level **Hard Invariant Failure** procedure

## 13f. Display summary

Read coverage and e2e results. Coverage may have skipped (e.g., all changed files were `package main`); in that case `coverage_skip_reason` is set and `coverage_result` is empty. Render a textual reason instead of `<COV_RESULT>%`:

```bash
COV_RESULT=$(get_loop_field "$STATE_FILE" "coverage_result" "$WORKFLOW_STATE_PATH")
COV_SKIP_REASON=$(get_loop_field "$STATE_FILE" "coverage_skip_reason" "$WORKFLOW_STATE_PATH")
COV_THRESHOLD=$(get_loop_field "$STATE_FILE" "coverage_threshold" "$WORKFLOW_STATE_PATH")
TESTS_GEN=$(get_loop_field "$STATE_FILE" "coverage_tests_generated" "$WORKFLOW_STATE_PATH")
E2E_ATTEMPTED=$(get_loop_field "$STATE_FILE" "e2e_attempted" "$WORKFLOW_STATE_PATH")
E2E_RESULT=$(get_loop_field "$STATE_FILE" "e2e_result" "$WORKFLOW_STATE_PATH")
E2E_PAGES=$(get_loop_field "$STATE_FILE" "e2e_pages_tested" "$WORKFLOW_STATE_PATH")
E2E_REQUIRED=$(get_loop_field "$STATE_FILE" "e2e_required" "$WORKFLOW_STATE_PATH")
E2E_SKIP_REASON=$(get_loop_field "$STATE_FILE" "e2e_skip_reason" "$WORKFLOW_STATE_PATH")
COV_THRESHOLD="${COV_THRESHOLD:-60}"
TESTS_GEN="${TESTS_GEN:-0}"
E2E_RESULT="${E2E_RESULT:-skipped}"
E2E_PAGES="${E2E_PAGES:-0}"
E2E_REQUIRED="${E2E_REQUIRED:-false}"

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

# E2E line: never render missing required E2E as complete.
if [ -z "$E2E_RESULT" ]; then
  E2E_RESULT="skipped"
fi

if [ "$E2E_REQUIRED" = "true" ] && [ "$E2E_RESULT" != "passed" ]; then
  E2E_LINE="blocked - ${E2E_SKIP_REASON:-required E2E did not pass}; ${E2E_PAGES} pages tested"
  VERIFICATION_LINE="Verification partial - E2E was blocked. Unit, integration, lint, and CI may have passed, but browser verification did not."
elif [ "$E2E_RESULT" = "skipped" ] && [ -n "$E2E_SKIP_REASON" ]; then
  E2E_LINE="skipped - $E2E_SKIP_REASON"
  VERIFICATION_LINE="Verification partial - E2E was skipped because $E2E_SKIP_REASON."
elif [ "$E2E_RESULT" = "skipped" ]; then
  E2E_LINE="skipped"
  VERIFICATION_LINE="Verification partial - E2E was skipped."
else
  E2E_LINE="${E2E_PAGES} pages tested, ${E2E_RESULT}"
  VERIFICATION_LINE="Verification complete."
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
- **E2E tests:** <E2E_LINE>
- **CI:** green
- **Bot approvals:** <list or "none required">
- **Merge strategy:** <merge|squash|rebase>
- **Merged:** yes (or "skipped — --no-merge")

<VERIFICATION_LINE>
```

## 13g. Return result

Persist the result before returning. The caller owns the only terminal promise
and marker during composition.

```bash
set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "shipped" "" "complete"
if [ "$SHIP_EMBEDDED" != "true" ]; then
  echo "<done>SHIPPED</done>"
fi
```
