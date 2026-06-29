# Worktree — Create

Create or reuse an isolated git worktree for a GitHub issue or PR. Loaded by
`SKILL.md` when the user wants to start work on an issue.

## Usage

User-facing slash command: `/create-worktree <issue-or-pr-number>`. Skill
invocation: `$worktree` (with create intent).

## Steps

### Step 1: Capture Input

Set `NUMBER` to the issue or PR number from the user. The script validates that
the value is numeric and resolves whether it is an issue or PR.

```bash
NUMBER="<issue-or-pr-number>"
```

### Step 2: Check for Environment Files

```bash
SOURCE_DIR="$(pwd)"
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-create.sh" env-files --source-dir "$SOURCE_DIR"
```

If the output starts with `ENV_FILES_FOUND=true`, ask the user: "Found
environment files (may contain secrets). Copy them to the worktree?"

### Step 3: Create or Reuse Worktree

If the user chose to copy env files:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-create.sh" create "$NUMBER" --source-dir "$SOURCE_DIR" --copy-env
```

Otherwise:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-create.sh" create "$NUMBER" --source-dir "$SOURCE_DIR" --no-copy-env
```

The script detects PR vs issue, derives the standard branch and path, fetches
the default branch, creates or reuses the worktree, optionally copies env files,
registers state, and prints the absolute worktree path plus branch.

## Working in the Worktree

After creating a worktree, all file operations must use the worktree's absolute
path. The worktree is a separate copy of the repo, so edits there do not affect
the original directory.

When done with the worktree, see `remove.md` (single removal) or `prune.md`
(batch cleanup) — both siblings of this file under the `worktree` skill.
