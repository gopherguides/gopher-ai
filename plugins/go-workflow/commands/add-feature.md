---
argument-hint: "<issue-number>"
description: "Implement feature from issue, add tests, push PR"
model: claude-opus-4-5-20251101
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion"]
---

# Add Feature

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command implements a feature from a GitHub issue, including tests and a PR.

**Usage:** `/add-feature <issue-number>`

**Example:** `/add-feature 123`

**Workflow:**

1. Fetch issue details and acceptance criteria
2. Explore codebase for relevant patterns
3. Plan implementation approach
4. Create feature branch (`feat/<issue>-<desc>`)
5. Implement the feature
6. Write comprehensive tests
7. Verify (tests, linting, type checking)
8. Create PR referencing the issue

Ask the user: "What issue number would you like to implement?"

---

**If `$ARGUMENTS` is provided:**

Implement feature from GitHub issue #$ARGUMENTS. Follow these steps:

1. **Understand**: Use `gh issue view $ARGUMENTS` to get issue details, acceptance criteria, and comments
2. **Explore**: Search the codebase for relevant patterns, similar implementations, and integration points
3. **Plan**: Outline the implementation approach and identify files to create/modify
4. **Branch**: Create a feature branch (`feat/$ARGUMENTS-<short-desc>`)
5. **Implement**: Build the feature following existing code patterns and conventions
6. **Test**: Write comprehensive tests covering the new functionality
7. **Verify**: Run the full test suite, linting, and type checking
8. **Submit**: Commit, push, and create a PR referencing the issue

Use extended thinking for complex analysis.
