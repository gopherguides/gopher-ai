# Ship — Step 4 Prerequisite Diagnostics

Loaded by `skills/ship/SKILL.md` Step 4 when the selected LLM CLI is not
available. Print diagnostics, persist failure, then resolve the backend gate
from explicit intent and available review capabilities.

## Detect LLM CLI

```bash
LLM_AVAILABLE=true
if [ "$LLM_CHOICE" = "codex" ]; then
  if command -v codex &>/dev/null; then
    CODEX_CMD="codex"
  else
    LLM_AVAILABLE=false
  fi
elif [ "$LLM_CHOICE" = "gemini" ]; then
  command -v gemini >/dev/null 2>&1 || LLM_AVAILABLE=false
elif [ "$LLM_CHOICE" = "ollama" ]; then
  command -v ollama >/dev/null 2>&1 || LLM_AVAILABLE=false
elif [ "$LLM_CHOICE" = "fable" ]; then
  LLM_AVAILABLE=true  # no CLI — runs as a Claude subagent (see local-review.md)
fi
```

For explicitly selected `--llm fable` only: no external CLI is required when the
active surface can delegate the review to a Claude subagent (subscription-billed). When that delegation
capability is unavailable, **never shell out to `claude -p`** (headless print
mode bills metered API usage, not the subscription); use the tmux-driven
interactive Claude window path described in `local-review.md`. If neither is
available, apply the recovery policy below.

A CLI on PATH is not sufficient: it must be usable in the active session.
When nested Codex execution is prohibited by the active driver, treat Codex as
unavailable without launching it. Never substitute native delegation for it.

## Diagnostic Output

```bash
echo "=== LLM CLI Diagnostic ==="
echo "LLM selected: $LLM_CHOICE"
if [ "$LLM_CHOICE" = "codex" ]; then
  echo "codex in PATH: $(command -v codex 2>/dev/null || echo 'NOT FOUND')"
  echo "Codex authentication: run 'codex login' for ChatGPT sign-in or API-key authentication"
elif [ "$LLM_CHOICE" = "gemini" ]; then
  echo "gemini in PATH: $(command -v gemini 2>/dev/null || echo 'NOT FOUND')"
elif [ "$LLM_CHOICE" = "ollama" ]; then
  echo "ollama in PATH: $(command -v ollama 2>/dev/null || echo 'NOT FOUND')"
  echo "ollama serve running: $(curl -s http://localhost:11434/api/version 2>/dev/null || echo 'NOT RUNNING')"
fi
echo "========================="
```

## Persist failure flag

```bash
set_loop_field "$STATE_FILE" "llm_check_failed" "true" "$WORKFLOW_STATE_PATH"
```

## Recovery policy

First re-run detection once after printing diagnostics. On success:

```bash
delete_loop_field "$STATE_FILE" "llm_check_failed" "$WORKFLOW_STATE_PATH"
```

Set `LLM_AVAILABLE=true` and continue to Step 5.

When the backend remains unavailable, display relevant install guidance:

Display:

- **codex:** install the global `@openai/codex` package with npm, then run `codex login` for ChatGPT sign-in or API-key authentication
- **gemini:** install the global `@google/gemini-cli` package with npm
- **ollama:** `brew install ollama && ollama serve`

Then classify the decision:

- If `LLM_EXPLICIT=true`, replacing the backend is a **missing-intent gate**.
  Request whether to retry the selected backend or replace it. If structured
  input is unavailable, ask in the final response and stop without advancing
  the phase or claiming completion.
- If `LLM_EXPLICIT=false`, resolve a **driver-resolvable gate**. Select the first
  usable external CLI in this order: installed Gemini, then installed Ollama
  with a model. Persist the selected `llm` and keep `llm_explicit=false`.
  State `Decision`, `Evidence`, and `Rationale`.
- Never select Fable or any sub-agent automatically. Fable requires an explicit
  `--llm fable` invocation or an explicit user decision to replace the backend.
  For an authorized replacement, persist `llm=fable` and `llm_explicit=true`.
- If no external review CLI is usable for an unpinned backend, record the skip:

  ```bash
  REVIEW_RESULT=skipped
  REVIEW_CLEAN=false
  set_loop_field "$STATE_FILE" "review_result" "skipped" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "review_skip_reason" "review-backend-unavailable" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "review_clean" "false" "$WORKFLOW_STATE_PATH"
  echo "Local LLM review skipped: no usable external review CLI (review-backend-unavailable). Continuing with verification and PR CI."
  ```

Continue to Step 5. A skipped review bypasses review planning and execution;
local verification, applicable coverage/E2E, commit, push, non-draft PR creation,
and exact-head CI remain mandatory. A skip is never a clean-review verdict.
