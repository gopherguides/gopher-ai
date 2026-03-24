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
   --arg review_clean "" --arg head_sha "" \
   '. + {args: $args, llm: $llm, pass: $pass, no_merge: $no_merge, pr_number: $pr_number, base_branch: $base_branch, bot_review_baseline: $bot_review_baseline, discovered_bots: $discovered_bots, has_ci: $has_ci, skip_coverage: $skip_coverage, coverage_threshold: $coverage_threshold, coverage_result: $coverage_result, coverage_tests_generated: $coverage_tests_generated, e2e_attempted: $e2e_attempted, e2e_result: $e2e_result, e2e_pages_tested: $e2e_pages_tested, review_clean: $review_clean, head_sha: $head_sha}' \
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
2. Read `pass`, `pr_number`, `base_branch`, `bot_review_baseline`, `llm`, `discovered_bots`, `has_ci`, `skip_coverage`, `coverage_threshold`, `coverage_result`, `coverage_tests_generated`, `e2e_attempted`, `e2e_result`, `e2e_pages_tested`, `review_clean`, `head_sha` fields via `jq -r '.field // empty' "$STATE_FILE"`
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

<!-- SYNC: codex-exec-review — keep aligned with review-loop.md Step 5b -->

Execute review based on `LLM_CHOICE`:

**Codex (exhaustive mode via `codex exec`):**

Use `codex exec` with a structured output schema to get ALL findings in one pass (bypasses the 2-3 finding limit of `codex review`).

1. Assemble the review prompt by constructing a heredoc with these sections:
   - The review instructions (find ALL issues, priority levels, categories, rules)
   - `{REPO_GUIDELINES}` — auto-detect `AGENTS.md` or `CLAUDE.md` in repo root; include contents if found
   - The diff from Step 5a

2. Create a temporary schema file:

```bash
SCHEMA_FILE=$(mktemp /tmp/codex-review-schema.XXXXXX.json)
cat > "$SCHEMA_FILE" <<'SCHEMA_EOF'
{"type":"object","properties":{"findings":{"type":"array","items":{"type":"object","properties":{"title":{"type":"string","maxLength":80},"body":{"type":"string","minLength":1},"confidence_score":{"type":"number","minimum":0,"maximum":1},"priority":{"type":"integer","minimum":0,"maximum":3},"category":{"type":"string","enum":["correctness","security","performance","maintainability","developer-experience"]},"code_location":{"type":"object","properties":{"file_path":{"type":"string","minLength":1},"line_range":{"type":"object","properties":{"start":{"type":"integer","minimum":1},"end":{"type":"integer","minimum":1}},"required":["start","end"],"additionalProperties":false}},"required":["file_path","line_range"],"additionalProperties":false}},"required":["title","body","confidence_score","priority","category","code_location"],"additionalProperties":false}},"overall_correctness":{"type":"string","enum":["patch is correct","patch is incorrect"]},"overall_explanation":{"type":"string","minLength":1},"overall_confidence_score":{"type":"number","minimum":0,"maximum":1}},"required":["findings","overall_correctness","overall_explanation","overall_confidence_score"],"additionalProperties":false}
SCHEMA_EOF
```

3. Write the assembled prompt to a temp file (avoids heredoc expansion issues with special characters in diffs), then execute:

```bash
PROMPT_FILE=$(mktemp /tmp/codex-review-prompt.XXXXXX.md)
echo "$ASSEMBLED_PROMPT" > "$PROMPT_FILE"
REVIEW_JSON=$(codex exec -m "${MODEL:-gpt-5.4}" -s read-only \
  --output-schema "$SCHEMA_FILE" \
  - < "$PROMPT_FILE")
rm -f "$PROMPT_FILE" "$SCHEMA_FILE"
```

The review prompt must include these instructions:

```text
You are reviewing a code change (diff) for a pull request. Your task is to identify ALL issues — do not limit yourself to a small number. Report every actionable finding you discover.

Focus on: Correctness (bugs, logic errors, race conditions, nil dereference), Security (injection, auth bypass, data exposure), Performance (O(n²) loops, unnecessary allocations), Maintainability (dead code, excessive complexity), Developer Experience (missing error context, unclear APIs).

Rules:
1. Only flag issues INTRODUCED by this diff.
2. Every finding MUST cite the exact file path (relative to repo root) and line range.
3. Verify line numbers against the diff — accuracy is critical.
4. Priority: 0=critical, 1=high, 2=medium, 3=low.
5. If the diff is clean, return an empty findings array.
6. Do NOT stop after finding a few issues — review the ENTIRE diff.
```

