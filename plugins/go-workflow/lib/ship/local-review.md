# Ship — Phase 1: Local LLM Review (Steps 5–8)

Loaded by `skills/ship/SKILL.md` Phase 1. Owns the full review/fix/verify/coverage/E2E/commit cycle.

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
  fi
fi
```

If `CODEX_CMD` is still empty, return to the Step 4 prerequisite flow. Do not
download or execute a package during re-entry detection.

### 5a. Generate Diff

```bash
git fetch origin "$BASE_BRANCH" 2>/dev/null || true
DIFF=$(git diff "origin/${BASE_BRANCH}...HEAD")
```

If the diff is empty, skip the review loop entirely — proceed to Phase 2 (Step 9).

### 5b. Run LLM Review

**Cross-model default:** the value of this stage is a second model's
perspective. When the diff was written by Claude (the usual case), keep the
`codex` default. When the diff was written by Codex (wtcodex flows), prefer
`--llm fable` so a different model family reviews the work.

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

# Adaptive timeout sized for high reasoning effort: 300s base + 4s per 100 lines, capped at 900s
CODEX_TIMEOUT=$(( 300 + (DIFF_LINES / 25) ))
if [ "$CODEX_TIMEOUT" -gt 900 ]; then CODEX_TIMEOUT=900; fi
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
CODEX_TIMEOUT="${CODEX_TIMEOUT:-300}"
CODEX_MODEL_ARGS=()
if [ -n "${MODEL:-}" ]; then
  CODEX_MODEL_ARGS=(-m "$MODEL")
fi

set +e
if [ -n "$TIMEOUT_CMD" ]; then
  REVIEW_JSON=$($TIMEOUT_CMD "${CODEX_TIMEOUT}" $CODEX_CMD exec "${CODEX_MODEL_ARGS[@]}" -s read-only \
    -c model_reasoning_effort="high" \
    --output-schema "$SCHEMA_FILE" \
    - < "$PROMPT_FILE" 2>"/tmp/codex-review-stderr-$$")
else
  REVIEW_JSON=$($CODEX_CMD exec "${CODEX_MODEL_ARGS[@]}" -s read-only \
    -c model_reasoning_effort="high" \
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
if [ "$DOUBLED_TIMEOUT" -gt 1800 ]; then DOUBLED_TIMEOUT=1800; fi
```

Display diff size, timeout used, partial output, stderr. `AskUserQuestion`:

| Option | Description |
|--------|-------------|
| **Retry with longer timeout** | Double the timeout to ${DOUBLED_TIMEOUT}s |
| **Switch to Fable subagent review** | Same prompt + schema via a Claude subagent — no timeout, no extra cost |
| **Use `codex review --base`** | Faster mode, limited to 2-3 findings per pass |
| **Drop `--output-schema`** | Run codex exec without structured output (faster, parse free-text) |
| **Use agent-based review** | Fall back to Claude agent review |
| **Abort** | Stop the `$ship` workflow |

For "Retry": set `CODEX_TIMEOUT=$DOUBLED_TIMEOUT` and re-run. For "Switch to Fable subagent review": set `LLM_CHOICE=fable` for this pass, re-assemble the prompt and schema (steps 1–2 above), and run the Fable section below. For "Drop --output-schema": set `CODEX_EXEC_FALLBACK=true`.

#### Other non-zero exit codes

Display exit code, stderr, output. `AskUserQuestion`:

| Option | Description |
|--------|-------------|
| **Retry** | Run the LLM review command again |
| **Debug / Fix** | Show diagnostics (version, API key, auth, network) |
| **Use agent-based review** | Fall back for this pass |
| **Abort** | Stop `$ship` |

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
CODEX_REVIEW_MODEL_ARGS=()
if [ -n "${MODEL:-}" ]; then
  CODEX_REVIEW_MODEL_ARGS=(-c "model=$MODEL")
fi

$CODEX_CMD review --base "$BASE_BRANCH" "${CODEX_REVIEW_MODEL_ARGS[@]}" -c model_reasoning_effort="high"
```

Capture output as free-text `FINDINGS`. Set `CODEX_EXEC_FALLBACK=true`. Persist `quick_mode=true`:

```bash
TMP="$STATE_FILE.tmp"
jq '.quick_mode = "true"' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

### Fable — Claude Subagent (`LLM_CHOICE=fable`)

<!-- SYNC: fable-subagent-review — keep aligned with llm-tools lib/review-loop/review-phase.md -->

Review by a fresh-context Claude subagent. No external CLI, no API key, no
timeout wrapper — the subagent runs on the session's subscription and inherits
the session's model. A fresh context window means the reviewer has none of the
implementer's assumptions loaded, which is what makes it a genuine second read.

1. **Assemble the prompt and schema** exactly as in the Codex Exhaustive
   section above (same review instructions, `{REPO_GUIDELINES}`, diff, and
   `$SCHEMA_FILE` contents) — both backends consume the same evidence so
   findings are comparable.
