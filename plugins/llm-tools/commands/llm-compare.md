---
argument-hint: "[--tier flex|standard|priority] <prompt>"
description: "Compare responses from multiple LLMs"
allowed-tools: ["Bash(codex:*)", "Bash(gemini:*)", "Bash(ollama:*)", "Bash(npx:*)", "Bash(command:*)", "Bash(echo:*)", "Bash(git:*)", "Bash(cat:*)", "Read", "AskUserQuestion"]
---

# Compare Multiple LLMs

**If `$ARGUMENTS` is empty or not provided:**

Run the same prompt through multiple LLMs and compare responses.

**Usage:** `/llm-compare <prompt>`

| Command | Description |
|---------|-------------|
| `/llm-compare should I use microservices or monolith` | Architectural decision |
| `/llm-compare review this error handling approach` | Code review comparison |
| `/llm-compare what are the security risks here` | Security analysis |
| `/llm-compare is this the idiomatic Go approach` | Best practices |

**Available LLMs:** OpenAI (`codex`, cloud, strong reasoning) · Gemini (`gemini`, cloud, good at analysis) · Ollama (`ollama`, local, private, various models).

Ask: "What question would you like multiple LLMs to answer?"

---

**If `$ARGUMENTS` is provided:**

Compare responses from multiple LLMs for: `$ARGUMENTS`.

## 1. Select LLMs to Compare

`AskUserQuestion` (select 2-3): OpenAI / Gemini / Ollama. Default: all available.

For each selected, verify availability:

```bash
# Codex with npx fallback
CODEX_AVAILABLE=false
if command -v codex &>/dev/null; then
  CODEX_CMD="codex"; CODEX_AVAILABLE=true
elif npx -y codex --version &>/dev/null 2>&1; then
  CODEX_CMD="npx -y codex"; CODEX_AVAILABLE=true
fi
command -v gemini >/dev/null 2>&1 && GEMINI_AVAILABLE=true || GEMINI_AVAILABLE=false
command -v ollama >/dev/null 2>&1 && OLLAMA_AVAILABLE=true || OLLAMA_AVAILABLE=false
```

If a user-selected LLM is unavailable, do NOT silently skip. Use `AskUserQuestion`:

> **"`$LLM_NAME` CLI not found. How would you like to proceed?"**

| Option | Description |
|--------|-------------|
| **Retry** | Check again after installing |
| **Install instructions** | Show how to install the missing CLI |
| **Skip this LLM** | Continue without it |
| **Abort** | Stop the comparison |

Only skip if the user explicitly chooses "Skip this LLM".

## 2. Select Models (Optional)

For each LLM, ask if user wants to specify a model. Defaults: **OpenAI** provider default (no `-m`; Codex CLI chooses), **Gemini** `gemini-2.5-flash`, **Ollama** first available code model (codellama, deepseek-coder, etc.).

## 3. Include Context (Optional)

`AskUserQuestion`: "Include additional context?"

| Option | Description |
|--------|-------------|
| **No** (default) | Run with prompt only |
| **File context** | Include contents of specific file(s) |
| **Diff context** | Include `git diff` output |

If selected, gather once and use for all LLMs.

## 4. Strip `--tier` and detect review-fix prompts

Strip `--tier` before passing to any LLM (Codex, Gemini, Ollama):

```bash
CLEAN_PROMPT=$(echo "$ARGUMENTS" | sed 's/--tier  *[^ ]*//g' | sed 's/^  *//;s/  *$//')
```

If Gemini is selected, display a warning:

> **Note:** `--tier` is accepted but the Gemini CLI does not currently support service tiers. The tier will be ignored for the Gemini comparison.

Detect review-fix prompts (phrases like "fix review comment", "address feedback", "fix the issue from review", or `/address-review` context). If detected, append to **ALL** LLM prompts:

```text

---

For every testable fix, write a corresponding test. A fix is testable if it changes observable behavior (return values, errors, side effects, HTTP responses). Skip tests for cosmetic changes (comments, formatting, renames, log changes). Add cases to existing table-driven tests when possible, or create new table-driven tests following the package's conventions.
```

## 5. Run LLMs

Run in parallel where possible. Use `CLEAN_PROMPT`:

```bash
# OpenAI (only if CODEX_AVAILABLE=true)
OPENAI_MODEL_ARGS=()
if [ -n "$OPENAI_MODEL" ]; then
  OPENAI_MODEL_ARGS=(-m "$OPENAI_MODEL")
fi

$CODEX_CMD exec "${OPENAI_MODEL_ARGS[@]}" -s read-only -c model_reasoning_effort="high" --skip-git-repo-check "$CLEAN_PROMPT"

# Gemini
gemini "$CLEAN_PROMPT" -m <model>

# Ollama
ollama run <model> "$CLEAN_PROMPT"
```

If `codex exec` fails (non-zero exit or no output), do NOT silently skip. Display exit code + stderr, then `AskUserQuestion`: **Retry** / **Debug** / **Skip this LLM** / **Abort**.

## 6. Generate Comparison Report

```markdown
## LLM Comparison: <prompt>

### OpenAI (Codex provider default)
[Response]

---

### Google Gemini (gemini-2.5-flash)
[Response]

---

### Ollama (codellama:34b)
[Response]

---

## Analysis

### Points of Agreement
- [Where models agree]

### Key Differences
- [Significant differences in approach/recommendation]

### Synthesis
[Claude's analysis combining insights from all responses]

### Test Coverage
(only when review-fix detection is active)
- Which LLMs included tests
- Quality comparison (coverage, edge cases, conventions)
- If no LLM produced tests: "No LLM generated tests — Claude will generate them as fallback"

### Recommendation
- Models agree → "All models align on [approach]. Consensus suggests [conclusion]."
- Models disagree → "Models differ on [aspect]. Consider [factors] when deciding."
```

### Review-Fix Fallback

After the report, if review-fix detection was active: check if ANY LLM produced test code (`func Test` or `_test.go` content). If no LLM produced tests for testable changes, Claude generates the missing tests using the same guidelines.

## 7. Follow-up Options

| Option | Description |
|--------|-------------|
| Drill into specific response | Ask follow-up to one specific LLM |
| Re-run with different models | Try larger/different models |
| Ask clarifying question | Refine the original prompt |
| Accept recommendation | Proceed with suggested approach |

## Error Handling

- If one LLM fails, continue with others and note the failure
- If all LLMs fail, report errors and suggest troubleshooting
- If response truncated, note it and suggest re-running with simpler prompt

## Notes

- 3 LLMs takes longer than 1 — set expectations
- Local Ollama models may be slower but keep data private
- Cloud LLMs (Codex, Gemini) are typically faster but require connectivity

## Example

```markdown
## LLM Comparison: Should I use channels or mutexes for this shared counter?

### OpenAI (Codex provider default)
For a simple shared counter, a mutex is more appropriate. Channels are designed for communication between goroutines, not protecting shared state. Use `sync/atomic` for even better performance.

### Gemini (gemini-2.5-flash)
Both work, but: Mutex — simpler for protecting shared state; Channels — better for coordination. For a counter specifically, consider `sync/atomic.Int64` which avoids locking entirely.

### Ollama (codellama:34b)
Use `sync.Mutex` for the counter. Channels add unnecessary complexity. The Go proverb "share memory by communicating" applies when you need coordination, not just protection.

## Analysis

### Points of Agreement
- All models: mutex > channels for a counter
- Multiple suggest `sync/atomic` as the better option

### Recommendation
Strong consensus: use `sync/atomic` for counters, or `sync.Mutex` for more complex operations. Channels are overkill here.
```
