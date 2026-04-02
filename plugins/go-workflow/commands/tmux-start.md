---
argument-hint: "<issue-number>"
description: "Create worktree + tmux window and kick off /start-issue autonomously"
allowed-tools: ["Bash(git:*)", "Bash(gh:*)", "Bash(tmux:*)", "Bash(pwd:*)", "Bash(echo:*)", "Bash(cd:*)", "Bash(basename:*)", "Bash(sleep:*)", "Bash(if:*)", "Bash(cp:*)", "Bash(for:*)", "Bash(find:*)", "Bash(mkdir:*)", "Bash(*worktree-state*)", "Read", "AskUserQuestion"]
---

# Start Issue in tmux Window

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command creates a git worktree for an issue, opens a new tmux window, launches Claude Code, and sends `/go-workflow:start-issue` automatically.

**Usage:** `/tmux-start <issue-number>`

**Example:** `/tmux-start 294`

**What it does:**

1. Validates prerequisites (tmux session, gh CLI, git repo)
2. Pulls latest code from the primary branch
3. Creates a worktree (or reuses an existing one)
4. Opens a new named tmux window
5. Launches Claude Code with `--dangerously-skip-permissions`
6. Sends `/go-workflow:start-issue <issue-number>` after Claude boots

**Prerequisites:**

- Must be running inside a tmux session (`$TMUX` is set)
- GitHub CLI (`gh`) authenticated
- Must be inside a git repository

Ask the user: "What issue number would you like to start in a tmux window?"

---

**If `$ARGUMENTS` is provided:**

## Clear Worktree State

Clear any stale worktree state so the pre-tool-use hook doesn't block setup commands:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" clear 2>/dev/null || true`

## Context

- Current directory: !`pwd 2>&1 || echo "unknown"`
- Repository name: !`basename \`git rev-parse --show-toplevel 2>/dev/null\` 2>/dev/null || echo "unknown"`
- Default branch: !`git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main"`
- Existing worktrees: !`git worktree list 2>&1 || echo "No worktrees found"`
- In tmux: !`if [ -n "$TMUX" ]; then echo "yes"; else echo "NO - not in a tmux session"; fi`

## Steps

