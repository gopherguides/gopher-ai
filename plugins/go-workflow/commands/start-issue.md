---
argument-hint: "<issue-number>"
description: "Create a new git worktree for a GitHub issue"
allowed-tools: ["Bash", "Read", "AskUserQuestion"]
---

# Start Issue Worktree

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command creates an isolated git worktree for working on a GitHub issue.

**Usage:** `/start-issue <issue-number>`

**Example:** `/start-issue 789`

**What it does:**

1. Creates a new worktree directory (e.g., `../myproject-issue-789-feature-name/`)
2. Checks out from the default branch (main/dev/master)
3. Creates a feature branch for the issue
4. Copies your `.claude` configuration to the new worktree

**Prerequisites:**

- `WORKTREE_PREFIX` environment variable (will prompt if not set)
- GitHub CLI (`gh`) authenticated

Ask the user: "What issue number would you like to start working on?"

---

**If `$ARGUMENTS` is provided:**

Create a new git worktree for GitHub issue #$ARGUMENTS

## Pre-flight: Check Configuration

First, check if WORKTREE_PREFIX is configured:

!echo "WORKTREE_PREFIX=${WORKTREE_PREFIX:-NOT_SET}"

**If WORKTREE_PREFIX is "NOT_SET"**, stop and help the user configure it:

1. Ask them what prefix they want (e.g., their project name like "my-api", "frontend-app")
2. Detect their platform and provide the appropriate command:

   **macOS/Linux (bash/zsh):**

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

**If WORKTREE_PREFIX is set**, proceed with the steps below.

## Steps

1. **Fetch issue details from GitHub**
   !gh issue view $ARGUMENTS --json title,state,number

2. **Validate issue exists and is open**
   !if ! gh issue view $ARGUMENTS >/dev/null 2>&1; then echo "Error: Issue #$ARGUMENTS not found"; exit 1; fi
   !if [ "$(gh issue view $ARGUMENTS --json state --jq '.state')" = "CLOSED" ]; then echo "Warning: Issue #$ARGUMENTS is already closed"; fi

3. **Detect the default branch**
   !DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | sed 's/.*: //')
   !echo "Default branch: $DEFAULT_BRANCH"

4. **Create worktree directory name**
   !WORKTREE_PREFIX="${WORKTREE_PREFIX:-project}"
   !ISSUE_TITLE=$(gh issue view $ARGUMENTS --json title --jq '.title' | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
   !WORKTREE_NAME="${WORKTREE_PREFIX}-issue-$ARGUMENTS-$ISSUE_TITLE"
   !WORKTREE_PATH="../$WORKTREE_NAME"
   !BRANCH_NAME="issue-$ARGUMENTS-$ISSUE_TITLE"

5. **Check if worktree already exists**
   !if [ -d "$WORKTREE_PATH" ]; then echo "Error: Worktree already exists at $WORKTREE_PATH"; exit 1; fi

6. **Fetch latest default branch**
   !git fetch origin "$DEFAULT_BRANCH"

7. **Create worktree from default branch**
   !git worktree add "$WORKTREE_PATH" "origin/$DEFAULT_BRANCH"

8. **Switch to new worktree and create feature branch**
   !cd "$WORKTREE_PATH" && git checkout -b "$BRANCH_NAME"

9. **Copy .claude directory to new worktree**
   !SOURCE_CLAUDE_DIR="$(pwd)/.claude"
   !if [ -d "$SOURCE_CLAUDE_DIR" ]; then cp -r "$SOURCE_CLAUDE_DIR" "$WORKTREE_PATH/"; else echo "Note: No .claude directory found to copy"; fi

10. **Display success message**
   !echo "Created worktree for issue #$ARGUMENTS"
   !echo "Path: $WORKTREE_PATH"
   !echo "Branch: $BRANCH_NAME"
   !echo "To switch: cd $WORKTREE_PATH"

## Next Steps

- Change to the new worktree directory: `cd $WORKTREE_PATH`
- Start working on issue #$ARGUMENTS
- When done, use `/prune-worktree` to clean up
