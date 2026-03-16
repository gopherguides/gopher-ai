---
argument-hint: "[--llm codex|gemini|ollama] [--passes <n>] [--no-merge] [--skip-coverage] [--coverage-threshold <n>]"
description: "Ship a PR: LLM review, coverage gate, e2e tests, push, CI watch, bot approval, merge"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion", "mcp__chrome-devtools-mcp__navigate_page", "mcp__chrome-devtools-mcp__take_screenshot", "mcp__chrome-devtools-mcp__list_console_messages", "mcp__chrome-devtools-mcp__list_network_requests", "mcp__chrome-devtools-mcp__fill", "mcp__chrome-devtools-mcp__click", "mcp__chrome-devtools-mcp__new_page"]
---

# Ship PR

## 0. State File Bootstrap

Before calling setup-loop, check if a state file already exists with a non-empty phase (re-entry).
If so, **skip** setup-loop to preserve custom fields (`args`, `pass`, `pr_number`, `base_branch`, `no_merge`, `llm`, `discovered_bots`).

```bash
STATE_FILE=".claude/ship.loop.local.json"
if [ -f "$STATE_FILE" ]; then
  EXISTING_PHASE=$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$EXISTING_PHASE" ]; then
    echo "Re-entry detected (phase: $EXISTING_PHASE) — skipping setup-loop to preserve state."
  fi
fi
```

**Only call setup-loop on fresh starts** (no state file or empty phase):

!`if [ -f ".claude/ship.loop.local.json" ] && [ -n "$(jq -r '.phase // empty' .claude/ship.loop.local.json 2>/dev/null)" ]; then echo "Re-entry detected — skipping setup-loop."; elif [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "ship" "SHIPPED" 50 "" '{"reviewing":"Resume LLM review pass.","fixing":"Continue fixing LLM review findings.","verifying":"Re-run verification: build, test, lint.","coverage-check":"Resume coverage analysis for changed files.","e2e-testing":"Resume e2e testing. Restart dev server if needed.","pushing":"Resume push and PR creation.","ci-watch":"Resume CI monitoring. Run gh pr checks and fix any failures.","bot-watching":"Resume bot approval polling (Step 11). Check discovered bots for approval status. If bots request changes, go to Step 12. If all approved, go to Step 13.","addressing":"Resume addressing bot review feedback (Steps 2-11 of address-review). After fixes, return to CI watch.","merging":"Verify CI green and bot approval, then merge the PR."}'; fi`

## 1. Parse Arguments

Parse `$ARGUMENTS` to extract:

- `--llm <value>`: LLM to use for reviews. Options: `codex` (default), `gemini`, `ollama`
- `--passes <n>`: Maximum LLM review passes (default: 3)
- `--no-merge`: Stop after bot approval, don't auto-merge
- `--skip-coverage`: Skip the coverage verification and e2e testing phases entirely
- `--coverage-threshold <n>`: Override default 60% threshold for changed-file coverage
- Remaining text: ignored

Store as `LLM_CHOICE`, `MAX_PASSES`, `NO_MERGE`, `SKIP_COVERAGE`, `COVERAGE_THRESHOLD` (default: 60).

**Persist arguments to state file** for re-entry recovery. After parsing, merge these fields into `.claude/ship.loop.local.json` using `jq`:

```bash
STATE_FILE=".claude/ship.loop.local.json"
TMP="$STATE_FILE.tmp"
jq --arg args "$ARGUMENTS" --arg llm "$LLM_CHOICE" --argjson pass 0 \
   --arg no_merge "$NO_MERGE" --arg pr_number "" --arg base_branch "" \
   --arg bot_review_baseline "" --arg discovered_bots "" --arg has_ci "" \
   --arg skip_coverage "$SKIP_COVERAGE" --arg coverage_threshold "$COVERAGE_THRESHOLD" \
   --arg coverage_result "" --argjson coverage_tests_generated 0 \
   --arg e2e_attempted "" --arg e2e_result "" --argjson e2e_pages_tested 0 \
   --arg review_clean "" \
   '. + {args: $args, llm: $llm, pass: $pass, no_merge: $no_merge, pr_number: $pr_number, base_branch: $base_branch, bot_review_baseline: $bot_review_baseline, discovered_bots: $discovered_bots, has_ci: $has_ci, skip_coverage: $skip_coverage, coverage_threshold: $coverage_threshold, coverage_result: $coverage_result, coverage_tests_generated: $coverage_tests_generated, e2e_attempted: $e2e_attempted, e2e_result: $e2e_result, e2e_pages_tested: $e2e_pages_tested, review_clean: $review_clean}' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## 2. Re-entry Check

Read the loop state file:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
STATE_FILE=".claude/ship.loop.local.json"
if [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE"
fi
```

If `PHASE` is set (non-empty), this is a re-entry from the stop-hook. Recover state from persisted fields using `jq`:

