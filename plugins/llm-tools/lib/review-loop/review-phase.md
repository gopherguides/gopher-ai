# Review Loop — Review Phase Execution (Step 5b)

Loaded by `commands/review-loop.md` Step 5b. Owns the five LLM execution paths
(codex exhaustive `exec --output-schema`, codex quick `review`, gemini, ollama,
fable Claude-subagent), the prompt-template assembly, the timeout detection,
the large-diff warning, and all `AskUserQuestion`-based error handling.

## Codex — Exhaustive Mode (default, `QUICK_MODE=false`)

Use `codex exec` with structured output to bypass `codex review`'s 2-3 finding
cap.

### Step 1 — Read prompt template

```bash
PROMPT_TEMPLATE=$(cat "${CLAUDE_PLUGIN_ROOT}/prompts/codex-review.md")
```

### Step 2 — Fill placeholders

- `{DIFF}` ← diff from review-loop Step 5a
- `{SCOPE_HINT}` ← if `SCOPE_HINT` is set, render as `## Specific Focus Area\n$SCOPE_HINT`; else empty
- `{REPO_GUIDELINES}` ← `AGENTS.md` in repo root if present, else `CLAUDE.md`, else empty. When found, render as `## Repository Review Guidelines\n$(cat <file>)`.
- `{PR_CONTEXT}` ← if a PR was detected in Step 4a, render PR number, title, body, and linked issues; otherwise empty

### Step 3 — Detect timeout command and size diff

```bash
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
else
  TIMEOUT_CMD=""
fi

DIFF_LINES=$(printf '%s\n' "$DIFF" | wc -l)
DIFF_FILES=$(printf '%s\n' "$DIFF" | grep -c '^diff --git' || echo 0)
echo "Diff size: $DIFF_LINES lines across $DIFF_FILES files"

# Adaptive timeout sized for high reasoning effort: 300s base + 4s per 100 lines, capped at 900s
CODEX_TIMEOUT=$(( 300 + (DIFF_LINES / 25) ))
if [ "$CODEX_TIMEOUT" -gt 900 ]; then CODEX_TIMEOUT=900; fi
```

### Large-diff warning (>3000 lines)

If `DIFF_LINES > 3000`, ask via `AskUserQuestion` BEFORE starting:

> **"Large diff detected ($DIFF_LINES lines, $DIFF_FILES files). Codex exec may timeout on diffs this large. How would you like to proceed?"**

| Option | Description |
|--------|-------------|
| **Proceed with codex exec** | Run with extended timeout (${CODEX_TIMEOUT}s) — may still timeout |
| **Use `codex review --base`** | Faster but limited to 2-3 findings per pass (no structured output) |
| **Skip review** | Stop the review loop |

If the user picks `codex review --base`, set `QUICK_MODE=true` and persist:

```bash
TMP="$STATE_FILE.tmp"
jq '.quick_mode = "true"' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

Then use the quick-mode path below.

### Step 4 — Execute

Write the assembled prompt to a temp file (avoids heredoc expansion issues with special characters in diffs), then run with the adaptive timeout:

```bash
PROMPT_FILE=$(mktemp /tmp/codex-review-prompt-XXXXXX)
echo "$ASSEMBLED_PROMPT" > "$PROMPT_FILE"

MODEL_ARGS=()
if [ -n "$MODEL" ]; then
  MODEL_ARGS=(-m "$MODEL")
fi

set +e
if [ -n "$TIMEOUT_CMD" ]; then
  REVIEW_JSON=$($TIMEOUT_CMD "${CODEX_TIMEOUT}" $CODEX_CMD exec "${MODEL_ARGS[@]}" -s read-only \
    -c model_reasoning_effort="high" \
    --output-schema "${CLAUDE_PLUGIN_ROOT}/schemas/codex-review.json" \
    - < "$PROMPT_FILE" 2>"/tmp/codex-review-stderr-$$")
else
  REVIEW_JSON=$($CODEX_CMD exec "${MODEL_ARGS[@]}" -s read-only \
    -c model_reasoning_effort="high" \
    --output-schema "${CLAUDE_PLUGIN_ROOT}/schemas/codex-review.json" \
    - < "$PROMPT_FILE" 2>"/tmp/codex-review-stderr-$$")
