# Ship — Phase 1: Local LLM Review (Steps 5–8)

Loaded by `skills/ship/SKILL.md` Phase 1. Owns the full review/fix/verify/coverage/E2E/commit cycle.

## Step 5: Review Phase

```bash
source "<PLUGIN_ROOT>/lib/loop-state.sh"
set_loop_phase "$STATE_FILE" "reviewing" "$WORKFLOW_STATE_PATH"
PASS=$(get_loop_field "$STATE_FILE" "pass" "$WORKFLOW_STATE_PATH")
PASS="${PASS:-0}"
```

The pass counter is incremented in Step 8 (after commit), not here. This prevents burning a pass number if the session exits mid-review.

### Session-boundary rule for agent-backed reviews

Fable and agent-based reviews must run synchronously in the foreground. Never
use `run_in_background: true`, return while an agent is still running, or
persist an agent handle for a successor session. Wait for the final response
and parse it before leaving Step 5.

In a headless worker context, if an agent-backed review cannot complete in the
current session, do not start it. Persist `review_result="skipped"` and
`review_skip_reason="headless-worker"`, then continue through verification,
commit, push, and non-draft PR creation. PR CI is the authoritative remote
gate. A successor that finds `phase="reviewing"` follows the expired-review
recovery in `skills/ship/SKILL.md`; it never restarts the review.

**Re-detect `$CODEX_CMD` when Step 5 is resumed within the same session**
(the stop hook can jump directly here, skipping Step 4):

```bash
if [ "$LLM_CHOICE" = "codex" ] && [ -z "${CODEX_CMD:-}" ]; then
  if command -v codex &>/dev/null; then
    CODEX_CMD="codex"
  fi
fi
```

If `CODEX_CMD` is still empty, return to the Step 4 prerequisite flow. Do not
download or execute a package during re-entry detection.

### 5a. Generate Diff and Coverage Plan

```bash
git -C "$WORKTREE_PATH" fetch origin "$BASE_BRANCH" 2>/dev/null || true
DIFF=$(git -C "$WORKTREE_PATH" diff "origin/${BASE_BRANCH}...HEAD")
```

If the diff is empty, skip the review loop entirely — proceed to Phase 2 (Step 9).

Otherwise set `REVIEW_BASE="origin/${BASE_BRANCH}"`,
`REVIEW_BACKEND="$LLM_CHOICE"`, and `REVIEW_CONCURRENCY=auto`. Read
`../review-planning.md`, run the shared planner, display the coverage plan, and
follow its units and final coordinator pass. The planner, not raw diff length,
determines whether further partitioning or a backend decision is necessary.

### 5b. Run LLM Review

**Cross-model default:** the value of this stage is a second model's
perspective. When the diff was written by Claude (the usual case), keep the
`codex` default. When the diff was written by Codex (wtcodex flows), prefer
`--llm fable` so a different model family reviews the work.

<!-- SYNC: codex-exec-review — keep aligned with review-loop.md Step 5b -->

#### Codex — Adaptive Timeout

```bash
if command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD="timeout"
else TIMEOUT_CMD=""
fi

DIFF_LINES=$(printf '%s\n' "$DIFF" | wc -l)

# Adaptive timeout sized for high reasoning effort: 300s base + 4s per 100 lines, capped at 900s
CODEX_TIMEOUT=$(( 300 + (DIFF_LINES / 25) ))
if [ "$CODEX_TIMEOUT" -gt 900 ]; then CODEX_TIMEOUT=900; fi
```

Use the shared coverage plan for full-context or partitioned execution. If it
reports `REVIEW_PLAN_REQUIRES_INPUT=yes`, apply the decision policy in
`../review-planning.md`. Never narrow baseline coverage or request input solely
because the diff is large.

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
  REVIEW_JSON=$(cd "$WORKTREE_PATH" && $TIMEOUT_CMD "${CODEX_TIMEOUT}" $CODEX_CMD exec "${CODEX_MODEL_ARGS[@]}" -s read-only \
    -c model_reasoning_effort="high" \
    --output-schema "$SCHEMA_FILE" \
    - < "$PROMPT_FILE" 2>"/tmp/codex-review-stderr-$$")
