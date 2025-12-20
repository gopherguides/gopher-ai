---
description: "Create a git commit with auto-generated message"
allowed-tools: ["Bash(git add:*)", "Bash(git status:*)", "Bash(git commit:*)", "Bash(git diff:*)", "Bash(git log:*)"]
model: haiku
---

# Create Git Commit

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits (for style matching): !`git log --oneline -10`

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