fi
CODEX_EXIT_CODE=$?
CODEX_STDERR=$(cat "/tmp/codex-review-stderr-$$" 2>/dev/null)
rm -f "/tmp/codex-review-stderr-$$"
set -e

# Strip codex exec headers (version/config info printed before JSON)
REVIEW_JSON=$(printf '%s\n' "$REVIEW_JSON" | awk '/^\{/{found=1} found{print}')
# Guard: if stripping removed all output, codex exec returned no JSON
if [ -z "$REVIEW_JSON" ] && [ "$CODEX_EXIT_CODE" -eq 0 ]; then
  echo "WARNING: $CODEX_CMD exec produced no JSON output after header stripping"
  REVIEW_JSON='{"error":"no JSON output"}'
fi
rm -f "$PROMPT_FILE"
```

### Error Handling — never silently fail

#### Exit code 124 (timeout)

```bash
DOUBLED_TIMEOUT=$(( CODEX_TIMEOUT * 2 ))
if [ "$DOUBLED_TIMEOUT" -gt 1800 ]; then DOUBLED_TIMEOUT=1800; fi
```

Display diff size, timeout used, partial output, and stderr. Then ask:

> **"Codex exec timed out after ${CODEX_TIMEOUT}s. How would you like to proceed?"**

| Option | Description |
|--------|-------------|
| **Retry with longer timeout** | Double the timeout to ${DOUBLED_TIMEOUT}s |
| **Use `codex review --base`** | Faster mode, limited to 2-3 findings per pass |
| **Drop `--output-schema`** | Run codex exec without structured output (faster, parse free-text) |
| **Skip review** | Stop the review loop |

For "Retry with longer timeout": set `CODEX_TIMEOUT=$DOUBLED_TIMEOUT` and re-run from Step 4.
For "Drop `--output-schema`": re-run without the schema flag and parse the free-text response. Set `CODEX_EXEC_FALLBACK=true`.

#### Other non-zero exit codes

Display exit code, stderr, and any output. Then ask:

> **"`$LLM_CHOICE` exec failed (exit code $CODEX_EXIT_CODE). How would you like to proceed?"**

| Option | Description |
|--------|-------------|
| **Retry** | Run the command again |
| **Debug / Fix** | Show diagnostics (version, API key, auth, network) |
| **Skip review** | Stop the review loop |

### JSON validation guard

If `codex exec` returns non-JSON or empty output (and `CODEX_EXIT_CODE == 0`),
this is a review failure — do NOT fall through to the free-text clean-review
path (which would treat empty output as `NO_ISSUES_FOUND`). Display the raw
output (first 500 chars), then ask:

> **"Codex exec returned invalid output. Review did not complete."**

| Option | Description |
|--------|-------------|
| **Retry** | Run `$CODEX_CMD exec` again |
| **Debug / Fix** | Investigate (codex version, API key status, raw output) |
| **Use `codex review --base`** | Use the simpler codex review mode for this pass |
| **Skip review** | Stop the review loop |

## Codex — Quick Mode (`--quick` flag, `QUICK_MODE=true`)

Standard `codex review`, faster but capped at 2-3 findings per pass.

```bash
MODEL_CONFIG=()
if [ -n "$MODEL" ]; then
  MODEL_CONFIG=(-c "model=$MODEL")
fi

# For changes vs branch:
$CODEX_CMD review --base "$BASE_BRANCH" "${MODEL_CONFIG[@]}" -c model_reasoning_effort="high"

# For uncommitted:
$CODEX_CMD review --uncommitted "${MODEL_CONFIG[@]}" -c model_reasoning_effort="high"

# For specific files or when scope hint is provided, use stdin:
DIFF=$(git diff ${BASE_BRANCH}...HEAD -- <files>)
$CODEX_CMD review "${MODEL_CONFIG[@]}" -c model_reasoning_effort="high" - <<EOF
$DIFF

