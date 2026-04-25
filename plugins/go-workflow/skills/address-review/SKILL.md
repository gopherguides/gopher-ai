---
name: address-review
description: "Address PR review feedback: fetch comments, fix in code, verify, push, resolve threads, request re-review. Use when reviewers/bots left feedback to apply."
argument-hint: "[PR-number] [--no-watch]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "Task", "AskUserQuestion", "Agent"]
---

# Address PR Review Comments

**If `$ARGUMENTS` is empty or not provided:**

Auto-detect PR from current branch:

```bash
gh pr view --json number --jq '.number' 2>/dev/null
```

If no PR found, display usage and ask:

**Usage:** `/address-review [PR-number] [--no-watch]`

**Example:** `/address-review 123` or just `/address-review` on a PR branch. Add `--no-watch` to exit after one fix cycle instead of watching for bot re-reviews.

Ask the user: "No PR found for current branch. What PR number would you like to address?"

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
RESOLVED_PR="${PR_ARG:-$(gh pr view --json number --jq '.number' 2>/dev/null || echo 'auto')}"
echo "Resolved PR: $RESOLVED_PR"
```

## Loop Initialization & Re-entry

Read `loop-management.md` for loop setup and phase re-entry logic. Key behavior:
- If resuming `watching` phase in watch mode → skip to Step 12 (watch loop)
- If resuming `watching` phase in no-watch mode → clear phase, run full fix cycle
- Otherwise → continue normally

## Context & Bot Discovery

Read `setup-and-discovery.md` for PR context gathering, mode banner display, and bot discovery via GraphQL. Match discovered authors against `bot-registry.md`.

---

## Step 1: Checkout PR Branch and Rebase

Read `checkout-rebase.md` for the full procedure: checkout via `gh pr checkout`, detect base remote, check if behind, rebase + force-push if needed, wait for CI after rebase.

## Step 2: Fetch All Review Feedback

Read `fetch-feedback.md` for GraphQL queries to fetch review threads (line-specific, auto-resolvable) and pending reviews (CHANGES_REQUESTED).

## Steps 3-9: Fix Cycle

Read `fix-cycle.md` for the complete fix cycle:
- **Step 3:** Categorize comments into Group A (resolvable threads) and Group B (pending reviews)
- **Step 4:** Address each comment — parallel dispatch for 3+ comments on different files, sequential otherwise. Understand request, locate code, make minimal fix, validate against feedback
- **Step 4.5:** Generate tests for testable fixes (read `test-generation.md`)
- **Step 5:** Verify locally — `go build`, `go test`, `golangci-lint`
- **Step 6:** Commit and push, capture `BOT_REVIEW_BASELINE` timestamp
- **Step 7:** Watch CI — retry up to 3x if no checks reported
- **Step 8:** Reply to each comment
- **Step 9:** Resolve review threads via GraphQL (Group A only)

## Step 10: Request Re-review

Read `bot-registry.md` for the full re-review procedure (Steps 10a-10e) including bot detection, opt-out checks, and data-driven re-review triggering.

## Step 11: Verify Completion

Confirm all resolvable threads are resolved and CI is passing:

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')

gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes { isResolved }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq '.data.repository.pullRequest.reviewThreads.nodes | map(select(.isResolved == false)) | length'
```

Confirm CI: `gh pr checks "$PR_NUM"`

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

**Safety:** If 15+ iterations without success, document blockers and ask user.

## Supporting Files

- `bot-registry.md` — Bot registry table, detection logic, and Step 10 re-review procedures
- `test-generation.md` — Step 4.5 test generation guidelines and testability rules
- `watch-loop.md` — Phase Transition logic and Step 12 watch loop procedures
- `loop-management.md` — Loop initialization and re-entry check logic
- `setup-and-discovery.md` — PR context gathering, mode banner, and bot discovery
- `checkout-rebase.md` — Step 1 checkout and rebase procedure
- `fetch-feedback.md` — Step 2 GraphQL queries for review feedback
- `fix-cycle.md` — Steps 3-9 categorize, fix, verify, commit, CI, reply, resolve
