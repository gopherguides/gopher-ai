---
name: commit
description: "Create a git commit with an auto-generated conventional message from staged changes. Use for 'commit', 'save my work', or 'make a commit'. Does not push or open PRs; use `create-pr` for PR-only flow and `ship` for verify+push+merge."
---

# Commit

Create a git commit with an auto-generated conventional commit message.

Before requesting decisions, read
`${CLAUDE_PLUGIN_ROOT}/lib/driver-interaction.md` and follow its
cross-platform capability-binding rules.

## Usage

```
$go-workflow:commit
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

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=default-branch
```

Stop without committing. Create or switch to a feature branch before invoking
this skill again; no driver may authorize a direct default-branch commit.

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
