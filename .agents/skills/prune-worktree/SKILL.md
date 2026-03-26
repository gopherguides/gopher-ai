---
name: prune-worktree
description: |
  WHEN: User wants to batch-clean all completed git worktrees, says "prune worktrees",
  "clean up worktrees", "remove old worktrees", or invokes $prune-worktree.
  WHEN NOT: User wants to remove a single specific worktree (use $remove-worktree) or
  create a new worktree (use $create-worktree).
---

# Prune Worktrees

Batch cleanup of all git worktrees for issues that are closed and branches that are merged.

## Usage

```
$prune-worktree
```

## Steps

### Step 1: List All Issue Worktrees

```bash
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
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
   MERGED=$(git log "origin/$DEFAULT_BRANCH" --oneline | head -100)
   ```

4. Classify as:
   - **Pruneable**: Issue is closed AND branch is merged
   - **Keep**: Issue is open OR branch is not merged

### Step 4: Report and Confirm

Display a summary:
- Worktrees to prune (with issue number and status)
- Worktrees to keep (with reason)

Ask the user to confirm before removing any worktrees.

### Step 5: Remove Pruneable Worktrees

For each confirmed worktree:

```bash
git worktree remove "$WORKTREE_PATH"
git branch -D "$BRANCH_NAME" 2>/dev/null || true
```

### Step 6: Clean Up Stale Entries

```bash
git worktree prune
```

Report what was removed and what remains.
