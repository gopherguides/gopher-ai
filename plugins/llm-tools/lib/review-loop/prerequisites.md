# Review Loop — Prerequisite Diagnostics & Install

Loaded by `commands/review-loop.md` Step 2 when the selected LLM CLI is not
available. Print diagnostics, then route the user via `AskUserQuestion`.

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

## AskUserQuestion

> **"`$LLM_CHOICE` CLI not found. How would you like to proceed?"**

| Option | Description |
|--------|-------------|
| **Retry** | Check again (after you install or fix `$LLM_CHOICE`) |
| **Debug / Install instructions** | Show install steps and help troubleshoot |
| **Abort** | Stop the review loop entirely |

**Retry** → re-run the Step 2 detection. If still failing, present options again.

**Debug / Install instructions** → display:

- **codex:** `npm install -g @openai/codex`, then run `codex login` for ChatGPT sign-in or API-key authentication
- **gemini:** `npm install -g @google/gemini-cli`
- **ollama:** `brew install ollama && ollama serve`

After the user says they've fixed it, re-run Step 2 detection.

**Abort** → clean up and stop:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" "review-loop"
```

Output `<done>REVIEW_CLEAN</done>`.
