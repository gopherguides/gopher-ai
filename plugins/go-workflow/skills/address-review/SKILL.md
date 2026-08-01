---
name: address-review
description: "Address pull request review feedback from humans or bots. Use when existing comments, requested changes, unresolved review threads, or CodeRabbit/codex review findings need code fixes, verification, push updates, and thread resolution. SKIP fresh code-review requests with no existing feedback; use review-deep."
argument-hint: "[PR-number] [--no-watch]"
disable-model-invocation: true
---

# Address PR Review Comments

Before requesting decisions or delegating work, read
`${CLAUDE_PLUGIN_ROOT}/lib/driver-interaction.md` and follow its
cross-platform capability-binding rules.

Read `${CLAUDE_PLUGIN_ROOT}/lib/decision-gates.md` before resolving any workflow
choice.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/github-rest.sh"
```

## Output Durability

Replies to review comments and any new commit messages describe what behavior changed and why, not file paths or line numbers. A reviewer reading the reply six months later, after the file in question has moved, must still understand what was fixed.

**If `$ARGUMENTS` is empty or not provided:**

Auto-detect PR from current branch:

```bash
CURRENT_CHECKOUT_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_PATH="$CURRENT_CHECKOUT_ROOT"
CURRENT_PR_JSON=$(cd "$WORKTREE_PATH" && github_current_pr 2>/dev/null) || true
jq -r '.number' <<< "$CURRENT_PR_JSON" 2>/dev/null
```

If no PR is found, display usage:

**Claude Code:** `/go-workflow:address-review [PR-number] [--no-watch]`

**Codex:** `$go-workflow:address-review [PR-number] [--no-watch]`

**Example:** `/address-review 123` or just `/address-review` on a PR branch. Add `--no-watch` to exit after one fix cycle instead of watching for bot re-reviews.

This is a **missing-intent gate**. Request: "No PR was found for the current
branch. What PR number should I address?" If structured input is unavailable,
ask in the final response and stop before loop initialization or a completion
claim.

---

**If PR number is available (from `$ARGUMENTS` or auto-detected):**

## Parse Arguments

```bash
WATCH_MODE=true
PR_ARG=""
for arg in $ARGUMENTS; do
  case "$arg" in
    --no-watch) WATCH_MODE=false ;;
    *) PR_ARG="$arg" ;;
  esac
done
echo "WATCH_MODE=$WATCH_MODE PR_ARG=$PR_ARG"
```

## Security Validation

!if [ -n "$PR_ARG" ] && ! echo "$PR_ARG" | grep -qE '^[0-9]+$'; then echo "Error: PR number must be numeric"; exit 1; fi

## Resolve PR Number

```bash
CURRENT_CHECKOUT_ROOT=$(git rev-parse --show-toplevel)
ORIGINAL_REPO_ROOT=$(git -C "$CURRENT_CHECKOUT_ROOT" worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print; exit}')
WORKTREE_PATH="${WORKTREE_PATH:-$CURRENT_CHECKOUT_ROOT}"
if [ -z "$ORIGINAL_REPO_ROOT" ] || [ "${ORIGINAL_REPO_ROOT#/}" = "$ORIGINAL_REPO_ROOT" ] ||
   [ -z "$WORKTREE_PATH" ] || [ "${WORKTREE_PATH#/}" = "$WORKTREE_PATH" ] || [ ! -d "$WORKTREE_PATH" ]; then
  echo "ERROR: Could not resolve absolute repository paths."
  exit 1
fi
CURRENT_REPO_SLUG=$(cd "$WORKTREE_PATH" && gh api "repos/{owner}/{repo}" --jq '.full_name')
REPO_SLUG="${REPO_SLUG:-$CURRENT_REPO_SLUG}"
if [ -n "$PR_ARG" ]; then
  RESOLVED_PR="$PR_ARG"
elif CURRENT_PR_JSON=$(cd "$WORKTREE_PATH" && github_current_pr 2>/dev/null); then
  RESOLVED_PR=$(jq -er '.number' <<< "$CURRENT_PR_JSON")
else
  RESOLVED_PR="auto"
fi
PR_NUM="$RESOLVED_PR"
echo "Resolved PR: $RESOLVED_PR"
```

## Loop Initialization & Re-entry

Read `loop-management.md` for loop setup and phase re-entry logic. Key behavior:
- If resuming `watching` phase in watch mode → skip to Step 12 (watch loop)
- If resuming `watching` phase in no-watch mode → clear phase, run full fix cycle
- Otherwise → continue normally

## Hard Invariant Failure

When this skill or a supporting file reports
`WORKFLOW_RESULT=INCOMPLETE`, persist the supplied reason:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
set_loop_field "$LOOP_STATE_FILE" "workflow_result" "incomplete"
set_loop_field "$LOOP_STATE_FILE" "workflow_reason" "$WORKFLOW_REASON"
set_loop_phase "$LOOP_STATE_FILE" "incomplete"
set_loop_field "$LOOP_STATE_FILE" "completion_promise" "INCOMPLETE"
```

