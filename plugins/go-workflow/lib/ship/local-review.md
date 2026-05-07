# Ship — Phase 1: Local LLM Review (Steps 5–8)

Loaded by `commands/ship.md` Phase 1. Owns the full review/fix/verify/coverage/E2E/commit cycle.

## Step 5: Review Phase

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
set_loop_phase ".local/state/ship.loop.local.json" "reviewing"
PASS=$(jq -r '.pass // 0' ".local/state/ship.loop.local.json")
```

The pass counter is incremented in Step 8 (after commit), not here. This prevents burning a pass number if the session exits mid-review.

**Re-detect `$CODEX_CMD` on re-entry** (re-entry jumps directly to Step 5, skipping Step 4):

```bash
if [ "$LLM_CHOICE" = "codex" ] && [ -z "${CODEX_CMD:-}" ]; then
  if command -v codex &>/dev/null; then
    CODEX_CMD="codex"
  elif npx -y codex --version &>/dev/null 2>&1; then
    CODEX_CMD="npx -y codex"
  fi
fi
```

### 5a. Generate Diff

```bash
git fetch origin "$BASE_BRANCH" 2>/dev/null || true
DIFF=$(git diff "origin/${BASE_BRANCH}...HEAD")
```

If the diff is empty, skip the review loop entirely — proceed to Phase 2 (Step 9).

### 5b. Run LLM Review

<!-- SYNC: codex-exec-review — keep aligned with review-loop.md Step 5b -->

#### Codex — Diff Size Estimation and Adaptive Timeout

```bash
if command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD="timeout"
else TIMEOUT_CMD=""
fi

DIFF_LINES=$(printf '%s\n' "$DIFF" | wc -l)
DIFF_FILES=$(printf '%s\n' "$DIFF" | grep -c '^diff --git' || echo 0)
echo "Diff size: $DIFF_LINES lines across $DIFF_FILES files"

# Adaptive timeout: 120s base + 2s per 100 lines, capped at 600s
CODEX_TIMEOUT=$(( 120 + (DIFF_LINES / 50) ))
if [ "$CODEX_TIMEOUT" -gt 600 ]; then CODEX_TIMEOUT=600; fi
```

If `DIFF_LINES > 3000`, ask via `AskUserQuestion`:

> **"Large diff detected ($DIFF_LINES lines, $DIFF_FILES files). Codex exec may timeout on diffs this large. How would you like to proceed?"**

| Option | Description |
|--------|-------------|
| **Proceed with codex exec** | Run with extended timeout (${CODEX_TIMEOUT}s) — may still timeout |
| **Use `codex review --base`** | Faster but limited to 2-3 findings per pass (no structured output) |
| **Use agent-based review** | Claude agent review (no external LLM) |
| **Skip review** | Proceed to push without LLM review |

For `codex review --base`: set `QUICK_MODE=true`. For agent-based: set `USE_AGENT_REVIEW=true` and `CODEX_EXEC_FALLBACK=true`.

#### Codex Exhaustive (`codex exec --output-schema`)

1. Assemble the review prompt as a heredoc with: review instructions, `{REPO_GUIDELINES}` (auto-detect `AGENTS.md` or `CLAUDE.md`), and the diff.

2. Create a temporary schema file:

```bash
SCHEMA_FILE=$(mktemp /tmp/codex-review-schema-XXXXXX)
cat > "$SCHEMA_FILE" <<'SCHEMA_EOF'
{"type":"object","properties":{"findings":{"type":"array","items":{"type":"object","properties":{"title":{"type":"string","maxLength":80},"body":{"type":"string","minLength":1},"confidence_score":{"type":"number","minimum":0,"maximum":1},"priority":{"type":"integer","minimum":0,"maximum":3},"category":{"type":"string","enum":["correctness","security","performance","maintainability","developer-experience"]},"code_location":{"type":"object","properties":{"file_path":{"type":"string","minLength":1},"line_range":{"type":"object","properties":{"start":{"type":"integer","minimum":1},"end":{"type":"integer","minimum":1}},"required":["start","end"],"additionalProperties":false}},"required":["file_path","line_range"],"additionalProperties":false}},"required":["title","body","confidence_score","priority","category","code_location"],"additionalProperties":false}},"overall_correctness":{"type":"string","enum":["patch is correct","patch is incorrect"]},"overall_explanation":{"type":"string","minLength":1},"overall_confidence_score":{"type":"number","minimum":0,"maximum":1}},"required":["findings","overall_correctness","overall_explanation","overall_confidence_score"],"additionalProperties":false}
SCHEMA_EOF
```

3. Write the assembled prompt to a temp file (avoids heredoc expansion issues), execute with adaptive timeout:

```bash
PROMPT_FILE=$(mktemp /tmp/codex-review-prompt-XXXXXX)
echo "$ASSEMBLED_PROMPT" > "$PROMPT_FILE"
CODEX_TIMEOUT="${CODEX_TIMEOUT:-120}"