1. Read `args` field and re-parse to restore `LLM_CHOICE`, `MAX_PASSES`, `NO_MERGE`, `SKIP_COVERAGE`, `COVERAGE_THRESHOLD`
2. Read `pass`, `pr_number`, `base_branch`, `bot_review_baseline`, `llm`, `discovered_bots`, `has_ci`, `skip_coverage`, `coverage_threshold`, `coverage_result`, `coverage_tests_generated`, `e2e_attempted`, `e2e_result`, `e2e_pages_tested`, `review_clean` fields via `jq -r '.field // empty' "$STATE_FILE"`
3. If `review_clean` is `"true"`, set `REVIEW_CLEAN=true` to preserve the clean-review fast path after re-entry

Then skip to the corresponding phase:

- `reviewing` → go to Step 5
- `fixing` → go to Step 6
- `verifying` → go to Step 7
- `coverage-check` → go to Step 7.5
- `e2e-testing` → go to Step 7.6
- `pushing` → go to Step 9
- `ci-watch` → go to Step 10
- `bot-watching` → go to Step 11
- `addressing` → go to Step 12
- `merging` → go to Step 13

If `PHASE` is empty or unset, this is a fresh start. Continue to Step 3.

## 3. Detect Context

### 3a. Auto-detect base branch and PR

```bash
CURRENT_BRANCH=$(git branch --show-current)
PR_JSON=$(gh pr view --json number,baseRefName --jq '.' 2>/dev/null || echo "")
```

**If a PR exists**, use the PR's base branch (handles PRs targeting non-default branches like release branches):

```bash
if [ -n "$PR_JSON" ]; then
  PR_NUM=$(echo "$PR_JSON" | jq -r '.number')
  BASE_BRANCH=$(echo "$PR_JSON" | jq -r '.baseRefName')
  echo "PR #$PR_NUM targets: $BASE_BRANCH"
else
  BASE_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' | grep . || echo "main")
  PR_NUM=""
  echo "No PR found. Base: $BASE_BRANCH"
fi
```

**CRITICAL:** If `CURRENT_BRANCH` equals `BASE_BRANCH` (e.g., both are `main`), **STOP** — do not ship from the default branch. Inform the user and ask how to proceed.

Store `BASE_BRANCH` and `PR_NUM` (if found) in state file.

### 3b. Check for uncommitted changes

```bash
git status --porcelain
```

If there are uncommitted changes, ask the user: "There are uncommitted changes. Commit them before shipping, or abort?"

## 4. Prerequisite Check

Verify the selected LLM CLI is installed. Fail fast with install instructions if not found.

```bash
if [ "$LLM_CHOICE" = "codex" ]; then
  command -v codex >/dev/null 2>&1 || { echo "codex not found. Install: npm install -g @openai/codex"; exit 1; }
elif [ "$LLM_CHOICE" = "gemini" ]; then
  command -v gemini >/dev/null 2>&1 || { echo "gemini not found. Install: npm install -g @google/gemini-cli"; exit 1; }
elif [ "$LLM_CHOICE" = "ollama" ]; then
  command -v ollama >/dev/null 2>&1 || { echo "ollama not found. Install: brew install ollama"; exit 1; }
fi
```

If the check fails, report the error, clean up the loop state file, and **stop without emitting the completion promise** (the PR was NOT shipped):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" "ship"
```

Do NOT output `<done>SHIPPED</done>`. Simply inform the user of the missing prerequisite and stop.

---

## Phase 1: Local LLM Review (Steps 5-8)

### Step 5: Review Phase

Set phase to `reviewing`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
set_loop_phase ".claude/ship.loop.local.json" "reviewing"
PASS=$(jq -r '.pass // 0' ".claude/ship.loop.local.json")
```

**Note:** The pass counter is incremented in Step 8 (after the review completes and findings are committed), not here. This prevents burning a pass number if the session exits during the review and re-enters.

#### 5a. Generate Diff

Fetch the base branch to ensure the ref exists locally (handles cases where the base branch has never been checked out):

```bash
git fetch origin "$BASE_BRANCH" 2>/dev/null || true
DIFF=$(git diff "origin/${BASE_BRANCH}...HEAD")
```

If the diff is empty, skip the review loop entirely — nothing to review. Proceed to Step 9 (pushing).

#### 5b. Run LLM Review

Execute review based on `LLM_CHOICE`:

**Codex:**

```bash
codex review --base "origin/$BASE_BRANCH"
```

**Gemini:**

```bash
gemini <<EOF
Review the following code changes for bugs, security issues, performance problems, and best practice violations.

Report each finding with: file path, line number, severity (error/warning/suggestion), and description.
If there are no issues, respond with exactly: NO_ISSUES_FOUND

\`\`\`diff
$DIFF
\`\`\`
EOF
```

**Ollama:**

```bash
ollama run codellama <<EOF
Review the following code changes for bugs, security issues, performance problems, and best practice violations.

Report each finding with: file path, line number, severity (error/warning/suggestion), and description.
If there are no issues, respond with exactly: NO_ISSUES_FOUND

\`\`\`diff
$DIFF
\`\`\`
EOF
```

Capture the output as `FINDINGS`.

#### 5c. Parse Findings

