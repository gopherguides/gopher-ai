# Review Loop — PR Scope Detection (Step 4a)

Loaded by `commands/review-loop.md` Step 4a. Three silent strategies for
auto-detecting a PR from the current branch / HEAD commit, plus the base-branch
fallback.

## Strategy 1 — Current branch

Works when the branch name matches a PR.

```bash
PR_JSON=`gh pr view --json number,title,body,state,baseRefName,closingIssuesReferences --jq '.' 2>/dev/null`
```

## Strategy 2 — Match HEAD commit against open PRs

Handles worktrees where the current branch isn't directly tied to a PR.

```bash
if [ -z "$PR_JSON" ]; then
  HEAD_SHA=`git rev-parse HEAD 2>/dev/null`
  PR_NUM=`gh pr list --search "$HEAD_SHA" --state open --json number --jq '.[0].number' 2>/dev/null`
  if [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ]; then
    PR_JSON=`gh pr view "$PR_NUM" --json number,title,body,state,baseRefName,closingIssuesReferences 2>/dev/null`
  fi
fi
```

## Strategy 3 — Check merged/closed PRs too

Covers recently merged work where the user is reviewing a hotfix.

```bash
if [ -z "$PR_JSON" ]; then
  HEAD_SHA=`git rev-parse HEAD 2>/dev/null`
  PR_NUM=`gh pr list --search "$HEAD_SHA" --state all --limit 5 --json number --jq '.[0].number' 2>/dev/null`
  if [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ]; then
    PR_JSON=`gh pr view "$PR_NUM" --json number,title,body,state,baseRefName,closingIssuesReferences 2>/dev/null`
  fi
fi
```

If a PR was found, display a brief summary (number, title, state).

## Base Branch Fallback (Step 4c)

When Step 4b's "Changes vs branch" or "Specific files" was selected:

```bash
if [ -n "$PR_JSON" ]; then
  BASE_BRANCH=`echo "$PR_JSON" | jq -r '.baseRefName'`
else
  BASE_BRANCH=`(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' | grep .) || (git remote show -n origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' | grep .) || echo "main"`
fi
echo "Detected base branch: $BASE_BRANCH"
```

If the user corrects the detected branch (e.g., "use `develop`"), update
`BASE_BRANCH` accordingly before proceeding.
