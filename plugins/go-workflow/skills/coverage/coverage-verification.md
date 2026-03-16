# Coverage Verification (Shared Reference)

This document is referenced by both `/ship` and `/start-issue` commands. Follow Steps A through F using the parameters provided by the calling command.

## Prerequisites

The calling command MUST set these variables before invoking this workflow:

| Variable | Description | Example |
|----------|-------------|---------|
| `BASE_BRANCH` | Branch to diff against | `origin/main` |
| `STATE_FILE` | **Absolute path** to the loop state JSON file | `/path/to/.claude/ship.loop.local.json` |
| `SKIP_COVERAGE` | Whether to skip coverage entirely | `true` or `false` |
| `COVERAGE_THRESHOLD` | Minimum coverage percentage for changed files | `60` |

**Worktree note:** When running in a worktree, `STATE_FILE` MUST be an absolute path to the state file (which lives in the original repo's `.claude/` directory, not the worktree). Coverage artifacts (`.claude/coverage.out`) are written relative to the current working directory — ensure `.claude/` exists via `mkdir -p .claude` before running coverage commands.

## Step A: Skip Conditions

Skip this entire workflow (return to the calling command's next step) if ANY of these are true:

- `SKIP_COVERAGE` is `true`
- No source files changed (only tests, docs, configs — see Step B)

## Step B: Detect Changed Source Files

Detect changed files including committed, uncommitted, staged, and untracked files (uncommitted/untracked changes are common when called from `/start-issue` before the commit step):

```bash
mkdir -p .claude
rm -f .claude/coverage.out .claude/coverage.json 2>/dev/null
CHANGED_FILES=$( (git diff --name-only "${BASE_BRANCH}...HEAD" 2>/dev/null; git diff --name-only HEAD 2>/dev/null; git diff --name-only --cached HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null) | sort -u )
```

The `rm -f` removes stale coverage artifacts from prior runs to prevent false results if the current coverage command fails.

Filter to source files per detected project type, excluding test files, generated files, and vendored code:

**Go** (go.mod exists):
```bash
CHANGED_SRC=$(echo "$CHANGED_FILES" | grep '\.go$' \
  | grep -v '_test\.go$' \
  | grep -v '_templ\.go$' \
  | grep -v '_mock\.go$' \
  | grep -v '\.pb\.go$' \
  | grep -v '_gen\.go$' \
  | grep -v '^vendor/' \
  || true)
```

**Node/TypeScript** (package.json exists):
```bash
CHANGED_SRC=$(echo "$CHANGED_FILES" | grep -E '\.(ts|tsx|js|jsx)$' \
  | grep -v -E '\.(test|spec)\.' \
  | grep -v '^node_modules/' \
  | grep -v '^dist/' \
  || true)
```

**Rust** (Cargo.toml exists):
```bash
CHANGED_SRC=$(echo "$CHANGED_FILES" | grep '\.rs$' \
  | grep -v -E '(^tests/|/tests/)' \
  || true)
```

**Python** (pyproject.toml or setup.py exists):
```bash
CHANGED_SRC=$(echo "$CHANGED_FILES" | grep '\.py$' \
  | grep -v -E '(^tests?/|/tests?/|test_[^/]*\.py$|_test\.py$|conftest\.py$)' \
  || true)
```

If `CHANGED_SRC` is empty → skip (no source files to measure coverage for). Return to calling command's next step.

## Step C: Run Coverage

Run the coverage tool appropriate for the detected project type. Store coverage output for analysis.

**Go** (built-in — always available):
```bash
go test -coverprofile=.claude/coverage.out ./... 2>/dev/null || true
go tool cover -func=.claude/coverage.out 2>/dev/null
```

Then extract coverage for changed files specifically:

```bash
for f in $CHANGED_SRC; do
  grep "^${f}:" .claude/coverage.out 2>/dev/null
done
```

Parse the `go tool cover -func` output — each line shows `file:line: functionName  coverage%`. Extract functions with 0% or low coverage in changed files.

**Node/TypeScript**:
```bash
if grep -q '"vitest"' package.json 2>/dev/null; then
  npx vitest run --coverage --coverage.reporter=json-summary 2>/dev/null || true
  COVERAGE_JSON="coverage/coverage-summary.json"
elif grep -q '"jest"' package.json 2>/dev/null; then
  npx jest --coverage --coverageReporters=json-summary 2>/dev/null || true
  COVERAGE_JSON="coverage/coverage-summary.json"
elif grep -q '"c8"' package.json 2>/dev/null || grep -q '"nyc"' package.json 2>/dev/null; then
  npx c8 --reporter=json-summary npm test 2>/dev/null || true
  COVERAGE_JSON="coverage/coverage-summary.json"
fi
```

Parse `coverage-summary.json` for per-file coverage. Both vitest, jest, and c8 (with `json-summary` reporter) use this format:
```json
{
  "path/to/file.ts": { "lines": { "total": 100, "covered": 75, "pct": 75.0 }, ... },
  "total": { "lines": { "total": 500, "covered": 350, "pct": 70.0 }, ... }
}
```

Extract `lines.pct` for each changed file to compute per-file and aggregate coverage.

**Rust**:
```bash
if command -v cargo-llvm-cov >/dev/null 2>&1; then
  cargo llvm-cov --json > .claude/coverage.json 2>/dev/null || true
elif command -v cargo-tarpaulin >/dev/null 2>&1; then
  cargo tarpaulin --out Json --output-dir .claude 2>/dev/null || true
fi
```

**Python**:
```bash
if command -v pytest >/dev/null 2>&1 && python3 -c "import pytest_cov" 2>/dev/null; then
  pytest --cov --cov-report=json:.claude/coverage.json 2>/dev/null || true
elif command -v coverage >/dev/null 2>&1; then
  coverage run -m pytest 2>/dev/null && coverage json -o .claude/coverage.json 2>/dev/null || true
fi
```

If the coverage tool binary is genuinely missing (e.g., `cargo-llvm-cov` not installed) → display a warning ("Coverage tool unavailable, skipping coverage gate") and return to calling command's next step. However, if the coverage command ran and produced output (e.g., `coverage.out` exists with content, or JSON file exists with data), the tool did NOT fail — proceed to Step D even if coverage is 0%. Do NOT treat low coverage as a tool failure.

## Step D: Analyze Changed-File Coverage

Parse the coverage output and compute per-file coverage for changed files only:

1. For each file in `CHANGED_SRC`, extract its line or function coverage percentage
2. Identify specific uncovered functions/methods in changed files
3. Calculate the aggregate coverage percentage across all changed source files

For Go, parse the raw coverprofile to compute **statement-weighted** coverage (not function-average). The coverprofile format is:
```
mode: set
file.go:startLine.startCol,endLine.endCol numStatements hitCount
```

Use statement counts weighted by whether they were hit:

```bash
COVERAGE_FUNC=$(go tool cover -func=.claude/coverage.out 2>/dev/null)
AGGREGATE_COVERAGE=""
FILE_REPORT=""
UNCOVERED_FUNCS=""
TOTAL_STMTS=0
TOTAL_COVERED=0

for f in $CHANGED_SRC; do
  FILE_STMTS=$(grep "^${f}:" .claude/coverage.out 2>/dev/null | awk '{
    split($2, a, " "); stmts=$2; hit=$3
    total+=stmts; if(hit>0) covered+=stmts
  } END {printf "%d %d", total, covered}')
  FILE_TOTAL=$(echo "$FILE_STMTS" | awk '{print $1}')
  FILE_COVERED=$(echo "$FILE_STMTS" | awk '{print $2}')

  if [ "$FILE_TOTAL" -eq 0 ] 2>/dev/null; then
    FILE_REPORT="${FILE_REPORT}\n| ${f} | N/A (no statements) | — |"
    continue
  fi

  FILE_COV=$(awk "BEGIN {printf \"%.1f\", ($FILE_COVERED/$FILE_TOTAL)*100}")
  TOTAL_STMTS=$((TOTAL_STMTS + FILE_TOTAL))
  TOTAL_COVERED=$((TOTAL_COVERED + FILE_COVERED))

  FILE_FUNC_LINES=$(echo "$COVERAGE_FUNC" | grep "^${f}:" | grep -v "^total:")
  UNCOV=$(echo "$FILE_FUNC_LINES" | awk '$NF == "0.0%" {print $2}' | paste -sd ", " -)
  UNCOV_DISPLAY="${UNCOV:-—}"
  FILE_REPORT="${FILE_REPORT}\n| ${f} | ${FILE_COV}% | ${UNCOV_DISPLAY} |"

  if [ -n "$UNCOV" ]; then
    UNCOVERED_FUNCS="${UNCOVERED_FUNCS}\n${f}:${UNCOV}"
  fi
done

if [ "$TOTAL_STMTS" -gt 0 ]; then
  AGGREGATE_COVERAGE=$(awk "BEGIN {printf \"%.1f\", ($TOTAL_COVERED/$TOTAL_STMTS)*100}")
else
  AGGREGATE_COVERAGE="0.0"
fi
```

For **Node/TypeScript**, parse JSON coverage summary — extract `lines.pct` for each changed file from the JSON output.

For **Rust**, parse the JSON output from llvm-cov or tarpaulin — extract per-file line coverage.

For **Python**, parse `coverage.json` — extract `files.<path>.summary.percent_covered` for each changed file.

## Step E: Coverage Gate Decision

**MANDATORY RULE — NO EXCEPTIONS:**

When coverage is below `COVERAGE_THRESHOLD`, you MUST call `AskUserQuestion` to let the user decide. You MUST NOT:
- Decide on your own to skip, waive, or bypass the coverage gate
- Rationalize that low coverage is "pre-existing," "inherited," or "not caused by your changes"
- Argue that the threshold does not apply because changes were small, trivial, or limited to a few lines
- Conclude that coverage is "effectively" acceptable despite being numerically below threshold
- Claim that other tests (template tests, integration tests, etc.) make up for low unit coverage
- Add commentary, analysis, or justification between the coverage report and the `AskUserQuestion` call
- Proceed to the next step without calling `AskUserQuestion` when coverage < threshold

**Design philosophy: "if you touch it, you own it."** The entire file's coverage counts, regardless of which lines you changed or whether uncovered code existed before your changes. This is intentional. The purpose of this gate is to **improve coverage in the codebase over time** — every touched file is an opportunity. Only the USER can decide to proceed with low coverage. You cannot make that decision.

**If coverage < `COVERAGE_THRESHOLD`: your ONLY permitted action is to display the report (Step E.1) and then IMMEDIATELY call `AskUserQuestion` (Step E.2). Any other action is a violation of this workflow.**

### Step E.1: Display Coverage Report

Output ONLY the coverage table and aggregate line. Do NOT add any analysis, explanation, or commentary. Do NOT discuss why coverage is low or whether the low coverage is justified.

```
## Coverage Report (Changed Files)

| File | Coverage | Uncovered Functions |
|------|----------|-------------------|
<one row per file from CHANGED_SRC, using FILE_REPORT from Step D>

**Changed-file coverage: {AGGREGATE_COVERAGE}% (threshold: {COVERAGE_THRESHOLD}%)**
```

### Step E.2: Gate Decision

Apply IMMEDIATELY after displaying the report — no intervening text or analysis:

- **Coverage >= `COVERAGE_THRESHOLD`** → pass. Return to calling command's next step.
- **Coverage < `COVERAGE_THRESHOLD`** → you MUST call `AskUserQuestion` with this exact question and options:

  **Question:** "Changed files have {AGGREGATE_COVERAGE}% coverage (threshold: {COVERAGE_THRESHOLD}%). What would you like to do?"

  **Options (Go projects):**
  1. "Generate tests for all uncovered functions in changed files"
  2. "Generate tests only for functions I added or modified"
  3. "Proceed without additional tests"
  4. "Show me the uncovered functions so I can decide"

  **Options (non-Go projects):** Omit option 2 — changed-function detection is only supported for Go. Present options 1, 3, and 4 only.

  Handle the user's choice:
  - Option 1 → proceed to Step F in **all uncovered functions** mode
  - Option 2 (Go only) → proceed to Step F in **changed functions only** mode
  - Option 3 → return to calling command's next step
  - Option 4 → display the full `UNCOVERED_FUNCS` list with file locations, then re-ask with options 1-3 (or 1-2-3 for Go)

- **No test files exist at all** (coverage output is empty or all functions show 0%) → you MUST call `AskUserQuestion` with:
  "No test files found for changed packages. Changed files have 0% coverage (threshold: {COVERAGE_THRESHOLD}%). What would you like to do?"
  Options:
  1. "Generate initial tests for changed files"
  2. "Proceed without tests"

  You MUST NOT decide to skip test generation on your own. Only the user can make this decision.

- **Coverage tool genuinely failed or unavailable** → warn and proceed ONLY if the tool genuinely failed (non-zero exit code AND no usable output, or missing binary). If `go test -coverprofile` produced a `coverage.out` file with content, or if the JSON coverage file exists with data, the tool did NOT fail — proceed with coverage analysis even if coverage is 0%.

### Step E.3: Persist Result

Persist `coverage_result` in state file:

```bash
TMP="${STATE_FILE}.tmp"
jq --arg cr "$AGGREGATE_COVERAGE" '.coverage_result = $cr' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## Step F: Test Generation for Uncovered Code

**Mode selection** (set by Step E.2 user choice):

- **All uncovered functions mode** (option 1 or no-test-files path): Generate tests for every uncovered function in `CHANGED_SRC`, as listed in `UNCOVERED_FUNCS` from Step D.
- **Changed functions only mode** (option 2, Go only): Restrict test generation to Go functions whose bodies were added or modified. Identify changed functions by mapping diff hunks to their enclosing function using both committed and worktree changes:
  ```bash
  # Combine committed + staged + unstaged diffs to match Step B's file detection
  COMBINED_DIFF=$( (git diff "${BASE_BRANCH}...HEAD" -- $CHANGED_SRC 2>/dev/null; git diff HEAD -- $CHANGED_SRC 2>/dev/null; git diff --cached HEAD -- $CHANGED_SRC 2>/dev/null) )
  # Extract function names from diff hunk headers (@@...@@ func Name) — these identify
  # the enclosing function for ANY changed line, not just added func declarations
  CHANGED_FUNC_NAMES=$(echo "$COMBINED_DIFF" | grep -oE '^@@.*@@.*func (\([^)]*\) )?[A-Za-z_][A-Za-z0-9_]*' | grep -oE 'func (\([^)]*\) )?[A-Za-z_][A-Za-z0-9_]*' | awk '{print $NF}' | sort -u)
  # Also catch newly added functions (func declaration on an added line)
  NEW_FUNCS=$(echo "$COMBINED_DIFF" | grep -E '^\+.*func [A-Z]' | grep -oE 'func (\([^)]*\) )?[A-Za-z_][A-Za-z0-9_]*' | awk '{print $NF}' | sort -u)
  CHANGED_FUNC_NAMES=$(printf '%s\n%s' "$CHANGED_FUNC_NAMES" "$NEW_FUNCS" | sort -u | grep -v '^$')
  ```
  Cross-reference `CHANGED_FUNC_NAMES` with `UNCOVERED_FUNCS`. Only generate tests for functions that appear in BOTH lists (changed AND uncovered). If no functions match (all changed functions are already covered), report this and return to calling command's next step.

Generate tests appropriate for the detected project type. For each target uncovered function:

1. **Read the source file** and understand the function signature, parameters, return types, and dependencies

2. **Check for existing test files** and **detect testing conventions** per language:

**Go:**
- Check for existing test files following patterns from `${CLAUDE_PLUGIN_ROOT}/skills/address-review/test-generation.md` Steps 4.5b-4.5c:
  ```bash
  ls "${FILE%.*}_test.go" 2>/dev/null || ls "$(dirname "$FILE")"/*_test.go 2>/dev/null
  ```
- Detect: stdlib `testing` vs `testify`, table-driven patterns (`tests := []struct`), naming conventions
- Generate table-driven tests with `t.Run()`, `t.Parallel()`, following `test-gen.md` patterns
- Verify: `go test ./path/to/package/... -run "TestFunctionName" -v`
- Re-run coverage: `go test -coverprofile=.claude/coverage.out ./... 2>/dev/null || true`

**Node/TypeScript:**
- Check for existing test files: `*.test.ts`, `*.spec.ts`, `__tests__/*.ts`
- Detect: vitest vs jest vs mocha, describe/it patterns, assertion style
- Generate tests following detected conventions (describe blocks, beforeEach setup)
- Verify: `npx vitest run <test-file>` or `npx jest <test-file>`

**Rust:**
- Check for existing `#[cfg(test)]` modules in the same file or `tests/` directory
- Detect: built-in `#[test]` vs `rstest` vs `proptest`
- Generate test functions with `#[test]` attribute, `assert_eq!` / `assert!` macros
- Verify: `cargo test <test-name>`

**Python:**
- Check for existing test files: `test_*.py`, `*_test.py` in the same or `tests/` directory
- Detect: pytest vs unittest, fixture patterns, parametrize decorators
- Generate pytest functions with `@pytest.mark.parametrize` for multiple cases
- Verify: `pytest <test-file> -v`

3. **Include test scenarios** for all languages:
   - Happy path with typical inputs
   - Edge cases (nil/empty/boundary values)
   - Error scenarios (invalid input, expected failures)
   - If existing table/parametrized tests exist for the function, add new cases to them
   - If no test exists, create a new test following project conventions

Track the number of tests generated and persist in state file:

```bash
TMP="${STATE_FILE}.tmp"
jq --argjson n "$TESTS_GENERATED" '.coverage_tests_generated = $n' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

Generated test files will be staged and committed alongside other changes.