set +e
if [ -n "$TIMEOUT_CMD" ]; then
  REVIEW_JSON=$($TIMEOUT_CMD "${CODEX_TIMEOUT}" $CODEX_CMD exec -m "${MODEL:-gpt-5.5}" -s read-only \
    --output-schema "$SCHEMA_FILE" \
    - < "$PROMPT_FILE" 2>"/tmp/codex-review-stderr-$$")
else
  REVIEW_JSON=$($CODEX_CMD exec -m "${MODEL:-gpt-5.5}" -s read-only \
    --output-schema "$SCHEMA_FILE" \
    - < "$PROMPT_FILE" 2>"/tmp/codex-review-stderr-$$")
fi
CODEX_EXIT_CODE=$?
CODEX_STDERR=$(cat "/tmp/codex-review-stderr-$$" 2>/dev/null)
rm -f "/tmp/codex-review-stderr-$$"
set -e

# Strip codex exec headers (version/config info printed before JSON)
REVIEW_JSON=$(printf '%s\n' "$REVIEW_JSON" | awk '/^\{/{found=1} found{print}')
if [ -z "$REVIEW_JSON" ] && [ "$CODEX_EXIT_CODE" -eq 0 ]; then
  echo "WARNING: $CODEX_CMD exec produced no JSON output after header stripping"
  REVIEW_JSON='{"error":"no JSON output"}'
fi
rm -f "$PROMPT_FILE" "$SCHEMA_FILE"
```

The review prompt includes:

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

### Error handling — never silently fall back

#### Exit code 124 (timeout)

```bash
DOUBLED_TIMEOUT=$(( CODEX_TIMEOUT * 2 ))
if [ "$DOUBLED_TIMEOUT" -gt 900 ]; then DOUBLED_TIMEOUT=900; fi
```

Display diff size, timeout used, partial output, stderr. `AskUserQuestion`:

| Option | Description |
|--------|-------------|
| **Retry with longer timeout** | Double the timeout to ${DOUBLED_TIMEOUT}s |
| **Use `codex review --base`** | Faster mode, limited to 2-3 findings per pass |
| **Drop `--output-schema`** | Run codex exec without structured output (faster, parse free-text) |
| **Use agent-based review** | Fall back to Claude agent review |
| **Abort** | Stop the `/ship` workflow |

For "Retry": set `CODEX_TIMEOUT=$DOUBLED_TIMEOUT` and re-run. For "Drop --output-schema": set `CODEX_EXEC_FALLBACK=true`.

#### Other non-zero exit codes

Display exit code, stderr, output. `AskUserQuestion`:

| Option | Description |
|--------|-------------|
| **Retry** | Run the LLM review command again |
| **Debug / Fix** | Show diagnostics (version, API key, auth, network) |
| **Use agent-based review** | Fall back for this pass |
| **Abort** | Stop `/ship` |

#### Invalid JSON

If `codex exec` returns non-JSON or empty output (and exit code 0), do NOT fall through to the free-text clean-review path. Display the raw output (first 500 chars). `AskUserQuestion`:

| Option | Description |
|--------|-------------|
| **Retry** | Run again |
| **Debug / Fix** | Show codex version, API key, raw output |
| **Use `codex review --base`** | Switch modes for this pass |
| **Use agent-based review** | Fall back |
| **Abort** | Stop |

### Codex Quick Mode (`codex review --base`)

```bash
$CODEX_CMD review --base "$BASE_BRANCH" -c model="${MODEL:-gpt-5.5}"
```

Capture output as free-text `FINDINGS`. Set `CODEX_EXEC_FALLBACK=true`. Persist `quick_mode=true`:

```bash
TMP="$STATE_FILE.tmp"
jq '.quick_mode = "true"' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

