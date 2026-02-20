---
description: "Batch cleanup of all completed issue worktrees"
allowed-tools: ["Bash(git:*)", "Bash(gh:*)", "Bash(echo:*)", "Bash(basename:*)", "Bash(grep:*)", "Bash(*worktree-state*)", "Read", "AskUserQuestion"]
model: haiku
---

# Prune Issue Worktrees

This command safely removes worktrees for completed GitHub issues.

**What it does:**

1. Scans for worktrees matching the `{reponame}-issue-*` pattern
2. Checks each associated GitHub issue status
3. Verifies branches are merged into the default branch
4. Removes worktrees for closed/merged issues
5. Cleans up local branches

**Safety checks:**

- Only removes closed issues with merged PRs
- Warns about uncommitted changes
- Provides manual commands for edge cases

**Usage:** `/prune-worktree` (no arguments needed)

## Clear Worktree State

Clear any active worktree state so the pre-tool-use hook doesn't block cleanup commands:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" clear 2>/dev/null || true`

## Context

- Repository name: !$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")
- Default branch: !$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main")
- All worktrees: !$(git worktree list 2>&1 || echo "No worktrees found")
- Issue worktrees: !$(git worktree list 2>/dev/null | grep -E "issue-[0-9]+" || echo "No issue worktrees found")

---

## Scan and Cleanup

**CRITICAL: When executing bash commands below, use backticks (\`) for command substitution, NOT $(). Claude Code has a bug that mangles $() syntax into broken commands.**

**CRITICAL: Before removing any worktree, first cd to the main repository directory.** This prevents CWD invalidation errors if running from a worktree that will be removed:

!cd `git worktree list | head -1 | awk '{print $1}'`

First, get the repository name:

!REPO_NAME=`basename \`git rev-parse --show-toplevel\``
!echo "Repository: $REPO_NAME"

List all worktrees:

!git worktree list

For each worktree matching the `{REPO_NAME}-issue-*` pattern:

1. Extract issue number from directory name using: `grep -oE '[0-9]+'`
2. **Validate issue number is numeric** (security: prevent command injection)
3. Check GitHub issue status: `gh issue view "$ISSUE_NUM" --json state`
4. Check if branch is merged: `git branch --merged "$DEFAULT_BRANCH" | grep -F "$BRANCH_NAME"`
5. If issue is closed AND branch is merged, offer to remove

**Security note:** Always validate extracted issue numbers are numeric before using in gh commands, and quote all variables in shell commands.

## Safety Features

- **Changes to main repo before removing worktrees** (prevents CWD errors if running from a worktree being removed)
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

## Worktree State Cleanup

After removing worktrees, clear the active worktree state so the pre-tool-use hook stops enforcing path prefixes:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" clear
```

## Manual Override

If you need to force remove a worktree:

```bash
git worktree remove <path> --force
git branch -D <branch-name>  # if needed
```
