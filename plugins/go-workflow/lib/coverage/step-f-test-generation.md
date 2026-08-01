# Step F — Test Generation for Uncovered Code

Loaded by `coverage-verification.md` Step F. Owns mode selection,
`CHANGED_FUNC_NAMES` extraction, per-language test-writing conventions, and
the final `coverage_tests_generated` state-file write.

Only runs when Step E routes here for below-threshold coverage or the
no-test-files branch.

## Mode selection

Set by the Step E branch:

- **All uncovered functions mode**: Generate tests for every
  uncovered function in `CHANGED_SRC` (Go: `CHANGED_SRC_GATED`), as listed
  in `UNCOVERED_FUNCS` from Step D.
- **No-test-files path**:
  `UNCOVERED_FUNCS` may be empty because Step D short-circuits when coverage
  data is missing. In this case, read each file in `CHANGED_SRC` (Go:
  `CHANGED_SRC_GATED` — `package main` files are excluded so Step F never
  generates tests for `func main()`-style code) directly and extract all
  exported function/method signatures as test targets.
- **Changed functions only mode** (Go only): Available to callers that already
  selected this scope before entering the mandatory gate; it is never offered
  as a low-coverage bypass.

## Changed-functions extraction (Go only)

When a caller selected this scope before the gate, identify changed functions
by mapping diff hunks to their enclosing function
using committed, staged, unstaged, and untracked changes (matching Step B's
file detection):

```bash
# Combine committed + staged + unstaged diffs
COMBINED_DIFF=$( (git -C "$WORKTREE_PATH" diff "${BASE_BRANCH}...HEAD" -- $CHANGED_SRC 2>/dev/null; git -C "$WORKTREE_PATH" diff HEAD -- $CHANGED_SRC 2>/dev/null; git -C "$WORKTREE_PATH" diff --cached HEAD -- $CHANGED_SRC 2>/dev/null) )
# For untracked files: generate a synthetic diff so new functions are detected
UNTRACKED_SRC=$(git -C "$WORKTREE_PATH" ls-files --others --exclude-standard 2>/dev/null | grep '\.go$' | grep -v '_test\.go$' || true)
for uf in $UNTRACKED_SRC; do
  COMBINED_DIFF="${COMBINED_DIFF}
$(git -C "$WORKTREE_PATH" diff --no-index /dev/null "$WORKTREE_PATH/$uf" 2>/dev/null || true)"
done
# Extract function names from diff hunk headers (@@...@@ func Name or func (r *T) Name)
# These identify the enclosing function for ANY changed line, not just added declarations.
# Use `go tool cover -func` format for matching: bare name for functions, receiver for methods.
CHANGED_FUNC_NAMES=$(echo "$COMBINED_DIFF" | grep -oE '^@@.*@@ func (\([^)]*\) )?[A-Za-z_][A-Za-z0-9_]*' | sed 's/^@@.*@@ //' | sort -u)
# Also catch newly added function declarations (on added lines)
NEW_FUNCS=$(echo "$COMBINED_DIFF" | grep -E '^\+.*func ' | grep -v '^\+\+\+' | sed 's/^+//' | grep -oE 'func (\([^)]*\) )?[A-Za-z_][A-Za-z0-9_]*' | sed 's/^func //' | sort -u)
CHANGED_FUNC_NAMES=$(printf '%s\n%s' "$CHANGED_FUNC_NAMES" "$NEW_FUNCS" | sort -u | grep -v '^$')
```

**Matching logic:** Cross-reference per-file to avoid ambiguity (e.g., `Run`
in `pkg/a/a.go` vs `pkg/b/b.go`). For each file in `CHANGED_SRC`:

1. Get the functions changed in that file from `COMBINED_DIFF` (hunk headers
   and added `func` lines scoped to that file)
2. Get the uncovered functions in that file from `UNCOVERED_FUNCS` (Step D
   stores entries as `file:func1, func2`)
3. Intersect the two lists — only generate tests for functions that are BOTH
   changed AND uncovered in the same file

If no functions match across any file (all changed functions are already
covered), report this and return to the calling command's next step.

## Per-target test generation

Generate tests appropriate for the detected project type. For each target
uncovered function:

1. **Read the source file** and understand the function signature, parameters,
   return types, and dependencies.

2. **Check for existing test files** and **detect testing conventions** per
   language.

### Go

- Check for existing test files following patterns from `${CLAUDE_PLUGIN_ROOT}/skills/address-review/test-generation.md` Steps 4.5b-4.5c:
  ```bash
  ls "$WORKTREE_PATH/${FILE%.*}_test.go" 2>/dev/null || ls "$WORKTREE_PATH/$(dirname "$FILE")"/*_test.go 2>/dev/null
  ```
- Detect: stdlib `testing` vs `testify`, table-driven patterns
  (`tests := []struct`), naming conventions
- Generate table-driven tests with `t.Run()`, `t.Parallel()`, following
  `test-gen.md` patterns
- Verify: `go -C "$WORKTREE_PATH" test ./path/to/package/... -run "TestFunctionName" -v`
- Re-run coverage: `go -C "$WORKTREE_PATH" test -coverprofile=.local/state/coverage.out ./... 2>/dev/null || true`

### Node/TypeScript

- Check for existing test files: `*.test.ts`, `*.spec.ts`, `__tests__/*.ts`
- Detect: vitest vs jest vs mocha, describe/it patterns, assertion style
- Generate tests following detected conventions (describe blocks, beforeEach setup)
- Verify: `(cd "$WORKTREE_PATH" && npx vitest run <test-file>)` or `(cd "$WORKTREE_PATH" && npx jest <test-file>)`

### Rust

- Check for existing `#[cfg(test)]` modules in the same file or `tests/`
  directory
- Detect: built-in `#[test]` vs `rstest` vs `proptest`
- Generate test functions with `#[test]` attribute, `assert_eq!` / `assert!`
  macros
- Verify: `(cd "$WORKTREE_PATH" && cargo test <test-name>)`

### Python

- Check for existing test files: `test_*.py`, `*_test.py` in the same or
  `tests/` directory
- Detect: pytest vs unittest, fixture patterns, parametrize decorators
- Generate pytest functions with `@pytest.mark.parametrize` for multiple cases
- Verify: `(cd "$WORKTREE_PATH" && pytest <test-file> -v)`

## Test scenarios (all languages)

For each target function include:

- Happy path with typical inputs
- Edge cases (nil/empty/boundary values)
- Error scenarios (invalid input, expected failures)
- If existing table/parametrized tests exist for the function, add new cases
  to them
- If no test exists, create a new test following project conventions

## Persist count and return

Track the number of tests generated and persist in the state file:

```bash
set_loop_json_field "$STATE_FILE" "coverage_tests_generated" "$TESTS_GENERATED" "$WORKFLOW_STATE_PATH"
```

Generated test files will be staged and committed alongside other changes by
the calling command. Return to Step C and rerun coverage once; Step E stops
incomplete if the threshold is still not met.

If tests cannot be generated or made to pass, follow Step E.4 with:

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=coverage-test-generation-failed
```

Stop without returning to the calling workflow or emitting its success marker.
