---
argument-hint: "<issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
description: "Start working on a GitHub issue (auto-detects bug vs feature)"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion", "EnterPlanMode", "Agent"]
---

# Start Issue

**If `$ARGUMENTS` is empty or not provided:**

> This command starts work on a GitHub issue, automatically detecting whether it's a bug fix or new feature and following the appropriate workflow.
>
> **Usage:** `/start-issue <issue-number> [--skip-coverage] [--coverage-threshold <n>]`
>
> **Example:** `/start-issue 123` or `/start-issue 123 --coverage-threshold 80`
>
> **Options:**
> - `--skip-coverage`: Skip coverage verification after implementation
> - `--coverage-threshold <n>`: Override default 60% coverage threshold
> - `--no-agents`: Use single-session workflow instead of subagent dispatch (for small/simple issues)
>
> **Workflow:**
> 1. Fetch issue details, labels, and comments
> 2. Optionally create a git worktree for isolated work
> 3. Auto-detect issue type (bug vs feature)
> 4. Create `fix/` or `feat/` branch (or use worktree branch)
> 5. For bugs: Check duplicates → TDD red-green → verify → **coverage check** → security review
> 6. For features: Plan approach → TDD red-green → verify → **coverage check** → security review
> 7. Commit, push, and create PR

Ask the user: "What issue number would you like to work on?"

---

**If `$ARGUMENTS` is provided:**

## Output Durability

Any artifact this command produces — commit messages, PR titles and bodies, GitHub issue comments — describes modules, contracts, and observable behavior, not file paths, line numbers, or current internal layout. Acceptance criteria are stated as behaviors a reviewer can verify, not as file diffs. The artifact must remain interpretable after a future refactor.

## Clear Stale Worktree State

Clear any leftover worktree state from a prior session. This prevents the pre-tool-use hook from blocking commands in a fresh `/start-issue` invocation:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" clear 2>/dev/null || true`

## Security Validation & Flag Parsing

Strip optional flags and extract the issue number:
!ISSUE_NUM=`echo "$ARGUMENTS" | sed 's/--skip-coverage//g; s/--coverage-threshold *[0-9]*//g; s/--no-agents//g' | tr -d ' '`; HAS_SKIP=`echo "$ARGUMENTS" | grep -q '\-\-skip-coverage' && echo "true" || echo "false"`; COV_THRESH=`echo "$ARGUMENTS" | grep -oE '\-\-coverage-threshold [0-9]+' | awk '{print $2}'`; NO_AGENTS=`echo "$ARGUMENTS" | grep -q '\-\-no-agents' && echo "true" || echo "false"`; if ! echo "$ISSUE_NUM" | grep -qE '^[0-9]+$'; then echo "Error: Issue number must be numeric. Usage: /start-issue <number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"; exit 1; fi; echo "Issue: $ISSUE_NUM | skip-coverage: $HAS_SKIP | coverage-threshold: ${COV_THRESH:-60} | no-agents: $NO_AGENTS"

The output above shows the parsed issue number and flag values.

**CRITICAL: From this point forward, use `$ISSUE_NUM` (the numeric issue number shown above) everywhere you would use `$ARGUMENTS`.** The raw `$ARGUMENTS` may contain flags and MUST NOT be passed to `gh issue view`, branch names, worktree names, or state file paths.

Store the parsed flags:
- `SKIP_COVERAGE`: `true` if `--skip-coverage` was passed, `false` otherwise
- `COVERAGE_THRESHOLD`: the value after `--coverage-threshold`, or `60` if not specified
- `NO_AGENTS`: `true` if `--no-agents` was passed, `false` otherwise

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else ISSUE_NUM=$(echo "$ARGUMENTS" | sed 's/--skip-coverage//g; s/--coverage-threshold *[0-9]*//g; s/--no-agents//g' | tr -d ' '); "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "start-issue-$ISSUE_NUM" "COMPLETE" "" "" '{}'; fi`

## Context

- Issue details: !`ISSUE_NUM=$(echo "$ARGUMENTS" | sed 's/--skip-coverage//g; s/--coverage-threshold *[0-9]*//g; s/--no-agents//g' | tr -d ' '); gh issue view "$ISSUE_NUM" --json title,state,body,labels,comments --jq '.' 2>/dev/null || echo "Issue not found"`
- Current branch: !`git branch --show-current 2>&1 || echo "unknown"`
- Default branch: !`git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main"`
- Repository name: !`basename \`git rev-parse --show-toplevel 2>/dev/null\` 2>/dev/null || echo "unknown"`
- Existing worktrees: !`git worktree list 2>&1 || echo "No worktrees found"`

