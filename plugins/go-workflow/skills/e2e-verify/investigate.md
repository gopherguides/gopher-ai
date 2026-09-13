# E2E Verify — Investigation

Loaded by `SKILL.md` Step 4 only in `investigate` mode. Execute the complete procedure and retain findings for Step 6.

## Step 4: Investigate (conditional)

**Only for mode: `investigate`** — for all others, skip to Step 5.

```bash
set_loop_phase "$STATE_FILE" "investigating" "$WORKFLOW_STATE_PATH"
```

1. Refresh the PR metadata with `PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM")`, then read its requirements with `jq -r '"\(.title)\n\n\(.body // \"\")\n\n\(.html_url)"' <<< "$PR_JSON"`.
2. Review the implementation against requirements: `git -C "$WORKTREE_PATH" diff "${BASE_REMOTE}/${BASE_BRANCH}...HEAD"`
3. Identify gaps between issue requirements and implementation: missing acceptance criteria, untested edge cases, potential regressions, architectural concerns
4. Record findings for the PR comment. **Do NOT fix anything — only report.**

---
