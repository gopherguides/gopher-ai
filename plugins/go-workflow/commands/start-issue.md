---
argument-hint: "<issue-number>"
description: "Start working on a GitHub issue (auto-detects bug vs feature)"
model: claude-opus-4-6
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion", "EnterPlanMode"]
---

# Start Issue

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command starts work on a GitHub issue, automatically detecting whether it's a bug fix or new feature and following the appropriate workflow.

**Usage:** `/start-issue <issue-number>`

**Example:** `/start-issue 123`

**Workflow:**

1. Fetch issue details, labels, and comments
2. Optionally create a git worktree for isolated work
3. Auto-detect issue type (bug vs feature)
4. Create `fix/` or `feat/` branch (or use worktree branch)
5. For bugs: Check duplicates → TDD red-green → verify → security review
6. For features: Plan approach → TDD red-green → verify → security review
7. Commit, push, and create PR

Ask the user: "What issue number would you like to work on?"

---

**If `$ARGUMENTS` is provided:**

## Clear Stale Worktree State

Clear any leftover worktree state from a prior session. This prevents the pre-tool-use hook from blocking commands in a fresh `/start-issue` invocation:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" clear 2>/dev/null || true`

## Security Validation

First, validate input is numeric (prevent command injection):
!if ! echo "$ARGUMENTS" | grep -qE '^[0-9]+$'; then echo "Error: Issue number must be numeric"; exit 1; fi

## Loop Initialization

Initialize persistent loop to ensure work continues until complete:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "start-issue-$ARGUMENTS" "COMPLETE"`

## Context

- Issue details: !`gh issue view "$ARGUMENTS" --json title,state,body,labels,comments 2>/dev/null || echo "Issue not found"`
- Current branch: !`git branch --show-current`
- Default branch: !`git remote show origin | grep 'HEAD branch' | sed 's/.*: //'`
- Repository name: !`basename $(git rev-parse --show-toplevel)`
- Existing worktrees: !`git worktree list`

---

## Worktree Detection & Decision (BEFORE Plan Mode)

**First, check if already running inside a git worktree:**

```bash
IN_WORKTREE=false
if [ -f "$(git rev-parse --show-toplevel 2>/dev/null)/.git" ]; then
  IN_WORKTREE=true
fi
```

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

- **Question:** "Would you like to create a worktree for isolated work on issue #$ARGUMENTS?"
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
   ISSUE_TITLE=`gh issue view "$ARGUMENTS" --json title --jq '.title' | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//'`
   WORKTREE_NAME="${REPO_NAME}-issue-$ARGUMENTS-$ISSUE_TITLE"
   WORKTREE_PATH="../$WORKTREE_NAME"
   BRANCH_NAME="issue-$ARGUMENTS-$ISSUE_TITLE"
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
   "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-state.sh" save "$WORKTREE_ABS_PATH" "$REPO_ROOT" "$ARGUMENTS"
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

## Bug Fix Workflow

If issue is a **bug**, follow this workflow:

### 1. Check for Duplicates

Search for related issues before starting work:

```bash
gh issue list --state all --limit 50 --search "<key terms from title/body>"
```

**If potential duplicates found**, present them:

| Issue | State | Title |
|-------|-------|-------|
| #NNN | open/closed | Issue title |

Ask user: "Potential related issues found. How would you like to proceed?"

| Option | Action |
|--------|--------|
| Continue | Proceed with fix (not a duplicate) |
| Skip | Stop - user will handle manually |
| Link | Comment linking related issues, then continue |

**If "Link" selected:**

```bash
gh issue comment "$ARGUMENTS" --body "Potentially related to #NNN - investigating"
```

### 2. Explore Root Cause

When searching for root cause:
- **Start with error text**: Grep for exact error message first
- **Limit file reads**: Read max 3 files before forming hypothesis
- **Use targeted searches**: Grep for function names, not broad patterns

### 3. Create Branch (skip if worktree was created)