2. **Append the output contract** to the prompt:

   ```text
   ## Output Format

   Respond with ONLY a single JSON object (no markdown fences, no prose
   before or after) conforming exactly to this JSON Schema:

   <contents of $SCHEMA_FILE>
   ```

3. **Dispatch** a subagent via the `Agent` tool with the assembled prompt. Do
   not override the model — it inherits the session's model. Capture the
   subagent's final text as `REVIEW_JSON`, strip any accidental markdown
   fences, and validate with `jq empty`.
4. **Parse** via the structured-JSON path in 5c — identical handling to codex
   exhaustive (confidence filter, priority sort, de-duplication, state file).

**Error handling:** invalid JSON from the subagent is a review failure — do
NOT fall through to the free-text clean path. Display the raw output (first
500 chars), then `AskUserQuestion`: **Retry** / **Debug** (show raw output) /
**Use agent-based review** / **Abort**.

**Running under Codex CLI (no Agent tool):** never shell out to `claude -p` —
headless print mode bills metered API usage, not the subscription. Instead
drive an interactive Claude window via tmux: write the assembled prompt to a
temp file, then `tmux send-keys -t <claude-window> "Read <prompt-file> and
follow it; write the JSON result to <result-file>" Enter`, and poll for the
result file. If no Claude tmux window is available, ask the user via
`AskUserQuestion` (open one / switch to codex / skip) — never silently switch
backends.

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

**Structured JSON** ((`LLM_CHOICE=codex` AND `CODEX_EXEC_FALLBACK!=true`) OR `LLM_CHOICE=fable`):

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

Read `${CLAUDE_PLUGIN_ROOT}/lib/coverage/coverage-verification.md` and follow Steps A through F with:

| Variable | Value |
|----------|-------|
| `BASE_BRANCH` | `origin/${BASE_BRANCH}` |
| `STATE_FILE` | `.local/state/ship.loop.local.json` |
| `SKIP_COVERAGE` | from parsed args |
| `COVERAGE_THRESHOLD` | from parsed args (default 60) |

Generated test files will be staged + committed in Step 8 alongside LLM review fixes.

## Step 7.6: E2E Smoke Testing (blocking for UI-visible diffs)

### Skip vs. block decision

E2E is a gate for UI-visible diffs. Skipping is allowed only when there is
nothing visual to verify, or when a previous `$e2e-verify` pass is
explicitly being reused.

Skip to Step 8 only when ONE of:

- Project has NO web components (none of: `.templ` files, Go HTTP handler
  patterns `http.Handler|echo.Context|gin.Context|chi.Router|http.HandleFunc`,
  `*.html` / `*.tsx` / `*.vue` files).
- No UI-visible files were changed in the diff.
- `SKIP_COVERAGE=true` AND the PR is already marked `e2e-verified` or the
  current loop state shows a prior passing E2E result. This is the deliberate
  reuse path used after `$e2e-verify`; `--skip-coverage` alone is
  not permission to skip E2E.

Block the workflow when the diff is UI-visible and E2E cannot run or fails:

- Chrome DevTools MCP tools are NOT available.
- The dev server is unreachable and cannot be started, or project guidance says
  the user must start it.
- The dev server does not become ready within 30 seconds.
- Browser smoke tests find route failures, console errors, network 5xx errors,
  or MCP/browser failures before all required pages are inspected.

```bash
if [ -z "$CHANGED_FILES" ]; then
  CHANGED_FILES=$(git diff --name-only "origin/${BASE_BRANCH}...HEAD")
fi
WEB_CHANGES=$(echo "$CHANGED_FILES" | grep -E '\.(templ|html|css|tsx|vue|jsx)$' || true)
JS_CHANGES=$(echo "$CHANGED_FILES" | grep -E '(^|/)(cmd|web|ui|assets|static|templates)/.*\.js$' || true)
HANDLER_CHANGES=$(echo "$CHANGED_FILES" | grep '\.go$' | while IFS= read -r f; do
  grep -l -E 'http\.Handler|echo\.Context|gin\.Context|chi\.Router|http\.HandleFunc|http\.ServeMux' "$f" 2>/dev/null
done || true)
UI_VISIBLE_CHANGES=$(printf '%s\n%s\n%s\n' "$WEB_CHANGES" "$JS_CHANGES" "$HANDLER_CHANGES" | sed '/^$/d')
```

If `UI_VISIBLE_CHANGES` is empty, persist:

```bash
TMP=".local/state/ship.loop.local.json.tmp"
jq --arg required "false" --arg attempted "false" --arg result "skipped" --arg reason "no-ui-visible-changes" --argjson pages 0 \
   '.e2e_required = $required | .e2e_attempted = $attempted | .e2e_result = $result | .e2e_skip_reason = $reason | .e2e_pages_tested = $pages' \
   ".local/state/ship.loop.local.json" > "$TMP" && mv "$TMP" ".local/state/ship.loop.local.json"
```

Then skip to Step 8.