- If output equals `NO_ISSUES_FOUND` or has fewer than 20 characters: review is clean → set `REVIEW_CLEAN=true` and **persist it to state file** (`jq '.review_clean = "true"'`) for re-entry recovery. Skip directly to Step 7.5 (coverage verification). After Steps 7.5 and 7.6 complete, skip Step 8's loop-back decision and proceed directly to Step 9 (pushing) — do NOT re-run LLM review when the review was already clean
- Otherwise: extract structured findings and display with pass number
- **Filter bot noise:** Silently discard findings containing usage-limit or quota messages
- **De-duplicate across passes:** If a finding from a previous pass appears again (same file, same line, same issue), skip it

### Step 6: Fix Phase

Set phase to `fixing`:

```bash
set_loop_phase ".claude/ship.loop.local.json" "fixing"
```

For each finding from Step 5c:

1. Read the relevant file and surrounding code context
2. Evaluate the finding — is it valid and actionable?
3. If valid: make the fix using Edit tool
4. If not valid or intentionally skipped: record the reason
5. For testable fixes (changes observable behavior): generate a corresponding test
   - Check for existing test files (`_test.go`, `_test.ts`, `test_*.py`)
   - If table-driven tests exist, add a new case
   - If no test exists, create one following project conventions
   - Verify the new test passes

Track counts: `FIXED`, `SKIPPED` (with reasons).

### Step 7: Verify Phase

Set phase to `verifying`:

```bash
set_loop_phase ".claude/ship.loop.local.json" "verifying"
```

Auto-detect project type and run appropriate verification:

**Go** (go.mod exists):

```bash
go build ./...
go test ./...
golangci-lint run 2>/dev/null || true
```

**Node/TypeScript** (package.json exists):

```bash
npm run build
npm test
npm run lint 2>/dev/null || true
```

**Rust** (Cargo.toml exists):

```bash
cargo build
cargo test
cargo clippy 2>/dev/null || true
```

**Python** (pyproject.toml or setup.py exists):

```bash
pytest 2>/dev/null || python -m pytest
ruff check . 2>/dev/null || flake8 . 2>/dev/null || true
```

If any verification fails: analyze, fix, re-run until all pass.

### Step 7.5: Coverage Verification (Changed Files)

**This step runs only on the final pass** (when `PASS >= MAX_PASSES - 1` or when findings were clean in Step 5c). Running coverage on every LLM review iteration would be wasteful.

Set phase to `coverage-check`:

```bash
set_loop_phase ".claude/ship.loop.local.json" "coverage-check"
```

#### 7.5a. Skip Conditions

Skip this entire step (proceed to Step 7.6) if ANY of these are true:

- `SKIP_COVERAGE` is `true` (user passed `--skip-coverage`)
- This is NOT the final pass (`PASS < MAX_PASSES - 1` AND findings were not clean)
- No source files changed (only tests, docs, configs — see 7.5b)

#### 7.5b. Detect Changed Source Files

```bash
CHANGED_FILES=$(git diff --name-only "origin/${BASE_BRANCH}...HEAD")
```

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

If `CHANGED_SRC` is empty → skip to Step 7.6 (no source files to measure coverage for).

#### 7.5c. Run Coverage

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
  # Vitest writes coverage/coverage-summary.json by default
  COVERAGE_JSON="coverage/coverage-summary.json"
elif grep -q '"jest"' package.json 2>/dev/null; then
  npx jest --coverage --coverageReporters=json-summary 2>/dev/null || true
  # Jest writes coverage/coverage-summary.json by default
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

If the coverage command fails or the coverage tool is not available → display a warning ("Coverage tool unavailable, skipping coverage gate") and proceed to Step 7.6. Do NOT block shipping.

#### 7.5d. Analyze Changed-File Coverage

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
# Extract per-function coverage for display and statement-weighted coverage for the gate
COVERAGE_FUNC=$(go tool cover -func=.claude/coverage.out 2>/dev/null)
AGGREGATE_COVERAGE=""
FILE_REPORT=""
UNCOVERED_FUNCS=""
TOTAL_STMTS=0
TOTAL_COVERED=0

for f in $CHANGED_SRC; do
  # Statement-weighted coverage from raw coverprofile
  # Each line: file:start,end numStmts hitCount
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

  # Identify uncovered functions from go tool cover -func output
  FILE_FUNC_LINES=$(echo "$COVERAGE_FUNC" | grep "^${f}:" | grep -v "^total:")
  UNCOV=$(echo "$FILE_FUNC_LINES" | awk '$NF == "0.0%" {print $2}' | paste -sd ", " -)
  UNCOV_DISPLAY="${UNCOV:-—}"
  FILE_REPORT="${FILE_REPORT}\n| ${f} | ${FILE_COV}% | ${UNCOV_DISPLAY} |"

  if [ -n "$UNCOV" ]; then
    UNCOVERED_FUNCS="${UNCOVERED_FUNCS}\n${f}:${UNCOV}"
  fi
done

# Statement-weighted aggregate across all changed files
if [ "$TOTAL_STMTS" -gt 0 ]; then
  AGGREGATE_COVERAGE=$(awk "BEGIN {printf \"%.1f\", ($TOTAL_COVERED/$TOTAL_STMTS)*100}")
else
  AGGREGATE_COVERAGE="0.0"
