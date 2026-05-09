---
name: worktree
description: "Manage git worktrees for issue/PR isolation. Use when user says 'create worktree', 'worktree for issue #N', 'remove worktree', 'delete worktree', 'prune worktrees', 'clean up worktrees', or wants an isolated workspace per issue. Three actions: create (one new worktree from default branch), remove (interactively delete one with safety checks), prune (batch-remove all completed worktrees where issue is closed AND branch is merged)."
---

# Worktree

Manage git worktrees for isolated per-issue/per-PR work. Three sub-actions, each in its own sibling file.

## Action selection

| User intent | Sibling | Slash command |
|---|---|---|
| Create one worktree for an issue or PR | `create.md` | `/create-worktree <num>` |
| Remove a specific worktree (interactively) | `remove.md` | `/remove-worktree` |
| Batch-clean all completed worktrees | `prune.md` | `/prune-worktree` |

Match the user's request to one of the three rows, then read the corresponding sibling for the full procedure.

## Conventions (apply to all three actions)

- **Worktree path**: `../<reponame>-issue-<num>-<title-slug>/` — sibling to the source repo, never inside it
- **Branch name**: `issue-<num>-<title-slug>`
- **Title slug**: lowercase, alnum + hyphens, derived from `gh issue view --json title`
- **Identifier rule**: `issue-<NUM>-` prefix is the trusted issue marker on a branch — `fix/2fa-login` contains a number but is NOT an issue branch
- **Default branch**: `git remote show origin | grep 'HEAD branch'` (handles repos with `main` vs `master` vs custom)
- **State file**: `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh` registers the active worktree so the pre-tool-use hook blocks accidental edits to the source repo

## Prerequisites (all three)

- `gh` CLI installed and authenticated
- Run from inside a git repository (any worktree of the repo, not just the main checkout)

## Further Reading

- `create.md` — full create procedure (PR vs issue detection, env-file copy, state registration)
- `remove.md` — interactive selection + safety-check matrix (issue closed? branch merged? uncommitted changes?)
- `prune.md` — batch evaluation, classification, confirmation, removal
