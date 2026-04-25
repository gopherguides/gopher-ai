---
name: create-worktree
description: "Create a git worktree for an issue or PR. Trigger on 'create worktree', 'worktree for issue #N'."
---

# Create Worktree

Create an isolated git worktree for working on a GitHub issue or PR.

## Usage

```
$create-worktree <issue-or-pr-number>
```

## Prerequisites

- GitHub CLI (`gh`) installed and authenticated
- Must be inside a git repository

## Steps

### Step 1: Validate Input

Confirm the argument is a number:

```bash
NUMBER="<issue-or-pr-number>"
echo "$NUMBER" | grep -qE '^[0-9]+$' || { echo "Error: must be a number"; exit 1; }
```

### Step 2: Detect PR vs Issue

Check if the number is a PR:

```bash
PR_JSON=$(gh pr view "$NUMBER" --json number,title,headRefName 2>/dev/null)
```

**If PR detected**: Extract the linked issue number from the branch name (`issue-<NUM>-` pattern) or PR body (`Fixes #N`, `Closes #N`). Use the issue number for naming.

**If PR detected but no linked issue found**: Fall back to using the PR number itself as the identifier. Set `ISSUE_NUM=$NUMBER` and use the PR title for naming:

```bash
ISSUE_NUM=$NUMBER
PR_TITLE=$(echo "$PR_JSON" | jq -r '.title // empty')
```

**If not a PR**: Treat as an issue number directly. Set `ISSUE_NUM=$NUMBER`.

Fetch issue/PR details:

```bash
gh issue view "$ISSUE_NUM" --json title,state,number 2>/dev/null || \
  gh pr view "$ISSUE_NUM" --json title,state,number
```

### Step 3: Check for Existing Worktree

```bash
EXISTING=$(git worktree list | awk '{print $1}' | grep -E "issue-${ISSUE_NUM}-" | head -1)
```

If found, report the existing path and switch to it — skip creation.

### Step 4: Build Naming Variables

```bash
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
TITLE=$(gh issue view "$ISSUE_NUM" --json title --jq '.title' | \
  sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]' | \
  sed 's/--*/-/g; s/^-//; s/-$//')
WORKTREE_NAME="${REPO_NAME}-issue-${ISSUE_NUM}-${TITLE}"
WORKTREE_PATH="../${WORKTREE_NAME}"
BRANCH_NAME="issue-${ISSUE_NUM}-${TITLE}"
```

### Step 5: Create Worktree

```bash
DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | sed 's/.*: //')
git fetch origin "$DEFAULT_BRANCH"
git branch -D "$BRANCH_NAME" 2>/dev/null || true
git worktree add "$WORKTREE_PATH" "origin/$DEFAULT_BRANCH"
cd "$WORKTREE_PATH" && git checkout -b "$BRANCH_NAME"
```

### Step 6: Copy Environment Files (Optional)

Search for environment files in the source directory:

```bash
SOURCE_DIR="$(pwd)"
find "$SOURCE_DIR" \( -name node_modules -o -name .git -o -name vendor \) -prune -o \
  \( -name ".env" -o -name ".env.local" -o -name ".envrc" \) -type f -print
```

If found, ask the user: "Found environment files (may contain secrets). Copy them to the worktree?"

If confirmed, copy them preserving directory structure.

### Step 7: Report

Display the absolute worktree path:

```bash
WORKTREE_ABS=$(cd "$WORKTREE_PATH" && pwd)
echo "Worktree created at: $WORKTREE_ABS"
echo "Branch: $BRANCH_NAME"
```

## Working in the Worktree

After creating a worktree, all file operations must use the worktree's absolute path. The worktree is a separate copy of the repo — edits there do not affect the original directory.

When done with the worktree, use `$remove-worktree` or `$prune-worktree` to clean up.
