---
argument-hint: "<issue-or-pr-number>"
description: "Create a new git worktree for a GitHub issue or PR"
allowed-tools: ["Bash(git:*)", "Bash(gh:*)", "Bash(pwd:*)", "Bash(echo:*)", "Bash(cp:*)", "Bash(basename:*)", "Bash(for:*)", "Bash(if:*)", "Bash(*worktree-state*)", "Read", "AskUserQuestion"]
---

# Create Worktree for Issue or PR

**If `$ARGUMENTS` is empty or not provided:**

This command creates an isolated git worktree for working on a GitHub issue or PR. If a worktree already exists for the given number, it switches to that worktree instead.

**Usage:** `/create-worktree <issue-or-pr-number>`

**Examples:**
- `/create-worktree 789` — create worktree for issue #789
- `/create-worktree 42` — if #42 is a PR, resolves its linked issue and creates a worktree

**What it does:** detects PR vs issue → reuses existing worktree if found → otherwise creates `../reponame-issue-<num>-<title>/` from the default branch → creates a feature branch → optionally copies env files.

**Prerequisites:** `gh` authenticated; run from inside a git repository.

Ask the user: "What issue or PR number would you like to work on?"

---

**If `$ARGUMENTS` is provided:**

## Clear Worktree State

Clear stale worktree state so the pre-tool-use hook doesn't block setup commands:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" clear 2>/dev/null || true`

## Context

- Current directory: !`pwd 2>&1 || echo "unknown"`
- Repository name: !`basename \`git rev-parse --show-toplevel 2>/dev/null\` 2>/dev/null || echo "unknown"`
- Default branch: !`git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main"`
- Existing worktrees: !`git worktree list 2>&1 || echo "No worktrees found"`

## Steps

