# Test Generation for Review Fixes

## Step 4.5: Generate Tests for Testable Fixes

After all fixes are applied (Step 4 complete), generate tests for fixes classified as `testable` in Step 4e.

### Testability Guidelines

**DO write tests for:**
- Bug fixes that change function/method output or behavior
- Logic changes (conditionals, error handling, edge cases)
- New or modified validation rules
- Data transformation or parsing changes
- API response changes
- Concurrency or race condition fixes
- Any change that alters what a function returns, how it mutates state, or what side effects it produces

**DO NOT write tests for:**
- Removing or adding comments
- Adding/changing log statements
- Formatting or whitespace changes
- Import reordering
- Variable/function renames (unless public API)
- Documentation updates
- Config file tweaks that don't affect runtime behavior
- Typo fixes in non-user-facing strings

**Rule of thumb:** If the change affects something a caller or user could observe — a return value, an error, a side effect, an HTTP response — it's testable and should get a test. If it's purely cosmetic or informational, skip it.

### 4.5a. Identify Testable Fixes

Review the tracking notes from Step 4e. Collect all fixes marked `testable` along with their affected function/method and package.

If no fixes are testable, skip to Step 5.

### 4.5b. Check for Existing Tests

For each testable fix, check if a test file already exists:

```bash
ls "${FILE%.*}_test.go" 2>/dev/null || ls "$(dirname "$FILE")"/*_test.go 2>/dev/null
```

If a test file exists, look for existing table-driven tests for the affected function across ALL `*_test.go` files in the package (tests may be split across multiple files):

```bash
grep -n "func Test.*${FUNCTION_NAME}" "$(dirname "$FILE")"/*_test.go 2>/dev/null
```

### 4.5c. Detect Testing Patterns

Examine existing test files in the same package to detect conventions:

- **Test framework**: stdlib `testing` or `testify` (check for `github.com/stretchr/testify` imports)
- **Table-driven pattern**: look for `tests := []struct` or `tt := []struct` patterns
- **Naming conventions**: `Test_functionName` vs `TestFunctionName` vs `TestPackage_FunctionName`
- **Helper patterns**: test fixtures, setup/teardown, `testdata/` directory usage

Match these conventions when writing new tests.

### 4.5d. Write Tests

For each testable fix:

**If an existing table-driven test exists for the affected function:**
- Add a new test case to the existing table that covers the scenario the review comment flagged
- Name the case descriptively (e.g., `"returns error when input is nil"`)

**If no existing test exists:**
- Create a new table-driven test function in the appropriate `_test.go` file
- Follow the package's detected conventions (4.5c)
- Include at least:
  - A test case that exercises the fixed behavior (the "green" case)
  - A test case for the edge case or incorrect input the review comment identified

### 4.5e. Verify Tests Pass

Run the tests to confirm they pass with the fix applied:

```bash
go test ./path/to/package/... -run "TestFunctionName" -v
```

All new tests must pass (green). If any fail, fix the test until green.

**Note on red-green:** The traditional red-green cycle (verify test fails without fix, then passes with fix) is impractical here because fixes are applied in batch during Step 4. The review comment itself serves as the "red" evidence — it identified broken or incorrect behavior. The green confirmation in this step validates the test correctly covers the fixed behavior.