**REQUIRED unless using a worktree.** Never commit to main/master.

```bash
git checkout -b "fix/$ARGUMENTS-<short-desc>"
```

Verify you are on the new branch before proceeding:
```bash
git branch --show-current
```

### 4. TDD: Write Failing Test (Red)

Write a test that reproduces the bug and **fails**. This proves the bug exists and will verify the fix.

**Run the test and confirm it fails:**

```bash
go test ./path/to/package/... -run TestName -v
```

- **If the test FAILS** → The test correctly reproduces the bug. Proceed to step 5.
- **If the test PASSES** → The test does NOT reproduce the bug. Rewrite the test until it fails, proving the bug exists.

Do not proceed until the test fails.

### 5. TDD: Implement Fix (Green)

Implement the **minimal fix** to make the test pass. Avoid scope creep.

**Run the test and confirm it passes:**

```bash
go test ./path/to/package/... -run TestName -v
```

- **If the test PASSES** → The fix works. Proceed to step 6.
- **If the test FAILS** → The fix is incomplete. Iterate until the test passes.

Do not proceed until the test passes.

### 6. Verify

Run the full verification checklist. **All must pass before proceeding:**

- **Build**: `go build ./...` — confirm compilation succeeds
- **All tests**: `go test ./...` — confirm ALL tests pass (not just the new one)
- **Lint**: `golangci-lint run` (if available) — confirm no lint issues
- **Build logs**: If a dev server is running (Air, Vite, Webpack, etc.), check its log output for errors

If any step fails, fix the issue and re-run until all green.

### 7. Security Review

Before submitting, scan for security issues in changed files:

- **Dependency vulnerabilities**: Run `govulncheck ./...` (if available)
- **Scan changed files** for common Go security issues:
  - Hardcoded secrets or credentials
  - SQL injection (string concatenation in queries instead of parameterized)
  - Path traversal (`filepath.Join` with user input without `filepath.Clean`)
  - Unsafe `exec.Command` with unsanitized user input
  - Missing error checks on security-critical operations (crypto, auth, file permissions)
- **If changes touch auth, crypto, or data handling code**, suggest running `/codex review` with a security focus

### 8. Pre-PR Code Review (Optional)

Consider running `/codex review` for an independent code review before creating the PR. This is optional but recommended for non-trivial changes. If the review surfaces issues, address them before PR creation.

### 9. Submit

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

### 10. Watch CI

After creating the PR, watch CI and fix any failures:

1. Run: `gh pr checks --watch`
2. **If "no checks reported"**: CI takes time to register after a push. **Wait 10 seconds and retry, up to 3 times**, before concluding there are no checks:
   ```bash
   for i in 1 2 3; do sleep 10 && gh pr checks --watch && break; done
   ```
   If still no checks after retries, verify the repo actually has CI workflow files:
   ```bash
   find .github/workflows -maxdepth 1 -name '*.yml' -o -name '*.yaml' 2>/dev/null | head -1 | grep -q . || echo "No workflow files found"
   ```
   Only conclude there are no CI checks if no `.yml`/`.yaml` workflow files exist. If workflow files exist, the checks are likely still propagating — wait longer and retry.
3. If checks fail:
   - Get failure details: `gh pr checks --json name,state,description`
   - Analyze and fix the failing check (test, lint, build)
   - Commit and push the fix
   - Return to step 1
4. Continue only when all checks pass

---

## Feature Workflow

If issue is a **new feature**, follow this workflow:

### 1. Understand Requirements

Review the issue body and comments for:
- Acceptance criteria
- Edge cases mentioned
- User expectations
- Technical constraints

### 2. Explore Codebase

Search for:
- Similar existing implementations
- Related components
- Coding patterns to follow
- Integration points

### 3. Plan Approach

Before coding, outline:
- Files to create/modify
- Data structures needed
- API changes (if any)
- Test coverage plan

