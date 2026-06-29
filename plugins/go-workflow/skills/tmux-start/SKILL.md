---
name: tmux-start
description: "Start issue work in a new tmux window with its own worktree. Use when the user has tmux running and wants issue startup to continue outside the current session. SKIP when not inside a tmux session ($TMUX unset) or when the user wants to work in the current session; use start-issue directly."
argument-hint: "<issue-number>"
allowed-tools: ["Bash(*worktree-state.sh*)", "Bash(*worktree-create.sh*)", "Bash(*tmux-start.sh*)", "Bash(pwd:*)", "Read", "AskUserQuestion"]
disable-model-invocation: true
---

# Start Issue in tmux Window

## Empty Arguments

If `$ARGUMENTS` is empty or not provided, explain:

This skill creates or reuses a worktree, opens a new tmux window, launches
Claude Code, and sends `$start-issue` automatically.

**Usage:** `$tmux-start <issue-number>`. Example: `$tmux-start 294`.

**Prerequisites:** running inside a tmux session (`$TMUX` set); `gh`
authenticated; inside a git repo.

Ask: "What issue number would you like to start in a tmux window?"

---

## Clear Worktree State

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" clear 2>/dev/null || true
```

## Issue Number

Use `$ARGUMENTS` as the issue number. The script validates that it is numeric
and that the issue exists.

## Environment Files

Check whether the source repo has environment files before creating the
worktree:

```bash
SOURCE_DIR="$(pwd)"
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-create.sh" env-files --source-dir "$SOURCE_DIR"
```

If the output starts with `ENV_FILES_FOUND=true`, use `AskUserQuestion`: "Found
environment files (may contain secrets). Copy them to the new worktree?" with
**Yes, copy them** / **No, skip**.

## Start tmux Workflow

If the user chose to copy env files:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/tmux-start.sh" "$ARGUMENTS" --copy-env
```

Otherwise:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/tmux-start.sh" "$ARGUMENTS" --no-copy-env
```

The script validates prerequisites, creates or reuses the standard issue
worktree, registers worktree state, opens or switches to the issue tmux window,
launches Claude Code, waits for a prompt or stable launch marker, and sends
`$start-issue <issue-number>`.

Set `GOPHER_AI_TMUX_CLAUDE_CMD` before invocation to override the default
Claude launch command (`claude --dangerously-skip-permissions`).