4. Validate JSON. If invalid or empty, this is a review failure — do NOT fall through to the free-text clean-review path. Warn the user: "Codex exec returned invalid output. Review did not complete." Ask whether to retry, fall back to `codex review --base`, or abort.

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

Capture the output as `FINDINGS` (for gemini/ollama) or `REVIEW_JSON` (for codex).

#### 5c. Parse Findings

**Structured JSON (codex exec mode):**

When `LLM_CHOICE` is `codex` and `CODEX_EXEC_FALLBACK` is not `true`:

1. Validate JSON: `echo "$REVIEW_JSON" | jq empty 2>/dev/null`. If invalid, fall through to free-text parsing.
2. Extract findings count, overall correctness, and confidence via `jq`.
3. Filter findings with `confidence_score < 0.3` (likely false positives).
4. If zero findings and `overall_correctness` is `"patch is correct"`: review is clean → set `REVIEW_CLEAN=true` and persist to state file. Skip Step 6 but still run Step 7. Proceed to Steps 7.5 and 7.6, skip Step 8's loop-back, proceed to Step 9.
5. Display findings as formatted table sorted by priority then confidence.
6. De-duplicate across passes using `(file_path, line_range.start, normalized title)`.
7. Store findings in state file for re-entry.

**Free-text (codex quick/fallback / gemini / ollama):**

- If output equals `NO_ISSUES_FOUND` or has fewer than 20 characters: review is clean → set `REVIEW_CLEAN=true` and **persist it to state file** (`jq '.review_clean = "true"'`) for re-entry recovery. Skip Step 6 (fixing) but still run Step 7 (verify phase, including codegen detection) to catch generated file drift. Then proceed to Steps 7.5 and 7.6, skip Step 8's loop-back decision, and proceed directly to Step 9 (pushing) — do NOT re-run LLM review when the review was already clean
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

First, run code generation if a generation target is available:

```bash
if [ -f Makefile ]; then
  GEN_TARGET=$(make -qp 2>/dev/null | awk -F: '/^[a-zA-Z0-9_-]+:/ {print $1}' \
    | grep -E '^(generate|gen|codegen|sqlc|proto|templ)$' | head -1 || true)
  if [ -n "$GEN_TARGET" ]; then
    # Capture pre-run snapshot of dirty/untracked files to distinguish generator output from fix-phase edits
    GEN_SNAPSHOT=$(printf '%s\n%s' "$(git diff --name-only)" "$(git ls-files --others --exclude-standard)" | sed '/^$/d' | sort -u)
    echo "Running make $GEN_TARGET..."
    if ! make "$GEN_TARGET" 2>&1; then
      echo "WARNING: make $GEN_TARGET failed (tooling may not be installed). Skipping codegen check."
      GEN_TARGET=""
    fi
  fi
fi
```

If a codegen target ran successfully, check for modified or newly created generated files by comparing against a pre-run snapshot:

```bash
if [ -n "$GEN_TARGET" ]; then
  # GEN_SNAPSHOT was captured before running the generator (see above)
  GEN_MODIFIED=$(git diff --name-only)
  GEN_UNTRACKED=$(git ls-files --others --exclude-standard)
  GEN_ALL=$(printf '%s\n%s' "$GEN_MODIFIED" "$GEN_UNTRACKED" | sed '/^$/d' | sort -u)
  # Filter to only files that are NEW since the snapshot (not pre-existing edits from fix phase)
  if [ -n "$GEN_SNAPSHOT" ]; then
    GEN_NEW=$(comm -13 <(echo "$GEN_SNAPSHOT" | sort) <(echo "$GEN_ALL" | sort))
  else
    GEN_NEW="$GEN_ALL"
  fi
  if [ -n "$GEN_NEW" ]; then
    echo "Generated code is stale. The following files changed after running generation:"
    echo "$GEN_NEW"
    echo "Staging regenerated files..."
    echo "$GEN_NEW" | xargs git add
  fi
fi
```

Then run standard verification:

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

**Ship-specific skip condition:** Also skip this entire step if this is NOT the final pass (`PASS < MAX_PASSES - 1` AND findings were not clean). Proceed to Step 7.6.

Read `${CLAUDE_PLUGIN_ROOT}/skills/coverage/coverage-verification.md` and follow Steps A through F with these parameters:

| Variable | Value |
|----------|-------|
| `BASE_BRANCH` | `origin/${BASE_BRANCH}` (from Step 3) |
| `STATE_FILE` | `.claude/ship.loop.local.json` |
| `SKIP_COVERAGE` | from parsed arguments |
| `COVERAGE_THRESHOLD` | from parsed arguments (default: 60) |

After coverage verification completes (or is skipped), continue to Step 7.6.

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

#### 9c. Capture HEAD SHA and bot review baseline

