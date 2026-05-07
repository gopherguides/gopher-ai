# Review Loop — Verify and Commit (Steps 8-9)

Loaded by `commands/review-loop.md` Steps 8 and 9. Owns the per-language
verify command set and the commit logic.

## Step 8 — Verify Phase

Auto-detect project type and run the matching commands. If any verification
fails: analyze, fix, re-run, repeat until all pass.

### Go (`go.mod` exists)

```bash
go build ./...
go test ./...
golangci-lint run 2>/dev/null || true  # optional: may not be installed
```

### Node/TypeScript (`package.json` exists)

```bash
npm run build  # fail if build breaks
npm test       # fail if tests break
npm run lint 2>/dev/null || true  # optional: lint script may not exist
```

### Rust (`Cargo.toml` exists)

```bash
cargo build
cargo test
cargo clippy 2>/dev/null || true  # optional: may not be installed
```

### Python (`pyproject.toml` or `setup.py` exists)

```bash
pytest 2>/dev/null || python -m pytest  # fail if tests break
ruff check . 2>/dev/null || flake8 . 2>/dev/null || true  # optional: linter may not be installed
```

### Fallback

If no project type detected, ask the user what verify command to run.

## Step 9 — Commit

Stage **only the files that were fixed in this pass.** Do NOT use `git add -A`
as it may sweep in unrelated working-tree changes:

```bash
git add <list of files modified during fix phase>
```

Track which files were edited during the fix phase (Step 7) and stage only
those specific files.

**Only commit if there are staged changes.** Passes can legitimately have
zero fixable findings (all skipped/invalid):

```bash
if ! git diff --cached --quiet; then
  git commit -m "fix: address $LLM_CHOICE review findings (pass $PASS)"
else
  echo "No changes to commit for this pass"
fi
```

## Per-pass Summary

After commit (or skip), display:

- Findings reported by LLM
- Findings fixed
- Findings skipped (with reasons)
- Files changed
- Verification status