fi
```

For **Node/TypeScript**, parse JSON coverage summary — extract `lines.pct` for each changed file from the JSON output.

For **Rust**, parse the JSON output from llvm-cov or tarpaulin — extract per-file line coverage.

For **Python**, parse `coverage.json` — extract `files.<path>.summary.percent_covered` for each changed file.

#### 7.5e. Coverage Gate Decision

Display a coverage report:

```
## Coverage Report (Changed Files)

| File | Coverage | Uncovered Functions |
|------|----------|-------------------|
| pkg/auth/handler.go | 72% | ValidateToken, RefreshSession |
| pkg/api/routes.go | 45% | RegisterRoutes |
| internal/db/queries.go | 88% | — |

**Changed-file coverage: 62% (threshold: 60%)**
```

Decision logic:

- **Coverage >= `COVERAGE_THRESHOLD`** → pass. Display report and continue to Step 7.6
- **Coverage < `COVERAGE_THRESHOLD`** → ask user via `AskUserQuestion`:
  "Changed files have X% coverage (threshold: Y%). Options:\n1. Generate tests for uncovered functions\n2. Proceed without additional tests"
  - If "generate tests" → proceed to Step 7.5f
  - If "proceed" → continue to Step 7.6
- **No test files exist at all** (coverage output is empty or all functions show 0%) → report "No test files found for changed packages" and offer to generate initial tests via `AskUserQuestion`
- **Coverage tool failed or unavailable** → warn and proceed (non-blocking)

Persist `coverage_result` in state file:

```bash
TMP=".claude/ship.loop.local.json.tmp"
jq --arg cr "$AGGREGATE_COVERAGE" '.coverage_result = $cr' ".claude/ship.loop.local.json" > "$TMP" && mv "$TMP" ".claude/ship.loop.local.json"
```

#### 7.5f. Test Generation for Uncovered Code

Generate tests appropriate for the detected project type. For each uncovered function in changed files:

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
TMP=".claude/ship.loop.local.json.tmp"
jq --argjson n "$TESTS_GENERATED" '.coverage_tests_generated = $n' ".claude/ship.loop.local.json" > "$TMP" && mv "$TMP" ".claude/ship.loop.local.json"
```

Generated test files will be staged and committed in Step 8 alongside LLM review fixes.

### Step 7.6: E2E Smoke Testing (Optional)

This step performs browser-based smoke testing of web-facing changes using Chrome DevTools MCP. It is entirely optional and silently skips when conditions are not met.

#### 7.6a. Skip Conditions

Skip this entire step (proceed to Step 8) if ANY of these are true:

- `SKIP_COVERAGE` is `true` (user wants speed — skip all quality gates beyond build/test/lint)
- Chrome DevTools MCP tools are NOT available (check if `mcp__chrome-devtools-mcp__navigate_page` is in the available tools list — if not, skip silently)
- The project has NO web components (none of the indicators below are present)
- No web-facing files were changed in the diff

**Web component indicators** (at least one must be true):
- `.templ` files exist in the project
- Changed Go files contain HTTP handler patterns: `http.Handler`, `echo.Context`, `gin.Context`, `chi.Router`, `http.HandleFunc`
- `*.html`, `*.tsx`, `*.vue` files exist in the project

**Web-facing change detection** (recompute changed files if not already set — they may be empty if Step 7.5 was skipped):
```bash
if [ -z "$CHANGED_FILES" ]; then
  CHANGED_FILES=$(git diff --name-only "origin/${BASE_BRANCH}...HEAD")
fi
WEB_CHANGES=$(echo "$CHANGED_FILES" | grep -E '\.(templ|html|tsx|vue|jsx)$' || true)
HANDLER_CHANGES=$(echo "$CHANGED_FILES" | grep '\.go$' | while read f; do
  grep -l -E 'http\.Handler|echo\.Context|gin\.Context|chi\.Router|http\.HandleFunc|http\.ServeMux' "$f" 2>/dev/null
done || true)
```

If both `WEB_CHANGES` and `HANDLER_CHANGES` are empty → skip to Step 8.

#### 7.6b. Set Phase and Detect Dev Server

Set phase to `e2e-testing`:

```bash
set_loop_phase ".claude/ship.loop.local.json" "e2e-testing"
```

Detect the dev server command:

1. Check for Air config: `.air.toml` or `air.toml` → command: `air`
2. Check `Makefile` for targets: `run`, `serve`, `dev` → command: `make <target>`
3. Check `package.json` scripts: `dev`, `start` → command: `npm run dev` or `npm start`
4. Fallback for Go: `go run ./cmd/*/main.go` or `go run .`

Detect the server port:
- Parse Air config for proxy port or listen port
- Check for `PORT` env var patterns in code
- Check `.env` or `.env.local` for PORT
- Default: `8080` for Go, `3000` for Node, `5173` for Vite

#### 7.6c. Start Dev Server and Wait

Start the dev server in background:

```bash
# Start server in background
$DEV_SERVER_CMD &
SERVER_PID=$!
```

Wait for server readiness (poll up to 30 seconds):

```bash
for i in $(seq 1 30); do
  curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT" 2>/dev/null | grep -qE '^[23]' && break
  sleep 1
done
```