### 4. Create Branch (skip if worktree was created)

**REQUIRED unless using a worktree.** Never commit to main/master.

```bash
git checkout -b "feat/$ARGUMENTS-<short-desc>"
```

Verify you are on the new branch before proceeding:
```bash
git branch --show-current
```

### 5. TDD: Write Tests First (Red)

Write comprehensive tests covering:
- Happy path
- Edge cases
- Error conditions

**Run the tests and confirm they fail:**

```bash
go test ./path/to/package/... -run TestName -v
```

- **If the tests FAIL** → Tests correctly define the expected behavior. Proceed to step 6.
- **If the tests PASS** → The tests are not testing new functionality. Rewrite until they fail against the current (unimplemented) code.

Do not proceed until the tests fail.

### 6. TDD: Implement Feature (Green)

Build the feature following existing code patterns and conventions. Implement the **minimal code** to make the tests pass.

**Run the tests and confirm they pass:**

```bash
go test ./path/to/package/... -run TestName -v
```

- **If the tests PASS** → The implementation satisfies the requirements. Proceed to step 7.
- **If the tests FAIL** → The implementation is incomplete. Iterate until all tests pass.

Do not proceed until the tests pass.

### 7. Verify

Run the full verification checklist. **All must pass before proceeding:**

- **Build**: `go build ./...` — confirm compilation succeeds
- **All tests**: `go test ./...` — confirm ALL tests pass (not just the new ones)
- **Lint**: `golangci-lint run` (if available) — confirm no lint issues
- **Build logs**: If a dev server is running (Air, Vite, Webpack, etc.), check its log output for errors

If any step fails, fix the issue and re-run until all green.

### 8. Security Review

Before submitting, scan for security issues in changed files:

- **Dependency vulnerabilities**: Run `govulncheck ./...` (if available)
- **Scan changed files** for common Go security issues:
  - Hardcoded secrets or credentials
  - SQL injection (string concatenation in queries instead of parameterized)
  - Path traversal (`filepath.Join` with user input without `filepath.Clean`)
  - Unsafe `exec.Command` with unsanitized user input
  - Missing error checks on security-critical operations (crypto, auth, file permissions)
- **If changes touch auth, crypto, or data handling code**, suggest running `/codex review` with a security focus

### 9. Pre-PR Code Review (Optional)

Consider running `/codex review` for an independent code review before creating the PR. This is optional but recommended for non-trivial changes. If the review surfaces issues, address them before PR creation.

### 10. Submit

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

### 11. Watch CI

After creating the PR, watch CI and fix any failures:

1. Run: `gh pr checks --watch`
2. **If "no checks reported"**: CI takes time to register after a push. **Wait 10 seconds and retry, up to 3 times**, before concluding there are no checks:
   ```bash
   for i in 1 2 3; do sleep 10 && gh pr checks --watch && break; done
   ```
   If still no checks after retries, verify the repo actually has CI workflow files:
   ```bash
   find .github/workflows -maxdepth 1 -name '*.yml' -o -name '*.yaml' 2>/dev/null | head -1 | grep -q . || echo "No workflow files found"
   ```
   Only conclude there are no CI checks if no `.yml`/`.yaml` workflow files exist. If workflow files exist, the checks are likely still propagating — wait longer and retry.
3. If checks fail:
   - Get failure details: `gh pr checks --json name,state,description`
   - Analyze and fix the failing check (test, lint, build)
   - Commit and push the fix
   - Return to step 1
4. Continue only when all checks pass

---

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. Code changes are implemented and address the issue
2. Tests are written and ALL PASS (`go test ./...` or equivalent)
3. Linting passes (`golangci-lint run` or equivalent)
4. Changes are committed with a proper commit message
5. Changes are pushed to the remote branch
6. PR is created and the PR URL is displayed
7. CI checks pass (`gh pr checks` shows all green)

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, the issue will not be properly resolved.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.

Use extended thinking for complex analysis.
