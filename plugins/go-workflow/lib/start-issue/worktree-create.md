# Start-Issue — Worktree Creation

Loaded by `skills/start-issue/SKILL.md` when the driver selected "create
worktree". The executable script owns naming, default-branch fetch, worktree
creation/reuse, optional env-file copy, and state-file registration.

**Create the worktree NOW, before entering plan mode.** This ensures the
worktree path is a concrete, established fact when the plan is written.

## 1. Capture source directory first

```bash
SOURCE_DIR="$ORIGINAL_REPO_ROOT"
```

## 2. Check for environment files

```bash
/bin/bash "<PLUGIN_ROOT>/scripts/worktree-create.sh" env-files --source-dir "$SOURCE_DIR"
```

If the output starts with `ENV_FILES_FOUND=true`, this is a
**missing-intent gate** because the files may contain secrets. Request consent:
"Found environment files that may contain secrets. Copy them to the worktree?"
If structured input is unavailable, ask in the final response and stop before
creating the worktree. Do not infer consent.

## 3. Create or reuse the worktree

If copying environment files was explicitly authorized:

```bash
/bin/bash "<PLUGIN_ROOT>/scripts/worktree-create.sh" create "$ISSUE_NUM" --source-dir "$SOURCE_DIR" --copy-env
```

Otherwise:

```bash
/bin/bash "<PLUGIN_ROOT>/scripts/worktree-create.sh" create "$ISSUE_NUM" --source-dir "$SOURCE_DIR" --no-copy-env
```

The script prints the absolute worktree path and branch name, and registers the
compatibility worktree state file. Downstream commands must still target the
persisted path explicitly because hook enforcement is not assumed.

## 4. Capture absolute worktree path

Use the `Worktree absolute path:` line printed by the script as
`WORKTREE_PATH`, validate it is absolute and is a registered worktree, then
persist it before any downstream phase:

```bash
if [ -z "$WORKTREE_PATH" ] || [ "${WORKTREE_PATH#/}" = "$WORKTREE_PATH" ] ||
   ! git -C "$ORIGINAL_REPO_ROOT" worktree list --porcelain | awk -v expected="$WORKTREE_PATH" '/^worktree / {sub(/^worktree /, ""); if ($0 == expected) found=1} END {exit found ? 0 : 1}'; then
  echo "ERROR: Worktree creation did not return a valid absolute worktree path."
  exit 1
fi
TMP="${STATE_FILE}.tmp"
jq --arg worktree_path "$WORKTREE_PATH" '.worktree_path = $worktree_path' \
  "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

**Save this absolute path.** You will use it for EVERY tool call from this point
forward (see the trunk's "MANDATORY: All Work Happens in the Worktree" section).

## 5. Inform user

Display: "Created worktree at `$WORKTREE_PATH`. All work will happen there."

Continue to the trunk's **Plan Mode Check** section.
