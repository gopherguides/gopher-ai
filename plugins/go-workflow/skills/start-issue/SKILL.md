---
name: start-issue
description: "Start a GitHub issue end-to-end through PR: fetch, worktree, detect bug vs feature, implement with TDD, verify, submit."
---

# Start Issue

Full issue-to-PR workflow: fetch issue, create worktree, detect type, implement with TDD, verify, and submit PR.

## Usage

```
$start-issue <issue-number>
```

## Prerequisites

- GitHub CLI (`gh`) installed and authenticated
- Git repository with remote `origin`

## Workflow

### Step 1: Fetch Issue Details

```bash
ISSUE_NUM="<issue-number>"
gh issue view "$ISSUE_NUM" --json title,body,labels,state,comments
```

Confirm the issue exists and is open. Read the title, body, labels, and comments to understand the requirements.

### Step 2: Worktree Decision

Ask the user: "Would you like to create a worktree for isolated work on issue #$ISSUE_NUM?"

- **Yes**: Invoke the `$create-worktree` skill with the issue number, then continue working from the worktree path
- **No**: Stay in the current directory and create a branch in Step 4

If already inside a git worktree (check: `git rev-parse --git-dir` differs from `git rev-parse --git-common-dir`), skip this step entirely.

### Step 3: Detect Issue Type

Determine if this is a **bug fix** or **new feature** by checking:

1. **Labels** (most reliable):
   - Bug: `bug`, `fix`, `defect`, `error`, `regression`, `crash`
   - Feature: `enhancement`, `feature`, `feat`, `new`, `improvement`, `request`

2. **Title and body patterns**:
   - Bug: "fix", "broken", "error", "fail", "crash", "doesn't work", "regression", "incorrect"
   - Feature: "add", "implement", "create", "new", "support", "enable", "introduce", "enhance"

If uncertain, ask the user whether this is a bug fix or new feature.

### Step 4: Create Branch

Skip this step if a worktree was created (the branch already exists).

For bugs:
```bash
git checkout -b "fix/$ISSUE_NUM-<short-description>"
```

For features:
```bash
git checkout -b "feat/$ISSUE_NUM-<short-description>"
```

**Branch protection**: Never commit directly to `main` or `master`. Verify you are on the new branch before proceeding.

### Step 5: Explore the Codebase

Before writing any code:

1. Read the issue body and all comments thoroughly
2. Search for related code: files, functions, tests that are relevant
3. Identify existing patterns: test style, error handling, naming conventions, package organization
4. For bugs: form a hypothesis about the root cause
5. For features: identify integration points and similar implementations

### Step 6: Design Approach (Features Only)

Present the plan before coding. Plan approval is the gate — once the user accepts the plan, everything inside it (including migrations, schema changes, new packages) is approved. Do not re-prompt for items that were already in the approved plan.

Propose 2-3 approaches with concrete trade-offs:
- What files/types/APIs/migrations each approach changes
- Complexity vs simplicity, performance vs maintainability
- Your recommendation and why

Surface migrations and schema changes explicitly in the plan so they get approved in one shot. Do not treat migrations as a separate hard stop.

For trivial features (single function, obvious implementation), state your plan and proceed unless the user objects.

For non-trivial features (new package, API changes, data model), state the recommended plan and proceed unless the user objects. Use judgment: only wait for an explicit reply when the change is genuinely risky or you're uncertain which approach the user wants.

### Step 7: TDD Red — Write Failing Tests First

**IRON LAW: No implementation code before tests exist and fail.**

- Write tests that describe the expected behavior
- Each test should test ONE behavior
- Run the tests and verify they fail for the right reason
- If a test passes immediately, it's testing the wrong thing — fix it

For bugs:
```bash
go test -run TestNameOfFailingTest ./path/to/package/...
```

For features: write comprehensive tests covering happy path, edge cases, and error conditions.

### Step 8: TDD Green — Implement Minimal Code

- Write the minimum code needed to make all tests pass
- Do not add extra features or "nice to have" improvements
- Run tests after each change:

```bash
go test ./path/to/package/...
```

### Step 9: Verify

All must pass before proceeding:

```bash
go build ./...
go test ./...
golangci-lint run  # if available
```

If any step fails, fix the issue and re-run.

### Step 10: Security Review

Scan changed files for common issues:
- Hardcoded secrets or credentials
- SQL injection (string concatenation instead of parameterized queries)
- Path traversal (user input in `filepath.Join` without `filepath.Clean`)
- Unsafe `exec.Command` with unsanitized input
- Missing error checks on security-critical operations

### Step 11: Submit

1. Stage and commit with a conventional commit message:
   ```bash
   git add <relevant-files>
   git commit -m "<type>(<scope>): <subject>

   Fixes #$ISSUE_NUM"
   ```

2. Push the branch:
   ```bash
   git push -u origin "$(git branch --show-current)"
   ```

3. Create a PR (invoke `$create-pr` or create manually):
   ```bash
   gh pr create --title "<type>(<scope>): <subject>" --body "## Summary
   - <what changed and why>

   Fixes #$ISSUE_NUM

   ## Test Plan
   - <how changes were tested>"
   ```

### Step 12: Watch CI

```bash
gh pr checks --watch
```

If checks fail, analyze the failure, fix it, commit, push, and re-check.

## Completion Criteria

All of these must be true before the issue is considered done:

1. Code changes address the issue requirements
2. Tests are written and all pass
3. Build succeeds (`go build ./...`)
4. Lint passes (if golangci-lint is available)
5. Changes are committed and pushed
6. PR is created with issue reference
7. CI checks pass
