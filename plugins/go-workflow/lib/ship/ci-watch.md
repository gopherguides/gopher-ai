# Ship — Phase 3: CI Watch (Step 10)

Loaded by `skills/ship/SKILL.md` Phase 3. Owns SHA-anchored CI watching.

## 10a. Capture and verify HEAD SHA

```bash
HAS_WORKFLOWS=$(find .github/workflows -maxdepth 1 -name '*.yml' -o -name '*.yaml' 2>/dev/null | head -1)
```

If no workflow files exist → persist `has_ci: false` and skip to Step 11. Otherwise persist `has_ci: true`.

Read `head_sha` from state file (set during push in Step 9c, after CI failure recovery in Step 10e, or after Step 12c):

```bash
HEAD_SHA=$(jq -r '.head_sha // empty' ".local/state/ship.loop.local.json")
if [ -z "$HEAD_SHA" ]; then
  HEAD_SHA=$(git rev-parse HEAD)
fi
echo "Watching CI for commit: $HEAD_SHA"
```

## 10b. Wait for checks to register for the correct SHA

Poll until GitHub reports checks for `HEAD_SHA` (up to 120s). `pull_request`-triggered checks run on a merge commit, not the PR head SHA — use the REST API which reliably reports check runs for a specific commit:

```bash
CI_READY=false
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')
for i in $(seq 1 12); do
  CHECK_COUNT=$(gh api "repos/$OWNER/$REPO/commits/$HEAD_SHA/check-runs" \
    --jq '.total_count' 2>/dev/null || echo "0")
  if [ "$CHECK_COUNT" -gt 0 ]; then
    CI_READY=true
    break
  fi
  echo "No checks for $HEAD_SHA yet... ($i/12)"
  sleep 10
done
```

If still not ready after 120s, ask via `AskUserQuestion`:

> "CI checks for commit {HEAD_SHA} have not appeared after 120 seconds. The repo has workflow files. Wait longer, or proceed without CI verification?"

## 10c. Watch checks for the correct SHA

```bash
gh pr checks "$PR_NUM" --watch
```

## 10d. Post-watch SHA validation

After `--watch` completes, verify the PR head hasn't shifted (a concurrent push could have advanced it):

```bash
FINAL_SHA=$(gh pr view "$PR_NUM" --json headRefOid --jq '.headRefOid' 2>/dev/null || true)
if [ -n "$FINAL_SHA" ] && [ "$FINAL_SHA" != "$HEAD_SHA" ]; then
  echo "STOP: PR head shifted to SHA $FINAL_SHA during watch (expected $HEAD_SHA)."
  echo "A new commit landed on this PR that was NOT reviewed locally."
  echo "Restarting from review phase against the new HEAD."
  HEAD_SHA="$FINAL_SHA"
  BRANCH_REMOTE=$(git config "branch.$(git branch --show-current).remote" 2>/dev/null || echo "origin")
  PR_HEAD_BRANCH=$(gh pr view "$PR_NUM" --json headRefName --jq '.headRefName')
  git fetch "$BRANCH_REMOTE" "$PR_HEAD_BRANCH"
  git checkout "$PR_HEAD_BRANCH"
  git reset --hard "$BRANCH_REMOTE/$PR_HEAD_BRANCH"
  TMP=".local/state/ship.loop.local.json.tmp"
  jq --arg sha "$HEAD_SHA" --argjson pass 0 --arg rc "" --arg phase "reviewing" \
    '.head_sha = $sha | .pass = $pass | .review_clean = $rc | .phase = $phase' \
    ".local/state/ship.loop.local.json" > "$TMP" && mv "$TMP" ".local/state/ship.loop.local.json"
  # Go back to Step 5 (reviewing)
fi
```

The reset on SHA shift is critical: if a concurrent push lands content that
wasn't reviewed locally, we MUST re-review it. The pass counter is reset to
0 so the user gets full max-passes coverage of the new code.

## 10e. CI failure handling

If CI fails:

1. Analyze: `gh pr checks "$PR_NUM" --json name,state,description`
2. Fix the issue
3. Commit
4. Push: `git push`
5. Capture HEAD SHA: `HEAD_SHA=$(git rev-parse HEAD)`; persist `head_sha`
6. Re-capture `BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)`; persist
7. Re-watch CI — go back to 10b for the NEW SHA