If `UI_VISIBLE_CHANGES` is non-empty and Chrome DevTools MCP tools are missing,
persist:

```bash
TMP=".local/state/ship.loop.local.json.tmp"
jq --arg required "true" --arg attempted "false" --arg result "blocked" --arg reason "missing-browser-tooling" --argjson pages 0 \
   '.e2e_required = $required | .e2e_attempted = $attempted | .e2e_result = $result | .e2e_skip_reason = $reason | .e2e_pages_tested = $pages' \
   ".local/state/ship.loop.local.json" > "$TMP" && mv "$TMP" ".local/state/ship.loop.local.json"
```

Display:

```
E2E PREREQUISITE MISSING - Chrome DevTools MCP tooling is unavailable for a UI-visible diff.
No merge. Fix the browser tooling or run $e2e-verify successfully, then re-run $ship.
```

Stop the workflow. Do not continue to push, CI watch, or merge.

### Set phase, detect dev server

```bash
set_loop_phase ".local/state/ship.loop.local.json" "e2e-testing"
```

Detect command: Air (`.air.toml`) → `air`; Makefile target `run`/`serve`/`dev` → `make <target>`; `package.json` script `dev`/`start` → `npm run dev` / `npm start`; Go fallback → `go run ./cmd/*/main.go` or `go run .`.

Detect port: Air config, `PORT` env var, `.env`/`.env.local`, defaults `8080` (Go) / `3000` (Node) / `5173` (Vite).

### Start server, wait for readiness

First check whether the detected URL is already responding. If it is not
responding, start `DEV_SERVER_CMD` only when project guidance permits the agent
to start the dev server. If guidance says the user/operator owns the dev server,
do not start it from `$ship`; block with the prerequisite message below.

```bash
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT" 2>/dev/null | grep -qE '^[1234]'; then
  SERVER_ALREADY_RUNNING=true
elif [ -n "${DEV_SERVER_CMD:-}" ]; then
  # If AGENTS.md, CLAUDE.md, or project docs say the user runs the dev server,
  # leave DEV_SERVER_CMD unset and block below instead of starting it.
  $DEV_SERVER_CMD &
  SERVER_PID=$!
  SERVER_ALREADY_RUNNING=false
else
  SERVER_ALREADY_RUNNING=false
  SERVER_START_SKIPPED=true
fi

for i in $(seq 1 30); do
  curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT" 2>/dev/null | grep -qE '^[1234]' && break
  sleep 1
done
```

If the server is still unreachable after 30 seconds, or no start was attempted
because project guidance requires the user to run it, persist a blocked result:

```bash
TMP=".local/state/ship.loop.local.json.tmp"
jq --arg required "true" --arg attempted "false" --arg result "blocked" --arg reason "dev-server-unavailable" --argjson pages 0 \
   '.e2e_required = $required | .e2e_attempted = $attempted | .e2e_result = $result | .e2e_skip_reason = $reason | .e2e_pages_tested = $pages' \
   ".local/state/ship.loop.local.json" > "$TMP" && mv "$TMP" ".local/state/ship.loop.local.json"
```

Display:

```
E2E PREREQUISITE MISSING - local dev server is not responding at http://localhost:$PORT.
Start it (`make dev` or the project equivalent), then re-run `$ship`.
Pages tested: 0
No merge.
```

Stop the workflow. Do not continue to push, CI watch, or merge.

### Execute smoke tests

For each changed handler/route/template, identify the URL path and:

- `mcp__chrome-devtools-mcp__navigate_page` — load URL
- `mcp__chrome-devtools-mcp__take_screenshot` — capture page
- `mcp__chrome-devtools-mcp__list_console_messages` — JS errors
- `mcp__chrome-devtools-mcp__list_network_requests` — failed requests (5xx)
- For forms: `mcp__chrome-devtools-mcp__fill` + `mcp__chrome-devtools-mcp__click`, verify no errors

Record per page: URL, HTTP status, console errors, screenshot path.

If any page has an unexpected 4xx/5xx status, console JavaScript errors, failed
5xx network requests, browser tooling errors, or an uninspected screenshot,
persist `e2e_result="blocked"` with an explanatory `e2e_skip_reason`, display
the failed route(s), and stop the workflow. No merge.

### Cleanup and report

```bash
if [ "${SERVER_ALREADY_RUNNING:-false}" != "true" ]; then
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
fi

TMP=".local/state/ship.loop.local.json.tmp"
jq --arg required "true" --arg attempted "true" --arg result "$E2E_RESULT" --arg reason "${E2E_SKIP_REASON:-}" --argjson pages "$PAGES_TESTED" \
   '.e2e_required = $required | .e2e_attempted = $attempted | .e2e_result = $result | .e2e_skip_reason = $reason | .e2e_pages_tested = $pages' \
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

For UI-visible diffs, only `e2e_result="passed"` allows `$ship` to continue.
`e2e_result="blocked"` is a hard stop and must not be summarized as
verification complete.

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
