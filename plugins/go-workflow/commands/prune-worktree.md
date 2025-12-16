---
description: "Clean up completed issue worktrees that are merged into dev"
allowed-tools: ["Bash", "Read", "AskUserQuestion"]
---

# Prune Issue Worktrees

This command safely removes worktrees for completed GitHub issues.

**What it does:**

1. Scans for worktrees matching your `WORKTREE_PREFIX` pattern
2. Checks each associated GitHub issue status
3. Verifies branches are merged into `dev`
4. Removes worktrees for closed/merged issues
5. Cleans up local branches

**Safety checks:**

- Only removes closed issues with merged PRs
- Warns about uncommitted changes
- Provides manual commands for edge cases

**Usage:** `/prune-worktree` (no arguments needed)

---

## Pre-flight: Check Configuration

First, check if WORKTREE_PREFIX is configured:

!echo "WORKTREE_PREFIX=${WORKTREE_PREFIX:-NOT_SET}"

**If WORKTREE_PREFIX is "NOT_SET"**, stop and help the user configure it:

1. Ask them what prefix they use for worktrees (e.g., their project name like "my-api", "frontend-app")
2. Detect their platform and provide the appropriate command:

   **macOS/Linux (zsh):**

   ```bash
   echo 'export WORKTREE_PREFIX="<their-prefix>"' >> ~/.zshrc && source ~/.zshrc
   ```

   **macOS/Linux (bash):**

   ```bash
   echo 'export WORKTREE_PREFIX="<their-prefix>"' >> ~/.bashrc && source ~/.bashrc
   ```

   **Windows (PowerShell):**

   ```powershell
   [Environment]::SetEnvironmentVariable("WORKTREE_PREFIX", "<their-prefix>", "User")
   ```

   **Windows (CMD):**

   ```cmd
   setx WORKTREE_PREFIX "<their-prefix>"
   ```

3. After they run the command, ask them to restart Claude Code or run the command again.

**If WORKTREE_PREFIX is set**, proceed to scan worktrees.

## Scan and Cleanup

List all worktrees:

!git worktree list

For each worktree matching the WORKTREE_PREFIX pattern:

1. Extract issue number from directory name
2. Check GitHub issue status: `gh issue view <number> --json state`
3. Check if branch is merged: `git branch --merged dev | grep <branch>`
4. If issue is closed AND branch is merged, offer to remove

## Safety Features

- Only processes worktrees following issue naming convention
- Verifies GitHub issue exists and is closed
- Confirms branch is merged into dev branch
- Checks for uncommitted changes
- Requires user confirmation before deletion
- Offers optional branch cleanup

## Manual Cleanup Commands

**IMPORTANT**: When showing cleanup for closed but unmerged issues, display these commands:

```bash
git worktree remove "/path/to/worktree"
git branch -D "branch-name"
```

## Manual Override

If you need to force remove a worktree:

```bash
git worktree remove <path> --force
git branch -D <branch-name>  # if needed
```