**CRITICAL: Use backticks (`` ` ``) for command substitution, NOT `$()`. Claude Code has a bug that mangles `$()` syntax. Copy commands exactly as written.**

### 1. Validate input is numeric (security)

!if ! echo "$ARGUMENTS" | grep -qE '^[0-9]+$'; then echo "Error: Number must be numeric"; exit 1; fi

### 2. Capture source directory

!SOURCE_DIR=`pwd`
!echo "Source directory: $SOURCE_DIR"

### 3. Detect PR vs issue

Try PR first:

!PR_JSON=`gh pr view "$ARGUMENTS" --json number,title,state,headRefName 2>/dev/null`
!if [ -n "$PR_JSON" ]; then echo "PR_DETECTED"; echo "$PR_JSON"; else echo "NOT_A_PR"; fi

**If PR detected**, derive the underlying issue number — check the branch name for the `issue-<NUM>-` convention (only `issue-` prefix is trusted; branches like `fix/2fa-login` contain numbers that aren't issue IDs), then check the PR body for `Fixes #NNN` / `Closes #NNN` / `Resolves #NNN`. Fall back to the PR number if no linked issue is found.

```bash
BRANCH_FROM_PR=`echo "$PR_JSON" | grep -o '"headRefName":"[^"]*"' | sed 's/"headRefName":"//;s/"//'`
ISSUE_FROM_BRANCH=`echo "$BRANCH_FROM_PR" | grep -oE 'issue-([0-9]+)(-|$)' | grep -oE '[0-9]+' | head -1`
if [ -z "$ISSUE_FROM_BRANCH" ]; then
  PR_BODY=`gh pr view "$ARGUMENTS" --json body --jq '.body' 2>/dev/null`
  ISSUE_FROM_BODY=`echo "$PR_BODY" | grep -oiE '(fixes|closes|resolves) #[0-9]+' | grep -oE '[0-9]+' | head -1`
  ISSUE_NUM="${ISSUE_FROM_BODY:-$ARGUMENTS}"
else
  ISSUE_NUM="$ISSUE_FROM_BRANCH"
fi
echo "Using issue number: $ISSUE_NUM"
```

**If NOT a PR, treat as issue.** Only set ISSUE_NUM if PR detection didn't:
!if [ -z "$ISSUE_NUM" ]; then ISSUE_NUM="$ARGUMENTS"; echo "Using issue number: $ISSUE_NUM"; fi

### 4. Validate the identifier exists

```bash
ISSUE_EXISTS=`gh issue view "$ISSUE_NUM" --json number 2>/dev/null`
PR_EXISTS=`gh pr view "$ARGUMENTS" --json number 2>/dev/null`
if [ -z "$ISSUE_EXISTS" ] && [ -z "$PR_EXISTS" ]; then
  echo "Error: #$ARGUMENTS is neither a valid issue nor PR"
  exit 1
fi
```

Fetch issue details:
!gh issue view "$ISSUE_NUM" --json title,state,number 2>/dev/null || echo "Issue #$ISSUE_NUM not found — using PR details"

### 5. Build worktree naming

```bash
REPO_NAME=`basename \`git rev-parse --show-toplevel\``
ITEM_TITLE=`gh issue view "$ISSUE_NUM" --json title --jq '.title' 2>/dev/null`
if [ -z "$ITEM_TITLE" ]; then
  ITEM_TITLE=`gh pr view "$ARGUMENTS" --json title --jq '.title' 2>/dev/null`
fi
CLEAN_TITLE=`echo "$ITEM_TITLE" | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//'`
WORKTREE_NAME="${REPO_NAME}-issue-${ISSUE_NUM}-${CLEAN_TITLE}"
WORKTREE_PATH="../$WORKTREE_NAME"
BRANCH_NAME="issue-${ISSUE_NUM}-${CLEAN_TITLE}"
```

### 6. Check if worktree already exists

```bash
EXISTING_PATH=`git worktree list | awk '{print $1}' | grep -E "issue-${ISSUE_NUM}-" | head -1`
if [ -n "$EXISTING_PATH" ]; then
  echo "WORKTREE_EXISTS"
  echo "Path: $EXISTING_PATH"
else
  echo "WORKTREE_NOT_FOUND"
fi
```

If `WORKTREE_EXISTS` → skip to Step 12 (switch). If `WORKTREE_NOT_FOUND` → continue.

### 7–11. Create new worktree

```bash
# 7. Validate state (warn but don't block on closed)
if [ "`gh issue view "$ISSUE_NUM" --json state --jq '.state' 2>/dev/null`" = "CLOSED" ]; then
  echo "Warning: Issue #$ISSUE_NUM is already closed"
fi

# 8. Detect default branch
DEFAULT_BRANCH=`git remote show origin | grep 'HEAD branch' | sed 's/.*: //' | tr -cd '[:alnum:]-._/'`
if [ -z "$DEFAULT_BRANCH" ]; then echo "Error: Could not determine default branch"; exit 1; fi

# 9. Fetch
git fetch origin "$DEFAULT_BRANCH"

# 10. Delete existing branch from prior failed attempts
git branch -D "$BRANCH_NAME" 2>/dev/null || true

# 11. Create worktree from default branch
if ! git worktree add "$WORKTREE_PATH" "origin/$DEFAULT_BRANCH"; then
  echo "Error: Failed to create worktree"; exit 1
fi
cd "$WORKTREE_PATH" && git checkout -b "$BRANCH_NAME"

# Search for env files
ENV_FILES=`find "$SOURCE_DIR" \( -name "node_modules" -o -name ".git" -o -name "vendor" \) -prune -o \( -name ".env" -o -name ".env.local" -o -name ".envrc" \) -type f -print 2>/dev/null | sed "s|^$SOURCE_DIR/||" | grep -v "^-" | sort`
if [ -n "$ENV_FILES" ]; then echo "Found env files:"; echo "$ENV_FILES"; fi
```

If env files found, use `AskUserQuestion`: "Found environment files (may contain secrets). Copy them to the new worktree?" with options **Yes, copy them** / **No, skip**.

If confirmed, copy preserving directory structure:

```bash
echo "$ENV_FILES" | while read file; do
  if [ -n "$file" ]; then
    dir=`dirname "$file"`
    if [ "$dir" != "." ]; then mkdir -p "$WORKTREE_PATH/$dir"; fi
    cp -P "$SOURCE_DIR/$file" "$WORKTREE_PATH/$file" && echo "Copied $file"
  fi
done
```

### 12. Capture absolute worktree path

```bash
if [ -n "$EXISTING_PATH" ]; then
  WORKTREE_ABS_PATH="$EXISTING_PATH"
else
  WORKTREE_ABS_PATH=`cd "$WORKTREE_PATH" && pwd`
fi
echo "WORKTREE_ABS_PATH=$WORKTREE_ABS_PATH"
ls "$WORKTREE_ABS_PATH"
```

**Save this value. You will use it for EVERY tool call from this point forward.**

### 13. Register worktree state

```bash
REPO_ROOT=`git rev-parse --show-toplevel`
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" save "$WORKTREE_ABS_PATH" "$REPO_ROOT" "$ISSUE_NUM"
```

This saves the worktree path so the pre-tool-use hook will **block** any tool call that accidentally targets the original repo instead of the worktree.

If this was an existing worktree, display current branch and status:
!cd "$WORKTREE_ABS_PATH" && git branch --show-current && git status --short

---

## ⚠️ MANDATORY: All Work Happens in the Worktree ⚠️

**Your shell CWD does NOT persist between Bash calls. Claude Code resets it every time.** You CANNOT just `cd` once — it will be forgotten. You must actively use the worktree path in EVERY tool call.

| Tool | How to use the worktree path |
|------|------------------------------|
| **Bash** | Prefix EVERY command: `cd "$WORKTREE_ABS_PATH" && <your command>` |
| **Read** | Use `$WORKTREE_ABS_PATH/path/to/file` as the `file_path` |
| **Edit** | Use `$WORKTREE_ABS_PATH/path/to/file` as the `file_path` |
| **Write** | Use `$WORKTREE_ABS_PATH/path/to/file` as the `file_path` |
| **Glob** | Set `path` parameter to `$WORKTREE_ABS_PATH` |
| **Grep** | Set `path` parameter to `$WORKTREE_ABS_PATH` |

**If you forget to use the worktree path, you WILL edit the wrong codebase.** There is no safety net. The original repo and the worktree have identical file structures — you won't get an error, you'll just silently modify the wrong files.

**Self-check before EVERY file operation:** "Does this path start with `$WORKTREE_ABS_PATH`?" If not, STOP and fix it.

---

## Next Steps

- Start working on the issue, or continue where you left off if resuming an existing worktree
- When done, use `/prune-worktree` to clean up or `/remove-worktree` to remove a specific worktree