If server fails to start within 30 seconds → warn ("Dev server failed to start, skipping e2e tests") and skip to Step 8. Do NOT block shipping.

#### 7.6d. Execute Smoke Tests

For each changed handler/route/template, determine the URL path and test it:

1. **Identify routes from changed files:**
   - Parse Go handler registrations for URL patterns (e.g., `mux.HandleFunc("/api/users", ...)`)
   - Parse templ file names to infer page routes
   - If route detection fails, test the root path (`/`) as a baseline

2. **For each route, execute the smoke test:**
   - Navigate: Use `mcp__chrome-devtools-mcp__navigate_page` to load the URL
   - Screenshot: Use `mcp__chrome-devtools-mcp__take_screenshot` to capture the rendered page
   - Console check: Use `mcp__chrome-devtools-mcp__list_console_messages` to check for JavaScript errors
   - Network check: Use `mcp__chrome-devtools-mcp__list_network_requests` to verify no failed requests (5xx responses)
   - If the page contains forms related to changed code, test basic form interaction:
     - Use `mcp__chrome-devtools-mcp__fill` to populate form fields
     - Use `mcp__chrome-devtools-mcp__click` to submit
     - Verify no errors after submission

3. **Record results** for each page tested: URL, HTTP status, console errors (if any), screenshot path

#### 7.6e. Cleanup and Report

Kill the dev server:

```bash
kill $SERVER_PID 2>/dev/null || true
```

Persist e2e results in state file:

```bash
TMP=".claude/ship.loop.local.json.tmp"
jq --arg attempted "true" --arg result "$E2E_RESULT" --argjson pages "$PAGES_TESTED" \
   '.e2e_attempted = $attempted | .e2e_result = $result | .e2e_pages_tested = $pages' \
   ".claude/ship.loop.local.json" > "$TMP" && mv "$TMP" ".claude/ship.loop.local.json"
```

Display e2e results:

```
## E2E Smoke Test Results

| Route | Status | Console Errors | Screenshot |
|-------|--------|---------------|------------|
| / | 200 OK | None | ✓ captured |
| /api/users | 200 OK | None | N/A (API) |
| /dashboard | 500 Error | TypeError: ... | ✓ captured |

Pages tested: 3 | Passed: 2 | Errors: 1
```

**E2E failure handling:**
- Pages returning 500/404 → report as finding, show to user, but do NOT block shipping
- Console JavaScript errors → report but do NOT block
- MCP tool call fails mid-test → warn and skip remaining e2e tests
- All results are informational — e2e issues are warnings, not gates

Clean up transient files:

```bash
rm -f .claude/coverage.out .claude/coverage.json 2>/dev/null || true
```

### Step 8: Commit, Increment Pass, and Loop Decision

Stage only the files modified during the fix phase AND any test files generated in Step 7.5f (do NOT use `git add -A`):

```bash
git add <list of files modified during fix phase>
git add <list of test files generated in Step 7.5f, if any>
```

**Increment the pass counter** now that the review-fix-verify-coverage cycle is complete:

```bash
CURRENT_PASS=$(jq -r '.pass // 0' ".claude/ship.loop.local.json")
NEW_PASS=$((CURRENT_PASS + 1))
TMP=".claude/ship.loop.local.json.tmp"
jq --argjson p "$NEW_PASS" '.pass = $p' ".claude/ship.loop.local.json" > "$TMP" && mv "$TMP" ".claude/ship.loop.local.json"
PASS=$NEW_PASS
```

Only commit if there are staged changes:

```bash
TESTS_GEN=$(jq -r '.coverage_tests_generated // 0' ".claude/ship.loop.local.json")
if ! git diff --cached --quiet; then
  if [ "$TESTS_GEN" -gt 0 ] 2>/dev/null; then
    git commit -m "$(cat <<EOF
fix: address $LLM_CHOICE review findings (pass $PASS)

- Generated tests for $TESTS_GEN uncovered functions
EOF
)"
  else
    git commit -m "fix: address $LLM_CHOICE review findings (pass $PASS)"
  fi
fi
```

Check if we should continue reviewing:

- If `REVIEW_CLEAN` is `true` (review returned NO_ISSUES_FOUND) → proceed to Step 9 (no point re-reviewing clean code)
- If `PASS >= MAX_PASSES` → proceed to Step 9
- Otherwise → go back to Step 5 for next review pass

---

## Phase 2: Push and PR Creation (Step 9)

### Step 9: Pushing

Set phase to `pushing`:

```bash
set_loop_phase ".claude/ship.loop.local.json" "pushing"
```

#### 9a. Push to remote

Detect the correct remote and branch name from tracking config or PR metadata:

```bash
BRANCH_REMOTE=$(git config "branch.$(git branch --show-current).remote" 2>/dev/null || echo "origin")
PR_HEAD_BRANCH=$(gh pr view --json headRefName --jq '.headRefName' 2>/dev/null || git branch --show-current)
git push -u "$BRANCH_REMOTE" "HEAD:$PR_HEAD_BRANCH"
```

#### 9b. Ensure PR exists

