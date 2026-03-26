---
name: remove-worktree
description: |
  WHEN: User wants to remove a specific git worktree, says "remove worktree", "delete worktree",
  "clean up worktree", or invokes $remove-worktree.
  WHEN NOT: User wants to batch-remove all completed worktrees (use $prune-worktree) or
  create a new worktree (use $create-worktree).
---

# Remove Worktree

Interactively select and safely remove a single git worktree.

## Usage

```
$remove-worktree
```

## Steps

### Step 1: List Worktrees

```bash
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
git worktree list
```

Filter for issue worktrees (matching `*-issue-*` pattern). If none found, inform the user and stop.

### Step 2: Select Worktree

If multiple worktrees exist, list them and ask the user which one to remove.

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

Ask: "Remove worktree at $WORKTREE_PATH? (issue closed, branch merged)"

```bash
git worktree remove "$WORKTREE_PATH"
```

**Unsafe removal** (issue open, branch unmerged, or uncommitted changes):

Warn the user about the risks and ask for explicit confirmation:

```bash
git worktree remove --force "$WORKTREE_PATH"
```

### Step 5: Optional Branch Cleanup

Ask: "Also delete the branch $BRANCH_NAME?"

```bash
git branch -D "$BRANCH_NAME" 2>/dev/null || true
git push origin --delete "$BRANCH_NAME" 2>/dev/null || true
```
