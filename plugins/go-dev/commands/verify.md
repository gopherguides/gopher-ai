---
argument-hint: "[path]"
description: "Run full pre-push verification: build, test, lint, vet, dev-server checks"
model: claude-opus-4-6
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

**If `$ARGUMENTS` is empty or not provided:**

Run verification on entire project.

**Usage:** `/verify [path]`

**Examples:**

- `/verify` - Verify entire project
- `/verify ./pkg/...` - Verify specific package
- `/verify ./cmd/server/...` - Verify specific command path

**Workflow:**

1. Run `go vet` for static analysis
2. Run `go build` to ensure compilation succeeds
3. Run `go test` to verify all tests pass
4. Run `golangci-lint` (if available) with auto-fix
5. Check dev-server logs (Air, Vite, etc.) for runtime errors
6. Fix issues automatically where safe, report others
7. Loop until all blocking checks pass

This is your pre-push sanity check. Run it anytime before pushing.

Set default target path:

```bash
TARGET_PATH="./..."
echo "Verifying: $TARGET_PATH"
```

Proceed with verification.

---

**If `$ARGUMENTS` is provided:**

Run verification on the specified path.

## Loop Initialization

Initialize persistent loop to ensure all checks pass:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "verify" "COMPLETE"`

## Configuration

Parse target path from arguments:

```bash
TARGET_PATH="${ARGUMENTS:-./...}"
echo "Verifying: $TARGET_PATH"
```

---

## Step 1: go vet (Static Analysis)

Run `go vet` to catch suspicious constructs:

```bash
go vet $TARGET_PATH 2>&1
```

**Parse vet output:**
- Format: `file.go:line:col: message`
- Common issues: Printf format mismatches, unreachable code, shadowed variables

**If issues found:**

Report them with file:line references and fix them:

1. Read the failing files around the reported lines
2. Apply minimal fixes (format string mismatches, unreachable code removal, etc.)
3. Re-run `go vet $TARGET_PATH` to confirm fixes

**If clean:** Proceed to Step 2.

---

## Step 2: go build (Compilation)

**This check is BLOCKING.** Build must pass before verification can complete.

Run `go build` to ensure code compiles:

```bash
go build $TARGET_PATH 2>&1
```

**If errors found:**

Auto-fix using proven build-fix patterns:

1. Parse errors by file and group related errors
2. Read failing files to understand context
3. Identify root cause and apply minimal fixes:
   - Missing imports → add import or run `go get`
   - Unused imports → remove them
   - Type mismatches → fix type conversions
   - Missing dependencies → `go mod tidy`
   - Undefined variables/functions → check spelling, scope
4. Re-run `go build $TARGET_PATH` until clean

**Generated file detection:** Do NOT edit these directly:
- `*_templ.go` → fix the source `.templ` file, then run `templ generate`
- Files in sqlc output directories → fix the `.sql` file, then run `sqlc generate`
- `*_mock.go` → fix the interface, then regenerate mocks

**Cycle detection:** Track error signatures across iterations. If the same error reappears after being "fixed," try an alternative approach. If stuck after 5 attempts on the same error, ask the user for guidance.

**If clean:** Proceed to Step 3.

---

## Step 3: go test (Test Suite)

**This check is BLOCKING.** All tests must pass before verification can complete.

Run all tests:

```bash
go test $TARGET_PATH -count=1 2>&1
```

**If all tests pass:** Proceed to Step 4.

**If tests fail:**

Report failures with details:

```
Tests failed:

FAIL: TestName (0.01s)
    file_test.go:67: Expected X, got Y

N of M tests failed.
```

**DO NOT auto-fix test logic.** Test failures indicate real problems that need human judgment.

Ask the user: "Tests are failing (shown above). Would you like to investigate and fix them?"

| Option | Action |
|--------|--------|
| Yes, fix tests | Read test files, understand failures, attempt targeted fixes |
| No, stop here | Exit without completing — user will fix manually |

If "Yes": Read the failing test files and the code under test, understand the root cause, and apply targeted fixes. Re-run tests. If tests still fail after 3 attempts, ask the user for guidance.

If "No": **STOP** — do not output `<done>COMPLETE</done>`.

---

## Step 4: golangci-lint (Code Quality)

Check if golangci-lint is installed:

```bash
command -v golangci-lint >/dev/null 2>&1 && echo "FOUND" || echo "NOT_FOUND"
```

**If not installed:**

```
golangci-lint not found, skipping lint checks.
```

Proceed to Step 5.

**If installed:**

Run with auto-fix:

```bash
golangci-lint run --fix $TARGET_PATH 2>&1
```

**If all clean after auto-fix:** Proceed to Step 5.

**If unfixable issues remain:**

Report them (non-blocking):

```
golangci-lint found unfixable issues:

