---
argument-hint: "<issue-number>"
description: "Start working on a GitHub issue (auto-detects bug vs feature)"
model: claude-opus-4-5-20251101
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion"]
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
4. For bugs: Check duplicates → TDD red-green → verify → security review → PR → `fix/` branch
5. For features: Plan approach → TDD red-green → verify → security review → PR → `feat/` branch

Ask the user: "What issue number would you like to work on?"

---

**If `$ARGUMENTS` is provided:**

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

## **HARD STOP** - Worktree Decision Required

**You MUST use AskUserQuestion NOW before doing anything else.**

Do not:
- Analyze the issue beyond the context already gathered
- Launch Task or Explore agents
- Enter plan mode
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

5. **Inform user**: "Created worktree at $WORKTREE_PATH. Continuing with issue workflow..."

6. **CRITICAL: Change working directory to worktree**

   Your session started in `$SOURCE_DIR`. **ALL subsequent work MUST happen in `$WORKTREE_PATH`.**

   Run this now to change and verify directory:
   ```bash
   cd "$WORKTREE_PATH" && pwd
   ```

   **For every Bash command in this session**, prefix with `cd "$WORKTREE_PATH" &&` to ensure you're working in the worktree.

   **WARNING:** If you edit files or run commands without changing to the worktree first, you will modify the wrong codebase.

**Note:** When using a worktree, the branch is already created as `issue-<num>-<title>`. Skip the "Create Branch" step in the workflows below.

Continue to **Step 1: Detect Issue Type** below.

---

## If user chose "No, work in current directory":

Continue to **Step 1: Detect Issue Type** below. You will create a branch in the appropriate workflow step.

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
- **Build logs**: Check for auto-build/dev-server errors if running:
  - Air (Go): check `./tmp/air-combined.log` or path in `.air.toml`
  - Node/Vite/Webpack: check terminal/build output
  - Other: scan for common log locations

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

Commit, push, and create a PR referencing the issue.

### 10. Watch CI

After creating the PR, watch CI and fix any failures:

1. Run: `gh pr checks --watch`
2. If checks fail:
   - Get failure details: `gh pr checks --json name,state,description`
   - Analyze and fix the failing check (test, lint, build)
   - Commit and push the fix
   - Return to step 1
3. Continue only when all checks pass

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
- **Build logs**: Check for auto-build/dev-server errors if running:
  - Air (Go): check `./tmp/air-combined.log` or path in `.air.toml`
  - Node/Vite/Webpack: check terminal/build output
  - Other: scan for common log locations

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

Commit, push, and create a PR referencing the issue.

### 11. Watch CI

After creating the PR, watch CI and fix any failures:

1. Run: `gh pr checks --watch`
2. If checks fail:
   - Get failure details: `gh pr checks --json name,state,description`
   - Analyze and fix the failing check (test, lint, build)
   - Commit and push the fix
   - Return to step 1
3. Continue only when all checks pass

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
