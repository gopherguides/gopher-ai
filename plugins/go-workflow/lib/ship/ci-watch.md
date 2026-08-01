# Ship — Phase 3: CI Watch (Step 10)

Loaded by `skills/ship/SKILL.md` Phase 3. Owns SHA-anchored CI watching.

## 10a. Capture and verify HEAD SHA

```bash
HAS_WORKFLOWS=""
for WORKFLOW_FILE in "$WORKTREE_PATH"/.github/workflows/*.yml "$WORKTREE_PATH"/.github/workflows/*.yaml; do
  if [ -f "$WORKFLOW_FILE" ]; then
    HAS_WORKFLOWS="$WORKFLOW_FILE"
    break
  fi
done
```

If no workflow files exist → persist `has_ci: false`,
`ci_skip_reason: no-workflow-files`, and skip to Step 11. Workflow files alone
do not establish that CI applies to the current PR; leave `has_ci` unset until
Step 10b determines whether checks registered or an active workflow applies.

Read `head_sha` from state file (set during push in Step 9c, after CI failure recovery in Step 10e, or after Step 12c):

```bash
HEAD_SHA=$(get_loop_field "$STATE_FILE" "head_sha" "$WORKFLOW_STATE_PATH")
if [ -z "$HEAD_SHA" ]; then
  HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD)
fi
echo "Watching CI for commit: $HEAD_SHA"
```

## 10b. Watch every check source for the correct SHA

Use the shared watcher. It provides the bounded registration window, combines
check runs with legacy commit statuses, waits through a stability window for
late registrations, aggregates every terminal failure, and verifies the PR
head after watching.

```bash
if CI_SNAPSHOT=$(cd "$WORKTREE_PATH" && github_watch_pr_checks "$PR_NUM" "$HEAD_SHA"); then
  CI_STATUS=0
else
  CI_STATUS=$?
fi

case "$CI_STATUS" in
  0)
    HAS_CI=true
    CI_SKIP_REASON=""
    ;;
  "$GITHUB_CHECKS_FAILED")
    HAS_CI=true
    ;;
  "$GITHUB_CHECKS_REGISTRATION_TIMEOUT")
    HAS_CI=registration-timeout
    ;;
  "$GITHUB_CHECKS_API_ERROR")
    WORKFLOW_REASON="ci-api-error"
    ;;
  "$GITHUB_CHECKS_HEAD_SHIFT")
    WORKFLOW_REASON="ci-head-shift"
    ;;
  *)
    WORKFLOW_REASON="ci-watch-unknown-error"
    ;;
esac
```

On status 0, persist `has_ci: true`, clear `ci_skip_reason`, display
`CI_SNAPSHOT`, and continue to Step 11. On `GITHUB_CHECKS_FAILED`, display the
full snapshot and continue to Step 10e. On `GITHUB_CHECKS_HEAD_SHIFT`, continue
to Step 10d. On `GITHUB_CHECKS_API_ERROR` or an unknown status, follow **Hard
Invariant Failure** immediately with the supplied reason. Never treat an API
failure or head shift as passing CI.

On `GITHUB_CHECKS_REGISTRATION_TIMEOUT`, determine whether any workflow can
produce a check for this PR before stopping:

1. Read the PR base branch, head branch, and changed paths.
2. Inspect each workflow's GitHub Actions state and `on` filters. Ignore
   disabled workflows and workflows limited to unrelated events such as
   `schedule` or `workflow_dispatch`.
3. Apply GitHub Actions branch and path filter semantics to
   `pull_request`/`pull_request_target` against the base branch and to `push`
   against the head branch. Include reusable workflows through any applicable
   caller.

If this establishes that definitively no active workflow applies, this is a
valid no-CI repository state rather than a passing check. Persist:

```
has_ci=false
ci_skip_reason=no-applicable-workflow
```

Then skip to Step 11. Do not offer a menu or ask the user to waive CI.

