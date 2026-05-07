# Start-Issue — Worktree Creation

Loaded by `commands/start-issue.md` when the user picked "Yes, create worktree".
Owns the full worktree creation procedure including env-file copy and state-file
registration.

**CRITICAL: When executing bash commands below, use backticks (`` ` ``) for command substitution, NOT `$()`. Claude Code has a bug that mangles `$()` syntax.**

**Create the worktree NOW, before entering plan mode.** This ensures the worktree path is a concrete, established fact when the plan is written.

## 1. Capture source directory first

```bash
SOURCE_DIR=`pwd`
```

## 2. Create worktree directory name

```bash
REPO_NAME=`basename \`git rev-parse --show-toplevel\``
ISSUE_TITLE=`gh issue view "$ISSUE_NUM" --json title --jq '.title' | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//'`
WORKTREE_NAME="${REPO_NAME}-issue-$ISSUE_NUM-$ISSUE_TITLE"
WORKTREE_PATH="../$WORKTREE_NAME"
BRANCH_NAME="issue-$ISSUE_NUM-$ISSUE_TITLE"
```

## 3. Fetch and create worktree

```bash
DEFAULT_BRANCH=`git remote show origin | grep 'HEAD branch' | sed 's/.*: //' | tr -cd '[:alnum:]-._/'`
git fetch origin "$DEFAULT_BRANCH"
git branch -D "$BRANCH_NAME" 2>/dev/null || true
git worktree add "$WORKTREE_PATH" "origin/$DEFAULT_BRANCH"
cd "$WORKTREE_PATH" && git checkout -b "$BRANCH_NAME"
```

## 4. Search for environment files

Recursive find, excludes `node_modules`, `.git`, `vendor`:

```bash
ENV_FILES=`find "$SOURCE_DIR" \( -name "node_modules" -o -name ".git" -o -name "vendor" \) -prune -o \
  \( -name ".env" -o -name ".env.local" -o -name ".envrc" \) -type f -print 2>/dev/null | \
  sed "s|^$SOURCE_DIR/||" | grep -v "^-" | sort`
if [ -n "$ENV_FILES" ]; then
  echo "Found env files:"
  echo "$ENV_FILES"
fi
```

If env files are found, list them and ask the user via `AskUserQuestion`: "Found environment files (may contain secrets). Copy them to worktree?"

If confirmed, copy preserving directory structure:

```bash
echo "$ENV_FILES" | while read file; do
  if [ -n "$file" ]; then
    dir=`dirname "$file"`
    if [ "$dir" != "." ]; then
      mkdir -p "$WORKTREE_PATH/$dir"
    fi
    cp -P "$SOURCE_DIR/$file" "$WORKTREE_PATH/$file"
    echo "Copied $file"
  fi
done
```

## 5. Capture absolute worktree path

```bash
WORKTREE_ABS_PATH=`cd "$WORKTREE_PATH" && pwd`
echo "Worktree absolute path: $WORKTREE_ABS_PATH"
ls "$WORKTREE_ABS_PATH"
```

**Save this absolute path.** You will use it for EVERY tool call from this point forward (see the trunk's "MANDATORY: All Work Happens in the Worktree" section).

## 6. Register worktree state

Enables hook-based path enforcement. The pre-tool-use hook reads this state file and **blocks** any tool call that accidentally targets the original repo:

```bash
REPO_ROOT=`git rev-parse --show-toplevel`
"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" save "$WORKTREE_ABS_PATH" "$REPO_ROOT" "$ISSUE_NUM"
```

## 7. Inform user

Display: "Created worktree at `$WORKTREE_ABS_PATH`. All work will happen there."

Continue to the trunk's **Plan Mode Check** section.
