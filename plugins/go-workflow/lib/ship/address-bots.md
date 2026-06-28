# Ship — Phase 5: Address Bot Feedback (Step 12)

Loaded by `skills/ship/SKILL.md` Phase 5.

## 12a. Fetch and rebase against base branch

Before applying fixes, ensure the branch is up to date with the base to avoid conflicts:

```bash
git fetch origin "$BASE_BRANCH"
git rebase "origin/$BASE_BRANCH" || git rebase --abort
```

If the rebase fails (conflicts), abort and inform the user. Proceed with fixes WITHOUT rebasing — the user can resolve conflicts manually.

## 12b. Apply address-review fixes

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/SKILL.md` and follow **Steps 2–11 only**:

- **Skip Step 1** (loop init / PR checkout) — we're already on the branch; loop is owned by `$ship`
- **Skip Step 12** (bot watch) — `$ship` Step 11 owns that
- Do NOT create a second loop state file — all phases run under the `ship` loop

## 12c. Capture baseline BEFORE push, HEAD SHA AFTER push

**CRITICAL:** Capture `BOT_REVIEW_BASELINE` BEFORE pushing. Capturing after the push misses fast bot responses that arrive between push and timestamp:

```bash
BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
```

Then push the fixes. After pushing, capture HEAD SHA:

```bash
git push
HEAD_SHA=$(git rev-parse HEAD)
echo "HEAD SHA captured: $HEAD_SHA"
```

Persist `bot_review_baseline` and `head_sha` in the state file.

Return to Step 10 (ci-watch) — set phase to `ci-watch` and re-watch CI for the new HEAD SHA before checking bot approval again.
