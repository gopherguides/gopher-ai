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

After detection succeeds in `SKILL.md`, plan and run codex review on the PR
diff with an adaptive timeout:

```bash
DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main")
DIFF=$(git diff "origin/${DEFAULT_BRANCH}...HEAD")
DIFF_LINES=$(printf '%s\n' "$DIFF" | wc -l)
REVIEW_BASE="origin/${DEFAULT_BRANCH}"
REVIEW_BACKEND=codex
REVIEW_CONCURRENCY=auto
# Adaptive timeout sized for high reasoning effort: 300s base + 4s per 100 lines, capped at 900s
CODEX_TIMEOUT=$(( 300 + (DIFF_LINES / 25) ))
if [ "$CODEX_TIMEOUT" -gt 900 ]; then CODEX_TIMEOUT=900; fi
# Detect timeout command (macOS does not ship GNU timeout)
if command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD="timeout"
else TIMEOUT_CMD=""; fi
```

If `$TIMEOUT_CMD` is available, invoke `$TIMEOUT_CMD $CODEX_TIMEOUT $CODEX_CMD exec -c model_reasoning_effort="high"` with structured output. If no timeout command is available, run `$CODEX_CMD exec -c model_reasoning_effort="high"` without a timeout wrapper. Reasoning effort is always pinned to `high`.

No model flag is passed in either Codex path. A `model = "..."` pin in
`~/.codex/config.toml` is respected; leaving it unset lets the Codex CLI choose
its recommended default.

Read `../../lib/review-planning.md`, run the shared planner, display the coverage
plan, and execute every unit plus the coordinator pass. Partition sequentially
when the selected fallback lacks concurrent agents. Ask only when the planner
reports that reliable coverage is unavailable or a material scope choice is
required; do not stop solely because the raw diff is large.

Any runtime failure (non-zero exit, timeout, no output) → see `codex-fallback.md`.

## Address Findings

After verifying and deduplicating all unit findings against the checkout, make
each valid fix in ranked order. Skip findings that are:

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