If `PR_NUM` is empty (no existing PR), create one:

1. Check for a PR template at `.github/pull_request_template.md` (also check `.github/PULL_REQUEST_TEMPLATE.md`, `docs/`, repo root)
2. If found, read the template and use its section structure
3. If not found, use default format: `## Summary` + `## Test Plan`
4. Generate conventional commit title from commits: `<type>(<scope>): <subject>`
5. Check branch name and commit messages for issue references
6. Create PR targeting the detected base branch:

```bash
gh pr create --base "$BASE_BRANCH" --title "<title>" --body "$(cat <<'EOF'
<filled-in template or default body>
EOF
)"
```

Store the PR number:

```bash
PR_NUM=$(gh pr view --json number --jq '.number')
```

Persist `pr_number` in state file.

#### 9c. Capture bot review baseline

**CRITICAL: Capture immediately after push:**

```bash
BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Bot review baseline captured: $BOT_REVIEW_BASELINE"
```

Persist `bot_review_baseline` in state file.

---

## Phase 3: CI Watch (Step 10)

### Step 10: CI Watch

Set phase to `ci-watch`:

```bash
set_loop_phase ".claude/ship.loop.local.json" "ci-watch"
```

First, check if CI workflow files exist:

```bash
HAS_WORKFLOWS=$(find .github/workflows -maxdepth 1 -name '*.yml' -o -name '*.yaml' 2>/dev/null | head -1)
```

If no workflow files exist → persist `has_ci: false` in state file and skip to Step 11.

**If workflows exist**, persist `has_ci: true` in state file and watch CI with extended retry to handle slow check registration:

```bash
for i in 1 2 3 4 5 6; do sleep 10 && gh pr checks "$PR_NUM" --watch && break; done
```

This waits up to 60 seconds for checks to appear (6 retries x 10s). If checks still haven't registered after all retries but workflow files exist, inform the user and ask whether to keep waiting or proceed.

If CI fails:
1. Analyze the failure: `gh pr checks "$PR_NUM" --json name,state,description`
2. Fix the issue
3. Commit the fix
4. Push: `git push`
5. Re-capture `BOT_REVIEW_BASELINE`: `BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)` and persist
6. Re-watch CI (go back to top of Step 10)

---

## Phase 4: Bot Watch (Step 11)

### Step 11: Bot Discovery and Watch

