---
description: "Create a git commit with auto-generated message"
allowed-tools: ["Bash(git add:*)", "Bash(git status:*)", "Bash(git commit:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git branch:*)", "Bash(git checkout:*)", "Bash(git remote:*)", "AskUserQuestion"]
model: haiku
---

# Create Git Commit

## Context

- Current git status: !`git status 2>&1 || echo "Unable to get git status"`
- Current git diff (staged and unstaged changes): !`git diff HEAD 2>&1 || echo "No diff available (may have no commits)"`
- Current branch: !`git branch --show-current 2>&1 || echo "unknown"`
- Default branch: !`git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main"`
- Recent commits (for style matching): !`git log --oneline -10 2>&1 || echo "No commits in history"`

## Branch Protection

**CRITICAL:** Check if you are on `main`, `master`, or the default branch.

If the current branch is `main`, `master`, or matches the default branch:
1. **STOP** - Do not commit directly to the main branch
2. **Inform the user**: "You are on the main branch. Creating a feature branch is recommended."
3. **Ask the user** using AskUserQuestion:
   - "You're on the main branch. How would you like to proceed?"
   - Options:
     - "Create feature branch" - Create a new branch first, then commit
     - "Commit to main anyway" - Only if user explicitly wants this

If the user chooses "Create feature branch":
- Analyze the changes to suggest a branch name
- Create branch: `git checkout -b <type>/<short-description>`
- Then proceed with the commit

## Your Task

Based on the above changes, create a single git commit.

**Guidelines:**

1. **Analyze the changes** - Understand what was modified, added, or deleted
2. **Match repository style** - Follow the commit message patterns from recent commits
3. **Use conventional commits** if the repo uses them: `type(scope): subject`
   - Types: feat, fix, docs, style, refactor, test, chore, perf
4. **Keep subject line ≤50 chars**, imperative mood ("add" not "added")
5. **Stage only relevant files** - Don't stage secrets (.env, credentials, etc.)

**Execution:**

You have the capability to call multiple tools in a single response. Stage relevant files and create the commit in a single message.

Do not include Claude Code attribution in the commit message (user can add if desired).

If there are no changes to commit, inform the user and stop.
