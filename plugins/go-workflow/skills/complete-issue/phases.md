# Complete Issue — Phase Sub-Steps

Loaded by `SKILL.md` Phases 1 and 2 when the agent needs the full sub-step
list (Phase 1) or the codex invocation bash (Phase 2). Phase 3 is a thin
delegation to `$e2e-verify` so it has no extra detail here.

## Phase 1: `$start-issue` Sub-Steps

`$start-issue $ISSUE_NUM $FLAGS` runs the full workflow:

1. Fetch issue details
2. Create worktree (if user chooses)
3. Detect issue type (bug/feature)
4. Explore codebase
5. Design approach (features: get user approval)
6. TDD implementation
7. Verify (build, test, lint)
8. Coverage check
9. Security review
10. Commit, push, create PR
11. Watch CI

This is purely informational — `$start-issue` owns the implementation. The
trunk in `SKILL.md` does the post-completion bookkeeping (PR detection,
worktree-CWD reassignment, state persistence).

`$start-issue` also owns subagent model tiering. Its orchestrated workflow uses
the `model` frontmatter in `agents/*.md` unless the user sets
`CLAUDE_CODE_SUBAGENT_MODEL` before invoking `$complete-issue`.

## Phase 2: Codex Run

After detection succeeds in `SKILL.md`, run codex review on the PR diff with
an adaptive timeout sized to the diff:

```bash
DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main")
DIFF=$(git diff "origin/${DEFAULT_BRANCH}...HEAD")
DIFF_LINES=$(printf '%s\n' "$DIFF" | wc -l)
# Adaptive timeout sized for high reasoning effort: 300s base + 4s per 100 lines, capped at 900s
CODEX_TIMEOUT=$(( 300 + (DIFF_LINES / 25) ))
if [ "$CODEX_TIMEOUT" -gt 900 ]; then CODEX_TIMEOUT=900; fi
# Detect timeout command (macOS does not ship GNU timeout)
if command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD="timeout"
else TIMEOUT_CMD=""; fi
```

If `$TIMEOUT_CMD` is available, invoke `$TIMEOUT_CMD $CODEX_TIMEOUT $CODEX_CMD exec -c model_reasoning_effort="high"` with structured output. If no timeout command is available, run `$CODEX_CMD exec -c model_reasoning_effort="high"` without a timeout wrapper. Reasoning effort is always pinned to `high`.

If the diff exceeds 3000 lines, warn the user via `AskUserQuestion` BEFORE starting:

> "Large diff ($DIFF_LINES lines) — codex exec may timeout. Proceed / Use `codex review --base` / Agent review / Skip?"

Forward the user's choice to the appropriate code path:

- **Proceed** → run codex with the adaptive timeout above.
- **Use `codex review --base`** → swap the command for `codex review --base origin/${DEFAULT_BRANCH} -c model_reasoning_effort="high"`.
- **Agent review** → dispatch an Agent subagent (sonnet) with the diff and the same review checklist.
- **Skip** → warn and proceed directly to Phase 3.

Any runtime failure (non-zero exit, timeout, no output) → see `codex-fallback.md`.

## Address Findings

For each valid codex finding, make the fix. Skip findings that are:

- False positives (the code is correct)
- Cosmetic-only and don't change observable behavior
- Pre-existing issues not introduced by this PR

Commit fixes if any changes were made:

```bash
git add -A
git commit -m "fix: address codex review findings"
git push
```

If no fixes were needed, skip the commit and proceed to Phase 3.
