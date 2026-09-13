# Complete-Issue Implementation Handoff

Loaded by `SKILL.md` Phase 1. Execute the complete start-issue component handoff and validate its persisted worktree and PR outputs.

## Phase 1: Implement (`$go-workflow:start-issue`)

```bash
set_loop_phase "$STATE_FILE" "implementing" "$WORKFLOW_STATE_PATH"
START_ISSUE_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "start_issue")
initialize_workflow_state "$STATE_FILE" "$START_ISSUE_STATE_PATH"
```

Read `<PLUGIN_ROOT>/skills/start-issue/SKILL.md` and execute its workflow
directly, treating `$ISSUE_NUM $FLAGS` as its `SKILL_ARGS`. Do not call the
Skill tool. Read `phases.md` for the full sub-step list (fetch issue, create
worktree, detect type, explore, design, TDD, verify, coverage, security review,
commit/push/PR, watch CI).

Before executing the loaded workflow, set its explicit caller contract:

```bash
CALLER_LOOP_STATE_FILE="$STATE_FILE"
CALLER_WORKFLOW_STATE_PATH="$WORKFLOW_STATE_PATH"
```

After it returns, clear both caller variables and route its structured result:

```bash
WORKFLOW_STATE_PATH="$CALLER_WORKFLOW_STATE_PATH"
unset CALLER_LOOP_STATE_FILE CALLER_WORKFLOW_STATE_PATH
START_ISSUE_RESULT=$(get_loop_field "$STATE_FILE" "result" "$START_ISSUE_STATE_PATH")
START_ISSUE_REASON=$(get_loop_field "$STATE_FILE" "reason" "$START_ISSUE_STATE_PATH")
if [ "$START_ISSUE_RESULT" != "complete" ]; then
  START_ISSUE_REASON="${START_ISSUE_REASON:-start-issue-incomplete}"
  set_loop_terminal_result "$STATE_FILE" "incomplete" "$START_ISSUE_REASON" "incomplete" "INCOMPLETE"
  echo "Complete-issue stopped during implementation: $START_ISSUE_REASON"
  echo "<done>INCOMPLETE</done>"
  exit 0
fi
```

After `$go-workflow:start-issue` completes, detect the PR number and worktree
context while retaining the already-normalized caller state path, then persist:

```bash
WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" '[]')
REPO_SLUG=$(get_loop_field "$STATE_FILE" "repo_slug" '[]')
START_ORIGINAL_REPO_ROOT=$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')
REGISTERED_WORKTREES=$(git -C "$ORIGINAL_REPO_ROOT" worktree list --porcelain | awk '/^worktree / { sub(/^worktree /, ""); print }')
if [ "$START_ORIGINAL_REPO_ROOT" != "$ORIGINAL_REPO_ROOT" ] ||
   [ -z "$WORKTREE_PATH" ] ||
   [ "${WORKTREE_PATH#/}" = "$WORKTREE_PATH" ] ||
   [ ! -d "$WORKTREE_PATH" ] ||
   ! printf '%s\n' "$REGISTERED_WORKTREES" | awk -v expected="$WORKTREE_PATH" '$0 == expected { found = 1 } END { exit found ? 0 : 1 }' ||
   [ -z "$REPO_SLUG" ]; then
  WORKFLOW_REASON=start-issue-worktree-path-invalid
  set_loop_terminal_result "$STATE_FILE" "incomplete" "$WORKFLOW_REASON" "incomplete" "INCOMPLETE"
  echo "WORKFLOW_RESULT=INCOMPLETE"
  echo "WORKFLOW_REASON=$WORKFLOW_REASON"
  echo "<done>INCOMPLETE</done>"
  exit 1
fi

PR_HEAD_BRANCH=$(git -C "$WORKTREE_PATH" branch --show-current)
HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD)
PR_JSON=$(cd "$WORKTREE_PATH" && github_current_pr "$PR_HEAD_BRANCH" "$HEAD_SHA") || {
  echo "Error: No open PR matches the persisted worktree branch and HEAD after start-issue"
  exit 1
}
PR_NUM=$(jq -er '.number' <<< "$PR_JSON")

GIT_DIR_ABS=$(cd "$WORKTREE_PATH" && cd "$(git rev-parse --git-dir 2>/dev/null)" && pwd)
GIT_COMMON_ABS=$(cd "$WORKTREE_PATH" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd)
if [ "$GIT_DIR_ABS" != "$GIT_COMMON_ABS" ]; then
  echo "Running in worktree: $WORKTREE_PATH"
fi

set_loop_field "$STATE_FILE" "pr_number" "$PR_NUM" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "worktree_path" "${WORKTREE_PATH:-}" '[]'
echo "PR #$PR_NUM created"
```

> **Worktree invariant (decision-time, must stay in trunk):** All subsequent
> phases MUST operate on `$WORKTREE_PATH`. Prefer `git -C "$WORKTREE_PATH"`,
> `go -C "$WORKTREE_PATH"`, and `gh ... --repo "$REPO_SLUG"`; use an explicit
> worktree-scoped group only when no per-command option exists. Use
> `$WORKTREE_PATH` as the base for all file tools. `STATE_FILE` remains the one
> normalized caller-owned path established before Phase 1. Do not assume a
> pre-tool-use hook will correct or reject an ambient-directory command.

---
