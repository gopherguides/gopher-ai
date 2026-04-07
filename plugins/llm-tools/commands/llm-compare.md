---
argument-hint: "[--tier flex|standard|priority] <prompt>"
description: "Compare responses from multiple LLMs"
allowed-tools: ["Bash", "Read", "AskUserQuestion"]
---

# Compare Multiple LLMs

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command runs the same prompt through multiple LLMs and compares their responses.

**Usage:** `/llm-compare <prompt>`

**Examples:**

| Command | Description |
|---------|-------------|
| `/llm-compare should I use microservices or monolith` | Architectural decision |
| `/llm-compare review this error handling approach` | Code review comparison |
| `/llm-compare what are the security risks here` | Security analysis |
| `/llm-compare is this the idiomatic Go approach` | Best practices |

**Available LLMs:**

| LLM | Via | Notes |
|-----|-----|-------|
| OpenAI | `codex` CLI | Cloud-based, strong reasoning |
| Gemini | `gemini` CLI | Cloud-based, good at analysis |
| Ollama | `ollama` CLI | Local, private, various models |

Ask the user: "What question would you like multiple LLMs to answer?"

---

**If `$ARGUMENTS` is provided:**

Compare responses from multiple LLMs for: $ARGUMENTS

## 1. Select LLMs to Compare

Ask the user which LLMs to include (select 2-3):

| LLM | Status | Notes |
|-----|--------|-------|
| OpenAI (Codex) | Check if `codex` installed | Requires API key |
| Google Gemini | Check if `gemini` installed | Requires API key |
| Ollama (Local) | Check if `ollama` running | Free, private |

Default: All available LLMs

For each selected LLM, verify it's available:

```bash
# Codex detection with npx fallback
CODEX_AVAILABLE=false
if command -v codex &>/dev/null; then
  CODEX_CMD="codex"
  CODEX_AVAILABLE=true
elif npx -y codex --version &>/dev/null 2>&1; then
  CODEX_CMD="npx -y codex"
  CODEX_AVAILABLE=true
fi
# Gemini
command -v gemini >/dev/null 2>&1 && GEMINI_AVAILABLE=true || GEMINI_AVAILABLE=false
# Ollama
command -v ollama >/dev/null 2>&1 && OLLAMA_AVAILABLE=true || OLLAMA_AVAILABLE=false
```

**If a user-selected LLM is not available**, do NOT silently skip it. Use `AskUserQuestion`:

**"`$LLM_NAME` CLI not found. How would you like to proceed?"**

| Option | Description |
|--------|-------------|
| **Retry** | Check again (after installing) |
| **Install instructions** | Show how to install the missing CLI |
| **Skip this LLM** | Continue comparison without this LLM |
| **Abort** | Stop the comparison entirely |

Only skip an unavailable LLM if the user explicitly chooses "Skip this LLM".

## 2. Select Models (Optional)

For each selected LLM, ask if user wants to specify a model or use default:

**OpenAI defaults:** `gpt-5.2`
**Gemini defaults:** `gemini-2.5-flash`
**Ollama defaults:** First available code model (codellama, deepseek-coder, etc.)

## 3. Include Context (Optional)

Ask the user: "Include additional context?"

| Option | Description |
|--------|-------------|
| No | Run with prompt only |
| File context | Include contents of specific file(s) |
| Diff context | Include git diff output |

Default: `No`

If context is selected, gather it once and use for all LLMs.

## Review Fix Detection

Before running the LLMs, detect if the prompt is addressing review feedback (e.g., contains phrases like "fix review comment", "address feedback", "fix the issue from review", or originates from an `/address-review` context). If a review-fix prompt is detected:

Append to **ALL** LLM prompts:

```text

---

For every testable fix, write a corresponding test. A fix is testable if it changes observable behavior (return values, errors, side effects, HTTP responses). Skip tests for cosmetic changes (comments, formatting, renames, log changes). Add cases to existing table-driven tests when possible, or create new table-driven tests following the package's conventions.
```

## 4. Run LLMs

Execute each LLM. Where possible, run in parallel for speed.

**OpenAI (only if `CODEX_AVAILABLE` is `true` — user was already prompted in Step 1 if unavailable):**
```bash
$CODEX_CMD exec -m <model> -s read-only --skip-git-repo-check "$CLEAN_PROMPT"
```

