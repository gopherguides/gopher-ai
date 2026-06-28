---
name: commit
description: "Create a git commit with an auto-generated conventional message from staged changes. Use for 'commit', 'save my work', or 'make a commit'. Does not push or open PRs; use `create-pr` for PR-only flow and `ship` for verify+push+merge."
allowed-tools: ["Bash(git add:*)", "Bash(git status:*)", "Bash(git commit:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git branch:*)", "Bash(git checkout:*)", "Bash(git remote:*)", "AskUserQuestion"]
---

# Commit

Create a git commit with an auto-generated conventional commit message.

## Usage

```
$commit
```

## Steps

### Step 1: Gather Context

Run these commands to understand the current state:

```bash
git status
git diff HEAD
git branch --show-current
git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main"
git log --oneline -10
```

### Step 2: Branch Protection

Check if you are on `main`, `master`, or the default branch:

```bash
DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //')
CURRENT=$(git branch --show-current)
```

If `$CURRENT` is `main`, `master`, or matches the default branch:
1. Stop — do not commit to the main branch
2. Ask the user how to proceed:
   - Create a feature branch first, then commit
   - Commit to main anyway (only if explicitly requested)

### Step 3: Analyze Changes

Review the diff to understand what changed:
- What files were modified, added, or deleted
- The nature of the changes (new feature, bug fix, refactor, docs, test, etc.)

### Step 4: Generate Commit Message

Follow the repository's commit style (check `git log --oneline -10`).

If the repo uses conventional commits:

```
<type>(<scope>): <subject>
```

- **Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`
- **Subject**: 50 chars max, imperative mood ("add" not "added"), no trailing period
- For complex changes, add a body explaining what and why (72-char line wrap)

### Step 5: Stage and Commit

Stage only relevant files — do not stage secrets (`.env`, credentials, etc.):

```bash
git add <relevant-files>
git commit -m "<type>(<scope>): <subject>"
```

If there are no changes to commit, inform the user and stop.