---

## Worktree Detection & Decision (BEFORE Plan Mode)

**First, check if already running inside a git worktree:**

```bash
IN_WORKTREE=false
GIT_DIR_ABS=`cd \`git rev-parse --git-dir 2>/dev/null\` && pwd`
GIT_COMMON_ABS=`cd \`git rev-parse --git-common-dir 2>/dev/null\` && pwd`
if [ -n "$GIT_DIR_ABS" ] && [ -n "$GIT_COMMON_ABS" ] && [ "$GIT_DIR_ABS" != "$GIT_COMMON_ABS" ]; then
  IN_WORKTREE=true
fi
```

This resolves both `--git-dir` and `--git-common-dir` to absolute paths via `cd ... && pwd`, then compares them. In the main repo (even from a subdirectory) both resolve to the same absolute `.git` path. In a linked worktree, `--git-dir` resolves to `.git/worktrees/<name>` while `--git-common-dir` resolves to `.git`.

**If `IN_WORKTREE=true`:** Skip the worktree question entirely. Proceed directly to "Plan Mode Check" (the "No, work in current directory" path). Display:

```
Already running in a worktree — skipping worktree creation.
```

**If `IN_WORKTREE=false`:** You MUST use AskUserQuestion NOW before doing anything else — including EnterPlanMode.

Do not:
- Call EnterPlanMode yet
- Analyze the issue beyond the context already gathered
- Launch Task or Explore agents
- Start any implementation work

Use AskUserQuestion with this exact configuration:

- **Question:** "Would you like to create a worktree for isolated work on issue #$ISSUE_NUM?"
- **Options:**
  1. "Yes, create worktree" - Create isolated worktree and switch to it
  2. "No, work in current directory" - Stay here and create a branch

**WAIT for the user's response. Do not proceed until they answer.**

---

## If user chose "Yes, create worktree"

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/start-issue/worktree-create.md` and follow the full procedure: capture `SOURCE_DIR`, derive `WORKTREE_NAME`/`BRANCH_NAME` from issue title, fetch and create the worktree, search for env files (`.env`/`.env.local`/`.envrc`) and offer to copy with directory structure preserved, capture `WORKTREE_ABS_PATH`, register the worktree state file (enables hook-based path enforcement), and confirm to the user.

After the worktree is established, continue to **Plan Mode Check** below.

## If user chose "No, work in current directory"

Continue to **Step 1: Detect Issue Type** below. You will create a branch in the appropriate workflow step.

**Now** call `EnterPlanMode` to create a plan for the implementation (if not already in plan mode).

---

## Plan Mode Check (AFTER worktree is established)

**Now** call `EnterPlanMode` to create a plan for the implementation.

If you are NOT currently in plan mode (no "Plan mode is active" in your system context), call the `EnterPlanMode` tool now.

**CRITICAL: When writing your plan, include these facts at the top of the plan file:**

If a worktree was created:
```
## Working Directory
All work MUST happen in: <the concrete WORKTREE_ABS_PATH value>
Original repo (DO NOT USE): <the SOURCE_DIR value>
The pre-tool-use hook will BLOCK any tool call targeting the original repo.
```

If no worktree:
```
## Working Directory
Working in current directory. A feature branch will be created.
```

If you ARE already in plan mode, continue with the workflow below.

---

## ⚠️ MANDATORY: All Work Happens in the Worktree ⚠️

**Your shell CWD does NOT persist between Bash calls. Claude Code resets it every time.** You CANNOT just `cd` once — it will be forgotten. You must actively use the worktree path in EVERY tool call.

| Tool | How to use the worktree path |
|------|------------------------------|
| **Bash** | Prefix EVERY command: `cd "$WORKTREE_ABS_PATH" && <your command>` |
| **Read** | Use `$WORKTREE_ABS_PATH/path/to/file` as the `file_path` |
| **Edit** | Use `$WORKTREE_ABS_PATH/path/to/file` as the `file_path` |
| **Write** | Use `$WORKTREE_ABS_PATH/path/to/file` as the `file_path` |
| **Glob** | Set `path` parameter to `$WORKTREE_ABS_PATH` |
| **Grep** | Set `path` parameter to `$WORKTREE_ABS_PATH` |

