# Start-Issue Workspace and Planning

Loaded by `skills/start-issue/SKILL.md` after repository context gathering. Execute the complete procedure before issue classification or implementation.

## Worktree Detection & Decision (BEFORE Plan Mode)

First, check if already running inside a git worktree:

```bash
IN_WORKTREE=false
GIT_DIR_ABS=$(git -C "$WORKTREE_PATH" rev-parse --absolute-git-dir 2>/dev/null)
GIT_COMMON_REL=$(git -C "$WORKTREE_PATH" rev-parse --git-common-dir 2>/dev/null)
GIT_COMMON_ABS=$(cd "$WORKTREE_PATH" && cd "$GIT_COMMON_REL" && pwd)
if [ -n "$GIT_DIR_ABS" ] && [ -n "$GIT_COMMON_ABS" ] && [ "$GIT_DIR_ABS" != "$GIT_COMMON_ABS" ]; then
  IN_WORKTREE=true
fi
```

This resolves both `--git-dir` and `--git-common-dir` to absolute paths via
`cd ... && pwd`, then compares them. In the main repo (even from a subdirectory)
both resolve to the same absolute `.git` path. In a linked worktree, `--git-dir`
resolves to `.git/worktrees/<name>` while `--git-common-dir` resolves to `.git`.

**If `IN_WORKTREE=true`:** Skip the worktree question entirely. Proceed directly
to "Plan Mode Check" (the "No, work in current directory" path). Display:

```text
Already running in a worktree — skipping worktree creation.
```

**If `IN_WORKTREE=false`:** resolve this as a **driver-resolvable gate** before
planning:

1. Use the current checkout when the request or execution environment already
   provides isolation, or when the checkout is a clean non-default feature
   branch dedicated to this issue.
2. Create a worktree when the user explicitly requested one or when the current
   checkout is the shared default checkout and isolation is available.
3. Otherwise use the current checkout and create the required feature branch.

State `Decision`, `Evidence`, and `Rationale` as defined by
`decision-gates.md`, then continue. Do not request input for this technical
choice.

---

## If the driver selected "create worktree"

→ Read `<PLUGIN_ROOT>/lib/start-issue/worktree-create.md` and follow the
full procedure: capture `SOURCE_DIR`, derive `WORKTREE_NAME`/`BRANCH_NAME` from
issue title, fetch and create the worktree, search for env files
(`.env`/`.env.local`/`.envrc`) and offer to copy with directory structure
preserved, capture `WORKTREE_ABS_PATH`, register the compatibility worktree
state file, and confirm to the user.

After the worktree is established, continue to **Plan Mode Check** below.

Persist the selected worktree in the root physical-context fields of the same
caller-owned file:

```bash
set_loop_field "$STATE_FILE" "worktree_path" "$WORKTREE_ABS_PATH" '[]'
```

## If the driver selected "work in current directory"

Continue to **Step 1: Detect Issue Type** below. You will create a branch in the
appropriate workflow step.

**Now** use the active surface's planning capability to create a plan for the
implementation. If no native planning capability is available, write and
maintain an explicit plan as required by the cross-platform binding rules.

---

## Plan Mode Check (AFTER worktree is established)

**Now** enter the active surface's planning workflow to create a plan for the
implementation. If no native planning workflow is available, write and
maintain an explicit plan.

**CRITICAL: When writing your plan, include these facts at the top of the plan
file:**

If a worktree was created:

```markdown
## Working Directory
All work MUST happen in: <the concrete WORKTREE_PATH value>
Original repo (state only): <the ORIGINAL_REPO_ROOT value>
Every repository command and file path must explicitly target the worktree.
Do not rely on a pre-tool-use hook to reject an ambient-directory operation.
```

If no worktree:

```markdown
## Working Directory
Working in current directory. A feature branch will be created.
```

If you ARE already in plan mode, continue with the workflow below.

---

## MANDATORY: All Work Happens in the Worktree

**Your shell CWD does NOT persist between Bash calls.** Every repository command
must explicitly target `WORKTREE_PATH`; a prior `cd` is never evidence of scope.

| Tool | How to use the worktree path |
|------|------------------------------|
| **Bash** | Prefer `git -C "$WORKTREE_PATH"`, `go -C "$WORKTREE_PATH"`, and `gh ... --repo "$REPO_SLUG"`; use `(cd "$WORKTREE_PATH" && ...)` only when a command has no directory option |
| **Read** | Use `$WORKTREE_PATH/path/to/file` as the `file_path` |
| **Edit** | Use `$WORKTREE_PATH/path/to/file` as the `file_path` |
| **Write** | Use `$WORKTREE_PATH/path/to/file` as the `file_path` |
| **Glob** | Set `path` parameter to `$WORKTREE_PATH` |
| **Grep** | Set `path` parameter to `$WORKTREE_PATH` |

No hook is assumed to enforce this invariant. Each command and file operation
must be correct on its own.

**Self-check before EVERY file operation:** "Does this path start with
`$WORKTREE_PATH`?" If not, STOP and fix it.

**Note:** When using a worktree, the branch is already
`issue-<num>-<title>`. Skip the "Create Branch" step in the workflows below.

Continue to **Step 1: Detect Issue Type** below.

---

## Branch Protection Check

**CRITICAL:** Before starting any work, verify you will NOT commit to
main/master.

This workflow creates feature branches (`fix/` or `feat/`). If you are
currently on `main`, `master`, or the default branch:

- **If worktree was created**: You should already be on the `issue-<num>-<title>` branch
- **If working in current directory**: A branch will be created in Step 3 (Bug) or Step 4 (Feature)

**NEVER commit directly to main/master.** Always ensure a feature branch exists
before making any code changes.

---