Output `<done>INCOMPLETE</done>` and stop. Never fetch feedback, edit files,
push, or output `<done>COMPLETE</done>` from an invariant-failure path.

## Context & Bot Discovery

Read `setup-and-discovery.md` for REST PR context gathering, mode banner display, and bot discovery from REST formal reviews plus GraphQL review threads. Match discovered authors against `bot-registry.md`.

---

## Step 1: Checkout PR Branch and Rebase

Read `checkout-rebase.md` for the full procedure: fetch and checkout the REST-declared PR head without overwriting local work, preserve fork/base metadata, check if behind, rebase + force-push if needed, and wait for CI after rebase.

## Step 2: Fetch All Review Feedback

Read `fetch-feedback.md` for GraphQL review threads (line-specific, auto-resolvable) and REST formal reviews (CHANGES_REQUESTED).

## Steps 3-9: Fix Cycle

Read `fix-cycle.md` for the complete fix cycle:
- **Step 3:** Categorize comments into Group A (resolvable threads) and Group B (pending reviews)
- **Step 4:** Address each comment — parallel dispatch for 3+ comments on different files, sequential otherwise. Understand request, locate code, make minimal fix, validate against feedback
- **Step 4.5:** Generate tests for testable fixes (read `test-generation.md`)
- **Step 5:** Verify locally — `go -C "$WORKTREE_PATH" build`, `go -C "$WORKTREE_PATH" test`, and a worktree-scoped `golangci-lint`
- **Step 6:** Commit and push, capture `BOT_REVIEW_BASELINE` timestamp
- **Step 7:** Watch CI — retry up to 3x if no checks reported
- **Step 8:** Reply to each comment
- **Step 9:** Resolve review threads via GraphQL (Group A only)

## Step 10: Request Re-review

Read `bot-registry.md` for the full re-review procedure (Steps 10a-10e) including bot detection, opt-out checks, and data-driven re-review triggering.

## Step 11: Verify Completion

Confirm all resolvable threads are resolved and CI is passing:

```bash
PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=pr-metadata-api-failure
}
OWNER=$(jq -er '.base.repo.owner.login' <<< "$PR_JSON")
REPO=$(jq -er '.base.repo.name' <<< "$PR_JSON")

(cd "$WORKTREE_PATH" && gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes { isResolved }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM") | jq '.data.repository.pullRequest.reviewThreads.nodes | map(select(.isResolved == false)) | length'
```

Pin completion checks to the exact published PR head:

```bash
PR_HEAD_SHA=$(jq -er '.head.sha' <<< "$PR_JSON") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=invalid-pr-metadata
}

CHECK_STATUS=0
CHECKS_JSON=$(cd "$WORKTREE_PATH" && github_watch_pr_checks "$PR_NUM" "$PR_HEAD_SHA") || CHECK_STATUS=$?
case "$CHECK_STATUS" in
  0) printf '%s\n' "$CHECKS_JSON" | jq '.' ;;
  1) echo "CI failed. Return to the fix cycle and do not claim completion." ;;
  2) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=checks-registration-timeout ;;
  3) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=checks-api-failure ;;
  4) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=pr-head-shift ;;
  *) WORKFLOW_RESULT=INCOMPLETE; WORKFLOW_REASON=checks-unknown-failure ;;
esac
```

For statuses 2-4 or an unknown status, follow **Hard Invariant Failure**. A
registration timeout, API failure, or PR head shift is never a successful CI
result.

## Step 12: Watch for Bot Re-review

**Skip if `WATCH_MODE` is `false` or no review bots were detected.**

Read `watch-loop.md` for Phase Transition logic, bot polling, quiet period detection, timeout handling, and re-trigger procedures.

---

## Completion Criteria

### With `--no-watch`:
Output `<done>COMPLETE</done>` when: branch rebased, all feedback addressed, fixes validated, local verification passes, changes pushed, CI green, replies posted, threads resolved, re-review requested.

### Default (watch mode):
All above, PLUS all detected review bots signaled approval per `bot-registry.md`.

**When ALL criteria are met, output exactly:** `<done>COMPLETE</done>`

If the user exits or skips a bot before all detected bots approve, follow the **Incomplete Approval Outcome** procedure in `watch-loop.md`. Persist `approval_result` and `approval_reason`, then output `<done>INCOMPLETE</done>` instead. Never output the completion marker for this path.

**Safety:** If 15+ iterations complete without success, document the blocking
evidence and stop incomplete. Do not bypass review or approval criteria.

## Supporting Files

- `bot-registry.md` — Bot registry table, detection logic, and Step 10 re-review procedures
- `test-generation.md` — Step 4.5 test generation guidelines and testability rules
- `watch-loop.md` — Phase Transition logic and Step 12 watch loop procedures
- `loop-management.md` — Loop initialization and re-entry check logic
- `setup-and-discovery.md` — PR context gathering, mode banner, and bot discovery
- `checkout-rebase.md` — Step 1 checkout and rebase procedure
- `fetch-feedback.md` — Step 2 GraphQL queries for review feedback
- `fix-cycle.md` — Steps 3-9 categorize, fix, verify, commit, CI, reply, resolve
