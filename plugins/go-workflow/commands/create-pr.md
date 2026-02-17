---
description: "Create a PR following the repo's PR template"
allowed-tools: ["Read", "Bash(git:*)", "Bash(gh:*)", "Bash(cat:*)", "Bash(ls:*)", "Glob", "AskUserQuestion"]
---

# Create Pull Request

## Context

- Current branch: !`git branch --show-current`
- Default branch: !`git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' | grep . || echo "main"`
- Commits on this branch: !`git log $(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' | grep . || echo "main")..HEAD --oneline 2>/dev/null || echo "No commits found"`
- Diff stat: !`git diff $(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' | grep . || echo "main")..HEAD --stat 2>/dev/null || echo "No diff"`
- PR template: !`cat .github/pull_request_template.md 2>/dev/null || cat .github/PULL_REQUEST_TEMPLATE.md 2>/dev/null || cat docs/pull_request_template.md 2>/dev/null || cat pull_request_template.md 2>/dev/null || ls .github/PULL_REQUEST_TEMPLATE/*.md 2>/dev/null || ls docs/PULL_REQUEST_TEMPLATE/*.md 2>/dev/null || ls PULL_REQUEST_TEMPLATE/*.md 2>/dev/null || echo "NO_TEMPLATE_FOUND"`
- Multiple templates directory: !`ls .github/PULL_REQUEST_TEMPLATE/ 2>/dev/null || ls docs/PULL_REQUEST_TEMPLATE/ 2>/dev/null || ls PULL_REQUEST_TEMPLATE/ 2>/dev/null || echo "NO_TEMPLATE_DIR"`

## Branch Protection

**CRITICAL:** If the current branch is `main`, `master`, or matches the default branch:
1. **STOP** — do not create a PR from the default branch
2. Inform the user and ask how to proceed

## Instructions

### Step 1: Verify Push State

Ensure the branch is pushed to the remote:
```bash
git push -u origin $(git branch --show-current)
```

### Step 2: Determine PR Body

**If multiple templates directory exists** (the "Multiple templates directory" context above does NOT say "NO_TEMPLATE_DIR"):
- List the available templates and ask the user which one to use via AskUserQuestion
- Read the selected template and use its structure

**If a PR template was found** (the "PR template" context above does NOT say "NO_TEMPLATE_FOUND"):
- Use the template's exact section structure for the PR body
- Fill in **every** section — do not omit or skip any sections
- Replace placeholder text with actual content based on the commits and diff
- If a section asks for something not applicable, write "N/A" with a brief reason

**If no PR template exists**:
- Use this default format:
  ```
  ## Summary
  <1-3 bullet points describing what changed and why>

  ## Test Plan
  <How the changes were tested>
  ```

### Step 3: Determine PR Title

- Use conventional commit format: `<type>(<scope>): <subject>`
- Keep under 70 characters
- Derive from the commits and changes, not from the template

### Step 4: Link Issues

- Look at the branch name for issue references (e.g., `issue-42`, `fix/42`)
- Check commit messages for issue references
- If an issue number is found, include `Fixes #<number>` or `Closes #<number>` in the PR body
- If the argument to this command contains an issue number, use that

### Step 5: Create the PR

Create the PR using heredoc for body formatting:
```bash
gh pr create --title "<title>" --body "`cat <<'EOF'
<filled-in template or default body>
EOF
`"
```

### Step 6: Report

Output the PR URL so the user can review it.
