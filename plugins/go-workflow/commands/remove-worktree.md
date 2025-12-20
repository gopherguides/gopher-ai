---
description: "Interactively select and remove a git worktree"
allowed-tools: ["Bash", "Read", "AskUserQuestion"]
---

# Remove Worktree

This command interactively removes a single git worktree. Unlike `/prune-worktree` which auto-removes all safe worktrees, this command lets you select a specific worktree and handles cases where the issue isn't closed or branch isn't merged.

**Usage:** `/remove-worktree` (no arguments - interactive selection)

---

## Steps

**CRITICAL: When executing bash commands below, use backticks (\`) for command substitution, NOT $(). Claude Code has a bug that mangles $() syntax into broken commands. Copy the commands exactly as written.**

### 1. Get Repository Info

!REPO_NAME=`basename \`git rev-parse --show-toplevel\``
!echo "Repository: $REPO_NAME"

### 2. List All Issue Worktrees

!echo "Scanning for issue worktrees..."
!git worktree list

Filter for worktrees matching the `{REPO_NAME}-issue-*` pattern and display them as a numbered list.

!git worktree list | grep -E "/${REPO_NAME}-issue-[0-9]+" | cat -n

If no issue worktrees are found, inform the user and stop:
"No issue worktrees found matching the pattern '{REPO_NAME}-issue-*'"

### 3. Ask User to Select Worktree

Use AskUserQuestion to ask: "Which worktree would you like to remove? Enter the number from the list above, or the full path."

Store the selected worktree path and extract:
- `WORKTREE_PATH`: The full path to the worktree
- `BRANCH_NAME`: The branch associated with the worktree
- `ISSUE_NUM`: The issue number extracted from the directory name

To extract issue number from path:
!ISSUE_NUM=`echo "$WORKTREE_PATH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+'`
!echo "Issue number: $ISSUE_NUM"

To get branch name:
!BRANCH_NAME=`git worktree list --porcelain | grep -A2 "worktree $WORKTREE_PATH" | grep "branch" | sed 's/branch refs\/heads\///'`
!echo "Branch: $BRANCH_NAME"

### 4. Check Worktree Status

#### Check for uncommitted changes
!cd "$WORKTREE_PATH" && git status --porcelain

If there are uncommitted changes, warn the user immediately.

#### Check GitHub issue status
!gh issue view $ISSUE_NUM --json state,title --jq '"\(.state): \(.title)"'

#### Detect default branch and check if merged
!DEFAULT_BRANCH=`git remote show origin | grep 'HEAD branch' | sed 's/.*: //'`
!echo "Default branch: $DEFAULT_BRANCH"
!git fetch origin "$DEFAULT_BRANCH" --quiet
!MERGED=`git branch --merged "origin/$DEFAULT_BRANCH" | grep -F "$BRANCH_NAME" || echo ""`

### 5. Determine Safety and Proceed

Evaluate the status:
- `ISSUE_CLOSED`: true if GitHub issue state is "CLOSED"
- `BRANCH_MERGED`: true if branch appears in merged branches
- `HAS_CHANGES`: true if uncommitted changes exist

#### If SAFE (issue closed AND branch merged AND no uncommitted changes):

Display: "This worktree is safe to remove:"
- Issue #$ISSUE_NUM is closed
- Branch '$BRANCH_NAME' is merged into $DEFAULT_BRANCH
- No uncommitted changes

Use AskUserQuestion: "Remove this worktree?"
- Options: "Yes, remove it" / "No, cancel"

If confirmed:
!git worktree remove "$WORKTREE_PATH"
!echo "Worktree removed: $WORKTREE_PATH"

Ask: "Also delete the local branch '$BRANCH_NAME'?"
- Options: "Yes, delete branch" / "No, keep branch"

If confirmed:
!git branch -d "$BRANCH_NAME"

#### If NOT SAFE (issue open OR branch not merged OR has uncommitted changes):

Display a prominent warning:

```
⚠️  WARNING: This worktree may contain unfinished work!

Status:
- Issue #$ISSUE_NUM: [OPEN/CLOSED]
- Branch merged: [YES/NO]
- Uncommitted changes: [YES/NO]

Removing this worktree could result in PERMANENT DATA LOSS.
This action cannot be undone.
```

Use AskUserQuestion with a serious tone:
"Are you SURE you want to force-remove this worktree? This may delete unfinished work."
- Options:
  - "Yes, I understand the consequences - force remove"
  - "No, cancel and keep the worktree"

**Only if user explicitly confirms force removal:**

!git worktree remove "$WORKTREE_PATH" --force
!echo "Worktree force-removed: $WORKTREE_PATH"

Ask: "Also delete the local branch '$BRANCH_NAME'? (Use -D to force delete unmerged branch)"
- Options: "Yes, force delete branch" / "No, keep branch"

If confirmed:
!git branch -D "$BRANCH_NAME"

### 6. Completion

Display final status:
!echo "Done."
!git worktree list

---

## Why Use This vs /prune-worktree?

| Command | Use Case |
|---------|----------|
| `/prune-worktree` | Batch cleanup of all completed (closed + merged) worktrees |
| `/remove-worktree` | Remove a specific worktree, including abandoned/unfinished ones |

Use `/remove-worktree` when:
- You abandoned work on an issue and want to clean up
- The issue was closed without merging (won't fix, duplicate, etc.)
- You need to remove a specific worktree without affecting others
