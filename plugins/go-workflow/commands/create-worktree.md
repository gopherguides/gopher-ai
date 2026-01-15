---
argument-hint: "<issue-number>"
description: "Create a new git worktree for a GitHub issue"
allowed-tools: ["Bash(git:*)", "Bash(gh:*)", "Bash(pwd:*)", "Bash(echo:*)", "Bash(cp:*)", "Bash(basename:*)", "Bash(for:*)", "Bash(if:*)", "Read", "AskUserQuestion"]
model: haiku
---

# Create Worktree for Issue

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command creates an isolated git worktree for working on a GitHub issue.

**Usage:** `/create-worktree <issue-number>`

**Example:** `/create-worktree 789`

**What it does:**

1. Creates a new worktree directory (e.g., `../reponame-issue-789-feature-name/`)
2. Checks out from the default branch (main/dev/master)
3. Creates a feature branch for the issue
4. Copies LLM config directories (`.claude`, `.codex`, `.gemini`, `.cursor`)
5. Optionally copies environment files (`.env`, `.envrc`) if you confirm

**Prerequisites:**

- GitHub CLI (`gh`) authenticated
- Must be run from within a git repository

Ask the user: "What issue number would you like to start working on?"

---

**If `$ARGUMENTS` is provided:**

Create a new git worktree for GitHub issue #$ARGUMENTS

## Context

- Current directory: !`pwd`
- Repository name: !`basename $(git rev-parse --show-toplevel)`
- Default branch: !`git remote show origin | grep 'HEAD branch' | sed 's/.*: //'`
- Issue details: !`gh issue view "$ARGUMENTS" --json title,state,number 2>/dev/null || echo "Issue not found"`
- Existing worktrees: !`git worktree list`

## Steps

**CRITICAL: When executing bash commands below, use backticks (\`) for command substitution, NOT $(). Claude Code has a bug that mangles $() syntax into broken commands. Copy the commands exactly as written.**

1. **Validate input is numeric** (security: prevent command injection)
   !if ! echo "$ARGUMENTS" | grep -qE '^[0-9]+$'; then echo "Error: Issue number must be numeric"; exit 1; fi

2. **Capture source directory** (must be done first, before any cd operations)
   !SOURCE_DIR=`pwd`
   !echo "Source directory: $SOURCE_DIR"

3. **Fetch issue details from GitHub**
   !gh issue view "$ARGUMENTS" --json title,state,number

4. **Validate issue exists and is open**
   !if ! gh issue view "$ARGUMENTS" >/dev/null 2>&1; then echo "Error: Issue #$ARGUMENTS not found"; exit 1; fi
   !if [ "`gh issue view "$ARGUMENTS" --json state --jq '.state'`" = "CLOSED" ]; then echo "Warning: Issue #$ARGUMENTS is already closed"; fi

5. **Detect the default branch**
   !DEFAULT_BRANCH=`git remote show origin | grep 'HEAD branch' | sed 's/.*: //' | tr -cd '[:alnum:]-._/'`
   !if [ -z "$DEFAULT_BRANCH" ]; then echo "Error: Could not determine default branch"; exit 1; fi
   !echo "Default branch: $DEFAULT_BRANCH"

6. **Create worktree directory name**
   !REPO_NAME=`basename \`git rev-parse --show-toplevel\``
   !ISSUE_TITLE=`gh issue view "$ARGUMENTS" --json title --jq '.title' | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//'`
   !WORKTREE_NAME="${REPO_NAME}-issue-$ARGUMENTS-$ISSUE_TITLE"
   !WORKTREE_PATH="../$WORKTREE_NAME"
   !BRANCH_NAME="issue-$ARGUMENTS-$ISSUE_TITLE"

7. **Fetch latest default branch**
   !git fetch origin "$DEFAULT_BRANCH"

8. **Delete existing branch if it exists** (from previous failed attempts)
   !git branch -D "$BRANCH_NAME" 2>/dev/null || true

9. **Create worktree from default branch** (also checks if path exists)
   !if ! git worktree add "$WORKTREE_PATH" "origin/$DEFAULT_BRANCH"; then echo "Error: Failed to create worktree (may already exist)"; exit 1; fi

10. **Switch to new worktree and create feature branch**
    !cd "$WORKTREE_PATH" && git checkout -b "$BRANCH_NAME"

11. **Symlink LLM config directories to new worktree** (shared for plans/memory/settings)
    !for dir in .claude .codex .gemini .cursor; do if [ -d "$SOURCE_DIR/$dir" ]; then ln -s "$SOURCE_DIR/$dir" "$WORKTREE_PATH/$dir" && echo "Symlinked $dir -> $SOURCE_DIR/$dir"; fi; done

12. **Search for environment files** (recursive, excludes node_modules/.git/vendor)
    !ENV_FILES=`find "$SOURCE_DIR" \( -name "node_modules" -o -name ".git" -o -name "vendor" \) -prune -o \( -name ".env" -o -name ".env.local" -o -name ".envrc" \) -type f -print 2>/dev/null | sed "s|^$SOURCE_DIR/||" | grep -v "^-" | sort`
    !if [ -n "$ENV_FILES" ]; then echo "Found env files:"; echo "$ENV_FILES"; fi

    **If environment files were found**, use AskUserQuestion to ask:
    "Found environment files (may contain secrets). Copy them to the new worktree?"
    - Options: "Yes, copy them" / "No, skip"

    If user confirms, copy the files preserving directory structure:
    !echo "$ENV_FILES" | while read file; do if [ -n "$file" ]; then dir=`dirname "$file"`; if [ "$dir" != "." ]; then mkdir -p "$WORKTREE_PATH/$dir"; fi; cp -P "$SOURCE_DIR/$file" "$WORKTREE_PATH/$file" && echo "Copied $file"; fi; done

13. **Display success message**
    !echo "Created worktree for issue #$ARGUMENTS"
    !echo "Path: $WORKTREE_PATH"
    !echo "Branch: $BRANCH_NAME"

14. **CRITICAL: Change working directory to worktree**

    Your session started in `$SOURCE_DIR`. **ALL subsequent work MUST happen in `$WORKTREE_PATH`.**

    Run this now to change and verify directory:
    !cd "$WORKTREE_PATH" && pwd

    **For every Bash command after this**, prefix with `cd "$WORKTREE_PATH" &&` to ensure you're working in the worktree.

    **WARNING:** If you edit files or run commands without changing to the worktree first, you will modify the wrong codebase.

## Next Steps

- You are now in the worktree directory: `$WORKTREE_PATH`
- Start working on issue #$ARGUMENTS
- When done, use `/prune-worktree` to clean up or `/remove-worktree` to remove a specific worktree
