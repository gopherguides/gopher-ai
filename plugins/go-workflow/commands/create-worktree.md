---
argument-hint: "<issue-or-pr-number>"
description: "Create a new git worktree for a GitHub issue or PR"
allowed-tools: ["Bash(git:*)", "Bash(gh:*)", "Bash(pwd:*)", "Bash(echo:*)", "Bash(cp:*)", "Bash(basename:*)", "Bash(for:*)", "Bash(if:*)", "Read", "AskUserQuestion"]
model: haiku
---

# Create Worktree for Issue or PR

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command creates an isolated git worktree for working on a GitHub issue or PR. If a worktree already exists for the given number, it switches to that worktree instead.

**Usage:** `/create-worktree <issue-or-pr-number>`

**Examples:**
- `/create-worktree 789` — create worktree for issue #789
- `/create-worktree 42` — if #42 is a PR, resolves its linked issue and creates a worktree

**What it does:**

1. Detects whether the number is a PR or issue
2. If a worktree already exists for this number, switches to it
3. Otherwise creates a new worktree directory (e.g., `../reponame-issue-789-feature-name/`)
4. Checks out from the default branch (main/dev/master)
5. Creates a feature branch for the issue
6. Optionally copies environment files (`.env`, `.envrc`) if you confirm

**Prerequisites:**

- GitHub CLI (`gh`) authenticated
- Must be run from within a git repository

Ask the user: "What issue or PR number would you like to work on?"

---

**If `$ARGUMENTS` is provided:**

## Context

- Current directory: !`pwd`
- Repository name: !`basename $(git rev-parse --show-toplevel)`
- Default branch: !`git remote show origin | grep 'HEAD branch' | sed 's/.*: //'`
- Existing worktrees: !`git worktree list`

## Steps