file.go:45 [errcheck] Error return value not checked
file.go:23 [gocritic] Consider using errors.Is

These require manual review but are non-blocking.
```

Proceed to Step 5.

---

## Step 5: Dev-Server Logs (Runtime Checks)

Check for Air or other dev-server build systems.

### 5a. Detect Air

```bash
if [ -f .air.toml ]; then
  AIR_CONFIG=".air.toml"
elif [ -f air.toml ]; then
  AIR_CONFIG="air.toml"
fi
```

**If Air config found:**

Extract log configuration:

```bash
TMP_DIR=$(awk '/^tmp_dir[[:space:]]*=/ { gsub(/.*=[[:space:]]*"|".*/, ""); print; exit }' "$AIR_CONFIG")
TMP_DIR="${TMP_DIR:-tmp}"

BUILD_LOG=$(awk '/^\[build\]/,/^\[/ { if ($0 ~ /^[[:space:]]*log[[:space:]]*=/) { gsub(/.*=[[:space:]]*"|".*/, ""); print; exit } }' "$AIR_CONFIG")
BUILD_LOG="${BUILD_LOG:-build-errors.log}"
```

**Log path priority** (use first that exists):
1. `${TMP_DIR}/air-combined.log` — primary combined log (compilation + template + SQL errors)
2. `${TMP_DIR}/${BUILD_LOG}` — Air's configured build error log

### 5b. Stale Log Check

If a log exists, verify it's fresh by comparing its modification time to the most recently changed source file. If source files are newer than the log, skip it — the log is stale.

### 5c. Read and Parse Log

If the log is fresh, read the tail:

```bash
tail -200 "$LOG_PATH"
```

Parse for errors:
- Go compilation errors: `file.go:line:col: message`
- templ errors: `Error in file.templ at line X`
- sqlc errors: `sqlc generate: message`
- Runtime panics: `panic:` or `fatal error:`

**If errors found:** Report them (non-blocking). These may indicate template or runtime issues worth reviewing.

**If clean:** Report clean status.

### 5d. No Air Detected

If no Air config found:

```
No Air config detected, skipping dev-server log checks.
```

Proceed to Step 6.

---

## Step 6: Summary

Generate a summary table:

```
Verification Summary

| Check          | Status                          |
|----------------|---------------------------------|
| go vet         | Passed / Fixed N issues         |
| go build       | Passed                          |
| go test        | Passed (N tests)                |
| golangci-lint  | Passed / N warnings / Skipped   |
| Dev-server logs| Clean / N warnings / Skipped    |

Your code is ready to push!
```

If auto-fixes were applied, list them:

```
Auto-fixes applied:
- file.go:12 - Added missing import "fmt"
- file.go:45 - Fixed formatting (gofmt)
```

---

## Notes

- Auto-fixes build errors and lint issues using proven patterns from `/build-fix` and `/lint-fix`
- **Blocks on**: build errors, test failures (must be resolved)
- **Reports but does not block on**: vet issues, unfixable lint, dev-server warnings
- Test failures are never auto-fixed without user approval to avoid masking real bugs
- For Air projects, `air-combined.log` is the authoritative log source (not `build-errors.log`)

---

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. `go vet` has been run (issues fixed or reported)
2. `go build $TARGET_PATH` exits with status 0
3. `go test $TARGET_PATH` exits with status 0
4. `golangci-lint` has been run or skipped (if not installed)
5. Dev-server logs have been checked or skipped (if no config)

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, issues may remain.

**NEVER output `<done>COMPLETE</done>` if:**
- Build errors remain
- Tests are failing
- You've iterated 15+ times (ask the user for guidance instead)

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.