**If you forget to use the worktree path, the pre-tool-use hook will BLOCK the tool call** and tell you the correct path to use. This is your safety net.

**Self-check before EVERY file operation:** "Does this path start with `$WORKTREE_ABS_PATH`?" If not, STOP and fix it.

**Note:** When using a worktree, the branch is already `issue-<num>-<title>`. Skip the "Create Branch" step in the workflows below.

Continue to **Step 1: Detect Issue Type** below.

---

## Branch Protection Check

**CRITICAL:** Before starting any work, verify you will NOT commit to main/master.

This workflow creates feature branches (`fix/` or `feat/`). If you are currently on `main`, `master`, or the default branch:
- **If worktree was created**: You should already be on the `issue-<num>-<title>` branch
- **If working in current directory**: A branch will be created in Step 3 (Bug) or Step 4 (Feature)

**NEVER commit directly to main/master.** Always ensure a feature branch exists before making any code changes.

---

## Step 1: Detect Issue Type

Analyze the issue to determine if it's a **bug fix** or **new feature**:

**Check labels first** (most reliable):
- Bug indicators: `bug`, `fix`, `defect`, `error`, `regression`, `crash`
- Feature indicators: `enhancement`, `feature`, `feat`, `new`, `improvement`, `request`

**If no clear labels, analyze title and body:**
- Bug patterns: "fix", "broken", "error", "fail", "crash", "doesn't work", "issue with", "problem", "bug", "regression", "incorrect"
- Feature patterns: "add", "implement", "create", "new", "support", "enable", "allow", "introduce", "enhance"

**If still uncertain**, ask the user via `AskUserQuestion`: "I couldn't determine if this is a bug fix or new feature. Which workflow should I follow?" with options **Bug Fix** / **New Feature**.

---

## Implementation Workflow

### Subagent-Orchestrated (default — when `NO_AGENTS=false`)

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/start-issue/orchestrated-workflow.md` for the full 12-step procedure: duplicate check (bugs only), branch creation, Explore subagent dispatch, design approach (features only), task decomposition + parallel-dispatch decision, Implementer subagent dispatch (parallel or sequential), spec-compliance review (opus), quality review (sonnet), verify (build/test/lint), Step 9.5 coverage gate, security review, submit (PR template detection + creation), watch CI.

### Manual (`--no-agents` fallback)

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/start-issue/manual-workflow.md` for the single-session bug and feature flows. Both follow the same shape: explore/design → TDD red (IRON LAW: no implementation code before failing tests) → green → verify → coverage → security → submit → watch CI.

---

## Verification Gate (HARD — applies before ANY completion signal)

Before outputting `<done>COMPLETE</done>`, every claim MUST have FRESH evidence from THIS session — actual command output, not narrative:

- **"Tests pass"** → `go test` output with "ok" lines, zero failures
- **"Build succeeds"** → `go build ./...` exit 0
- **"Lint clean"** → `golangci-lint run` output (skip if not installed)
- **"CI passes"** → `gh pr checks` with all checks green

**Red-flag language check** — if you are about to write "should work" / "should be fine" / "probably" / "likely" / "I believe this fixes…" / "I think this resolves…" / "Done!" / "Complete!" without preceding command output proving it, STOP and run verification instead.

**Do NOT commit, push, or create a PR without fresh verification evidence.**

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:**

1. Code changes implemented and address the issue
2. Tests written and ALL PASS (`go test ./...` or equivalent) — with output shown above
3. Coverage verified or skipped (per `--skip-coverage` flag)
4. Linting passes (`golangci-lint run` or equivalent, if installed) — with output shown above
5. Changes committed with a proper commit message
6. Changes pushed to the remote branch
7. PR created and the PR URL displayed
8. CI checks pass (`gh pr checks` shows all green) — with output shown above

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, the issue will not be properly resolved.

**Safety note:** If you've iterated 15+ times without success, document what's blocking and ask the user.

Use extended thinking for complex analysis.

## Further Reading

- `${CLAUDE_PLUGIN_ROOT}/lib/start-issue/worktree-create.md` — full worktree creation procedure (env-file copy, state-file registration)
- `${CLAUDE_PLUGIN_ROOT}/lib/start-issue/orchestrated-workflow.md` — 12-step subagent-orchestrated flow (Explore → Implementer → spec/quality review → verify → coverage → security → submit → CI)
- `${CLAUDE_PLUGIN_ROOT}/lib/start-issue/manual-workflow.md` — single-session bug + feature flows for `--no-agents`
