---
name: create-pr
description: "Create a pull request using the repo PR template. Use when the user wants to open or submit a PR without immediately merging it. SKIP for end-to-end ship flows; use `ship` instead."
---

# Create PR

Create a pull request following the repo's PR template and conventions.

Before requesting decisions, read
`${CLAUDE_PLUGIN_ROOT}/lib/driver-interaction.md` and follow its
cross-platform capability-binding rules.

Read `${CLAUDE_PLUGIN_ROOT}/lib/decision-gates.md` before resolving template
selection.

## Usage

```
$go-workflow:create-pr
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

If the current branch is `main`, `master`, or matches the default branch:

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=default-branch
```

Stop without pushing or creating a PR.

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

If a template directory exists, resolve a **driver-resolvable gate**. Prefer an
explicit repository configuration or the template whose name and required
sections match the change type. Otherwise choose the general-purpose template,
or the first lexical template when all candidates are equally general. State
`Decision`, `Evidence`, and `Rationale`; do not request input.

### Step 5: Build PR Body

PR titles, bodies, and test-plan entries describe modules, contracts, and
observable behavior, not file paths, line numbers, or current internal layout.
Acceptance criteria are stated as behaviors a reviewer can verify.

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
- Arguments passed to this skill

Include `Fixes #<number>` or `Closes #<number>` in the PR body.

### Step 7: Determine PR Title

- Use conventional commit format: `<type>(<scope>): <subject>`
- Keep under 70 characters
- Derive from the commits and changes

### Step 8: Reuse or Create PR

Check for an open pull request associated with the current branch before
attempting to create one:

```bash
EXISTING_PR=$(gh pr view \
  --json number,url,state,headRefName,baseRefName \
  --jq 'select(.state == "OPEN") | [.number, .url, .headRefName, .baseRefName] | @tsv' \
  2>/dev/null || true)

if [ -n "$EXISTING_PR" ]; then
  IFS=$'\t' read -r PR_NUMBER PR_URL PR_HEAD PR_BASE <<< "$EXISTING_PR"

  if [ "$PR_HEAD" != "$CURRENT_BRANCH" ] || [ "$PR_BASE" != "$DEFAULT_BRANCH" ]; then
    echo "WORKFLOW_RESULT=INCOMPLETE"
    echo "WORKFLOW_REASON=existing-pr-mismatch"
    exit 1
  fi

  echo "Reusing pull request #$PR_NUMBER: $PR_URL"
else
  gh pr create --title "<title>" --body "<body>"
fi
```

### Step 9: Report

Display the PR URL so the user can review it.