## Review Instructions
${SCOPE_HINT:+Focus area: $SCOPE_HINT}
Report each finding with: file path, line number, severity (error/warning/suggestion), and description.
If there are no issues, respond with exactly: NO_ISSUES_FOUND
EOF
```

Capture output as free-text `FINDINGS`.

## Fable — Claude Subagent (`LLM_CHOICE=fable`)

<!-- SYNC: fable-subagent-review — keep aligned with go-workflow lib/ship/local-review.md -->

Review by a fresh-context Claude subagent. No external CLI, no API key, no
timeout wrapper — the subagent runs on the session's subscription and inherits
the session's model. A fresh context window means the reviewer has none of the
implementer's assumptions loaded, which is what makes it a genuine second read.

**Step 1 — Assemble the prompt.** Identical to codex exhaustive Steps 1–2:
read `${CLAUDE_PLUGIN_ROOT}/prompts/codex-review.md`, fill `{DIFF}`,
`{SCOPE_HINT}`, `{REPO_GUIDELINES}`, `{PR_CONTEXT}`. Both backends consume the
same assembled prompt — keep them identical so findings are comparable.

**Step 2 — Append the output contract.** Read
`${CLAUDE_PLUGIN_ROOT}/schemas/codex-review.json` and append to the prompt:

```text
## Output Format

Respond with ONLY a single JSON object (no markdown fences, no prose before or
after) conforming exactly to this JSON Schema:

<contents of schemas/codex-review.json>
```

**Step 3 — Dispatch.** Spawn a subagent via the `Agent` tool with the
assembled prompt. Do not override the model — it inherits the session's model.
Capture the subagent's final text as `REVIEW_JSON`, strip any accidental
markdown fences, and validate with `jq empty`.

**Step 4 — Parse.** Feed `REVIEW_JSON` through the same structured-JSON path
as codex exhaustive (Step 6 of `review-loop.md`): validate, filter
`confidence_score < 0.3`, sort by priority then confidence, de-duplicate
across passes.

**Error handling:** if the subagent returns invalid JSON, do NOT fall through
to the free-text clean path. Display the raw output (first 500 chars), then
`AskUserQuestion`: **Retry** / **Debug** (show raw output) / **Skip review**.

**Running under Codex CLI (no Agent tool):** never shell out to `claude -p` —
headless print mode bills metered API usage, not the subscription. Instead
drive an interactive Claude window via tmux: write the assembled prompt to a
temp file, then `tmux send-keys -t <claude-window> "Read <prompt-file> and
follow it; write the JSON result to <result-file>" Enter`, and poll for the
result file. If no Claude tmux window is available, ask the user via
`AskUserQuestion` (open one / switch to codex / skip) — never silently switch
backends.

## Gemini

Use the `DIFF` generated in Step 5a (scope-aware), not a hardcoded branch diff.

If `GEMINI_TIER` is set and non-empty, display this warning before running:

> **Note:** `--tier $GEMINI_TIER` was specified but the Gemini CLI does not support service tiers. The tier setting will be ignored for this review. When Gemini CLI adds `--service-tier` support, it will be applied automatically. Track [gemini-cli](https://github.com/google-gemini/gemini-cli) for updates.

```bash
GEMINI_MODEL_ARGS=()
if [ -n "${MODEL:-}" ]; then
  GEMINI_MODEL_ARGS=(-m "$MODEL")
fi

gemini "${GEMINI_MODEL_ARGS[@]}" <<EOF
Review the following code changes for bugs, security issues, performance problems, and best practice violations.

${SCOPE_HINT:+Focus area: $SCOPE_HINT}

Report each finding with: file path, line number, severity (error/warning/suggestion), and description.
If there are no issues, respond with exactly: NO_ISSUES_FOUND

\`\`\`diff
$DIFF
\`\`\`
EOF
```

## Ollama

Use the `DIFF` generated in Step 5a (scope-aware).

```bash
ollama run "$MODEL" <<EOF
Review the following code changes for bugs, security issues, performance problems, and best practice violations.

${SCOPE_HINT:+Focus area: $SCOPE_HINT}

Report each finding with: file path, line number, severity (error/warning/suggestion), and description.
If there are no issues, respond with exactly: NO_ISSUES_FOUND

\`\`\`diff
$DIFF
\`\`\`
EOF
```

Capture the output as `FINDINGS`.