### Gemini

If `GEMINI_TIER` is set, display:

> **Note:** `--tier $GEMINI_TIER` was specified but the Gemini CLI does not support service tiers. The tier setting will be ignored for this review pass. Track [gemini-cli](https://github.com/google-gemini/gemini-cli) for updates.

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

### Ollama

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

### Gemini/Ollama error handling

```bash
set +e
if [ "$LLM_CHOICE" = "gemini" ]; then
  FINDINGS=$(gemini <<< "$REVIEW_PROMPT" 2>"/tmp/llm-review-stderr-$$")
elif [ "$LLM_CHOICE" = "ollama" ]; then
  FINDINGS=$(ollama run codellama <<< "$REVIEW_PROMPT" 2>"/tmp/llm-review-stderr-$$")
fi
LLM_EXIT_CODE=$?
LLM_STDERR=$(cat "/tmp/llm-review-stderr-$$" 2>/dev/null)
rm -f "/tmp/llm-review-stderr-$$"
set -e
```

If exit code non-zero or output empty, display diagnostics. `AskUserQuestion` with **Retry** / **Debug / Fix** / **Use agent-based review** / **Abort**.

### Agent-based review (only when `USE_AGENT_REVIEW=true`)

This section runs **ONLY** when the user explicitly chose agent-based review. It NEVER activates automatically.

1. Set `CODEX_EXEC_FALLBACK=true`
2. Read `${CLAUDE_PLUGIN_ROOT}/agents/quality-review-prompt.md`. Adapt for the detected project language (replace Go-specific criteria when not a Go project).
3. Fill template variables: `{WORKTREE_PATH}`, `{CHANGED_FILES}`, `{DIFF}`, `{PATTERNS}` ("Follow existing project conventions"), `{REPO_CONVENTIONS}` (from CLAUDE.md/AGENTS.md if present)
4. `Agent(prompt=<filled>, model=sonnet)`
5. Parse the agent's structured response (skip JSON parsing in 5c):
   - `CLEAN` → `REVIEW_CLEAN=true`, persist, skip Step 6
   - `HAS_FINDINGS` → use FINDINGS section as free-text findings for Step 6

### 5c. Parse Findings

**Structured JSON** (`LLM_CHOICE=codex` AND `CODEX_EXEC_FALLBACK!=true`):

1. Validate JSON: `printf '%s\n' "$REVIEW_JSON" | jq empty 2>/dev/null`. If invalid, fall through to free-text.
2. Extract findings count, overall correctness, confidence via `jq`.
3. Filter `confidence_score < 0.3` (likely false positives).
4. **Zero findings AND `overall_correctness == "patch is correct"`:** clean → `REVIEW_CLEAN=true`, persist. Skip Step 6 but still run Step 7. Proceed to 7.5 + 7.6, skip Step 8's loop-back, go to Step 9.
5. Display findings as a formatted table sorted by priority then confidence.
6. De-duplicate across passes via `(file_path, line_range.start, normalized title)`.
7. Store findings in state file for re-entry.

**Free-text** (codex quick / fallback / gemini / ollama):

- Output `== NO_ISSUES_FOUND` or `< 20 chars`: clean → `REVIEW_CLEAN=true`, **persist** (`jq '.review_clean = "true"'`). Skip Step 6 but still run Step 7. Proceed to 7.5 + 7.6, skip Step 8's loop-back, go to Step 9.
- Otherwise: extract structured findings, display with pass number.
- **Filter bot noise:** silently discard findings containing usage-limit / quota messages.
- **De-duplicate across passes:** skip same `(file, line, issue)` tuples.

## Step 6: Fix Phase

```bash
set_loop_phase ".local/state/ship.loop.local.json" "fixing"
```

For each finding from Step 5c:

1. Read the file and surrounding context
2. Evaluate validity
3. Auto-skip `priority == 3` AND `confidence < 0.5`
4. Apply minimal fix or record skip reason
5. For testable fixes (changes observable behavior): generate a test (`_test.go`/`_test.ts`/`test_*.py`; add table-driven case if existing pattern)

Track `FIXED`, `SKIPPED` (with reasons).

## Step 7: Verify Phase

```bash
set_loop_phase ".local/state/ship.loop.local.json" "verifying"
```

### Codegen drift check (Go projects)

```bash
if [ -f Makefile ]; then
  GEN_TARGET=$(make -qp 2>/dev/null | awk -F: '/^[a-zA-Z0-9_-]+:/ {print $1}' \
    | grep -E '^(generate|gen|codegen|sqlc|proto|templ)$' | head -1 || true)
  if [ -n "$GEN_TARGET" ]; then
    GEN_SNAPSHOT=$(printf '%s\n%s' "$(git diff --name-only)" "$(git ls-files --others --exclude-standard)" | sed '/^$/d' | sort -u)
    echo "Running make $GEN_TARGET..."
    if ! make "$GEN_TARGET" 2>&1; then
      echo "WARNING: make $GEN_TARGET failed (tooling may not be installed). Skipping codegen check."
      GEN_TARGET=""
    fi
  fi
fi

if [ -n "$GEN_TARGET" ]; then
  GEN_MODIFIED=$(git diff --name-only)
  GEN_UNTRACKED=$(git ls-files --others --exclude-standard)
  GEN_ALL=$(printf '%s\n%s' "$GEN_MODIFIED" "$GEN_UNTRACKED" | sed '/^$/d' | sort -u)
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

### Per-language verification

| Language | Build / Test / Lint |
|---|---|
| **Go** (`go.mod`) | `go build ./... && go test ./...` (+ optional `golangci-lint run`) |
| **Node/TS** (`package.json`) | `npm run build && npm test` (+ optional `npm run lint`) |
| **Rust** (`Cargo.toml`) | `cargo build && cargo test` (+ optional `cargo clippy`) |
| **Python** (`pyproject.toml`/`setup.py`) | `pytest` or `python -m pytest` (+ optional `ruff check .` / `flake8 .`) |

If any verification fails: analyze, fix, re-run until all pass.

## Step 7.5: Coverage Verification (Final pass only)

```bash
set_loop_phase ".local/state/ship.loop.local.json" "coverage-check"
```

**Skip when:** `PASS < MAX_PASSES - 1` AND findings were not clean. Proceed to Step 7.6.

Read `${CLAUDE_PLUGIN_ROOT}/skills/coverage/coverage-verification.md` and follow Steps A through F with:

| Variable | Value |
|----------|-------|
| `BASE_BRANCH` | `origin/${BASE_BRANCH}` |
| `STATE_FILE` | `.local/state/ship.loop.local.json` |
| `SKIP_COVERAGE` | from parsed args |
| `COVERAGE_THRESHOLD` | from parsed args (default 60) |

Generated test files will be staged + committed in Step 8 alongside LLM review fixes.

## Step 7.6: E2E Smoke Testing (optional)

### Skip Conditions

Skip to Step 8 if ANY of:

- `SKIP_COVERAGE=true`
- Chrome DevTools MCP tools NOT available (check `mcp__chrome-devtools-mcp__navigate_page` in tool list)
- Project has NO web components (none of: `.templ` files, Go HTTP handler patterns `http.Handler|echo.Context|gin.Context|chi.Router|http.HandleFunc`, `*.html` / `*.tsx` / `*.vue` files)
- No web-facing files were changed in the diff

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

### Set phase, detect dev server

```bash
set_loop_phase ".local/state/ship.loop.local.json" "e2e-testing"
```

Detect command: Air (`.air.toml`) → `air`; Makefile target `run`/`serve`/`dev` → `make <target>`; `package.json` script `dev`/`start` → `npm run dev` / `npm start`; Go fallback → `go run ./cmd/*/main.go` or `go run .`.

Detect port: Air config, `PORT` env var, `.env`/`.env.local`, defaults `8080` (Go) / `3000` (Node) / `5173` (Vite).

### Start server, wait for readiness

```bash
$DEV_SERVER_CMD &
SERVER_PID=$!
for i in $(seq 1 30); do
  curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT" 2>/dev/null | grep -qE '^[23]' && break
  sleep 1
done
```

If server fails to start within 30s → warn and skip to Step 8. Do NOT block shipping.

### Execute smoke tests

For each changed handler/route/template, identify the URL path and:

- `mcp__chrome-devtools-mcp__navigate_page` — load URL
- `mcp__chrome-devtools-mcp__take_screenshot` — capture page
- `mcp__chrome-devtools-mcp__list_console_messages` — JS errors
- `mcp__chrome-devtools-mcp__list_network_requests` — failed requests (5xx)
- For forms: `mcp__chrome-devtools-mcp__fill` + `mcp__chrome-devtools-mcp__click`, verify no errors

Record per page: URL, HTTP status, console errors, screenshot path.

### Cleanup and report

```bash
kill $SERVER_PID 2>/dev/null || true

TMP=".local/state/ship.loop.local.json.tmp"
jq --arg attempted "true" --arg result "$E2E_RESULT" --argjson pages "$PAGES_TESTED" \
   '.e2e_attempted = $attempted | .e2e_result = $result | .e2e_pages_tested = $pages' \
   ".local/state/ship.loop.local.json" > "$TMP" && mv "$TMP" ".local/state/ship.loop.local.json"

rm -f .local/state/coverage.out .local/state/coverage.json 2>/dev/null || true
```

Display:

```
## E2E Smoke Test Results

| Route | Status | Console Errors | Screenshot |
|-------|--------|---------------|------------|
| / | 200 OK | None | ✓ captured |
| /api/users | 200 OK | None | N/A (API) |

Pages tested: N | Passed: N | Errors: N
```

E2E failures are informational, NEVER block:

- 500/404 → report as finding, don't block
- Console JS errors → report, don't block
- MCP tool fails mid-test → warn, skip remaining
- All results are warnings, not gates

## Step 8: Commit, Increment Pass, Loop Decision

Stage only files modified in fix phase + tests from Step 7.5f (do NOT use `git add -A`):

```bash
git add <list of files modified during fix phase>
git add <list of test files generated in Step 7.5f, if any>
```

Increment pass counter:

```bash
CURRENT_PASS=$(jq -r '.pass // 0' ".local/state/ship.loop.local.json")
NEW_PASS=$((CURRENT_PASS + 1))
TMP=".local/state/ship.loop.local.json.tmp"
jq --argjson p "$NEW_PASS" '.pass = $p' ".local/state/ship.loop.local.json" > "$TMP" && mv "$TMP" ".local/state/ship.loop.local.json"
PASS=$NEW_PASS
```

Commit only if there are staged changes:

```bash
TESTS_GEN=$(jq -r '.coverage_tests_generated // 0' ".local/state/ship.loop.local.json")
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

Loop decision:

- `REVIEW_CLEAN=true` → Phase 2 (no point re-reviewing clean code)
- `PASS >= MAX_PASSES` → Phase 2
- Otherwise → back to Step 5
