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

For `fable`: no external CLI is required when the active surface can delegate
the review to a Claude subagent (subscription-billed). When that delegation
capability is unavailable, **never shell out to `claude -p`** (headless print
mode bills metered API usage, not the subscription); use the tmux-driven
interactive Claude window path described in `local-review.md`. If neither is
available, apply the recovery policy below.

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
TMP="$STATE_FILE.tmp"
jq '.llm_check_failed = "true"' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## Recovery policy

First re-run detection once after printing diagnostics. On success:

```bash
TMP="$STATE_FILE.tmp"
jq 'del(.llm_check_failed)' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

Set `LLM_AVAILABLE=true` and continue to Step 5.

When the backend remains unavailable, display relevant install guidance:

Display:

- **codex:** `npm install -g @openai/codex`, then run `codex login` for ChatGPT sign-in or API-key authentication
- **gemini:** `npm install -g @google/gemini-cli`
- **ollama:** `brew install ollama && ollama serve`

Then classify the decision:

- If `LLM_EXPLICIT=true`, replacing the backend is a **missing-intent gate**.
  Request whether to retry the selected backend or replace it. If structured
  input is unavailable, ask in the final response and stop without advancing
  the phase or claiming completion.
- If `LLM_EXPLICIT=false`, resolve a **driver-resolvable gate**. Select the first
  usable independent path in this order: native Fable delegation, installed
  Gemini, installed Ollama with a model, then agent-based review. State
  `Decision`, `Evidence`, and `Rationale`.
- If no review path is usable, stop incomplete with
  `WORKFLOW_REASON=review-backend-unavailable`.

When the selected path is agent-based review, set `USE_AGENT_REVIEW=true` and
`CODEX_EXEC_FALLBACK=true`, then persist:

```bash
TMP="$STATE_FILE.tmp"
jq '.use_agent_review = "true"' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

Continue to Step 5 — Phase 1 will route through the agent-based review
section in `local-review.md`.
