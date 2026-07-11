---
name: review-deep
description: "Deep-review a PR or branch with issue and repo context, then fix actionable findings. Use for 'review my changes', 'check this PR', or post-implementation quality/spec review requests. SKIP existing human/bot review comments that need replies/thread resolution; use address-review."
argument-hint: "[PR-number|--issue <N>] [--post] [--scope <hint>]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion", "Agent"]
---

# Deep Review: Full-Context Code Review + Fix

Performs a thorough code review with full PR/issue context, then fixes all actionable findings.
Combines the depth of spec review, quality review, and Go-specific analysis in a single pass.

## Step 0: Parse Arguments

Parse `$ARGUMENTS` to extract:

- Bare numeric value: PR number (e.g., `$review-deep 42`)
- `--issue <N>`: Use specific issue as context (no PR required)
- `--post`: Auto-post findings to PR as a comment (skip asking)
- `--scope <hint>`: Focus area for the review (e.g., "error handling", "concurrency")
- Remaining text after flags: treated as scope hint

Store as `PR_ARG`, `ISSUE_ARG`, `AUTO_POST` (default: `false`), `SCOPE_HINT`.

```bash
PR_ARG=""
ISSUE_ARG=""
AUTO_POST=false
SCOPE_HINT=""
ARGS="$ARGUMENTS"

while [ -n "$ARGS" ]; do
  case "$ARGS" in
    --issue\ *)
      ARGS="${ARGS#--issue }"
      ISSUE_ARG="${ARGS%% *}"
      ARGS="${ARGS#"$ISSUE_ARG"}"
      ARGS="${ARGS# }"
      ;;
    --post*)
      AUTO_POST=true
      ARGS="${ARGS#--post}"
      ARGS="${ARGS# }"
      ;;
    --scope\ *)
      ARGS="${ARGS#--scope }"
      SCOPE_HINT="$ARGS"
      ARGS=""
      ;;
    [0-9]*)
      PR_ARG="${ARGS%% *}"
      ARGS="${ARGS#"$PR_ARG"}"
      ARGS="${ARGS# }"
      ;;
    *)
      SCOPE_HINT="$ARGS"
      ARGS=""
      ;;
  esac
done

echo "PR_ARG=$PR_ARG ISSUE_ARG=$ISSUE_ARG AUTO_POST=$AUTO_POST SCOPE_HINT=$SCOPE_HINT"
```

## Step 1: Detect Scope & Base Branch

If `PR_ARG` is set, use it directly. Otherwise, auto-detect from the current branch using three strategies in order — fall through when each returns empty.

**Strategy 1 — current branch:**

```bash
PR_JSON=$(gh pr view --json number,title,body,state,baseRefName,closingIssuesReferences --jq '.' 2>/dev/null)
```

**Strategy 2 — match HEAD commit against open PRs:**

```bash
if [ -z "$PR_JSON" ]; then
  HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
  PR_NUM=$(gh pr list --search "$HEAD_SHA" --state open --json number --jq '.[0].number' 2>/dev/null)
  if [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ]; then
    PR_JSON=$(gh pr view "$PR_NUM" --json number,title,body,state,baseRefName,closingIssuesReferences 2>/dev/null)
  fi
fi
```

**Strategy 3 — match HEAD against any (open/closed/merged) PRs:**

```bash
if [ -z "$PR_JSON" ]; then
  HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
  PR_NUM=$(gh pr list --search "$HEAD_SHA" --state all --limit 5 --json number --jq '.[0].number' 2>/dev/null)
  if [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ]; then
    PR_JSON=$(gh pr view "$PR_NUM" --json number,title,body,state,baseRefName,closingIssuesReferences 2>/dev/null)
  fi
fi
```

**Extract PR number and base branch:**

```bash
if [ -n "$PR_JSON" ]; then
  PR_NUM=$(echo "$PR_JSON" | jq -r '.number')
  BASE_BRANCH=$(echo "$PR_JSON" | jq -r '.baseRefName')
  echo "Found PR #$PR_NUM (base: $BASE_BRANCH)"
else
  BASE_BRANCH=$( (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' | grep .) || (git remote show -n origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' | grep .) || echo "main" )
  echo "No PR found. Using base branch: $BASE_BRANCH"
fi
```

Display a brief summary of what was detected.

## Step 2: Gather Full Context

Read `context-gathering.md` and execute the procedure end-to-end:

- PR metadata (title, body, state, comments, reviews)
- Linked issues (title, body, labels, comments)
- Review threads (unresolved, with file paths and line numbers)
- Inline review comments
- Pending reviews (CHANGES_REQUESTED)
- Repo guidelines (AGENTS.md or CLAUDE.md)

If `--issue N` was provided instead of a PR, fetch just the issue context. If no PR and no issue, proceed with diff-only review (no requirement verification, no review-comment status).

`context-gathering.md` includes the size guard — if combined context exceeds ~6000 characters, use summary format.

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

## Step 5: Perform Review

Read `review-criteria.md` for the full criteria, the Quality Score Rubric, the confidence-scoring guide, and the breaking-change detection block. Apply all criteria to the diff with the gathered context.

Process:

1. Review every unit from the Step 3 coverage plan against every criterion in `review-criteria.md`.
2. Cross-reference with requirements (when PR/issue context is available): each acceptance criterion → implementation → tests; check for missing requirements and scope creep.
3. For each existing review thread, mark whether it appears addressed in the current diff.
4. Include the Step 4 static-analysis results.
5. Detect breaking changes in exported symbols (grep recipe in `review-criteria.md`).
6. Run the plan's cross-cutting pass, then verify, deduplicate, and rank findings against the checkout before Step 6.

For the exact findings-table layout, spec-compliance table, review-comments-status table, and the recommendation values — Read `output-format.md`.

## Step 6: Fix Findings

Read `fix-and-verify.md` and follow it end-to-end. Highlights:

- Process findings in priority order (P0 → P3)
- Auto-skip priority 3 AND confidence < 0.5 (nit noise)
- Make minimal fixes; track which fixes are testable
- Parallel-dispatch Agent subagents when 3+ findings target different files
- Generate tests for testable fixes; verify build/test/lint pass
- Stage only modified files (never `git add -A`); commit with a descriptive message

## Step 7: Post-Review Summary & Actions

Display the final summary:

```
## Review Complete

- **Findings reported:** <n>
- **Findings fixed:** <n>
- **Findings skipped:** <n> (with reasons)
- **Files changed:** <list>
- **Quality Score:** <n>/100
- **All verifications passed:** yes/no
- **Recommendation:** APPROVE / REQUEST_CHANGES / COMMENT
```

### Post to PR

If `AUTO_POST` is `true` and a PR was detected, post immediately with `gh pr comment "$PR_NUM" --body ...` using the formatting from `output-format.md`.

If `AUTO_POST` is `false` and a PR was detected, ask via `AskUserQuestion`:

| Option | Description |
|--------|-------------|
| Post to PR | Add review findings as a PR comment |
| Done | Exit the review |

Default: `Done`.

## Further Reading

- `context-gathering.md` — PR/issue/review-thread fetching, repo-guideline detection, size guard
- `review-criteria.md` — full review criteria, Go idiom checks, Quality Score Rubric, confidence scoring, breaking-change detection
- `fix-and-verify.md` — fix iteration, parallel dispatch, test generation, verification, commit
- `output-format.md` — findings table, spec-compliance table, review-comments-status table, PR-comment template
- `../../lib/review-planning.md` — shared adaptive coverage planning and finding coordination
