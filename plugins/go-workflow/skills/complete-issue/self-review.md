# Complete-Issue Self-Review

Loaded by `SKILL.md` Phase 2. Execute the complete session-local review procedure before verification handoff.

## Phase 2: Self-Review (Codex)

```bash
set_loop_phase "$STATE_FILE" "reviewing" "$WORKFLOW_STATE_PATH"
```

Run an LLM review to catch issues before E2E verification. Never silently skip
review. Resolve unpinned backend recovery from diagnostics; replacing a backend
the user explicitly required is a missing-intent gate.

Delegated fallback reviews are session-local and must complete
synchronously. Never dispatch them in the background or persist them for a
successor session. If a successor re-enters with `phase="reviewing"`, skip the
expired review and continue to Phase 3; the PR already created in Phase 1 and
its CI are the durable gate.

Detect codex availability:

```bash
CODEX_AVAILABLE=false
if command -v codex &>/dev/null; then
  CODEX_CMD="codex"
  CODEX_AVAILABLE=true
fi
```

- **If codex is NOT available** OR **if codex exec fails at runtime** → Read
  `codex-fallback.md` and follow its evidence-based recovery order.
- **If codex IS available** → run codex review on the PR diff with an adaptive timeout, address findings, and commit fixes. See `phases.md` for the full bash (diff sizing, timeout calculation, large-diff warning).

Address findings: for each valid finding, make the fix. Skip false positives or
cosmetic-only items. Maintain `REVIEW_FILES` as the exact list of files modified
in this review phase, including generated or updated tests. Before modifying an
existing path, confirm
`git -C "$WORKTREE_PATH" status --porcelain -- "$TARGET_FILE"` is empty so
pre-existing changes cannot enter the review-fix commit. Every GitHub and Git
operation in this phase runs against the persisted `WORKTREE_PATH` and
`REPO_SLUG`. Commit fixes if any changes were made:

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

---
