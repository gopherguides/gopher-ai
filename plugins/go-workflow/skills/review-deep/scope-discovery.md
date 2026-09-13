# Review-Deep Scope Discovery

Loaded by `SKILL.md` Steps 1-2. Execute PR/branch scope detection before gathering full issue, review, and repository context.

## Step 1: Detect Scope & Base Branch

If `PR_ARG` is set, use it directly. Otherwise, auto-detect from the current branch using two strategies in order — fall through when each returns empty.

**Strategy 1 — current branch:**

```bash
PR_JSON=$(gh pr view --json number,title,body,state,baseRefName,headRefName,closingIssuesReferences --jq '.' 2>/dev/null)
```

**Strategy 2 — associated HEAD PRs, preferring the open current branch:**

```bash
if [ -z "$PR_JSON" ]; then
  HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
  if ! PR_NUM=$(set -o pipefail; gh api --paginate --slurp "repos/{owner}/{repo}/commits/$HEAD_SHA/pulls?per_page=100" \
    | jq -r --arg branch "$(git branch --show-current)" '
        [.[][]] as $all
        | ([$all[] | select(.state == "open" and .head.ref == $branch)]
          + [$all[] | select(.state == "open")]
          + $all)
        | map(.number) | first // empty'); then
    printf '%s\n' 'PR discovery failed; retry with backoff before continuing.' >&2
    exit 1
  fi
  if [ -n "$PR_NUM" ]; then
    if ! PR_JSON=$(gh pr view "$PR_NUM" --json number,title,body,state,baseRefName,headRefName,closingIssuesReferences); then
      printf '%s\n' 'PR metadata lookup failed; retry with backoff before continuing.' >&2
      exit 1
    fi
  fi
fi
```

An API failure is incomplete discovery: report it and retry with backoff; do
not interpret it as evidence that no PR exists. An empty successful response
allows branch-only review. Closed and merged associations remain eligible when
no open PR is associated with HEAD.

**Extract PR number and base branch:**

```bash
if [ -n "$PR_JSON" ]; then
  PR_NUM=$(echo "$PR_JSON" | jq -r '.number')
  BASE_BRANCH=$(echo "$PR_JSON" | jq -r '.baseRefName')
  PR_HEAD_BRANCH=$(echo "$PR_JSON" | jq -r '.headRefName')
  echo "Found PR #$PR_NUM (base: $BASE_BRANCH, head: $PR_HEAD_BRANCH)"
else
  BASE_BRANCH=$( (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' | grep .) || (git remote show -n origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' | grep .) || echo "main" )
  PR_HEAD_BRANCH=""
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