If at least one workflow applies, do not treat the absence as a pass:

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=ci-checks-not-registered
```

Follow the top-level **Hard Invariant Failure** procedure and stop. A later
invocation may repeat the bounded registration wait for the same `HEAD_SHA`.

If applicability cannot be determined from workflow state, triggers, filters,
callers, and changed paths, stop incomplete with
`WORKFLOW_REASON=ci-applicability-unknown`. Do not guess that CI is absent.

## 10c. Record the exact-head result

Persist `has_ci` and `ci_skip_reason` only after applying the Step 10b outcome.
The successful snapshot is the fresh CI evidence for this session.

```bash
set_loop_field "$STATE_FILE" "has_ci" "$HAS_CI" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "ci_skip_reason" "$CI_SKIP_REASON" "$WORKFLOW_STATE_PATH"
```

## 10d. Post-watch SHA validation

When the helper reports `GITHUB_CHECKS_HEAD_SHIFT`, or when explicitly
revalidating after the watch, read the PR through the shared REST helper:

```bash
if ! FINAL_PR=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM"); then
  WORKFLOW_REASON="ci-post-watch-api-error"
fi
FINAL_SHA=$(jq -er '.head.sha' <<< "$FINAL_PR")
if [ "$FINAL_SHA" != "$HEAD_SHA" ]; then
  echo "STOP: PR head shifted to SHA $FINAL_SHA during watch (expected $HEAD_SHA)."
  echo "A new commit landed on this PR that was NOT reviewed locally."
  echo "Restarting from review phase against the new HEAD."
  if [ -n "$(git -C "$WORKTREE_PATH" status --porcelain)" ]; then
    echo "BLOCKED: PR head shifted, but the working tree has uncommitted changes."
    echo "Inspect ownership before synchronization; never overwrite unrelated work."
    exit 1
  fi
  HEAD_SHA="$FINAL_SHA"
  BRANCH_REMOTE=$(git -C "$WORKTREE_PATH" config "branch.$(git -C "$WORKTREE_PATH" branch --show-current).remote" 2>/dev/null || echo "origin")
  PR_HEAD_BRANCH=$(jq -er '.head.ref' <<< "$FINAL_PR")
  git -C "$WORKTREE_PATH" fetch "$BRANCH_REMOTE" "$PR_HEAD_BRANCH"
  git -C "$WORKTREE_PATH" checkout "$PR_HEAD_BRANCH"
  git -C "$WORKTREE_PATH" reset --hard "$BRANCH_REMOTE/$PR_HEAD_BRANCH"
  set_loop_field "$STATE_FILE" "head_sha" "$HEAD_SHA" "$WORKFLOW_STATE_PATH"
  set_loop_json_field "$STATE_FILE" "pass" 0 "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "review_clean" "" "$WORKFLOW_STATE_PATH"
  set_loop_phase "$STATE_FILE" "review-required" "$WORKFLOW_STATE_PATH"
fi
```

If the PR read fails, follow **Hard Invariant Failure** with
`WORKFLOW_REASON=ci-post-watch-api-error`. A missing head SHA is an API/schema
failure, not a successful watch.

The dirty-tree check reapplies Step 3's driver-resolvable ownership policy
during recovery. Inspect the diff and original workflow scope. Commit only
validated workflow-owned changes; preserve unrelated changes and stop
incomplete with `WORKFLOW_REASON=dirty-worktree-head-shift` when they prevent
safe synchronization. State `Decision`, `Evidence`, and `Rationale`. Do not
fetch, check out, or reset until the working tree is clean.

The reset on SHA shift is critical: if a concurrent push lands content that
wasn't reviewed locally, we MUST re-review it. The pass counter is reset to
0 so the user gets full max-passes coverage of the new code. The distinct
`review-required` phase survives a session boundary because no reviewer has
started yet; once Step 5 changes it to `reviewing`, the normal expired-review
recovery applies.

## 10e. CI failure handling

If CI fails:

1. Analyze every unsuccessful item in `CI_SNAPSHOT`:
   `jq '.items[] | select(.terminal and (.successful | not))' <<< "$CI_SNAPSHOT"`
2. Fix the issue
3. Commit
4. Push: `git -C "$WORKTREE_PATH" push`
5. Capture HEAD SHA: `HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD)`; persist `head_sha`
6. Re-capture `BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)`; persist
7. Re-watch CI — go back to 10b for the NEW SHA

Persist Steps 5–6 through the resolved ship workflow object:

```bash
set_loop_field "$STATE_FILE" "head_sha" "$HEAD_SHA" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "bot_review_baseline" "$BOT_REVIEW_BASELINE" "$WORKFLOW_STATE_PATH"
```
