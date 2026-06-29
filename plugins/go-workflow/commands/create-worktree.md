---
argument-hint: "<issue-or-pr-number>"
description: "Create or reuse a git worktree for a GitHub issue or PR"
allowed-tools: ["Bash(*worktree-state.sh*)", "Bash(*worktree-create.sh*)", "Bash(pwd:*)", "Read", "AskUserQuestion"]
---

# Create Worktree for Issue or PR

**If `$ARGUMENTS` is empty or not provided:**

This command creates or reuses an isolated git worktree for working on a GitHub
issue or PR.

**Usage:** `/create-worktree <issue-or-pr-number>`

**Examples:**
- `/create-worktree 789` — create worktree for issue #789
- `/create-worktree 42` — if #42 is a PR, resolve its linked issue and create
  or reuse the issue worktree

**What it does:** detects PR vs issue → reuses an existing standard issue
worktree if found → otherwise creates `../reponame-issue-<num>-<title>/` from
the default branch → creates the issue branch → optionally copies env files →
registers worktree state.

**Prerequisites:** `gh` authenticated; run from inside a git repository.

Ask the user: "What issue or PR number would you like to work on?"

---

**If `$ARGUMENTS` is provided:**

## Clear Worktree State

Clear stale worktree state so the pre-tool-use hook does not block setup
commands:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" clear 2>/dev/null || true
```

## Environment Files

Check whether the source repo has environment files before creating or reusing
the worktree:

```bash
SOURCE_DIR="$(pwd)"
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-create.sh" env-files --source-dir "$SOURCE_DIR"
```

If the output starts with `ENV_FILES_FOUND=true`, use `AskUserQuestion`: "Found
environment files (may contain secrets). Copy them to the worktree?" with
**Yes, copy them** / **No, skip**.

## Create or Reuse Worktree

If the user chose to copy env files:

```bash
SOURCE_DIR="$(pwd)"
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-create.sh" create "$ARGUMENTS" --source-dir "$SOURCE_DIR" --copy-env
```

Otherwise:

```bash
SOURCE_DIR="$(pwd)"
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-create.sh" create "$ARGUMENTS" --source-dir "$SOURCE_DIR" --no-copy-env
```

The script validates input and prerequisites, detects PR vs issue, derives the
standard branch and path, fetches the default branch, creates or reuses the
worktree, optionally copies env files, registers state, and prints:

- `Worktree absolute path: <path>`
- `Branch: <branch>`

Save the printed worktree path as `WORKTREE_ABS_PATH`.

---

## Mandatory: All Work Happens in the Worktree

Your shell CWD does not persist between Bash calls. You cannot just `cd` once;
you must actively use the worktree path in every tool call.

| Tool | How to use the worktree path |
|------|------------------------------|
| **Bash** | Prefix every command: `cd "$WORKTREE_ABS_PATH" && <your command>` |
| **Read** | Use `$WORKTREE_ABS_PATH/path/to/file` as the `file_path` |
| **Edit** | Use `$WORKTREE_ABS_PATH/path/to/file` as the `file_path` |
| **Write** | Use `$WORKTREE_ABS_PATH/path/to/file` as the `file_path` |
| **Glob** | Set `path` parameter to `$WORKTREE_ABS_PATH` |
| **Grep** | Set `path` parameter to `$WORKTREE_ABS_PATH` |

Self-check before every file operation: "Does this path start with
`$WORKTREE_ABS_PATH`?" If not, stop and fix it.

---

## Next Steps

- Start working on the issue, or continue where you left off if resuming an
  existing worktree
- When done, use `/prune-worktree` to clean up or `/remove-worktree` to remove
  a specific worktree
