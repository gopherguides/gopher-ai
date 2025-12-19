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

## Steps

1. **Capture source directory** (must be done first, before any cd operations)
   !SOURCE_DIR=`pwd`
   !echo "Source directory: $SOURCE_DIR"

2. **Fetch issue details from GitHub**
   !gh issue view $ARGUMENTS --json title,state,number

3. **Validate issue exists and is open**
   !if ! gh issue view $ARGUMENTS >/dev/null 2>&1; then echo "Error: Issue #$ARGUMENTS not found"; exit 1; fi
   !if [ "`gh issue view $ARGUMENTS --json state --jq '.state'`" = "CLOSED" ]; then echo "Warning: Issue #$ARGUMENTS is already closed"; fi

4. **Detect the default branch**
   !DEFAULT_BRANCH=`git remote show origin | grep 'HEAD branch' | sed 's/.*: //'`
   !echo "Default branch: $DEFAULT_BRANCH"

5. **Create worktree directory name**
   !REPO_NAME=`basename \`git rev-parse --show-toplevel\``
   !ISSUE_TITLE=`gh issue view $ARGUMENTS --json title --jq '.title' | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//'`
   !WORKTREE_NAME="${REPO_NAME}-issue-$ARGUMENTS-$ISSUE_TITLE"
   !WORKTREE_PATH="../$WORKTREE_NAME"
   !BRANCH_NAME="issue-$ARGUMENTS-$ISSUE_TITLE"

6. **Check if worktree already exists**
   !if [ -d "$WORKTREE_PATH" ]; then echo "Error: Worktree already exists at $WORKTREE_PATH"; exit 1; fi

7. **Fetch latest default branch**
   !git fetch origin "$DEFAULT_BRANCH"

8. **Create worktree from default branch**
   !git worktree add "$WORKTREE_PATH" "origin/$DEFAULT_BRANCH"

9. **Switch to new worktree and create feature branch**
   !cd "$WORKTREE_PATH" && git checkout -b "$BRANCH_NAME"

10. **Copy LLM config directories to new worktree**
    !for dir in .claude .codex .gemini .cursor; do if [ -d "$SOURCE_DIR/$dir" ]; then cp -r "$SOURCE_DIR/$dir" "$WORKTREE_PATH/" && echo "Copied $dir"; fi; done

11. **Check for environment files**
    !ENV_FILES=""
    !if [ -f "$SOURCE_DIR/.env" ]; then ENV_FILES="$ENV_FILES .env"; fi
    !if [ -f "$SOURCE_DIR/.envrc" ]; then ENV_FILES="$ENV_FILES .envrc"; fi
    !echo "ENV_FILES=$ENV_FILES"

    **If environment files were found**, use AskUserQuestion to ask:
    "Found environment files ($ENV_FILES). Copy them to the new worktree? (These may contain secrets)"
    - Options: "Yes, copy them" / "No, skip"

    If user confirms, copy the files:
    !for file in $ENV_FILES; do cp "$SOURCE_DIR/$file" "$WORKTREE_PATH/" && echo "Copied $file"; done

12. **Display success message**
    !echo "Created worktree for issue #$ARGUMENTS"
    !echo "Path: $WORKTREE_PATH"
    !echo "Branch: $BRANCH_NAME"
    !echo "To switch: cd $WORKTREE_PATH"

## Next Steps

- Change to the new worktree directory: `cd $WORKTREE_PATH`
- Start working on issue #$ARGUMENTS
- When done, use `/prune-worktree` to clean up