**CRITICAL: Capture immediately after push:**

```bash
HEAD_SHA=$(git rev-parse HEAD)
echo "HEAD SHA captured: $HEAD_SHA"
BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Bot review baseline captured: $BOT_REVIEW_BASELINE"
```

Persist both `head_sha` and `bot_review_baseline` in state file.

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

**If workflows exist**, persist `has_ci: true` in state file.

**MANDATORY — NO EXCEPTIONS:** You MUST verify that CI checks correspond to the latest pushed commit before considering CI as passed. You MUST NOT:
- Assume passing checks from a prior commit apply to the current commit
- Rationalize that "only a minor fix was pushed so old checks are still valid"
- Skip SHA verification because `gh pr checks --watch` returned success
- Treat "no checks yet" as "checks passed"

The ENTIRE purpose of CI is to validate the EXACT code being merged. Stale check results from a previous push are meaningless.

#### 10a. Capture and verify HEAD SHA

Read `head_sha` from state file (set during push in Step 9a, 10 retry, or 12c):

```bash
HEAD_SHA=$(jq -r '.head_sha // empty' ".claude/ship.loop.local.json")
if [ -z "$HEAD_SHA" ]; then
  HEAD_SHA=$(git rev-parse HEAD)
fi
echo "Watching CI for commit: $HEAD_SHA"
```

#### 10b. Wait for checks to register for the correct SHA

Poll until GitHub reports checks for the HEAD SHA (up to 120 seconds). Note: `pull_request`-triggered checks run on a merge commit, not the PR head SHA. Use the REST API which reliably reports check runs for a specific commit:

```bash
CI_READY=false
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')
for i in $(seq 1 12); do
  CHECK_COUNT=$(gh api "repos/$OWNER/$REPO/commits/$HEAD_SHA/check-runs" \
    --jq '.total_count' 2>/dev/null || echo "0")
  if [ "$CHECK_COUNT" -gt 0 ]; then
    CI_READY=true
    break
  fi
  echo "No checks for $HEAD_SHA yet... ($i/12)"
  sleep 10
done
```

If STILL not ready after 120 seconds: ask the user via `AskUserQuestion`: "CI checks for commit {HEAD_SHA} have not appeared after 120 seconds. The repo has workflow files. Wait longer, or proceed without CI verification?"

#### 10c. Watch checks for the correct SHA

Once checks for HEAD_SHA are confirmed, watch them:

```bash
gh pr checks "$PR_NUM" --watch
```

#### 10d. Post-watch SHA validation

After `--watch` completes, verify that the PR head hasn't changed (a concurrent push could have shifted it):

```bash
FINAL_SHA=$(gh pr view "$PR_NUM" --json headRefOid --jq '.headRefOid' 2>/dev/null || true)
if [ -n "$FINAL_SHA" ] && [ "$FINAL_SHA" != "$HEAD_SHA" ]; then
  echo "STOP: PR head shifted to SHA $FINAL_SHA during watch (expected $HEAD_SHA)."
  echo "A new commit landed on this PR that was NOT reviewed locally."
  echo "Restarting from review phase against the new HEAD."
  HEAD_SHA="$FINAL_SHA"
  # Fetch and checkout the new PR head so local review runs against the correct code
  BRANCH_REMOTE=$(git config "branch.$(git branch --show-current).remote" 2>/dev/null || echo "origin")
  PR_HEAD_BRANCH=$(gh pr view "$PR_NUM" --json headRefName --jq '.headRefName')
  git fetch "$BRANCH_REMOTE" "$PR_HEAD_BRANCH"
  git checkout "$PR_HEAD_BRANCH"
  git reset --hard "$BRANCH_REMOTE/$PR_HEAD_BRANCH"
  # Persist new HEAD SHA, reset pass counter, and set phase to reviewing for correct re-entry
  TMP=".claude/ship.loop.local.json.tmp"
  jq --arg sha "$HEAD_SHA" --argjson pass 0 --arg rc "" --arg phase "reviewing" \
    '.head_sha = $sha | .pass = $pass | .review_clean = $rc | .phase = $phase' \
    ".claude/ship.loop.local.json" > "$TMP" && mv "$TMP" ".claude/ship.loop.local.json"
  # Go back to Step 5 (reviewing)
fi
```

#### 10e. CI failure handling

If CI fails:
1. Analyze the failure: `gh pr checks "$PR_NUM" --json name,state,description`
2. Fix the issue
3. Commit the fix
4. Push: `git push`
5. Capture HEAD SHA: `HEAD_SHA=$(git rev-parse HEAD)` and persist `head_sha` in state file
6. Re-capture `BOT_REVIEW_BASELINE`: `BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)` and persist
7. Re-watch CI (go back to Step 10b — wait for checks for the NEW SHA)

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

