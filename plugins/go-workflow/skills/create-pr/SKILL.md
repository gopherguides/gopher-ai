---
name: create-pr
description: Create a pull request following the repo's PR template. Trigger on 'create PR', 'open PR', 'submit PR'.

---

# Create PR

Create a pull request following the repo's PR template and conventions.

## Usage

```
$create-pr
```

## Steps

### Step 1: Gather Context

```bash
CURRENT_BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //')
git log "${DEFAULT_BRANCH}..HEAD" --oneline
git diff "${DEFAULT_BRANCH}..HEAD" --stat
```

### Step 2: Branch Protection

If the current branch is `main`, `master`, or matches the default branch, stop and inform the user — do not create a PR from the default branch.

### Step 3: Push Branch

Ensure the branch is pushed to the remote:

```bash
git push -u origin "$CURRENT_BRANCH"
```

### Step 4: Find PR Template

Check for a PR template in these locations (in order):

```bash
cat .github/pull_request_template.md 2>/dev/null || \
cat .github/PULL_REQUEST_TEMPLATE.md 2>/dev/null || \
cat docs/pull_request_template.md 2>/dev/null || \
cat pull_request_template.md 2>/dev/null || \
echo "NO_TEMPLATE"
```

If a template directory exists (`.github/PULL_REQUEST_TEMPLATE/`), list templates and ask the user which to use.

### Step 5: Build PR Body

**If a template was found**: Use its exact section structure. Fill in every section based on the commits and diff. Do not omit or skip sections.

**If no template**: Use this default format:

```markdown
## Summary
- <1-3 bullet points describing what changed and why>

## Test Plan
- <How the changes were tested>
```

### Step 6: Link Issues

Look for issue references in:
- Branch name (e.g., `issue-42-`, `fix/42-`)
- Commit messages

Include `Fixes #<number>` or `Closes #<number>` in the PR body.

### Step 7: Determine PR Title

- Use conventional commit format: `<type>(<scope>): <subject>`
- Keep under 70 characters
- Derive from the commits and changes

### Step 8: Create PR

```bash
gh pr create --title "<title>" --body "<body>"
```

### Step 9: Report

Display the PR URL so the user can review it.