**If `codex exec` fails** (non-zero exit or no output), do NOT silently skip. Display exit code and stderr, then use `AskUserQuestion` with options: Retry / Debug / Skip this LLM / Abort.

**Gemini:**

If `--tier` was provided in `$ARGUMENTS`, strip it from the prompt **before passing to any LLM** (including Codex and Ollama, so they don't see the flag as part of the question):

```bash
CLEAN_PROMPT=$(echo "$ARGUMENTS" | sed 's/--tier  *[^ ]*//g' | sed 's/^  *//;s/  *$//')
```

If Gemini is selected, display a warning:

> **Note:** `--tier` is accepted but the Gemini CLI does not currently support service tiers. The tier will be ignored for the Gemini comparison. Track [gemini-cli](https://github.com/google-gemini/gemini-cli) for updates.

Use `CLEAN_PROMPT` in all LLM invocations below:

```bash
gemini "$CLEAN_PROMPT" -m <model>
```

**Ollama:**
```bash
ollama run <model> "$CLEAN_PROMPT"
```

Capture output from each.

## 5. Generate Comparison Report

Present results in a structured format:

```markdown
## LLM Comparison: <prompt>

### OpenAI (gpt-5.2)

[Response from OpenAI]

---

### Google Gemini (gemini-2.5-flash)

[Response from Gemini]

---

### Ollama (codellama:34b)

[Response from Ollama]

---

## Analysis

### Points of Agreement
- [List where models agree]

### Key Differences
- [List significant differences in approach/recommendation]

### Synthesis
[Your analysis as Claude combining insights from all responses]

### Test Coverage
(Only included when review fix detection is active)
- Which LLMs included tests with their fix
- Quality comparison of generated tests (coverage, edge cases, conventions)
- If no LLM produced tests: "No LLM generated tests — Claude will generate them as fallback"

### Recommendation
Based on the comparison:
- If models agree: "All models align on [approach]. This consensus suggests [conclusion]."
- If models disagree: "Models differ on [aspect]. Consider [factors] when deciding."
```

### Review Fix Fallback

After generating the comparison report, if the review fix detection was active: check if ANY LLM produced test code (look for `func Test` or `_test.go` content in their responses). If no LLM produced tests for testable changes, Claude generates the missing tests using the same guidelines.

## 6. Follow-up Options

After presenting the comparison, offer:

| Option | Description |
|--------|-------------|
| Drill into specific response | Ask follow-up to one specific LLM |
| Re-run with different models | Try larger/different models |
| Ask clarifying question | Refine the original prompt |
| Accept recommendation | Proceed with suggested approach |

## Error Handling

- If one LLM fails, continue with others and note the failure
- If all LLMs fail, report the errors and suggest troubleshooting
- If response is truncated, note it and suggest re-running with simpler prompt

## Performance Notes

- Running 3 LLMs takes longer than one - set expectations
- Local Ollama models may be slower but keep data private
- Cloud LLMs (Codex, Gemini) are typically faster but require connectivity

## Example Output

```markdown
## LLM Comparison: Should I use channels or mutexes for this shared counter?

### OpenAI (gpt-5.2)

For a simple shared counter, a mutex is more appropriate. Channels are
designed for communication between goroutines, not protecting shared
state. Use `sync/atomic` for even better performance with counters.

---

### Google Gemini (gemini-2.5-flash)

Both can work, but:
- Mutex: simpler for protecting shared state
- Channels: better for coordination/signaling
For a counter specifically, consider `sync/atomic.Int64` which avoids
locking entirely.

---

### Ollama (codellama:34b)

Use a mutex with sync.Mutex for the counter. Channels add unnecessary
complexity for simple shared state. The Go proverb "share memory by
communicating" applies when you need coordination, not just protection.

---

## Analysis

### Points of Agreement
- All models agree mutex is more appropriate than channels for a counter
- Multiple models suggest sync/atomic as an even better alternative

### Key Differences
- Gemini provides more nuanced "it depends" framing
- CodeLlama quotes Go philosophy directly

### Recommendation
Strong consensus: Use `sync/atomic` for counters, or `sync.Mutex` if you
need more complex operations. Channels are overkill for this use case.
```