else
  REVIEW_JSON=$(cd "$WORKTREE_PATH" && $CODEX_CMD exec "${CODEX_MODEL_ARGS[@]}" -s read-only \
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
  echo "WARNING: Codex review produced no JSON output after header stripping"
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

Display diff size, timeout used, partial output, and stderr. Resolve a
**driver-resolvable gate**:

1. Retry once with `CODEX_TIMEOUT=$DOUBLED_TIMEOUT`.
2. If the longer attempt times out and schema processing is implicated, set
   `CODEX_EXEC_FALLBACK=true` and retry without `--output-schema`.
3. Otherwise select `codex review --base` when its bounded findings can be
   covered across the remaining passes.
4. If the selected recovery cannot provide complete coverage, use an available
   fallback only when `LLM_EXPLICIT=false`; state `Decision`, `Evidence`, and
   `Rationale`.

If recovery would replace an explicitly selected backend, follow the shared
**missing-intent gate** and stop before switching.

#### Other non-zero exit codes

Display exit code, stderr, and output. Inspect version, authentication, network,
and command diagnostics. Retry once when the evidence identifies a transient or
correctable failure. If failure persists, use an available fallback only when
`LLM_EXPLICIT=false`; otherwise follow the shared **missing-intent gate** before
replacing the explicitly selected backend. If no complete review path remains,
stop incomplete with `WORKFLOW_REASON=review-backend-failed`.

#### Invalid JSON

If `codex exec` returns non-JSON or empty output (and exit code 0), do NOT fall
through to the free-text clean-review path. Display the raw output (first 500
chars), retry once, then set `CODEX_EXEC_FALLBACK=true` and run the same backend
without structured output. If output is still unusable, apply the explicit
backend rule above. Never interpret invalid output as a clean review.

### Codex Quick Mode (`codex review --base`)

```bash
CODEX_REVIEW_MODEL_ARGS=()
if [ -n "${MODEL:-}" ]; then
  CODEX_REVIEW_MODEL_ARGS=(-c "review_model=$MODEL")
fi

(cd "$WORKTREE_PATH" && $CODEX_CMD review --base "$BASE_BRANCH" "${CODEX_REVIEW_MODEL_ARGS[@]}" -c model_reasoning_effort="high")
```

Capture output as free-text `FINDINGS`. Set `CODEX_EXEC_FALLBACK=true`. Persist `quick_mode=true`:

```bash
set_loop_field "$STATE_FILE" "quick_mode" "true" "$WORKFLOW_STATE_PATH"
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

3. **Delegate synchronously** through the active surface with the assembled
   prompt. Do not override the model — it inherits the session's model. Wait
   for the final response in the current session, capture it as `REVIEW_JSON`,
   strip any accidental markdown fences, and validate with `jq empty`.
4. **Parse** via the structured-JSON path in 5c — identical handling to codex
   exhaustive (confidence filter, priority sort, de-duplication, state file).

**Error handling:** invalid JSON from the subagent is a review failure — do
NOT fall through to the free-text clean path. Display the raw output (first
500 chars) and retry once. If the backend was explicitly selected, follow the
shared missing-intent gate before replacing it. Otherwise select the next
usable review path from prerequisite evidence and state the rationale.

**When native Claude-subagent delegation is unavailable:** never shell out to
`claude -p` — headless print mode bills metered API usage, not the
subscription. Instead drive an interactive Claude window via tmux: write the
assembled prompt to a temp file, then `tmux send-keys -t <claude-window> "Read
<prompt-file> and follow it; write the JSON result to <result-file>" Enter`,
and poll for the result file. If no Claude tmux window is available and Fable
was explicitly selected, follow the shared missing-intent gate before switching
backends. If it was driver-selected as an unpinned fallback, select the next
usable backend, state the evidence and rationale, and continue. Never skip the
review silently.

### Gemini

If `GEMINI_TIER` is set, display:

> **Note:** `--tier $GEMINI_TIER` was specified but the Gemini CLI does not support service tiers. The tier setting will be ignored for this review pass. Track [gemini-cli](https://github.com/google-gemini/gemini-cli) for updates.

```bash
(cd "$WORKTREE_PATH" && gemini <<EOF
Review the following code changes for bugs, security issues, performance problems, and best practice violations.

Report each finding with: file path, line number, severity (error/warning/suggestion), and description.
If there are no issues, respond with exactly: NO_ISSUES_FOUND

\`\`\`diff
$DIFF
\`\`\`
EOF
)
```

### Ollama

Resolve the model once per ship run. On re-entry, restore `OLLAMA_MODEL` from
the state file before resolving so every review pass uses the same model.

```bash
OLLAMA_MODEL=${OLLAMA_MODEL:-$(get_loop_field "$STATE_FILE" "ollama_model" "$WORKFLOW_STATE_PATH")}
if [ -z "$OLLAMA_MODEL" ]; then
  set +e
  OLLAMA_MODEL=$(cd "$WORKTREE_PATH" && /bin/bash "<PLUGIN_ROOT>/scripts/select-ollama-model.sh" 2>"/tmp/ollama-select-stderr-$$")
  OLLAMA_SELECT_EXIT_CODE=$?
  OLLAMA_SELECT_STDERR=$(cat "/tmp/ollama-select-stderr-$$" 2>/dev/null)
  rm -f "/tmp/ollama-select-stderr-$$"
  set -e
fi
```

If model selection exits non-zero or returns an empty model, display
`OLLAMA_SELECT_STDERR`, inspect the installed model list and service state, and
retry selection once after any evidenced local fix. If Ollama was explicitly
selected, follow the shared missing-intent gate before replacing it. Otherwise
select the next usable review path and state the rationale. Do not persist a
model or continue to `ollama run` until selection succeeds.

After successful selection, persist the model:

```bash
set_loop_field "$STATE_FILE" "ollama_model" "$OLLAMA_MODEL" "$WORKFLOW_STATE_PATH"

echo "Using installed Ollama model: $OLLAMA_MODEL"
(cd "$WORKTREE_PATH" && ollama run "$OLLAMA_MODEL" <<EOF
Review the following code changes for bugs, security issues, performance problems, and best practice violations.

Report each finding with: file path, line number, severity (error/warning/suggestion), and description.
If there are no issues, respond with exactly: NO_ISSUES_FOUND

\`\`\`diff
$DIFF
\`\`\`
EOF
)
```

### Gemini/Ollama error handling

```bash
set +e
if [ "$LLM_CHOICE" = "gemini" ]; then
  FINDINGS=$(cd "$WORKTREE_PATH" && gemini <<< "$REVIEW_PROMPT" 2>"/tmp/llm-review-stderr-$$")
elif [ "$LLM_CHOICE" = "ollama" ]; then
  FINDINGS=$(cd "$WORKTREE_PATH" && ollama run "$OLLAMA_MODEL" <<< "$REVIEW_PROMPT" 2>"/tmp/llm-review-stderr-$$")
fi
LLM_EXIT_CODE=$?
LLM_STDERR=$(cat "/tmp/llm-review-stderr-$$" 2>/dev/null)
rm -f "/tmp/llm-review-stderr-$$"
set -e
```

If exit code is non-zero or output is empty, display diagnostics, including the
selected Ollama model for an Ollama run failure. Retry the same persisted model
once when diagnostics identify a transient or correctable failure. Do not
silently select a different Ollama model. Replacing an explicitly selected
backend follows the shared missing-intent gate; an unpinned backend follows the
prerequisite fallback ordering with a stated rationale.

### Delegated agent review (only when `USE_AGENT_REVIEW=true`)

This section runs only when the driver selected agent-based review for an
unpinned backend or the user explicitly authorized replacing a pinned backend.

1. Set `CODEX_EXEC_FALLBACK=true`
2. Read `<PLUGIN_ROOT>/agents/quality-review-prompt.md`. Adapt for the detected project language (replace Go-specific criteria when not a Go project).
3. Fill template variables: `{WORKTREE_PATH}`, `{CHANGED_FILES}`, `{DIFF}`, `{PATTERNS}` ("Follow existing project conventions"), `{REPO_CONVENTIONS}` (from CLAUDE.md/AGENTS.md if present)
4. Delegate synchronously through the active surface with the filled prompt,
   selecting sonnet when the surface supports model choice, and wait for the
   final response in the current session.
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
set_loop_phase "$STATE_FILE" "fixing" "$WORKFLOW_STATE_PATH"
```

For each finding from Step 5c:

1. Read the file and surrounding context
2. Evaluate validity
3. Auto-skip `priority == 3` AND `confidence < 0.5`
4. Apply minimal fix or record skip reason
5. For testable fixes (changes observable behavior): generate a test (`_test.go`/`_test.ts`/`test_*.py`; add table-driven case if existing pattern)

Track `FIXED`, `SKIPPED` (with reasons), and `REVIEW_FILES`, an array containing
only paths modified while addressing findings or generating their tests.

## Step 7: Verify Phase

```bash
set_loop_phase "$STATE_FILE" "verifying" "$WORKFLOW_STATE_PATH"
```

### Codegen drift check (Go projects)

```bash
if [ -f "$WORKTREE_PATH/Makefile" ]; then
  GEN_TARGET=$(cd "$WORKTREE_PATH" && make -qp 2>/dev/null | awk -F: '/^[a-zA-Z0-9_-]+:/ {print $1}' \
    | grep -E '^(generate|gen|codegen|sqlc|proto|templ)$' | head -1 || true)
  if [ -n "$GEN_TARGET" ]; then
    GEN_SNAPSHOT=$(printf '%s\n%s' "$(git -C "$WORKTREE_PATH" diff --name-only)" "$(git -C "$WORKTREE_PATH" ls-files --others --exclude-standard)" | sed '/^$/d' | sort -u)
    echo "Running make $GEN_TARGET..."
    if ! (cd "$WORKTREE_PATH" && make "$GEN_TARGET" 2>&1); then
      WORKFLOW_REASON="generation-failed"
    fi
  fi
fi

if [ -n "$GEN_TARGET" ] && [ -z "${WORKFLOW_REASON:-}" ]; then
  GEN_MODIFIED=$(git -C "$WORKTREE_PATH" diff --name-only)
  GEN_UNTRACKED=$(git -C "$WORKTREE_PATH" ls-files --others --exclude-standard)
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
    printf '%s\n' "$GEN_NEW" | xargs git -C "$WORKTREE_PATH" add --
  fi
fi
```

If `WORKFLOW_REASON=generation-failed`, report:

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=generation-failed
```

Follow the top-level **Hard Invariant Failure** procedure and stop before
verification or commit.

### Per-language verification

| Language | Build / Test / Lint |
|---|---|
| **Go** (`go.mod`) | `go -C "$WORKTREE_PATH" build ./... && go -C "$WORKTREE_PATH" test ./...`; run `(cd "$WORKTREE_PATH" && golangci-lint run)` when installed |
| **Node/TS** (`package.json`) | `(cd "$WORKTREE_PATH" && npm run build && npm test && npm run lint --if-present)` |
| **Rust** (`Cargo.toml`) | `(cd "$WORKTREE_PATH" && cargo build && cargo test)`; run `(cd "$WORKTREE_PATH" && cargo clippy)` when `(cd "$WORKTREE_PATH" && cargo clippy --version)` succeeds or the repository explicitly configures Clippy |
| **Python** (`pyproject.toml`/`setup.py`) | `(cd "$WORKTREE_PATH" && pytest)` or `(cd "$WORKTREE_PATH" && python -m pytest)`; run installed linters from the same worktree-scoped group |

If any verification fails: analyze, fix, and rerun until all pass. If a
generation, build, test, or configured lint failure cannot be fixed in this
run, report:

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=verification-failed
```

Follow the top-level **Hard Invariant Failure** procedure and stop before
coverage, commit, push, or completion.

## Step 7.5: Coverage Verification (Final pass only)

```bash
set_loop_phase "$STATE_FILE" "coverage-check" "$WORKFLOW_STATE_PATH"
```

**Skip when:** `PASS < MAX_PASSES - 1` AND findings were not clean. Proceed to Step 7.6.

Read `<PLUGIN_ROOT>/lib/coverage/coverage-verification.md` and follow Steps A through F with:

| Variable | Value |
|----------|-------|
| `BASE_BRANCH` | `origin/${BASE_BRANCH}` |
| `WORKTREE_PATH` | absolute persisted worktree path |
| `STATE_FILE` | resolved caller-owned or standalone absolute state path |
| `WORKFLOW_STATE_PATH` | resolved ship object path in `STATE_FILE` |
| `SKIP_COVERAGE` | from parsed args |
| `COVERAGE_THRESHOLD` | from parsed args (default 60) |

Generated test files will be staged + committed in Step 8 alongside LLM review fixes.

## Step 7.6: E2E Smoke Testing (blocking for UI-visible diffs)

### Skip vs. block decision

E2E is a gate for UI-visible diffs. Skipping is allowed only when there is
nothing visual to verify, or when a previous `$go-workflow:e2e-verify` pass is
explicitly being reused.

Skip to Step 8 only when ONE of:

- Project has NO web components (none of: `.templ` files, Go HTTP handler
  patterns `http.Handler|echo.Context|gin.Context|chi.Router|http.HandleFunc`,
  `*.html` / `*.tsx` / `*.vue` files).
- No UI-visible files were changed in the diff.
- The PR is already marked `e2e-verified` or the current loop state shows a
  prior passing E2E result. This is the deliberate reuse path used after
  `$go-workflow:e2e-verify`; the coverage compatibility flag is not permission to skip
  E2E.

Block the workflow when the diff is UI-visible and E2E cannot run or fails:

- Chrome DevTools MCP tools are NOT available.
- The dev server is unreachable and cannot be started, or project guidance says
  the user must start it.
- The dev server does not become ready within 30 seconds.
- Browser smoke tests find route failures, console errors, network 5xx errors,
  or MCP/browser failures before all required pages are inspected.

```bash
if [ -z "$CHANGED_FILES" ]; then
  CHANGED_FILES=$(git -C "$WORKTREE_PATH" diff --name-only "origin/${BASE_BRANCH}...HEAD")
fi
WEB_CHANGES=$(echo "$CHANGED_FILES" | grep -E '\.(templ|html|css|tsx|vue|jsx)$' || true)
JS_CHANGES=$(echo "$CHANGED_FILES" | grep -E '(^|/)(cmd|web|ui|assets|static|templates)/.*\.js$' || true)
HANDLER_CHANGES=$(echo "$CHANGED_FILES" | grep '\.go$' | while IFS= read -r f; do
  grep -l -E 'http\.Handler|echo\.Context|gin\.Context|chi\.Router|http\.HandleFunc|http\.ServeMux' "$WORKTREE_PATH/$f" 2>/dev/null
done || true)
UI_VISIBLE_CHANGES=$(printf '%s\n%s\n%s\n' "$WEB_CHANGES" "$JS_CHANGES" "$HANDLER_CHANGES" | sed '/^$/d')
```

If `UI_VISIBLE_CHANGES` is empty, persist:

```bash
set_loop_field "$STATE_FILE" "e2e_required" "false" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_attempted" "false" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_result" "skipped" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_skip_reason" "no-ui-visible-changes" "$WORKFLOW_STATE_PATH"
set_loop_json_field "$STATE_FILE" "e2e_pages_tested" 0 "$WORKFLOW_STATE_PATH"
```

Then skip to Step 8.

Resolve the Chrome DevTools namespace from the available tools once. The
official Chrome DevTools Claude plugin uses `mcp__chrome-devtools__*`; existing
user configurations may expose `mcp__chrome-devtools-mcp__*`. Examples below
show the latter, but invoke the namespace that is actually available. If
`UI_VISIBLE_CHANGES` is non-empty and neither namespace provides the required
browser tools, persist:

```bash
set_loop_field "$STATE_FILE" "e2e_required" "true" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_attempted" "false" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_result" "blocked" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_skip_reason" "missing-browser-tooling" "$WORKFLOW_STATE_PATH"
set_loop_json_field "$STATE_FILE" "e2e_pages_tested" 0 "$WORKFLOW_STATE_PATH"
```

Display:

```
E2E PREREQUISITE MISSING - Chrome DevTools MCP tooling is unavailable for a UI-visible diff.
No merge. Fix the browser tooling or run $go-workflow:e2e-verify successfully, then re-run $go-workflow:ship.
```

Stop the workflow. Do not continue to push, CI watch, or merge.

### Set phase, detect dev server

```bash
set_loop_phase "$STATE_FILE" "e2e-testing" "$WORKFLOW_STATE_PATH"
```

Detect command beneath `$WORKTREE_PATH` and store the raw executable command in
`DEV_SERVER_CMD`: Air (`.air.toml`) → `air`; Makefile target
`run`/`serve`/`dev` → `make <target>`; `package.json` script `dev`/`start` →
`npm run dev` / `npm start`; Go fallback → `go run ./cmd/*/main.go` or `go run .`.

Detect port: Air config, `PORT` env var, `.env`/`.env.local`, defaults `8080` (Go) / `3000` (Node) / `5173` (Vite).

### Start server, wait for readiness

First check whether the detected URL is already responding. If it is not
responding, start `DEV_SERVER_CMD` only when project guidance permits the agent
to start the dev server. If guidance says the user/operator owns the dev server,
do not start it from `$go-workflow:ship`; block with the prerequisite message below.

```bash
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT" 2>/dev/null | grep -qE '^[1234]'; then
  SERVER_ALREADY_RUNNING=true
elif [ -n "${DEV_SERVER_CMD:-}" ]; then
  # If AGENTS.md, CLAUDE.md, or project docs say the user runs the dev server,
  # leave DEV_SERVER_CMD unset and block below instead of starting it.
  (cd "$WORKTREE_PATH" && $DEV_SERVER_CMD) &
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
set_loop_field "$STATE_FILE" "e2e_required" "true" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_attempted" "false" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_result" "blocked" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_skip_reason" "dev-server-unavailable" "$WORKFLOW_STATE_PATH"
set_loop_json_field "$STATE_FILE" "e2e_pages_tested" 0 "$WORKFLOW_STATE_PATH"
```

Display:

```
E2E PREREQUISITE MISSING - local dev server is not responding at http://localhost:$PORT.
Start it (`(cd "$WORKTREE_PATH" && make dev)` or the project equivalent), then re-run `$go-workflow:ship`.
Pages tested: 0
No merge.
```

Stop the workflow. Do not continue to push, CI watch, or merge.

### Browser tool-call failures

MCP connection and tool discovery prove only that the client and server can
complete discovery. The first real browser call can still fail because the
browser cannot launch, the selected page was lost, a tool schema changed, or
the client/server connection churned. Treat any browser tool error before all
required pages are inspected as a blocking runtime failure. A failure on the
first call records zero pages; a later failure preserves the number already
inspected. Never downgrade either case to skipped or passed.

### Record browser tool-call failure

```bash
set_loop_field "$STATE_FILE" "e2e_required" "true" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_attempted" "true" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_result" "blocked" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_skip_reason" "browser-tool-call-failed" "$WORKFLOW_STATE_PATH"
set_loop_json_field "$STATE_FILE" "e2e_pages_tested" "${PAGES_TESTED:-0}" "$WORKFLOW_STATE_PATH"
```

Display the failed tool, route, and returned error, clean up a server started
by the workflow, and stop. Do not retry against a reconnected MCP server in the
same E2E result because its page selection and browser state are not proven.

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
persist `e2e_result="blocked"` with an explanatory `e2e_skip_reason`. Browser
tooling errors use the recording block above. Display the failed route(s) and
stop the workflow. No merge.

### Cleanup and report

```bash
if [ "${SERVER_ALREADY_RUNNING:-false}" != "true" ]; then
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
fi

set_loop_field "$STATE_FILE" "e2e_required" "true" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_attempted" "true" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_result" "$E2E_RESULT" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "e2e_skip_reason" "${E2E_SKIP_REASON:-}" "$WORKFLOW_STATE_PATH"
set_loop_json_field "$STATE_FILE" "e2e_pages_tested" "$PAGES_TESTED" "$WORKFLOW_STATE_PATH"

rm -f "$WORKTREE_PATH/.local/state/coverage.out" "$WORKTREE_PATH/.local/state/coverage.json" 2>/dev/null || true
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

For UI-visible diffs, only `e2e_result="passed"` allows `$go-workflow:ship` to continue.
`e2e_result="blocked"` is a hard stop and must not be summarized as
verification complete.

## Step 8: Commit, Increment Pass, Loop Decision

Stage only files modified in fix phase + tests from Step 7.5f (do NOT use `git add -A`):

```bash
if [ "${#REVIEW_FILES[@]}" -gt 0 ]; then
  git -C "$WORKTREE_PATH" add -- "${REVIEW_FILES[@]}"
fi
```

Increment pass counter:

```bash
CURRENT_PASS=$(get_loop_field "$STATE_FILE" "pass" "$WORKFLOW_STATE_PATH")
CURRENT_PASS="${CURRENT_PASS:-0}"
NEW_PASS=$((CURRENT_PASS + 1))
set_loop_json_field "$STATE_FILE" "pass" "$NEW_PASS" "$WORKFLOW_STATE_PATH"
PASS=$NEW_PASS
```

Commit only if there are staged changes:

```bash
TESTS_GEN=$(get_loop_field "$STATE_FILE" "coverage_tests_generated" "$WORKFLOW_STATE_PATH")
TESTS_GEN="${TESTS_GEN:-0}"
if ! git -C "$WORKTREE_PATH" diff --cached --quiet; then
  if [ "$TESTS_GEN" -gt 0 ] 2>/dev/null; then
    git -C "$WORKTREE_PATH" commit -m "$(cat <<EOF
fix: address $LLM_CHOICE review findings (pass $PASS)

- Generated tests for $TESTS_GEN uncovered functions
EOF
)"
  else
    git -C "$WORKTREE_PATH" commit -m "fix: address $LLM_CHOICE review findings (pass $PASS)"
  fi
fi
```

Loop decision:

- `REVIEW_CLEAN=true` → Phase 2 (no point re-reviewing clean code)
- `PASS >= MAX_PASSES` → Phase 2
- Otherwise → back to Step 5
