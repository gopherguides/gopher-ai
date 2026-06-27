---
argument-hint: "<issue-number>"
description: "Start issue work in a new tmux window"
allowed-tools: ["Bash(git:*)", "Bash(gh:*)", "Bash(tmux:*)", "Bash(pwd:*)", "Bash(echo:*)", "Bash(cd:*)", "Bash(basename:*)", "Bash(sleep:*)", "Bash(if:*)", "Bash(cp:*)", "Bash(for:*)", "Bash(find:*)", "Bash(mkdir:*)", "Bash(*worktree-state*)", "Read", "AskUserQuestion"]
---

# Start Issue in tmux Window

**If `$ARGUMENTS` is empty or not provided:**

This command creates a worktree, opens a new tmux window, launches Claude Code, and sends `/go-workflow:start-issue` automatically.

**Usage:** `/tmux-start <issue-number>`. Example: `/tmux-start 294`.

**What it does:** validate prereqs (tmux session, gh, git repo) → fetch latest primary branch → create or reuse worktree → open named tmux window → launch Claude with `--dangerously-skip-permissions` → send `/go-workflow:start-issue <num>` after Claude boots.

**Prerequisites:** running inside a tmux session (`$TMUX` set); `gh` authenticated; inside a git repo.

Ask: "What issue number would you like to start in a tmux window?"

---

**If `$ARGUMENTS` is provided:**

## Clear Worktree State

!`"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" clear 2>/dev/null || true`

## Context

- Current directory: !`pwd 2>&1 || echo "unknown"`
- Repository name: !`basename \`git rev-parse --show-toplevel 2>/dev/null\` 2>/dev/null || echo "unknown"`
- Default branch: !`git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main"`
- Existing worktrees: !`git worktree list 2>&1 || echo "No worktrees found"`
- In tmux: !`if [ -n "$TMUX" ]; then echo "yes"; else echo "NO - not in a tmux session"; fi`

## Steps

