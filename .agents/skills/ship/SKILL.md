---
name: ship
description: |
  WHEN: User wants to ship a PR end-to-end: verify, push, create PR, watch CI, and optionally
  merge. Trigger on "ship", "ship it", "ship this PR", "push and merge", or $ship invocation.
  WHEN NOT: User only wants to commit ($commit), only create a PR ($create-pr), or only
  manage worktrees ($remove-worktree, $prune-worktree).
---

# Ship

Ship a PR: verify build/tests/lint, push, create PR, watch CI, and merge.

## Usage

```
$ship [--no-merge]
```

**Options:**
- `--no-merge`: Skip the merge step (just push and watch CI)

## Prerequisites

- GitHub CLI (`gh`) installed and authenticated
- Changes committed on a feature branch (not `main`/`master`)

## Workflow

### Phase 1: Pre-Flight Verification

All must pass before pushing:

```bash
go build ./...
go test ./...
golangci-lint run  # if available
```

If any step fails, fix the issue and re-run before continuing.

### Phase 2: Push

```bash
CURRENT_BRANCH=$(git branch --show-current)
git push -u origin "$CURRENT_BRANCH"
```

### Phase 3: Create or Find PR

Check if a PR already exists for this branch:

```bash
PR_URL=$(gh pr view --json url --jq '.url' 2>/dev/null)
```

If no PR exists, create one using the `$create-pr` workflow (or directly with `gh pr create`).

### Phase 4: Watch CI

Monitor CI checks until they all pass:

```bash
gh pr checks --watch
```

If "no checks reported", wait 10 seconds and retry up to 3 times:

```bash
for i in 1 2 3; do sleep 10 && gh pr checks --watch && break; done
```

If checks fail:
1. Get failure details: `gh pr checks --json name,state,description`
2. Analyze and fix the failing check
3. Commit and push the fix
4. Re-run `gh pr checks --watch`

### Phase 5: Merge (unless `--no-merge`)

Before merging, verify:
1. All CI checks pass
2. All required reviews are approved

```bash
gh pr merge --auto --squash
```

If merge is blocked by required reviews, inform the user and stop.

### Phase 6: Report

Display the final PR URL and merge status.

## Completion Criteria

1. Build, tests, and lint all pass
2. Changes pushed to remote
3. PR created (or existing PR found)
4. CI checks pass
5. PR merged (unless `--no-merge` was specified)
