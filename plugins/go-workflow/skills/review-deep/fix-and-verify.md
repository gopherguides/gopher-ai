# Fix, Test Generation, Verification, and Commit

This document details the fix phase that runs after the review completes.

## Fix Iteration

Process findings in priority order (P0 first, then P1, P2, P3):

### For Each Finding

#### 1. Read and Evaluate

Read the file at the cited line range plus surrounding context (~10 lines above and below):

```bash
# Example: read lines 35-55 of the file
```

Evaluate the finding:
- Is this a real issue? Cross-reference with the code.
- Is it already handled elsewhere (e.g., error checked in a wrapper)?
- Is the pattern intentional (e.g., documented exception, performance trade-off)?

#### 2. Skip Criteria

Auto-skip (record skip reason) when:
- **Priority 3 AND confidence < 0.5**: Nit-level noise, not worth fixing
- **Finding is invalid**: The code is correct as written; the review was wrong
- **Finding is pre-existing**: Not introduced by this diff (should have been caught in review, but double-check)
- **Finding is intentional**: Documented exception or justified trade-off

For skipped findings, record: finding number, title, skip reason.

#### 3. Make the Fix

Apply the **minimal change** that addresses the finding. Follow existing patterns in the file:
- Match indentation, naming conventions, and style
- Prefer editing existing code over adding new code
- Don't refactor surrounding code -- fix only the flagged issue

#### 4. Track the Fix

Record: finding number, title, file(s) changed, whether the fix is testable.

A fix is **testable** if it changes observable behavior:
- Return values, errors, side effects
- HTTP responses, database writes
- Function output for given input
- Panic prevention

A fix is **not testable** if it's purely cosmetic:
- Comments, log messages, formatting
- Variable renames (unless public API)
- Import reordering, whitespace

---

## Parallel Fix Dispatch

When there are **3 or more findings targeting different files**, use parallel dispatch for faster resolution:

### 1. Group Findings by File

Findings in the same file must be handled by one subagent (sequential within file).

### 2. Group by Shared Test Files

If two source files are in the same Go package, they may share `_test.go` files. Check:

```bash
# For each pair of source files, check if they're in the same package
dirname "file1.go" == dirname "file2.go"
```

Files in the same package must be in the same group to avoid write conflicts on test files.

### 3. Dispatch Subagents

For each file group, dispatch an Agent subagent (sonnet) with:

- "You are fixing review findings in `{FILE_PATH}`. Working directory: `{PROJECT_ROOT}`."
- All findings for that file (title, body, line range, priority, category, confidence)
- "For each finding: read the file, evaluate validity, fix if valid (skip if not), generate test if testable. Report: STATUS (fixed/skipped), FILES_CHANGED, TEST_RESULTS, SKIPPED findings with reasons."

Dispatch all groups in parallel using `run_in_background: true`.

### 4. Collect Results

After all subagents complete, aggregate:
- Total FIXED count
- Total SKIPPED count with reasons
- All files changed
- All test results

Proceed to verification with combined results.

**Fall back to sequential processing** when:
- Fewer than 3 findings
- All findings target the same file

---

## Test Generation

For each fix marked as **testable**, generate a corresponding test.

### Check for Existing Tests

```bash
# Check if a test file exists for the source file
ls "${FILE%.*}_test.go" 2>/dev/null || ls "$(dirname "$FILE")"/*_test.go 2>/dev/null
```

### Check for Existing Table-Driven Tests

```bash
# Look for table-driven tests for the affected function
grep -n "func Test.*${FUNCTION_NAME}" "$(dirname "$FILE")"/*_test.go 2>/dev/null
```

### Detect Testing Patterns

Examine existing test files in the same package:

- **Test framework**: stdlib `testing` or `testify` (check for `github.com/stretchr/testify` imports)
- **Table-driven pattern**: `tests := []struct` or `tt := []struct`
- **Naming convention**: `Test_functionName` vs `TestFunctionName` vs `TestPackage_FunctionName`
- **Helper patterns**: test fixtures, `testdata/`, setup/teardown

Match these conventions.

### Write the Test

**If existing table-driven test exists for the function:**
- Add a new test case to the existing table
- Name descriptively (e.g., `"returns error when input is nil"`)

**If no existing test for the function:**
- Create a new table-driven test function in the appropriate `_test.go` file
- Follow the package's detected conventions
- Include at least:
  - A test case exercising the fixed behavior (the "green" case)
  - A test case for the edge case the finding identified

### Verify Test Passes

```bash
go test ./path/to/package/... -run "TestFunctionName" -v
```

All new tests must pass. If any fail, fix until green.

---

## Verification

After all fixes and tests are applied, run full verification:

### Go Projects (go.mod exists)

```bash
echo "=== Build ==="
go build ./...

echo "=== Tests ==="
go test ./...

echo "=== Lint ==="
golangci-lint run 2>/dev/null || true
```

### Other Project Types

**Node/TypeScript** (package.json exists):
```bash
npm run build && npm test
npm run lint 2>/dev/null || true
```

**Rust** (Cargo.toml exists):
```bash
cargo build && cargo test
cargo clippy 2>/dev/null || true
```

**Python** (pyproject.toml or setup.py exists):
```bash
pytest 2>/dev/null || python -m pytest
ruff check . 2>/dev/null || flake8 . 2>/dev/null || true
```

### Handling Failures

If any verification step fails:

1. Analyze the failure output
2. Identify which fix caused the failure
3. Fix the issue (the fix, not the original code)
4. Re-run the failing verification
5. Repeat until all pass

Do NOT proceed to commit until all verifications pass.

---

## Commit

Stage only files modified during this fix phase. Do NOT use `git add -A` -- it may capture unrelated changes.

```bash
# Stage only the specific files that were fixed
git add <file1> <file2> <file3>
```

Only commit if there are staged changes (some passes may have zero fixable findings):

```bash
if ! git diff --cached --quiet; then
  git commit -m "fix: address review-deep findings

- <brief summary of each fix>
- <tests added for testable fixes, if any>"
else
  echo "No changes to commit (all findings skipped or invalid)"
fi
```

Track the list of files edited during the fix phase and only stage those specific files.
