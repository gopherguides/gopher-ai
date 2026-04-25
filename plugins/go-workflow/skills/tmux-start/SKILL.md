---
name: tmux-start
description: "Start an issue in a new tmux window: create worktree, kick off /start-issue autonomously."
---

# tmux Start

Start working on a GitHub issue in a new tmux window with Claude Code running autonomously.

## Usage

```
$tmux-start <issue-number>
```

## Prerequisites

- Running inside a tmux session (`$TMUX` is set)
- GitHub CLI (`gh`) installed and authenticated
- Must be inside a git repository

## Workflow

### Step 1: Validate Prerequisites

Confirm inside a git repo, running inside tmux, `gh` CLI available and authenticated, and the issue number is valid.

### Step 2: Fetch Latest Code

Fetch the latest primary branch from origin (does not mutate the main checkout).

### Step 3: Create or Reuse Worktree

Check if a worktree already exists for this issue number. If so, reuse it. Otherwise, create a new worktree following the standard naming convention: `{repo}-issue-{number}-{slug}`.

### Step 4: Create Named tmux Window

Window name: `issue-{number}-{slug}` (slug is first ~40 chars of slugified issue title).

If a tmux window already exists for this issue, switch to it instead of creating a duplicate.

### Step 5: Launch Claude Code

Send `cd <worktree-path> && claude --dangerously-skip-permissions` to the new tmux window.

### Step 6: Send Start Command

Wait for Claude Code to boot (~8 seconds), then send `/go-workflow:start-issue <issue-number>`.

### Step 7: Report

Display the worktree path, window name, and instructions for switching to the window (`Ctrl+B w` for window picker).
