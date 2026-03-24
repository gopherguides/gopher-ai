---
argument-hint: "<issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
description: "Start working on a GitHub issue (auto-detects bug vs feature)"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion", "EnterPlanMode", "Agent"]
---

# Start Issue

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command starts work on a GitHub issue, automatically detecting whether it's a bug fix or new feature and following the appropriate workflow.

**Usage:** `/start-issue <issue-number> [--skip-coverage] [--coverage-threshold <n>]`

**Example:** `/start-issue 123` or `/start-issue 123 --coverage-threshold 80`

**Options:**
- `--skip-coverage`: Skip coverage verification after implementation
- `--coverage-threshold <n>`: Override default 60% coverage threshold
- `--no-agents`: Use single-session workflow instead of subagent dispatch (for small/simple issues)

**Workflow:**

1. Fetch issue details, labels, and comments
2. Optionally create a git worktree for isolated work
3. Auto-detect issue type (bug vs feature)
4. Create `fix/` or `feat/` branch (or use worktree branch)
5. For bugs: Check duplicates → TDD red-green → verify → **coverage check** → security review
6. For features: Plan approach → TDD red-green → verify → **coverage check** → security review
7. Commit, push, and create PR

Ask the user: "What issue number would you like to work on?"

---

**If `$ARGUMENTS` is provided:**

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

Initialize persistent loop to ensure work continues until complete (uses `$ISSUE_NUM`, not raw `$ARGUMENTS`):
!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else ISSUE_NUM=$(echo "$ARGUMENTS" | sed 's/--skip-coverage//g; s/--coverage-threshold *[0-9]*//g; s/--no-agents//g' | tr -d ' '); "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "start-issue-$ISSUE_NUM" "COMPLETE" "" "" '{}'; fi`

## Context

- Issue details: !`ISSUE_NUM=$(echo "$ARGUMENTS" | sed 's/--skip-coverage//g; s/--coverage-threshold *[0-9]*//g' | tr -d ' '); gh issue view "$ISSUE_NUM" --json title,state,body,labels,comments --jq '.' 2>/dev/null || echo "Issue not found"`
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

**If `IN_WORKTREE=true`:** Skip the worktree question entirely. You are already in an isolated worktree. Proceed directly to "Plan Mode Check" (the "No, work in current directory" path). Display:

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

## If user chose "Yes, create worktree":