**CRITICAL: When executing bash commands below, use backticks (\`) for command substitution, NOT $(). Claude Code has a bug that mangles $() syntax into broken commands. Copy the commands exactly as written.**

1. **Validate input is numeric** (security: prevent command injection)
   !if ! echo "$ARGUMENTS" | grep -qE '^[0-9]+$'; then echo "Error: Number must be numeric"; exit 1; fi

2. **Capture source directory** (must be done first, before any cd operations)
   !SOURCE_DIR=`pwd`
   !echo "Source directory: $SOURCE_DIR"

3. **Detect if this is a PR or issue**

   Try PR first, then fall back to issue:
   !PR_JSON=`gh pr view "$ARGUMENTS" --json number,title,state,headRefName 2>/dev/null`
   !if [ -n "$PR_JSON" ]; then echo "PR_DETECTED"; echo "$PR_JSON"; else echo "NOT_A_PR"; fi

   **If PR was detected:**
   - Extract the PR's branch name from `headRefName`
   - Try to extract an issue number from the branch name (pattern: `issue-<NUM>-` or `fix/<NUM>-` or `feat/<NUM>-`)
   - If no issue number found in branch name, check PR body for "Fixes #NNN", "Closes #NNN", or "Resolves #NNN"
   - If an issue number was found, use that as the ISSUE_NUM going forward
   - If no linked issue found, use the PR number itself as the identifier and the PR title for naming

   ```bash
   BRANCH_FROM_PR=`echo "$PR_JSON" | grep -o '"headRefName":"[^"]*"' | sed 's/"headRefName":"//;s/"//'`
   ISSUE_FROM_BRANCH=`echo "$BRANCH_FROM_PR" | grep -oE '(issue|fix|feat)[/-]([0-9]+)' | grep -oE '[0-9]+' | head -1`
   if [ -z "$ISSUE_FROM_BRANCH" ]; then
     PR_BODY=`gh pr view "$ARGUMENTS" --json body --jq '.body' 2>/dev/null`
     ISSUE_FROM_BODY=`echo "$PR_BODY" | grep -oiE '(fixes|closes|resolves) #[0-9]+' | grep -oE '[0-9]+' | head -1`
     ISSUE_NUM="${ISSUE_FROM_BODY:-$ARGUMENTS}"
   else
     ISSUE_NUM="$ISSUE_FROM_BRANCH"
   fi
   echo "Using issue number: $ISSUE_NUM"
   ```

   **If NOT a PR, treat as issue:**
   !ISSUE_NUM="$ARGUMENTS"

4. **Fetch issue/PR details from GitHub**

   If this was a PR, we already have details. If it was an issue:
   !gh issue view "$ISSUE_NUM" --json title,state,number 2>/dev/null || echo "Issue #$ISSUE_NUM not found — using PR details"

5. **Build worktree naming variables**
   !REPO_NAME=`basename \`git rev-parse --show-toplevel\``

   Get the title (from issue if available, otherwise from PR):
   ```bash
   ITEM_TITLE=`gh issue view "$ISSUE_NUM" --json title --jq '.title' 2>/dev/null`
   if [ -z "$ITEM_TITLE" ]; then
     ITEM_TITLE=`gh pr view "$ARGUMENTS" --json title --jq '.title' 2>/dev/null`
   fi
   CLEAN_TITLE=`echo "$ITEM_TITLE" | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//'`
   WORKTREE_NAME="${REPO_NAME}-issue-${ISSUE_NUM}-${CLEAN_TITLE}"
   WORKTREE_PATH="../$WORKTREE_NAME"
   BRANCH_NAME="issue-${ISSUE_NUM}-${CLEAN_TITLE}"
   echo "Worktree path: $WORKTREE_PATH"
   echo "Branch name: $BRANCH_NAME"
   ```

6. **Check if worktree already exists**

   Search existing worktrees for this issue number:
   ```bash
   EXISTING=`git worktree list | grep -E "issue-${ISSUE_NUM}-"`
   if [ -n "$EXISTING" ]; then
     EXISTING_PATH=`echo "$EXISTING" | awk '{print $1}'`
     echo "WORKTREE_EXISTS"
     echo "Path: $EXISTING_PATH"
   else
     echo "WORKTREE_NOT_FOUND"
   fi
   ```

   **If `WORKTREE_EXISTS`:** Skip to **Step 12 (Switch to existing worktree)**.

   **If `WORKTREE_NOT_FOUND`:** Continue to Step 7 to create a new worktree.

7. **Validate issue/PR state**
   !if [ "`gh issue view "$ISSUE_NUM" --json state --jq '.state' 2>/dev/null`" = "CLOSED" ]; then echo "Warning: Issue #$ISSUE_NUM is already closed"; fi

8. **Detect the default branch**
   !DEFAULT_BRANCH=`git remote show origin | grep 'HEAD branch' | sed 's/.*: //' | tr -cd '[:alnum:]-._/'`
   !if [ -z "$DEFAULT_BRANCH" ]; then echo "Error: Could not determine default branch"; exit 1; fi
   !echo "Default branch: $DEFAULT_BRANCH"

9. **Fetch latest default branch**
   !git fetch origin "$DEFAULT_BRANCH"

10. **Delete existing branch if it exists** (from previous failed attempts)
    !git branch -D "$BRANCH_NAME" 2>/dev/null || true

11. **Create worktree from default branch**
    !if ! git worktree add "$WORKTREE_PATH" "origin/$DEFAULT_BRANCH"; then echo "Error: Failed to create worktree"; exit 1; fi

    **Switch to new worktree and create feature branch:**
    !cd "$WORKTREE_PATH" && git checkout -b "$BRANCH_NAME"

    **Search for environment files** (recursive, excludes node_modules/.git/vendor):
    !ENV_FILES=`find "$SOURCE_DIR" \( -name "node_modules" -o -name ".git" -o -name "vendor" \) -prune -o \( -name ".env" -o -name ".env.local" -o -name ".envrc" \) -type f -print 2>/dev/null | sed "s|^$SOURCE_DIR/||" | grep -v "^-" | sort`
    !if [ -n "$ENV_FILES" ]; then echo "Found env files:"; echo "$ENV_FILES"; fi

    **If environment files were found**, use AskUserQuestion to ask:
    "Found environment files (may contain secrets). Copy them to the new worktree?"
    - Options: "Yes, copy them" / "No, skip"

    If user confirms, copy the files preserving directory structure:
    !echo "$ENV_FILES" | while read file; do if [ -n "$file" ]; then dir=`dirname "$file"`; if [ "$dir" != "." ]; then mkdir -p "$WORKTREE_PATH/$dir"; fi; cp -P "$SOURCE_DIR/$file" "$WORKTREE_PATH/$file" && echo "Copied $file"; fi; done

    **Display success message:**
    !echo "Created worktree for issue #$ISSUE_NUM"
    !echo "Path: $WORKTREE_PATH"
    !echo "Branch: $BRANCH_NAME"

    **Continue to Step 12.**

12. **CRITICAL: Change working directory to worktree**

    If reusing an existing worktree, use `$EXISTING_PATH`. If newly created, use `$WORKTREE_PATH`.

    Determine the target path:
    - If `$EXISTING_PATH` is set (existing worktree): `TARGET_PATH="$EXISTING_PATH"`
    - Otherwise: `TARGET_PATH="$WORKTREE_PATH"`

    **Change and verify directory:**
    !cd "$TARGET_PATH" && pwd

    This `cd` persists across Bash tool calls — Claude Code tracks the working directory via a temp file after each command. The status line's `workspace.current_dir` field updates automatically to reflect the new location.

    **For every Bash command after this**, prefix with `cd "$TARGET_PATH" &&` to ensure you stay in the worktree. This is necessary because the Bash tool can sometimes lose track of the working directory.

    **For Read, Edit, Write, and Glob tools**, use absolute paths rooted in `$TARGET_PATH` rather than relative paths. This ensures file operations target the worktree, not the original project directory.

    **WARNING:** If you edit files or run commands without ensuring the worktree directory, you will modify the wrong codebase.

    **If this was an existing worktree**, display the current branch and status:
    !cd "$TARGET_PATH" && git branch --show-current && git status --short

## Next Steps

- You are now in the worktree directory
- The session's working directory has been changed — subsequent commands will execute here
- Start working on the issue, or continue where you left off if resuming an existing worktree
- When done, use `/prune-worktree` to clean up or `/remove-worktree` to remove a specific worktree