#### 12c. Capture baseline BEFORE push, HEAD SHA AFTER push

**CRITICAL:** Capture `BOT_REVIEW_BASELINE` before pushing, not after. This ensures we don't miss fast bot responses that arrive between the push and the timestamp capture:

```bash
BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
```

Then push the fixes. After pushing, capture HEAD SHA:

```bash
git push
HEAD_SHA=$(git rev-parse HEAD)
echo "HEAD SHA captured: $HEAD_SHA"
```

Persist `bot_review_baseline` and `head_sha` in state file.

Return to Step 10 (ci-watch) — set phase and re-watch CI for the new HEAD SHA before checking bot approval again.

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

GitHub computes mergeability asynchronously — `UNKNOWN` is a transient state after pushes or check completions. **Follow the decision logic below strictly — do not invent reasons to merge when a state is not covered:**

Decision logic:

- If `MERGEABLE` is `UNKNOWN` or `STATE_STATUS` is `UNKNOWN`: retry up to 6 times (5s apart). If still `UNKNOWN` after retries, ask the user via `AskUserQuestion` whether to proceed or wait.
- If `MERGEABLE` is `CONFLICTING`:
  - **STOP** — display "PR has merge conflicts. Resolve conflicts before merging."
  - Clean up loop state and stop without `<done>SHIPPED</done>`
- If `STATE_STATUS` is `BLOCKED`:
  - **If the repo uses a merge queue** (`HAS_MERGE_QUEUE` is true): proceed to merge — `gh pr merge` will enqueue the PR correctly.
  - **If no merge queue**: **STOP immediately** — do NOT attempt merge. Display: "Branch protection requirements not met (status: BLOCKED). Cannot merge." Clean up loop state: `"${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" "ship"`. Do NOT output `<done>SHIPPED</done>`. Inform the user what is blocking and stop.
- If `STATE_STATUS` is `CLEAN` or `STATE_STATUS` is `HAS_HOOKS`: proceed to merge. These are the two states that mean "all checks passed and requirements satisfied."
- If `STATE_STATUS` is `BEHIND` and `MERGEABLE` is `MERGEABLE`: proceed to merge. `BEHIND` only means the base branch moved forward — GitHub still allows merging if the repo does not require branches to be up-to-date. If the merge fails due to a "strict" branch protection rule, the error will be caught in Step 13e.
- If `STATE_STATUS` is `UNSTABLE` and `MERGEABLE` is `MERGEABLE`: proceed to merge. `UNSTABLE` means some non-required or informational checks failed, but branch protection is still satisfied. GitHub allows the merge. If the merge fails, the error will be caught in Step 13e.
- **For ANY other `STATE_STATUS` value** (including but not limited to `DIRTY`, `DRAFT`): **STOP immediately.** Display: "PR is not ready to merge (mergeStateStatus: {STATE_STATUS}). Resolve the issue before merging." Clean up loop state: `"${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" "ship"`. Do NOT output `<done>SHIPPED</done>`. Inform the user and stop.

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

## Verification Gate (HARD — applies before ANY completion signal)

Before outputting `<done>SHIPPED</done>`, every claim MUST have FRESH evidence from THIS session:

1. **"Tests pass"** → show actual `go test` output with "ok" lines and zero failures. Not "I ran the tests earlier" — run them NOW.
2. **"Build succeeds"** → show actual `go build ./...` output with exit code 0.
3. **"CI passes"** → show actual `gh pr checks` output with all checks green.
4. **"Bot approvals received"** → show actual `gh pr reviews` output with APPROVED states.
5. **"PR merged"** → show actual merge output or `gh pr view` showing MERGED state.

**Red-flag language check** — if you are about to write any of the following, STOP and run verification instead:
- "should work" / "should be fine"
- "probably" / "likely"
- "I believe" / "I think"
- "Done!" / "Shipped!" without preceding command output showing proof

## Completion Criteria

Output `<done>SHIPPED</done>` ONLY when ALL of these are true:

1. LLM review passes completed (clean or max passes reached)
2. Coverage verified for changed files (or skipped via `--skip-coverage`)
3. E2E smoke tests passed (or skipped — no web components / MCP unavailable)
4. Changes pushed to remote
5. PR exists
6. CI passes (or no CI configured) — with output shown above
7. Bot approvals received (or no bots configured) — with output shown above
8. PR merged (or `--no-merge` specified) — with output shown above

**Safety note:** If you've iterated 15+ times without completion, document what's blocking and ask the user for guidance.

## Cancel

Users can run `/cancel-loop ship` at any time to cleanly exit the loop.