**CRITICAL: Use backticks (`` ` ``) for command substitution, NOT `$()`.**

### 1–3. Validate input + prereqs + issue exists

```bash
# 1. Numeric input
if ! echo "$ARGUMENTS" | grep -qE '^[0-9]+$'; then
  echo "Error: Issue number must be numeric. Usage: /tmux-start <number>"; exit 1
fi
ISSUE_NUM="$ARGUMENTS"

# 2. Prereqs
if [ -z "$TMUX" ]; then echo "Error: Not running inside a tmux session. tmux new-session -s work"; exit 1; fi
if ! command -v gh >/dev/null 2>&1; then echo "Error: gh not installed"; exit 1; fi
if ! gh auth status >/dev/null 2>&1; then echo "Error: gh not authenticated. Run: gh auth login"; exit 1; fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then echo "Error: Not inside a git repository"; exit 1; fi

# 3. Issue exists
ISSUE_JSON=`gh issue view "$ISSUE_NUM" --json number,title,state 2>/dev/null`
if [ -z "$ISSUE_JSON" ]; then echo "Error: Issue #$ISSUE_NUM not found"; exit 1; fi
echo "$ISSUE_JSON"
```

### 4–5. Resolve main repo root and fetch primary

If currently inside a worktree, resolve back to the main repo root. Fetch (don't pull) so we don't mutate the main checkout:

```bash
GIT_COMMON_DIR=`git rev-parse --path-format=absolute --git-common-dir 2>/dev/null`
MAIN_REPO_ROOT=`echo "$GIT_COMMON_DIR" | sed 's|/\.git$||'`
echo "Main repo root: $MAIN_REPO_ROOT"

DEFAULT_BRANCH=`git remote show origin | grep 'HEAD branch' | sed 's/.*: //' | tr -cd '[:alnum:]-._/'`
if [ -z "$DEFAULT_BRANCH" ]; then echo "Error: Could not determine default branch"; exit 1; fi
cd "$MAIN_REPO_ROOT" && git fetch origin "$DEFAULT_BRANCH"
echo "Fetched latest origin/$DEFAULT_BRANCH"
```

### 6–7. Build naming + check existing worktree

```bash
REPO_NAME=`basename "$MAIN_REPO_ROOT"`
ITEM_TITLE=`gh issue view "$ISSUE_NUM" --json title --jq '.title'`
CLEAN_TITLE=`echo "$ITEM_TITLE" | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//'`
WORKTREE_NAME="${REPO_NAME}-issue-${ISSUE_NUM}-${CLEAN_TITLE}"
WORKTREE_PATH="${MAIN_REPO_ROOT}/../${WORKTREE_NAME}"
BRANCH_NAME="issue-${ISSUE_NUM}-${CLEAN_TITLE}"

cd "$MAIN_REPO_ROOT" && EXISTING_PATH=`git worktree list | awk '{print $1}' | grep -E "issue-${ISSUE_NUM}-" | head -1`
if [ -n "$EXISTING_PATH" ]; then echo "WORKTREE_EXISTS: $EXISTING_PATH"; else echo "WORKTREE_NOT_FOUND"; fi
```

**If `WORKTREE_EXISTS`:** set `WORKTREE_ABS_PATH=$EXISTING_PATH`, register state, skip to Step 9:

```bash
WORKTREE_ABS_PATH="$EXISTING_PATH"
REPO_ROOT=`cd "$WORKTREE_ABS_PATH" && git rev-parse --show-toplevel`
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" save "$WORKTREE_ABS_PATH" "$REPO_ROOT" "$ISSUE_NUM"
```

### 8. Create new worktree (when not found)

```bash
cd "$MAIN_REPO_ROOT" && git fetch origin "$DEFAULT_BRANCH"
git branch -D "$BRANCH_NAME" 2>/dev/null || true
if ! git worktree add "$WORKTREE_PATH" "origin/$DEFAULT_BRANCH"; then echo "Error: Failed to create worktree"; exit 1; fi
cd "$WORKTREE_PATH" && git checkout -b "$BRANCH_NAME"
WORKTREE_ABS_PATH=`cd "$WORKTREE_PATH" && pwd`
echo "Created worktree at: $WORKTREE_ABS_PATH"

# Register state (enables hook-based path enforcement in spawned session)
REPO_ROOT=`cd "$WORKTREE_ABS_PATH" && git rev-parse --show-toplevel`
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" save "$WORKTREE_ABS_PATH" "$REPO_ROOT" "$ISSUE_NUM"

# Search for env files in main repo
ENV_FILES=`find "$MAIN_REPO_ROOT" \( -name "node_modules" -o -name ".git" -o -name "vendor" \) -prune -o \( -name ".env" -o -name ".env.local" -o -name ".envrc" \) -type f -print 2>/dev/null | sed "s|^$MAIN_REPO_ROOT/||" | grep -v "^-" | sort`
if [ -n "$ENV_FILES" ]; then echo "Found env files:"; echo "$ENV_FILES"; fi
```

If env files found, use `AskUserQuestion`: "Found environment files (may contain secrets). Copy them to the new worktree?" with **Yes, copy them** / **No, skip**.

If confirmed:

```bash
echo "$ENV_FILES" | while read file; do
  if [ -n "$file" ]; then
    dir=`dirname "$file"`
    if [ "$dir" != "." ]; then mkdir -p "$WORKTREE_ABS_PATH/$dir"; fi
    cp -P "$MAIN_REPO_ROOT/$file" "$WORKTREE_ABS_PATH/$file" && echo "Copied $file"
  fi
done
```

### 9–10. Build window name + check existing window

```bash
SLUG=`echo "$ITEM_TITLE" | sed 's/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g; s/^-//; s/-$//' | cut -c1-40 | sed 's/-$//'`
WINDOW_NAME="${REPO_NAME}-issue-${ISSUE_NUM}-${SLUG}"

# Scope lookup to this repo
EXISTING_WINDOW=`tmux list-windows -F '#{window_name}' 2>/dev/null | grep -F "${REPO_NAME}-issue-${ISSUE_NUM}" | head -1`
if [ -n "$EXISTING_WINDOW" ]; then echo "WINDOW_EXISTS: $EXISTING_WINDOW"; else echo "WINDOW_NOT_FOUND"; fi
```

**If `WINDOW_EXISTS`:** switch and report (skip Step 11):

```bash
tmux select-window -t "$EXISTING_WINDOW"
echo "Switched to existing tmux window: $EXISTING_WINDOW"
```

### 11. Create tmux window + launch Claude Code

```bash
tmux new-window -n "$WINDOW_NAME"
tmux send-keys -t "$WINDOW_NAME" "cd \"$WORKTREE_ABS_PATH\" && claude --dangerously-skip-permissions" Enter
echo "Created tmux window: $WINDOW_NAME"
```

### 12. Send start-issue after Claude boots

Wait for Claude's input prompt to appear, then send:

```bash
sleep 5
READY=false
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  sleep 2
  PANE_CONTENT=`tmux capture-pane -t "$WINDOW_NAME" -p 2>/dev/null`
  if echo "$PANE_CONTENT" | grep -qE '^\s*>\s*$'; then
    READY=true; break
  fi
done
if [ "$READY" = "false" ]; then
  echo "Warning: Claude Code may not be ready yet. Sending command anyway."
fi
tmux send-keys -t "$WINDOW_NAME" "/go-workflow:start-issue $ISSUE_NUM" Enter
echo "Sent /go-workflow:start-issue $ISSUE_NUM to window $WINDOW_NAME"
```

### 13. Report

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
