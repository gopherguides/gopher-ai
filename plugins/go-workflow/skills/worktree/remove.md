# Worktree — Remove

Interactively select and safely remove a single git worktree. Loaded by `SKILL.md` when the user wants to delete a specific worktree.

## Usage

User-facing slash command: `/remove-worktree` (interactive, no args). Skill invocation: `$go-workflow:worktree remove`.

## Steps

### Step 1: List Worktrees

```bash
git worktree list
```

Filter for issue worktrees (matching `*-issue-*` pattern). If none found, inform the user and stop.

### Step 2: Select Worktree

If the request, current path, or issue/PR context identifies exactly one
worktree, select it. If multiple worktrees remain equally valid, follow the
shared **missing-intent gate**: list them, request the target, and stop before
removal.

### Step 3: Safety Checks

For the selected worktree, check:

1. **Issue status**: Is the linked issue closed?
   ```bash
   ISSUE_NUM=$(echo "$WORKTREE_PATH" | grep -oE 'issue-([0-9]+)' | grep -oE '[0-9]+')
   gh issue view "$ISSUE_NUM" --json state --jq '.state'
   ```

2. **Merge status**: Is the branch merged into the default branch?
   ```bash
   DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | sed 's/.*: //')
   BRANCH_NAME=$(cd "$WORKTREE_PATH" && git branch --show-current)
   git branch --merged "$DEFAULT_BRANCH" | grep -q "$BRANCH_NAME"
   ```

3. **Uncommitted changes**: Are there any pending changes?
   ```bash
   cd "$WORKTREE_PATH" && git status --porcelain
   ```

### Step 4: Confirm and Remove

**Safe removal** (issue closed + branch merged + no uncommitted changes):

Treat the original removal request as authorization for this safe target. State
`Decision`, `Evidence`, and `Rationale`, including the closed issue, merged
branch, and clean status, then remove it without a redundant confirmation.

```bash
git worktree remove "$WORKTREE_PATH"
```

**Unsafe removal** (issue open, branch unmerged, or uncommitted changes):

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=unsafe-worktree
```

Stop without removing the worktree or deleting either branch. A driver cannot
override unmerged commits, an open issue, or uncommitted changes. Make the
worktree safe first, then rerun the workflow.

### Step 5: Optional Branch Cleanup

Branch deletion is a **missing-intent gate** unless the original request
explicitly included branch cleanup. Request: "Also delete the local and remote
branch `$BRANCH_NAME`?" If structured input is unavailable, ask in the final
response and stop without deleting either branch or claiming branch cleanup.

```bash
git branch -d "$BRANCH_NAME"
git push origin --delete "$BRANCH_NAME" 2>/dev/null || true
```