Set phase to `bot-watching` (distinct from address-review's `watching` phase to get ship-specific re-entry messages):

```bash
set_loop_phase ".claude/ship.loop.local.json" "bot-watching"
```

#### 11a. Discover review bots

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/bot-registry.md` for the bot registry table.

Query **all** author sources — formal reviews, review thread comments, AND top-level PR comments (issue comments) — since some bots (e.g., Claude) signal via ordinary PR comments:

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')

BOT_AUTHORS=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviews(first: 100) {
          nodes {
            author { login }
            state
          }
        }
        reviewThreads(first: 100) {
          nodes {
            comments(first: 50) {
              nodes {
                author { login }
              }
            }
          }
        }
        comments(first: 100) {
          nodes {
            author { login }
          }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq -r '
  [
    .data.repository.pullRequest.reviews.nodes[].author.login,
    .data.repository.pullRequest.reviewThreads.nodes[].comments.nodes[].author.login,
    .data.repository.pullRequest.comments.nodes[].author.login
  ] | unique | .[]
')
```

Also check PR status checks for bots that signal via commit statuses rather than reviews (e.g., Greptile):

```bash
CHECK_BOTS=$(gh pr checks "$PR_NUM" --json name 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)
```

Match both `BOT_AUTHORS` and `CHECK_BOTS` against the bot registry.

**If no review bots detected yet:** This may be because async bots haven't posted their first review. If `BOT_REVIEW_BASELINE` was captured less than 2 minutes ago, ask the user whether to wait or proceed:

Use `AskUserQuestion`: "No review bots detected yet. The push was recent — bots may still be starting. Wait for bots to respond, or proceed to merge without bot review?"

If the user chooses to wait, poll up to 3 times (30s apart). If still no bots after retries → proceed to Step 13 (merging).

**Persist discovered bots** to state file for re-entry recovery:

```bash
# Store as comma-separated list in state file
# e.g., discovered_bots: chatgpt-codex-connector[bot],coderabbitai[bot]
```

#### 11b. Poll for bot approval

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/watch-loop.md` for the complete polling logic.

Follow Steps 12a-12d from watch-loop.md:

- **All bots approved** → proceed to Step 13 (merging)
- **New comments / CHANGES_REQUESTED** → go to Step 12 (address feedback)
- **Timeout (5 min)** → ask user via `AskUserQuestion`

---

## Phase 5: Address Bot Feedback (Step 12)

### Step 12: Address Feedback

Set phase to `addressing` (distinct from `fixing` to ensure correct re-entry routing):

```bash
set_loop_phase ".claude/ship.loop.local.json" "addressing"
```

#### 12a. Fetch and rebase against base branch

Before applying fixes, ensure the branch is up to date with the base to avoid conflicts:

```bash
git fetch origin "$BASE_BRANCH"
git rebase "origin/$BASE_BRANCH" || git rebase --abort
```

If the rebase fails (conflicts), abort and inform the user. Proceed with fixes without rebasing — the user can resolve conflicts manually.

#### 12b. Apply address-review fixes

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/SKILL.md` and follow Steps 2-11 only:

- **Skip Step 1** (loop init / PR checkout) — we're already on the branch, loop is managed by `/ship`
- **Skip Step 12** (bot watch) — we handle that in Step 11 above
- Do NOT create a second loop state file — all phases are managed under the `ship` loop

#### 12c. Capture baseline BEFORE push

**CRITICAL:** Capture `BOT_REVIEW_BASELINE` before pushing, not after. This ensures we don't miss fast bot responses that arrive between the push and the timestamp capture:

```bash
BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
```

Persist in state file. Then push the fixes.

Return to Step 10 (ci-watch) — set phase and re-watch CI before checking bot approval again.

---

## Phase 6: Merge (Step 13)

### Step 13: Merge

Set phase to `merging`:

```bash
set_loop_phase ".claude/ship.loop.local.json" "merging"
```

#### 13a. Final checks

1. Verify CI is green (skip if `has_ci` is `false` in state file — Step 10 already determined no CI exists): `gh pr checks "$PR_NUM"`
2. Check for unresolved review threads:
   ```bash
   OWNER=$(gh repo view --json owner --jq '.owner.login')
   REPO=$(gh repo view --json name --jq '.name')
   UNRESOLVED=$(gh api graphql -f query='
     query($owner: String!, $repo: String!, $pr: Int!) {
       repository(owner: $owner, name: $repo) {
         pullRequest(number: $pr) {
           reviewThreads(first: 100) {
             nodes { isResolved }
           }
         }
       }
     }
   ' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length')
   ```
3. Check for **active** human `CHANGES_REQUESTED` (latest review per human reviewer, excluding bots):
   ```bash
   OWNER=$(gh repo view --json owner --jq '.owner.login')
   REPO=$(gh repo view --json name --jq '.name')
   BLOCKING_HUMANS=$(gh api graphql -f query='
     query($owner: String!, $repo: String!, $pr: Int!) {
       repository(owner: $owner, name: $repo) {
         pullRequest(number: $pr) {
           latestReviews(first: 50) {
             nodes {
               author { login }
               state
             }
           }
         }
       }
     }
   ' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq '[.data.repository.pullRequest.latestReviews.nodes[] | select(.state == "CHANGES_REQUESTED") | select(.author.login | test("\\[bot\\]$") | not)] | length')
   ```

If there are unresolved threads or human `CHANGES_REQUESTED`, inform the user and ask how to proceed.

#### 13b. Check `--no-merge` flag

If `NO_MERGE` is `true`:
- Display summary (see below)
- Output `<done>SHIPPED</done>`
- Stop here

#### 13c. Auto-detect merge strategy and merge

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')
MERGE_SETTINGS=$(gh api "repos/$OWNER/$REPO" --jq '{merge: .allow_merge_commit, squash: .allow_squash_merge, rebase: .allow_rebase_merge}' 2>/dev/null || echo '{}')
```

Determine the merge flag based on what the repo allows (prefer merge > squash > rebase):

```bash
MERGE_FLAG="--merge"
if echo "$MERGE_SETTINGS" | jq -e '.merge == true' >/dev/null 2>&1; then
  MERGE_FLAG="--merge"
elif echo "$MERGE_SETTINGS" | jq -e '.squash == true' >/dev/null 2>&1; then
  MERGE_FLAG="--squash"
elif echo "$MERGE_SETTINGS" | jq -e '.rebase == true' >/dev/null 2>&1; then
  MERGE_FLAG="--rebase"
fi
```

#### 13d. Branch protection mergeability check

**CRITICAL: Before attempting merge, verify that branch protection requirements are satisfied. NEVER bypass branch protection.**

Query GitHub's mergeability status:

```bash
MERGE_STATE=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        mergeStateStatus
        mergeable
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" --jq '.data.repository.pullRequest')

MERGEABLE=$(echo "$MERGE_STATE" | jq -r '.mergeable')
STATE_STATUS=$(echo "$MERGE_STATE" | jq -r '.mergeStateStatus')

# Check if repo uses a merge queue (URL-encode branch name for slash-containing branches)
ENCODED_BRANCH=$(printf '%s' "$BASE_BRANCH" | jq -sRr @uri)
HAS_MERGE_QUEUE=$(gh api "repos/$OWNER/$REPO/rules/branches/$ENCODED_BRANCH" 2>/dev/null | jq '[.[] | select(.type == "merge_queue")] | length > 0' 2>/dev/null || echo "false")
```

GitHub computes mergeability asynchronously — `UNKNOWN` is a transient state after pushes or check completions. **Poll when `UNKNOWN`, hard-block only on clear failures:**

- If `MERGEABLE` is `UNKNOWN` or `STATE_STATUS` is `UNKNOWN`: retry up to 6 times (5s apart). If still `UNKNOWN` after retries, ask the user via `AskUserQuestion` whether to proceed or wait.
- If `MERGEABLE` is `CONFLICTING`:
  - **STOP** — display "PR has merge conflicts. Resolve conflicts before merging."
  - Clean up loop state and stop without `<done>SHIPPED</done>`
- If `STATE_STATUS` is `BLOCKED`:
  - **If the repo uses a merge queue** (`HAS_MERGE_QUEUE` is true): proceed to merge — `gh pr merge` will enqueue the PR correctly.
  - **If no merge queue**: **STOP immediately** — do NOT attempt merge. Display: "Branch protection requirements not met (status: BLOCKED). Cannot merge." Clean up loop state: `"${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" "ship"`. Do NOT output `<done>SHIPPED</done>`. Inform the user what is blocking and stop.
- If `MERGEABLE` is `MERGEABLE` and `STATE_STATUS` is not `BLOCKED`: proceed to merge

#### 13e. Merge the PR

**CRITICAL: NEVER use `--admin` flag. NEVER use any flag or method that bypasses branch protection. If the merge fails due to branch protection, STOP and inform the user — do NOT retry with elevated privileges.**

For merge-queue repos, omit the merge strategy flag — `gh pr merge` will enqueue the PR automatically:

```bash
if [ "$HAS_MERGE_QUEUE" = "true" ]; then
  gh pr merge "$PR_NUM" --delete-branch
else
  gh pr merge "$PR_NUM" $MERGE_FLAG --delete-branch
fi
```

If the merge command fails (non-zero exit code):
- Do NOT retry with `--admin` or any other bypass flag
- Display the error output to the user
- Clean up loop state: `"${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" "ship"`
- Do NOT output `<done>SHIPPED</done>`
- Stop and let the user resolve the blocking issue

#### 13f. Display summary

Read coverage and e2e results from state file:

```bash
COV_RESULT=$(jq -r '.coverage_result // "skipped"' ".claude/ship.loop.local.json")
COV_THRESHOLD=$(jq -r '.coverage_threshold // "60"' ".claude/ship.loop.local.json")
TESTS_GEN=$(jq -r '.coverage_tests_generated // 0' ".claude/ship.loop.local.json")
E2E_ATTEMPTED=$(jq -r '.e2e_attempted // ""' ".claude/ship.loop.local.json")
E2E_RESULT=$(jq -r '.e2e_result // "skipped"' ".claude/ship.loop.local.json")
E2E_PAGES=$(jq -r '.e2e_pages_tested // 0' ".claude/ship.loop.local.json")
```

```
## Ship Complete

- **PR:** #<PR_NUM>
- **LLM:** <llm>
- **Review passes:** <n>
- **Findings addressed:** <n>
- **Coverage (changed files):** <COV_RESULT>% (threshold: <COV_THRESHOLD>%) — or "skipped"
- **Tests generated:** <TESTS_GEN>
- **E2E tests:** <E2E_PAGES> pages tested, <E2E_RESULT> — or "skipped — no web components" / "skipped — MCP unavailable"
- **CI:** green
- **Bot approvals:** <list or "none required">
- **Merge strategy:** <merge|squash|rebase>
- **Merged:** yes (or "skipped — --no-merge")
```

Output `<done>SHIPPED</done>`

---

## Phase Flow Summary

```
Step 5-8: local-review
  reviewing → fixing → verifying → [coverage-check] → [e2e-testing] → commit
    ↓
Step 9: pushing
    ↓
Step 10: ci-watch
    ↓
Step 11: bot-watch (bot-watching)
    ↓                ↓
    ↓          Step 12: address-feedback (addressing)
    ↓                ↓
    ↓          → back to Step 10 (ci-watch)
    ↓
Step 13: merging
    ↓
<done>SHIPPED</done>
```

**Note:** Steps in `[brackets]` are conditional — coverage-check runs only on the final pass and when `--skip-coverage` is not set. E2E testing runs only when Chrome DevTools MCP is available and the project has web components.

## Re-entry Matrix

| Phase at exit | Re-entry behavior |
|---|---|
| `reviewing` | Resume LLM review pass |
| `fixing` | Continue fixing LLM review findings |
| `verifying` | Re-run verification |
| `coverage-check` | Re-run coverage analysis on changed files |
| `e2e-testing` | Re-run e2e tests (restart dev server if needed) |
| `pushing` | Resume push and PR creation |
| `ci-watch` | Resume CI monitoring |
| `bot-watching` | Resume bot approval polling |
| `addressing` | Resume addressing bot review feedback (Steps 2-11 of address-review) |
| `merging` | Resume merge attempt |

## Completion Criteria

Output `<done>SHIPPED</done>` ONLY when ALL of these are true:

1. LLM review passes completed (clean or max passes reached)
2. Coverage verified for changed files (or skipped via `--skip-coverage`)
3. E2E smoke tests passed (or skipped — no web components / MCP unavailable)
4. Changes pushed to remote
5. PR exists
6. CI passes (or no CI configured)
7. Bot approvals received (or no bots configured)
8. PR merged (or `--no-merge` specified)

**Safety note:** If you've iterated 15+ times without completion, document what's blocking and ask the user for guidance.

## Cancel

Users can run `/cancel-loop ship` at any time to cleanly exit the loop.
