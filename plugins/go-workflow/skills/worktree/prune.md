# Worktree — Prune

Batch cleanup of all git worktrees for issues that are closed and branches that are merged. Loaded by `SKILL.md` when the user wants to clean up multiple worktrees at once.

## Usage

User-facing slash command: `/prune-worktree` (no args). Skill invocation: `$go-workflow:worktree prune`.

## Steps

### Step 1: List All Issue Worktrees

```bash
git worktree list | grep "issue-" || echo "No issue worktrees found"
```

If no issue worktrees found, inform the user and stop.

### Step 2: Check Default Branch

```bash
DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | sed 's/.*: //')
git fetch origin "$DEFAULT_BRANCH"
```

### Step 3: Evaluate Each Worktree

For each issue worktree:

1. Extract the issue number from the path:
   ```bash
   ISSUE_NUM=$(echo "$WORKTREE_PATH" | grep -oE 'issue-([0-9]+)' | grep -oE '[0-9]+')
   ```

2. Check if the issue is closed:
   ```bash
   STATE=$(gh issue view "$ISSUE_NUM" --json state --jq '.state' 2>/dev/null)
   ```

3. Check if the branch is merged:
   ```bash
   BRANCH=$(cd "$WORKTREE_PATH" && git branch --show-current)
   MERGED=$(git branch -r --merged "origin/$DEFAULT_BRANCH" | grep -q "origin/$BRANCH" && echo "true" || echo "false")
   ```

4. Classify as:
   - **Pruneable**: Issue is closed (`STATE` = `CLOSED`) AND branch is merged (`MERGED` = `true`)
   - **Keep**: Issue is open OR branch is not merged

### Step 4: Report and Resolve Cleanup Scope

Display a summary:
- Worktrees to prune (with issue number and status)
- Worktrees to keep (with reason)

The prune request authorizes removal of every worktree classified as
pruneable. State `Decision`, `Evidence`, and `Rationale`, then proceed without a
redundant confirmation.

Deleting the associated branches is optional and therefore a
**missing-intent gate** unless the original request specified it. Request one
branch-cleanup decision for the reported pruneable set. If structured input is
unavailable, ask in the final response and stop before any removal.

### Step 5: Remove Pruneable Worktrees

For each pruneable worktree:

```bash
git worktree remove "$WORKTREE_PATH"
```

Delete a branch with `git branch -d "$BRANCH"` only when branch cleanup was
explicitly authorized. The merge check makes forced deletion unnecessary.

### Step 6: Clean Up Stale Entries

```bash
git worktree prune
```

Report what was removed and what remains.
