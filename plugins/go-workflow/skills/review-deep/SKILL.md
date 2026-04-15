---
name: review-deep
description: |
  WHEN: User wants a thorough code review with full PR/issue context. Trigger on "review",
  "deep review", "review my changes", "review this PR", "review from issue", "code review",
  "check my changes", "what do you think of this code?", or $review-deep invocation. Also
  auto-trigger when user finishes implementing a feature or bug fix and wants feedback before
  shipping.
  WHEN NOT: User wants to address/fix existing review comments from reviewers (use $address-review).
  User wants to delegate review to another LLM ($codex, /review-loop). User only wants linting
  ($verify, $lint-fix). User wants to review someone else's PR. User is already mid-fix from
  a previous review-deep run.
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
      ARGS="${ARGS#$ISSUE_ARG}"
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
      ARGS="${ARGS#$PR_ARG}"
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

Read `context-gathering.md` for the full PR detection and context gathering procedure.

### 1a. Silent PR Auto-Detection

If `PR_ARG` is set, use it directly. Otherwise, auto-detect PR from current branch using three strategies:

**Strategy 1 -- Current branch:**

```bash
PR_JSON=$(gh pr view --json number,title,body,state,baseRefName,closingIssuesReferences --jq '.' 2>/dev/null)
```

**Strategy 2 -- Match HEAD commit against open PRs:**

```bash
if [ -z "$PR_JSON" ]; then
  HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
  PR_NUM=$(gh pr list --search "$HEAD_SHA" --state open --json number --jq '.[0].number' 2>/dev/null)
  if [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ]; then
    PR_JSON=$(gh pr view "$PR_NUM" --json number,title,body,state,baseRefName,closingIssuesReferences 2>/dev/null)
  fi
fi
```

**Strategy 3 -- Check merged/closed PRs:**

```bash
if [ -z "$PR_JSON" ]; then
  HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
  PR_NUM=$(gh pr list --search "$HEAD_SHA" --state all --limit 5 --json number --jq '.[0].number' 2>/dev/null)
  if [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ]; then
    PR_JSON=$(gh pr view "$PR_NUM" --json number,title,body,state,baseRefName,closingIssuesReferences 2>/dev/null)
  fi
fi
```

Extract PR number and base branch:

```bash
if [ -n "$PR_JSON" ]; then
  PR_NUM=$(echo "$PR_JSON" | jq -r '.number')
  BASE_BRANCH=$(echo "$PR_JSON" | jq -r '.baseRefName')
  echo "Found PR #$PR_NUM (base: $BASE_BRANCH)"
else
  BASE_BRANCH=$((git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' | grep .) || (git remote show -n origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' | grep .) || echo "main")
  echo "No PR found. Using base branch: $BASE_BRANCH"
fi
```

Display a brief summary of what was detected.

## Step 2: Gather Full Context

Read `context-gathering.md` and execute the context gathering procedure. This step fetches:

- PR metadata (title, body, state, comments, reviews)
- Linked issues (title, body, labels, comments)
- Review threads (unresolved, with file paths and line numbers)
- Inline review comments
- Pending reviews (CHANGES_REQUESTED)
- Repo guidelines (AGENTS.md or CLAUDE.md)

If `--issue N` was provided instead of a PR, fetch just the issue context.

If no PR and no issue: proceed with diff-only review (no requirement verification).

**Size guard:** If combined context exceeds ~6000 characters, use summary format (first 300 chars of bodies, key points from comments) to preserve context window for the diff and review.

## Step 3: Generate Diff

Based on detected scope:

- **Changes vs branch** (default when PR detected): `git diff ${BASE_BRANCH}...HEAD`
- **Uncommitted changes** (when no PR and uncommitted changes exist): `git diff HEAD` plus untracked files via `git ls-files --others --exclude-standard`
- **If PR_ARG was explicitly provided:** Always use changes vs base branch

```bash
DIFF=$(git diff "${BASE_BRANCH}...HEAD")
DIFF_LINES=$(printf '%s\n' "$DIFF" | wc -l)
DIFF_FILES=$(printf '%s\n' "$DIFF" | grep -c '^diff --git' || echo 0)
echo "Diff size: $DIFF_LINES lines across $DIFF_FILES files"
```

If diff exceeds 3000 lines, warn via `AskUserQuestion`:

**"Large diff detected ($DIFF_LINES lines, $DIFF_FILES files). Review quality may degrade on very large diffs. Continue with full diff, or narrow the scope?"**

| Option | Description |
|--------|-------------|
| Continue with full diff | Review everything |
| Go files only | Filter to `*.go` files |
| Specify files | Enter specific file paths to review |

## Step 4: Static Analysis

If a Go project is detected (`go.mod` exists):

```bash
CHANGED=$(git diff --name-only "${BASE_BRANCH}...HEAD" | grep '\.go$')
if [ -n "$CHANGED" ]; then
  echo "=== go vet ==="
  echo "$CHANGED" | xargs -I{} dirname {} | sort -u | xargs go vet 2>&1 || true

  echo "=== staticcheck ==="
  echo "$CHANGED" | xargs -I{} dirname {} | sort -u | xargs staticcheck 2>&1 || true

  echo "=== go test ==="
  echo "$CHANGED" | xargs -I{} dirname {} | sort -u | xargs go test -race -count=1 2>&1 || true
fi
```