**CRITICAL: When executing bash commands below, use backticks (\`) for command substitution, NOT $(). Claude Code has a bug that mangles $() syntax.**

**Create the worktree NOW, before entering plan mode.** This ensures the worktree path is a concrete, established fact when the plan is written.

1. **Capture source directory first**
   ```bash
   SOURCE_DIR=`pwd`
   ```

2. **Create worktree directory name**
   ```bash
   REPO_NAME=`basename \`git rev-parse --show-toplevel\``
   ISSUE_TITLE=`gh issue view "$ISSUE_NUM" --json title --jq '.title' | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//'`
   WORKTREE_NAME="${REPO_NAME}-issue-$ISSUE_NUM-$ISSUE_TITLE"
   WORKTREE_PATH="../$WORKTREE_NAME"
   BRANCH_NAME="issue-$ISSUE_NUM-$ISSUE_TITLE"
   ```

3. **Fetch and create worktree**
   ```bash
   DEFAULT_BRANCH=`git remote show origin | grep 'HEAD branch' | sed 's/.*: //' | tr -cd '[:alnum:]-._/'`
   git fetch origin "$DEFAULT_BRANCH"
   git branch -D "$BRANCH_NAME" 2>/dev/null || true
   git worktree add "$WORKTREE_PATH" "origin/$DEFAULT_BRANCH"
   cd "$WORKTREE_PATH" && git checkout -b "$BRANCH_NAME"
   ```

4. **Search for environment files** (recursive, excludes node_modules/.git/vendor)
   ```bash
   ENV_FILES=`find "$SOURCE_DIR" \( -name "node_modules" -o -name ".git" -o -name "vendor" \) -prune -o \
     \( -name ".env" -o -name ".env.local" -o -name ".envrc" \) -type f -print 2>/dev/null | \
     sed "s|^$SOURCE_DIR/||" | grep -v "^-" | sort`
   if [ -n "$ENV_FILES" ]; then
     echo "Found env files:"
     echo "$ENV_FILES"
   fi
   ```

   **If environment files found**, list them and ask user: "Found environment files (may contain secrets). Copy them to worktree?"

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

5. **Capture absolute worktree path**

   ```bash
   WORKTREE_ABS_PATH=`cd "$WORKTREE_PATH" && pwd`
   echo "Worktree absolute path: $WORKTREE_ABS_PATH"
   ls "$WORKTREE_ABS_PATH"
   ```

   **Save this absolute path.** You will use it for EVERY tool call from this point forward.

6. **Register worktree state** (enables hook-based path enforcement)

   ```bash
   REPO_ROOT=`git rev-parse --show-toplevel`
   "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" save "$WORKTREE_ABS_PATH" "$REPO_ROOT" "$ISSUE_NUM"
   ```

   This saves the worktree path so the pre-tool-use hook will **block** any tool call that accidentally targets the original repo instead of the worktree.

7. **Inform user**: "Created worktree at `$WORKTREE_ABS_PATH`. All work will happen there."

---

## Plan Mode Check (AFTER worktree is established)

**Now** call `EnterPlanMode` to create a plan for the implementation.

If you are NOT currently in plan mode (no "Plan mode is active" in your system context), call the `EnterPlanMode` tool now.

**CRITICAL: When writing your plan, you MUST include these facts at the top of the plan file:**

If a worktree was created:
```
## Working Directory
All work MUST happen in: <the concrete WORKTREE_ABS_PATH value>
Original repo (DO NOT USE): <the SOURCE_DIR value>
The pre-tool-use hook will BLOCK any tool call targeting the original repo.
```

If no worktree (working in current directory):
```
## Working Directory
Working in current directory. A feature branch will be created.
```

If you ARE already in plan mode, continue with the workflow below.

---

## ⚠️ MANDATORY: All Work Happens in the Worktree ⚠️

**Your shell CWD does NOT persist between Bash calls. Claude Code resets it every time.** You CANNOT just `cd` once — it will be forgotten. You must actively use the worktree path in EVERY tool call.

**Rules for EVERY tool call from this point forward:**

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

---

**Note:** When using a worktree, the branch is already created as `issue-<num>-<title>`. Skip the "Create Branch" step in the workflows below.

Continue to **Step 1: Detect Issue Type** below.

---

## If user chose "No, work in current directory":

Continue to **Step 1: Detect Issue Type** below. You will create a branch in the appropriate workflow step.

**Now** call `EnterPlanMode` to create a plan for the implementation (if not already in plan mode).

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

**If still uncertain**, ask the user:

"I couldn't determine if this is a bug fix or new feature. Which workflow should I follow?"

| Option | Description |
|--------|-------------|
| Bug Fix | TDD approach: write failing test (red), then fix (green) |
| New Feature | TDD approach: write failing tests (red), then implement (green) |

---

## Subagent-Orchestrated Workflow (Default)

**If `NO_AGENTS` is `true`, skip to the "Manual Workflow (Fallback)" section below.**

This workflow uses focused subagents for exploration, implementation, and review. The orchestrator (this session) retains all control flow, verification gates, and external interactions.

### Step 1: Check for Duplicates (Bug Fix Only)

If issue is a **bug**, search for related issues:

```bash
gh issue list --state all --limit 50 --search "<key terms from title/body>"
```

**If potential duplicates found**, present them and ask user how to proceed (Continue / Skip / Link).

### Step 2: Create Branch (skip if worktree was created)

**REQUIRED unless using a worktree.** Never commit to main/master.

For bugs:
```bash
git checkout -b "fix/$ISSUE_NUM-<short-desc>"
```

For features:
```bash
git checkout -b "feat/$ISSUE_NUM-<short-desc>"
```

Verify you are on the new branch before proceeding:
```bash
git branch --show-current
```

### Step 3: Explore Phase

Read `${CLAUDE_PLUGIN_ROOT}/agents/explore-prompt.md` and fill in the template variables:
- `{ISSUE_TITLE}` — from issue context
- `{ISSUE_BODY}` — from issue context (body + comments)
- `{ISSUE_TYPE}` — "bug" or "feature"
- `{WORKTREE_PATH}` — absolute path to working directory
- `{REPO_CONVENTIONS}` — from CLAUDE.md or AGENTS.md if present in the repo

Dispatch the Explore subagent:
```
Agent(prompt=<filled template>, model=sonnet, subagent_type=Explore)
```

Store the results: RELEVANT_FILES, PATTERNS, ROOT_CAUSE (bugs) or INTEGRATION_POINTS (features), PROPOSED_CHANGES, TASK_DECOMPOSITION.

### Step 4: Design Approach (Features Only)

**HARD GATE: Do NOT start implementation until the user has confirmed the approach.**

Using the Explore results, propose 2-3 approaches with concrete trade-offs:
- What it changes (files, types, APIs)
- Trade-offs (complexity vs simplicity, performance vs maintainability)
- Why you would or wouldn't recommend it

**For trivial features** (single function, obvious implementation): "I'll implement X using Y pattern — proceeding unless you object" with a 5-second pause.

**For non-trivial features** (new package, API changes, data model changes): present approaches and WAIT for explicit user approval via AskUserQuestion.

### Step 5: Task Decomposition

Using the Explore results and approved approach:

**For bugs:** Typically 1 task — fix the root cause identified in the Explore phase.

**For features:** Decompose into N tasks where each task:
- Has a clear description of what to implement
- Lists TARGET_FILES (files to create/modify) — must be disjoint across tasks for parallel dispatch
- Lists TEST_FILES
- Lists CONTEXT_FILES (read-only reference files)
- Notes dependencies on other tasks (empty = independent)

**Parallel dispatch decision:** If ALL tasks have disjoint TARGET_FILES and no dependencies, they can run in parallel. Otherwise, sequential.

### Step 6: Implementation Phase

For each task, read `${CLAUDE_PLUGIN_ROOT}/agents/implementer-prompt.md` and fill in the template variables:
- `{TASK_DESCRIPTION}` — from task decomposition
- `{TARGET_FILES}` — files this agent may create/modify
- `{TEST_FILES}` — test file(s) for this task
- `{WORKTREE_PATH}` — absolute path to working directory
- `{PATTERNS}` — from Explore results
- `{CONTEXT_FILES}` — read-only reference files
- `{ISSUE_TYPE}` — "bug" or "feature"

**Dispatch:**
- **Parallel** (independent tasks with disjoint files):
  ```
  For each task: Agent(prompt=<filled>, model=sonnet, run_in_background=true)
  Wait for all to complete. Collect results.
  ```
- **Sequential** (dependent tasks or overlapping files):
  ```
  For each task in order: Agent(prompt=<filled>, model=sonnet)
  ```

**Handle subagent status:**

| Status | Action |
|--------|--------|
| DONE | Continue to next task or review phase |
| DONE_WITH_CONCERNS | Evaluate concerns — fix correctness issues before proceeding |
| NEEDS_CONTEXT | Supply the requested information, re-dispatch the implementer |
| BLOCKED | Present blockers to user via AskUserQuestion, get guidance |

### Step 7: Spec Compliance Review

After ALL implementation tasks complete, generate the diff:

```bash
git diff origin/${DEFAULT_BRANCH}...HEAD
```

Read `${CLAUDE_PLUGIN_ROOT}/agents/spec-review-prompt.md` and fill in:
- `{ISSUE_TITLE}`, `{ISSUE_BODY}`, `{ACCEPTANCE_CRITERIA}` — from issue context
- `{WORKTREE_PATH}` — working directory
- `{CHANGED_FILES}` — list of all files changed
- `{DIFF}` — the full diff

Dispatch:
```
Agent(prompt=<filled>, model=opus)
```

**If VERDICT = FAIL:**
- Address missing requirements by re-dispatching implementer subagent(s) for the gaps
- Re-run spec review (max 2 retry cycles)

**If VERDICT = PASS:** Proceed to quality review.

### Step 8: Code Quality Review

Read `${CLAUDE_PLUGIN_ROOT}/agents/quality-review-prompt.md` and fill in:
- `{WORKTREE_PATH}` — working directory
- `{CHANGED_FILES}` — list of all files changed
- `{DIFF}` — the full diff
- `{PATTERNS}` — from Explore results
- `{REPO_CONVENTIONS}` — from CLAUDE.md or AGENTS.md

Dispatch:
```
Agent(prompt=<filled>, model=sonnet)
```

**If HAS_FINDINGS:**
- Priority 0-1 (critical/high): Fix these directly, then re-run quality review (max 1 retry)
- Priority 2-3 (medium/low): Note in PR description but do not block

**If CLEAN:** Proceed to verification.

### Step 9: Verify

Run the full verification checklist. **All must pass before proceeding:**

- **Build**: `go build ./...` — confirm compilation succeeds
- **All tests**: `go test ./...` — confirm ALL tests pass
- **Lint**: `golangci-lint run` (if available) — confirm no lint issues
- **Build logs**: If a dev server is running, check its log output for errors

If any step fails, fix the issue and re-run until all green.

### Step 9.5: Coverage Verification

Read `${CLAUDE_PLUGIN_ROOT}/skills/coverage/coverage-verification.md` and follow Steps A through F with these parameters:

| Variable | Value |
|----------|-------|
| `BASE_BRANCH` | `origin/${DEFAULT_BRANCH}` (from context above) |
| `STATE_FILE` | Absolute path to `.claude/start-issue-$ISSUE_NUM.loop.local.json` (in the original repo, not the worktree) |
| `SKIP_COVERAGE` | from parsed flags (default: `false`) |
| `COVERAGE_THRESHOLD` | from parsed flags (default: `60`) |

After coverage verification completes (or is skipped), continue to Step 10.

### Step 10: Security Review

Before submitting, scan for security issues in changed files:

- **Dependency vulnerabilities**: Run `govulncheck ./...` (if available)
- **Scan changed files** for common Go security issues:
  - Hardcoded secrets or credentials
  - SQL injection (string concatenation in queries instead of parameterized)
  - Path traversal (`filepath.Join` with user input without `filepath.Clean`)
  - Unsafe `exec.Command` with unsanitized user input
  - Missing error checks on security-critical operations (crypto, auth, file permissions)
- **If changes touch auth, crypto, or data handling code**, suggest running `/codex review` with a security focus

### Step 11: Submit

Commit and push changes, then create a PR:

1. Stage and commit with a conventional commit message referencing the issue
2. Push the branch: `git push -u origin <branch>`
3. **Check for PR template** — look for a template file in these locations (in order):
   - `.github/pull_request_template.md`
   - `.github/PULL_REQUEST_TEMPLATE.md`
   - `.github/PULL_REQUEST_TEMPLATE/` (directory with multiple templates — list and ask user which to use)
   - `docs/pull_request_template.md`
   - `docs/PULL_REQUEST_TEMPLATE/` (directory with multiple templates)
   - `pull_request_template.md` (repo root)
   - `PULL_REQUEST_TEMPLATE/` (repo root directory with multiple templates)
4. **If template found**: Read the template and use its exact section structure for the PR body. Fill in every section — do not omit or skip sections. Always include `Fixes #<issue-number>` or `Closes #<issue-number>` even if the template doesn't have a dedicated section for it.
5. **If no template found**: Use this default format:
   ```
   ## Summary
   <1-3 bullet points describing what changed and why>

   Fixes #<issue-number>

   ## Test Plan
   <How the changes were tested>
   ```
6. Create the PR with heredoc formatting:
   ```bash
   gh pr create --title "<type>(<scope>): <subject>" --body "`cat <<'EOF'
   <filled-in template or default body>
   EOF
   `"
   ```

### Step 12: Watch CI

After creating the PR, watch CI and fix any failures:

1. Run: `gh pr checks --watch`
2. **If "no checks reported"**: Wait 10 seconds and retry, up to 3 times:
   ```bash
   for i in 1 2 3; do sleep 10 && gh pr checks --watch && break; done
   ```
   If still no checks after retries, verify CI workflow files exist.
3. If checks fail:
   - Get failure details: `gh pr checks --json name,state,description`
   - Analyze and fix the failing check
   - Commit and push the fix
   - Return to step 1
4. Continue only when all checks pass

---

## Manual Workflow (Fallback — `--no-agents`)

**Use this workflow when `NO_AGENTS` is `true`.** This is the single-session flow for simple issues where subagent overhead is not justified.

### Bug Fix (Manual)

1. **Check for duplicates** (same as Step 1 above)
2. **Create branch** (skip if worktree): `git checkout -b "fix/$ISSUE_NUM-<short-desc>"`
3. **Explore root cause**: grep for error text, read max 3 files, form hypothesis
4. **TDD Red — IRON LAW: No fix code before this test.** If you already wrote fix code, DELETE IT. Write a failing test. Run it. Verify it fails FOR THE RIGHT REASON. Red flag: test passes immediately = wrong test.
5. **TDD Green**: Implement minimal fix. Run test. Verify it passes.
6. **Verify**: `go build ./...` + `go test ./...` + `golangci-lint run`
7. **Coverage**: Read `${CLAUDE_PLUGIN_ROOT}/skills/coverage/coverage-verification.md`, follow Steps A-F
8. **Security review**: govulncheck, scan for secrets/injection/traversal
9. **Submit**: commit, push, create PR with template
10. **Watch CI**: `gh pr checks --watch`, fix failures

### Feature (Manual)

1. **Understand requirements**: Read issue + comments, ask clarifying questions if ambiguous
2. **Explore codebase**: Find similar implementations, patterns, integration points
3. **Design approach — HARD GATE**: Propose 2-3 approaches, get user approval before coding
4. **Create branch** (skip if worktree): `git checkout -b "feat/$ISSUE_NUM-<short-desc>"`
5. **TDD Red — IRON LAW: No implementation code before these tests.** If you already wrote code, DELETE IT. Write comprehensive tests (happy path, edge cases, errors). Each test = ONE behavior. Run them. Verify they fail FOR THE RIGHT REASONS. Red flag: test passes immediately = wrong test.
6. **TDD Green**: Implement minimal code. Run tests. Verify all pass.
7. **Verify**: `go build ./...` + `go test ./...` + `golangci-lint run`
8. **Coverage**: Read `${CLAUDE_PLUGIN_ROOT}/skills/coverage/coverage-verification.md`, follow Steps A-F
9. **Security review**: govulncheck, scan for secrets/injection/traversal
10. **Submit**: commit, push, create PR with template
11. **Watch CI**: `gh pr checks --watch`, fix failures

---

## Verification Gate (HARD — applies before ANY completion signal)

Before outputting `<done>COMPLETE</done>`, every claim MUST have FRESH evidence from THIS session:

1. **"Tests pass"** → show actual `go test` output with "ok" lines and zero failures. Not "I ran the tests earlier" — run them NOW.
2. **"Build succeeds"** → show actual `go build ./...` output with exit code 0.
3. **"Lint clean"** → show actual `golangci-lint run` output.
4. **"CI passes"** → show actual `gh pr checks` output with all checks green.

**Red-flag language check** — if you are about to write any of the following, STOP and run verification instead:
- "should work" / "should be fine"
- "probably" / "likely"
- "I believe this fixes..." / "I think this resolves..."
- "Done!" / "Complete!" without preceding command output showing proof

**Do NOT commit, push, or create a PR without fresh verification evidence.**

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. Code changes are implemented and address the issue
2. Tests are written and ALL PASS (`go test ./...` or equivalent) — with output shown above
3. Coverage verified or skipped (per `--skip-coverage` flag)
4. Linting passes (`golangci-lint run` or equivalent) — with output shown above
5. Changes are committed with a proper commit message
6. Changes are pushed to the remote branch
7. PR is created and the PR URL is displayed
8. CI checks pass (`gh pr checks` shows all green) — with output shown above

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, the issue will not be properly resolved.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.

Use extended thinking for complex analysis.
