---
argument-hint: "<prompt>"
description: "Compare responses from multiple LLMs"
model: claude-opus-4-5-20251101
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
- `which codex` for OpenAI
- `which gemini` for Gemini
- `ollama ps` for Ollama

Skip unavailable LLMs with a note.

## 2. Select Models (Optional)

For each selected LLM, ask if user wants to specify a model or use default:

**OpenAI defaults:** `gpt-5.2`
**Gemini defaults:** `gemini-2.0-flash`
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

## 4. Run LLMs

Execute each LLM. Where possible, run in parallel for speed.

**OpenAI:**
```bash
codex exec -m <model> -s read-only --skip-git-repo-check "<prompt>"
```

**Gemini:**
```bash
gemini -m <model> "<prompt>"
```

**Ollama:**
```bash
ollama run <model> "<prompt>"
```

Capture output from each.

## 5. Generate Comparison Report

Present results in a structured format:

```markdown
## LLM Comparison: <prompt>

### OpenAI (gpt-5.2)

[Response from OpenAI]

---

### Google Gemini (gemini-2.0-flash)

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

### Recommendation
Based on the comparison:
- If models agree: "All models align on [approach]. This consensus suggests [conclusion]."
- If models disagree: "Models differ on [aspect]. Consider [factors] when deciding."
```

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

### Google Gemini (gemini-2.0-flash)

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
