---
argument-hint: "<issue-number>"
description: "Diagnose issue, create failing test, fix, push PR"
model: claude-opus-4-5-20251101
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion"]
---

# Fix Issue

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command diagnoses and fixes a bug from a GitHub issue using TDD.

**Usage:** `/fix-issue <issue-number>`

**Example:** `/fix-issue 456`

**Workflow:**

1. Check for duplicate/related issues
2. Fetch issue details and reproduction steps
3. Explore codebase to identify root cause
4. Create fix branch (`fix/<issue>-<desc>`)
5. Write failing test (Red)
6. Implement minimal fix (Green)
7. Verify (tests, linting, type checking)
8. Create PR referencing the issue

Ask the user: "What issue number would you like to fix?"

---

**If `$ARGUMENTS` is provided:**

## Context

- Issue details: !`gh issue view $ARGUMENTS --json title,state,body,labels 2>/dev/null || echo "Issue not found"`
- Current branch: !`git branch --show-current`
- Default branch: !`git remote show origin | grep 'HEAD branch' | sed 's/.*: //'`
- Recent related issues: !`gh issue list --state all --limit 10 --search "$(gh issue view $ARGUMENTS --json title --jq '.title' 2>/dev/null | head -c 50)" 2>/dev/null || echo ""`

Analyze and fix GitHub issue #$ARGUMENTS. Follow these steps:

1. **Check for Duplicates**: Search for related issues before starting work

   ```bash
   gh issue view $ARGUMENTS --json title,body,labels
   ```

   Extract key terms from the issue title and body (error messages, component names, symptoms).
   Search all issues:

   ```bash
   gh issue list --state all --limit 50 --search "<key terms>"
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

2. **Understand**: Use `gh issue view $ARGUMENTS` to get issue details and comments

3. **Explore Efficiently**

   When searching for root cause:

   - **Start with error text**: Grep for exact error message first
   - **Limit file reads**: Read max 3 files before forming hypothesis
   - **Use targeted searches**: Grep for function names, not broad patterns
   - **Summarize before diving**: List matching files, then read most relevant

   Avoid loading entire directories or many files into context.

4. **Branch**: Create a fix branch (`fix/$ARGUMENTS-<short-desc>`)
5. **Test (Red)**: Write a test that reproduces the bug and fails
6. **Fix (Green)**: Implement the minimal fix to make the test pass
7. **Verify**: Run the full test suite, linting, and type checking
8. **Submit**: Commit, push, and create a PR referencing the issue

Use extended thinking for complex analysis.