**CRITICAL: When executing bash commands below, use backticks (\`) for command substitution, NOT $(). Claude Code has a bug that mangles $() syntax into broken commands. Copy the commands exactly as written.**

1. **Validate input is numeric** (security: prevent command injection)
   !if ! echo "$ARGUMENTS" | grep -qE '^[0-9]+$'; then echo "Error: Issue number must be numeric. Usage: /tmux-start <number>"; exit 1; fi
   !ISSUE_NUM="$ARGUMENTS"

2. **Validate prerequisites**

   **Check tmux:**
   !if [ -z "$TMUX" ]; then echo "Error: Not running inside a tmux session. Please start tmux first: tmux new-session -s work"; exit 1; fi

   **Check gh CLI:**
   !if ! command -v gh >/dev/null 2>&1; then echo "Error: GitHub CLI (gh) is not installed"; exit 1; fi
   !if ! gh auth status >/dev/null 2>&1; then echo "Error: GitHub CLI is not authenticated. Run: gh auth login"; exit 1; fi

   **Check git repo:**
   !if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then echo "Error: Not inside a git repository"; exit 1; fi

3. **Validate issue exists**
   !ISSUE_JSON=`gh issue view "$ISSUE_NUM" --json number,title,state 2>/dev/null`
   !if [ -z "$ISSUE_JSON" ]; then echo "Error: Issue #$ISSUE_NUM not found"; exit 1; fi
   !echo "$ISSUE_JSON"

4. **Resolve main repo root** (not a worktree)

   If currently inside a worktree, resolve back to the main repo root:
   ```bash
   GIT_COMMON_DIR=`git rev-parse --path-format=absolute --git-common-dir 2>/dev/null`
   MAIN_REPO_ROOT=`echo "$GIT_COMMON_DIR" | sed 's|/\.git$||'`
   echo "Main repo root: $MAIN_REPO_ROOT"
   ```

5. **Pull latest primary branch**

   Detect and pull from the primary branch at the main repo root:
   ```bash
   DEFAULT_BRANCH=`git remote show origin | grep 'HEAD branch' | sed 's/.*: //' | tr -cd '[:alnum:]-._/'`
   if [ -z "$DEFAULT_BRANCH" ]; then echo "Error: Could not determine default branch"; exit 1; fi
   cd "$MAIN_REPO_ROOT" && git pull origin "$DEFAULT_BRANCH"
   echo "Pulled latest $DEFAULT_BRANCH"
   ```

6. **Build worktree naming variables**

   ```bash
   REPO_NAME=`basename "$MAIN_REPO_ROOT"`
   ITEM_TITLE=`gh issue view "$ISSUE_NUM" --json title --jq '.title'`
   CLEAN_TITLE=`echo "$ITEM_TITLE" | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//'`
   WORKTREE_NAME="${REPO_NAME}-issue-${ISSUE_NUM}-${CLEAN_TITLE}"
   WORKTREE_PATH="${MAIN_REPO_ROOT}/../${WORKTREE_NAME}"
   BRANCH_NAME="issue-${ISSUE_NUM}-${CLEAN_TITLE}"
   echo "Worktree name: $WORKTREE_NAME"
   echo "Branch name: $BRANCH_NAME"
   ```

7. **Check for existing worktree**

   ```bash
   cd "$MAIN_REPO_ROOT" && EXISTING_PATH=`git worktree list | awk '{print $1}' | grep -E "issue-${ISSUE_NUM}-" | head -1`
   if [ -n "$EXISTING_PATH" ]; then
     echo "WORKTREE_EXISTS"
     echo "Path: $EXISTING_PATH"
   else
     echo "WORKTREE_NOT_FOUND"
   fi
   ```

   **If `WORKTREE_EXISTS`:** Set `WORKTREE_ABS_PATH="$EXISTING_PATH"` and skip to **Step 9**.

   **If `WORKTREE_NOT_FOUND`:** Continue to Step 8.

8. **Create worktree**

   ```bash
   cd "$MAIN_REPO_ROOT" && git fetch origin "$DEFAULT_BRANCH"
   git branch -D "$BRANCH_NAME" 2>/dev/null || true
   if ! git worktree add "$WORKTREE_PATH" "origin/$DEFAULT_BRANCH"; then
     echo "Error: Failed to create worktree"
     exit 1
   fi
   cd "$WORKTREE_PATH" && git checkout -b "$BRANCH_NAME"
   WORKTREE_ABS_PATH=`cd "$WORKTREE_PATH" && pwd`
   echo "Created worktree at: $WORKTREE_ABS_PATH"
   ```

   **Search for environment files** in the main repo:
   ```bash
   ENV_FILES=`find "$MAIN_REPO_ROOT" \( -name "node_modules" -o -name ".git" -o -name "vendor" \) -prune -o \( -name ".env" -o -name ".env.local" -o -name ".envrc" \) -type f -print 2>/dev/null | sed "s|^$MAIN_REPO_ROOT/||" | grep -v "^-" | sort`
   if [ -n "$ENV_FILES" ]; then echo "Found env files:"; echo "$ENV_FILES"; fi
   ```

   **If environment files were found**, use AskUserQuestion to ask:
   "Found environment files (may contain secrets). Copy them to the new worktree?"
   - Options: "Yes, copy them" / "No, skip"

   If user confirms, copy the files preserving directory structure:
   ```bash
   echo "$ENV_FILES" | while read file; do
     if [ -n "$file" ]; then
       dir=`dirname "$file"`
       if [ "$dir" != "." ]; then mkdir -p "$WORKTREE_ABS_PATH/$dir"; fi
       cp -P "$MAIN_REPO_ROOT/$file" "$WORKTREE_ABS_PATH/$file" && echo "Copied $file"
     fi
   done
   ```

9. **Build tmux window name**

   Create a descriptive but compact window name:
   ```bash
   SLUG=`echo "$ITEM_TITLE" | sed 's/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g; s/^-//; s/-$//' | cut -c1-40 | sed 's/-$//'`
   WINDOW_NAME="issue-${ISSUE_NUM}-${SLUG}"
   echo "tmux window name: $WINDOW_NAME"
   ```

10. **Check for existing tmux window**

    ```bash
    EXISTING_WINDOW=`tmux list-windows -F '#{window_name}' 2>/dev/null | grep -F "issue-${ISSUE_NUM}-" | head -1`
    if [ -n "$EXISTING_WINDOW" ]; then
      echo "WINDOW_EXISTS: $EXISTING_WINDOW"
    else
      echo "WINDOW_NOT_FOUND"
    fi
    ```

    **If `WINDOW_EXISTS`:** Switch to that window and report. Do NOT create a new one.
    ```bash
    tmux select-window -t "$EXISTING_WINDOW"
    echo "Switched to existing tmux window: $EXISTING_WINDOW"
    ```
    **Skip to Step 13 (Report).**

    **If `WINDOW_NOT_FOUND`:** Continue to Step 11.

11. **Create tmux window and launch Claude Code**

    ```bash
    tmux new-window -n "$WINDOW_NAME"
    tmux send-keys -t "$WINDOW_NAME" "cd $WORKTREE_ABS_PATH && claude --dangerously-skip-permissions" Enter
    echo "Created tmux window: $WINDOW_NAME"
    echo "Launching Claude Code in: $WORKTREE_ABS_PATH"
    ```

12. **Send start-issue command after Claude boots**

    Wait for Claude Code to finish initializing, then send the command:
    ```bash
    sleep 8
    tmux send-keys -t "$WINDOW_NAME" "/go-workflow:start-issue $ISSUE_NUM" Enter
    echo "Sent /go-workflow:start-issue $ISSUE_NUM to window $WINDOW_NAME"
    ```

13. **Report**

    Display a summary:

    ```
    --- tmux-start complete ---

    Issue:     #$ISSUE_NUM
    Worktree:  $WORKTREE_ABS_PATH
    Branch:    $BRANCH_NAME
    Window:    $WINDOW_NAME

    Switch to it:
      Ctrl+B w          (window picker)
      Ctrl+B <number>   (direct switch by window index)

    Claude Code is running /go-workflow:start-issue $ISSUE_NUM autonomously.
    Monitor the window and accept plans when prompted.
    ```
