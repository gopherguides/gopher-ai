# Ship — Step 4 Prerequisite Diagnostics

Loaded by `skills/ship/SKILL.md` Step 4 when the selected LLM CLI is not
available. Print diagnostics, persist failure, then route the user via
`AskUserQuestion`.

## Detect LLM CLI

```bash
LLM_AVAILABLE=true
if [ "$LLM_CHOICE" = "codex" ]; then
  if command -v codex &>/dev/null; then
    CODEX_CMD="codex"
  elif npx -y codex --version &>/dev/null 2>&1; then
    CODEX_CMD="npx -y codex"
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

For `fable`: no external CLI is required in a Claude Code session — the Agent
tool dispatches the review subagent (subscription-billed). Under Codex CLI
there is no Agent tool — **never shell out to `claude -p`** (headless print
mode bills metered API usage, not the subscription); use the tmux-driven
interactive Claude window path described in `local-review.md`. If neither is
available, present the `AskUserQuestion` below.

## Diagnostic Output

```bash
echo "=== LLM CLI Diagnostic ==="
echo "LLM selected: $LLM_CHOICE"
if [ "$LLM_CHOICE" = "codex" ]; then
  echo "codex in PATH: $(command -v codex 2>/dev/null || echo 'NOT FOUND')"
  echo "npx codex: $(npx -y codex --version 2>/dev/null || echo 'FAILED')"
  echo "OPENAI_API_KEY set: $([ -n "${OPENAI_API_KEY:-}" ] && echo 'yes' || echo 'NO')"
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

## AskUserQuestion

> **"`$LLM_CHOICE` CLI not found. How would you like to proceed?"**

| Option | Description |
|--------|-------------|
| **Retry** | Check again (after you install or fix `$LLM_CHOICE`) |
| **Debug / Install instructions** | Show install steps and help troubleshoot |
| **Use agent-based review** | Fall back to Claude agent review (no external LLM) |
| **Abort** | Stop the `$ship` workflow entirely |

### Retry

Re-run `command -v` / `npx` from above. On success:

```bash
TMP="$STATE_FILE.tmp"
jq 'del(.llm_check_failed)' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

Set `LLM_AVAILABLE=true` and continue to Step 5. If still failing, present
options again.

### Debug / Install instructions

Display:

- **codex:** `npm install -g @openai/codex` (and ensure `OPENAI_API_KEY` is set)
- **gemini:** `npm install -g @google/gemini-cli`
- **ollama:** `brew install ollama && ollama serve`

After the user says they've fixed it, re-run detection. If still fails,
present options again.

### Use agent-based review

Set `USE_AGENT_REVIEW=true` and `CODEX_EXEC_FALLBACK=true`, persist:

```bash
TMP="$STATE_FILE.tmp"
jq '.use_agent_review = "true"' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

Continue to Step 5 — Phase 1 will route through the agent-based review
section in `local-review.md`.

### Abort

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" "ship"
```

Stop. Do NOT output `<done>SHIPPED</done>`.
