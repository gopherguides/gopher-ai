# Review-Deep Diff Planning and Static Analysis

Loaded by `SKILL.md` Steps 3-4. Execute the adaptive coverage plan and collect informational static-analysis evidence before semantic review.

## Step 3: Generate Diff and Coverage Plan

Based on detected scope:

- **Changes vs base branch** (default when PR detected): `git diff ${BASE_BRANCH}...HEAD`
- **Uncommitted changes** (no PR + uncommitted changes exist): `git diff HEAD` plus untracked files via `git ls-files --others --exclude-standard`
- **Explicit `PR_ARG`:** always use changes vs base branch

```bash
DIFF=$(git diff "${BASE_BRANCH}...HEAD")
REVIEW_BASE="$BASE_BRANCH"
REVIEW_BACKEND=agent
REVIEW_CONCURRENCY=auto
```

Read `../../lib/review-planning.md`, run the shared planner, display its coverage
plan, and follow it through the final coordinated pass. Do not interrupt solely
because of raw diff size. Preserve `SCOPE_HINT` as review emphasis.

## Step 4: Static Analysis

If a Go project is detected (`go.mod` exists):

```bash
CHANGED=$(git diff --name-only "${BASE_BRANCH}...HEAD" | grep '\.go$')
if [ -n "$CHANGED" ]; then
  echo "$CHANGED" | xargs -I{} dirname {} | sort -u | xargs go vet 2>&1 || true
  echo "$CHANGED" | xargs -I{} dirname {} | sort -u | xargs staticcheck 2>&1 || true
  echo "$CHANGED" | xargs -I{} dirname {} | sort -u | xargs go test -race -count=1 2>&1 || true
fi
```

Static-analysis failures are informational — they feed into the review, not block it.

When review includes browser screenshots, read
`<PLUGIN_ROOT>/lib/screenshot-evidence.md` before capturing. Initialize the
manifest and record every inspected route/capture, including failures, for the
Step 7 report. This does not add browser testing to reviews without visual work.
