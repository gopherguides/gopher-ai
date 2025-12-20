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
4. For bugs: Check duplicates → TDD workflow → `fix/` branch
5. For features: Plan approach → Implement → `feat/` branch
6. Write tests, verify, and create PR

Ask the user: "What issue number would you like to work on?"

---

**If `$ARGUMENTS` is provided:**

## Context

- Issue details: !`gh issue view $ARGUMENTS --json title,state,body,labels,comments 2>/dev/null || echo "Issue not found"`
- Current branch: !`git branch --show-current`
- Default branch: !`git remote show origin | grep 'HEAD branch' | sed 's/.*: //'`
- Repository name: !`basename $(git rev-parse --show-toplevel)`
- Existing worktrees: !`git worktree list`

---

## Step 0: Worktree Setup (Optional)

Ask the user if they want to work in an isolated worktree:

"Would you like to create a worktree for isolated work on this issue?"

| Option | Description |
|--------|-------------|
| Yes, create worktree | Create isolated worktree and switch to it |
| No, work in current directory | Stay here and create a branch |

**If user chooses worktree:**

**CRITICAL: When executing bash commands below, use backticks (\`) for command substitution, NOT $(). Claude Code has a bug that mangles $() syntax.**

1. **Capture source directory first**
   ```bash
   SOURCE_DIR=`pwd`
   ```

2. **Create worktree directory name**
   ```bash
   REPO_NAME=`basename \`git rev-parse --show-toplevel\``
   ISSUE_TITLE=`gh issue view $ARGUMENTS --json title --jq '.title' | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//'`
   WORKTREE_NAME="${REPO_NAME}-issue-$ARGUMENTS-$ISSUE_TITLE"
   WORKTREE_PATH="../$WORKTREE_NAME"
   BRANCH_NAME="issue-$ARGUMENTS-$ISSUE_TITLE"
   ```

3. **Fetch and create worktree**
   ```bash
   DEFAULT_BRANCH=`git remote show origin | grep 'HEAD branch' | sed 's/.*: //'`
   git fetch origin "$DEFAULT_BRANCH"
   git branch -D "$BRANCH_NAME" 2>/dev/null || true
   git worktree add "$WORKTREE_PATH" "origin/$DEFAULT_BRANCH"
   cd "$WORKTREE_PATH" && git checkout -b "$BRANCH_NAME"
   ```

4. **Copy LLM config directories**
   ```bash
   for dir in .claude .codex .gemini .cursor; do
     if [ -d "$SOURCE_DIR/$dir" ]; then
       cp -r "$SOURCE_DIR/$dir" "$WORKTREE_PATH/"
     fi
   done
   ```

5. **Check for environment files** and ask user before copying:
   - If `.env` or `.envrc` exist, ask: "Found environment files. Copy them? (They may contain secrets)"
   - If user confirms, copy them

6. **Inform user**: "Created worktree at $WORKTREE_PATH. Continuing with issue workflow..."

**Note:** When using a worktree, the branch is already created as `issue-<num>-<title>`. Skip the "Create Branch" step in the workflows below.

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
| Bug Fix | TDD approach: write failing test first, then fix |
| New Feature | Implementation approach: build feature, then add tests |

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
gh issue comment $ARGUMENTS --body "Potentially related to #NNN - investigating"
```

### 2. Explore Root Cause

When searching for root cause:
- **Start with error text**: Grep for exact error message first
- **Limit file reads**: Read max 3 files before forming hypothesis
- **Use targeted searches**: Grep for function names, not broad patterns

### 3. Create Branch (skip if worktree was created)

```bash
git checkout -b fix/$ARGUMENTS-<short-desc>
```

### 4. TDD: Write Failing Test (Red)

Write a test that reproduces the bug and **fails**. This proves the bug exists and will verify the fix.

### 5. TDD: Implement Fix (Green)

Implement the **minimal fix** to make the test pass. Avoid scope creep.

### 6. Verify

Run the full test suite, linting, and type checking.

### 7. Submit

Commit, push, and create a PR referencing the issue.

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

```bash
git checkout -b feat/$ARGUMENTS-<short-desc>
```

### 5. Implement Feature

Build the feature following existing code patterns and conventions.

### 6. Write Tests

Write comprehensive tests covering:
- Happy path
- Edge cases
- Error conditions

### 7. Verify

Run the full test suite, linting, and type checking.

### 8. Submit

Commit, push, and create a PR referencing the issue.

---

Use extended thinking for complex analysis.
