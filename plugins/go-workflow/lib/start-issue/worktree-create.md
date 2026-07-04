# Start-Issue — Worktree Creation

Loaded by `skills/start-issue/SKILL.md` when the user picked "Yes, create
worktree". The executable script owns naming, default-branch fetch, worktree
creation/reuse, optional env-file copy, and state-file registration.

**Create the worktree NOW, before entering plan mode.** This ensures the
worktree path is a concrete, established fact when the plan is written.

## 1. Capture source directory first

```bash
SOURCE_DIR="$(pwd)"
```

## 2. Check for environment files

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-create.sh" env-files --source-dir "$SOURCE_DIR"
```

If the output starts with `ENV_FILES_FOUND=true`, use `AskUserQuestion`: "Found
environment files (may contain secrets). Copy them to worktree?" with **Yes,
copy them** / **No, skip**.

## 3. Create or reuse the worktree

If the user chose to copy env files:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-create.sh" create "$ISSUE_NUM" --source-dir "$SOURCE_DIR" --copy-env
```

Otherwise:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-create.sh" create "$ISSUE_NUM" --source-dir "$SOURCE_DIR" --no-copy-env
```

The script prints the absolute worktree path and branch name, and registers the
worktree state file so hook-based path enforcement is active.

## 4. Capture absolute worktree path

Use the `Worktree absolute path:` line printed by the script as
`WORKTREE_ABS_PATH`.

**Save this absolute path.** You will use it for EVERY tool call from this point
forward (see the trunk's "MANDATORY: All Work Happens in the Worktree" section).

## 5. Inform user

Display: "Created worktree at `$WORKTREE_ABS_PATH`. All work will happen there."

Continue to the trunk's **Plan Mode Check** section.