Record static analysis results for inclusion in the review output. Failures here are informational -- they feed into the review, not block it.

## Step 5: Perform Review

Read `review-criteria.md` for the full review criteria. Apply all criteria to the diff with the gathered context.

### Review Process

1. **Review the diff** line-by-line against all criteria:
   - Correctness: bugs, logic errors, race conditions, nil dereference, missing error checks
   - Security: injection, auth bypass, data exposure, hardcoded secrets
   - Performance: O(n^2) loops, unnecessary allocations, unbounded growth
   - Maintainability: dead code, unclear naming, excessive complexity, missing cleanup/defer
   - Developer experience: missing error context, unclear APIs, poor defaults
   - Go idioms: `%w` wrapping, accept interfaces/return structs, `context.Context` first param, `errgroup`

2. **Cross-reference with requirements** (when PR/issue context available):
   - Does each acceptance criterion have implementation?
   - Does each acceptance criterion have tests?
   - Are there missing requirements from the issue?
   - Is there scope creep (changes not requested)?
   - For bug fixes: does the fix address root cause, not just symptom?

3. **Check existing review feedback** (when review threads available):
   - Which review comments appear addressed in the current diff?
   - Which appear still unresolved?

4. **Include static analysis results** from Step 4

5. **Detect breaking changes** in exported symbols:
   ```bash
   git diff "${BASE_BRANCH}...HEAD" -- '*.go' | grep -E "^-func [A-Z]|^-type [A-Z]|^-var [A-Z]|^-const [A-Z]"
   ```

### Review Output

Present findings in this format:

```
## Deep Review Findings -- N issues

| # | Priority | Category | File | Lines | Title | Confidence |
|---|----------|----------|------|-------|-------|------------|
| 1 | P0 | correctness | api/handler.go | 42-45 | Nil pointer on empty response | 0.95 |

**Overall:** patch is correct / patch is incorrect
**Explanation:** ...
**Quality Score:** 82/100
```

**Quality Score Rubric** (100 points total):

| Criteria | Points | Description |
|----------|--------|-------------|
| Error Handling | 20 | All errors checked and wrapped |
| Test Coverage | 20 | New code has tests |
| Naming/Style | 15 | Idiomatic Go conventions |
| Documentation | 15 | Exported symbols documented |
| Complexity | 15 | Functions focused, readable |
| Safety | 15 | No races, leaks, or panics |

**Spec Compliance** (when issue/PR context available):

```
## Spec Compliance

| Criterion | Implemented | Tested | Evidence |
|-----------|-------------|--------|----------|
| <requirement> | YES/NO/PARTIAL | YES/NO | file:line |

### Missing Requirements
- <any requirements from the issue not addressed>

### Scope Creep
- <any changes not requested> (or "None detected")
```

**Review Comments Status** (when review threads available):

```
## Review Comments Status

| Thread | File:Line | Reviewer | Status |
|--------|-----------|----------|--------|
| <summary> | file.go:42 | @reviewer | Addressed / Still open |
```

**Recommendation:** APPROVE / REQUEST_CHANGES / COMMENT

## Step 6: Fix Findings

Read `fix-and-verify.md` for the full fix, test generation, and verification procedure.

Always runs after the review. For each finding in priority order (P0 first):

1. Read the file and surrounding context
2. Evaluate validity -- is this a real issue?
3. Auto-skip findings with priority 3 AND confidence < 0.5 (nit noise)
4. If valid: make the minimal fix using Edit tool
5. If not valid: record skip reason
6. For testable fixes (changes observable behavior):
   - Check for existing `_test.go` files and table-driven tests
   - Add a new test case or create a new test following package conventions
   - Verify the test passes

### Parallel Dispatch (3+ findings on different files)

When there are 3 or more findings targeting **different files**, dispatch parallel Agent subagents:

1. Group findings by file (same file = one subagent)
2. Group by shared test files (same package `_test.go` = same group)
3. Dispatch each group as an Agent subagent (sonnet) with `run_in_background: true`
4. Collect results and proceed to verification

### Verify

```bash
go build ./...
go test ./...
golangci-lint run 2>/dev/null || true
```

If verification fails: analyze the failure, fix it, and re-run until all pass.

### Commit

Stage only files modified during the fix phase (not `git add -A`):

```bash
git add <list of modified files>
if ! git diff --cached --quiet; then
  git commit -m "fix: address review-deep findings

- <brief summary of each fix>
- <tests added, if any>"
fi
```

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

If `AUTO_POST` is `true` and a PR was detected, post immediately:

```bash
gh pr comment "$PR_NUM" --body "$(cat <<'EOF'
## Deep Review Results

<formatted findings table>
<spec compliance section if available>
<quality score>
<recommendation>

---
*Generated by gopher-ai review-deep*
EOF
)"
```

If `AUTO_POST` is `false` and a PR was detected, ask:

| Option | Description |
|--------|-------------|
| Post to PR | Add review findings as a PR comment |
| Done | Exit the review |

Default: `Done`
