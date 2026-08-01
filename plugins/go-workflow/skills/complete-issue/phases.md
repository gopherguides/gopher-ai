# Complete Issue — Phase Sub-Steps

Loaded by `SKILL.md` Phases 1 and 2 when the agent needs the full sub-step
list (Phase 1) or the codex invocation bash (Phase 2). Phase 3 loads the
user-only `e2e-verify` workflow directly, so it has no extra detail here.

## Phase 1: `$go-workflow:start-issue` Sub-Steps

The `start-issue` workflow runs with `$ISSUE_NUM $FLAGS` as its arguments:

1. Fetch issue details
2. Resolve worktree placement from isolation evidence
3. Detect issue type (bug/feature)
4. Explore codebase
5. Design approach (features: driver selects from evidence; missing product intent stops)
6. TDD implementation
7. Verify (build, test, lint)
8. Coverage check
9. Security review
10. Commit, push, create PR
11. Watch CI

This is purely informational — `$go-workflow:start-issue` owns the implementation. The
trunk in `SKILL.md` consumes its persisted worktree output, validates it, and
does the post-completion bookkeeping.

`$go-workflow:start-issue` also owns subagent model tiering. Its orchestrated workflow uses
the `model` frontmatter in `agents/*.md` unless the user sets
`CLAUDE_CODE_SUBAGENT_MODEL` before invoking `$go-workflow:complete-issue`.

## Phase 2: Codex Run

After detection succeeds in `SKILL.md`, plan and run codex review on the PR
diff with an adaptive timeout:

```bash
DEFAULT_BRANCH=$(git -C "$WORKTREE_PATH" remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main")
DIFF=$(git -C "$WORKTREE_PATH" diff "origin/${DEFAULT_BRANCH}...HEAD")
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

If `$TIMEOUT_CMD` is available, invoke
`(cd "$WORKTREE_PATH" && $TIMEOUT_CMD $CODEX_TIMEOUT $CODEX_CMD exec -c model_reasoning_effort="high")`
with structured output. If no timeout command is available, run
`(cd "$WORKTREE_PATH" && $CODEX_CMD exec -c model_reasoning_effort="high")`
without a timeout wrapper. Reasoning effort is always pinned to `high`.

No model flag is passed in either Codex path. A `model = "..."` pin in
`~/.codex/config.toml` is respected; leaving it unset lets the Codex CLI choose
its recommended default.

Read `../../lib/review-planning.md`, run the shared planner, display the coverage
plan, and execute every unit plus the coordinator pass. Partition sequentially
when the selected fallback lacks concurrent agents. Apply the shared review
planning decision policy when reliable coverage needs more partitions or an
unpinned backend change. Missing product intent or replacement of an explicitly
required backend stops at the missing-intent gate; raw diff size alone does not.

Any runtime failure (non-zero exit, timeout, no output) → see `codex-fallback.md`.

## Address Findings

After verifying and deduplicating all unit findings against the checkout, make
each valid fix in ranked order. Skip findings that are:

- False positives (the code is correct)
- Cosmetic-only and don't change observable behavior
- Pre-existing issues not introduced by this PR

Maintain `REVIEW_FILES` as the exact list of files modified while addressing
valid findings, including generated or updated tests. Before modifying an
existing path, confirm `git -C "$WORKTREE_PATH" status --porcelain -- "$TARGET_FILE"` is empty so
pre-existing changes cannot be attributed to this review phase. Commit fixes if
any changes were made:

```bash
if ! git -C "$WORKTREE_PATH" diff --cached --quiet; then
  echo "Error: Pre-existing staged changes must be committed or unstaged before complete-issue can commit review fixes."
  exit 1
fi

REVIEW_FILES=(
  "path/to/reviewed-file.go"
  "path/to/reviewed-file_test.go"
)
if [ "${#REVIEW_FILES[@]}" -gt 0 ]; then
  git -C "$WORKTREE_PATH" add -- "${REVIEW_FILES[@]}"
  if ! git -C "$WORKTREE_PATH" diff --cached --quiet; then
    git -C "$WORKTREE_PATH" commit -m "fix: address codex review findings"
    git -C "$WORKTREE_PATH" push
  fi
fi
```

If no fixes were needed, skip the commit and proceed to Phase 3.
