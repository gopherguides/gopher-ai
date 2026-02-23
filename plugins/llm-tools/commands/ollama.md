---
argument-hint: "<prompt>"
description: "Use local models via Ollama (private, data stays local)"
allowed-tools: ["Bash", "Read", "AskUserQuestion"]
---

# Use Local Models via Ollama

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command runs prompts through local models via Ollama. Your data stays on your machine.

**Usage:** `/ollama <prompt>`

**Examples:**

| Command | Description |
|---------|-------------|
| `/ollama review this authentication code` | Code review |
| `/ollama explain this concurrent pattern` | Code explanation |
| `/ollama suggest Go idioms for this function` | Best practices |
| `/ollama what security issues do you see` | Security analysis |

**Recommended Models for Code:**

| Model | Best For |
|-------|----------|
| `codellama:34b` | Code generation, large context |
| `deepseek-coder:33b` | Code review, analysis |
| `qwen2.5-coder:32b` | Code-focused tasks |
| `llama3.3:70b` | General reasoning, complex tasks |

**Privacy Note:** All processing happens locally. Your code never leaves your machine.

Ask the user: "What would you like to analyze locally?"

---

**If `$ARGUMENTS` is provided:**

Run a task using Ollama with the prompt: $ARGUMENTS

## 1. Check Prerequisites

First, check if Ollama is installed:

```bash
which ollama
```

If not found, inform the user:

> Ollama is not installed. Install it with:
> ```bash
> brew install ollama
> ```
> Or visit: https://ollama.ai

Then ask if they want to proceed after installation or use `/codex` or `/gemini` instead.

## 2. Check if Ollama is Running

```bash
ollama ps 2>/dev/null
```

If not running or errors, offer to start it:

> Ollama server is not running. Would you like me to start it?

If yes:
```bash
ollama serve &
sleep 2
```

## 3. List Available Models

```bash
ollama list
```

Show the user which models are already downloaded.

## 4. Select Model

Ask the user which model to use:

| Model | Size | Best For |
|-------|------|----------|
| codellama:34b | ~19GB | Code generation, large context |
| deepseek-coder:33b | ~19GB | Code review, detailed analysis |
| qwen2.5-coder:32b | ~18GB | Code-focused tasks |
| llama3.3:70b | ~40GB | General reasoning, complex tasks |
| codellama:7b | ~4GB | Quick code tasks, lower resources |
| llama3.2:3b | ~2GB | Fast responses, limited complexity |

Default: `codellama:34b` (or first available code model)

**If selected model is not downloaded:**

Ask user: "Model `<model>` is not downloaded (~<size>). Download it now?"

If yes:
```bash
ollama pull <model>
```

Note: This may take several minutes depending on model size and connection speed.

## 5. Include Context (Optional)

Ask the user: "Do you want to include additional context?"

| Option | Description |
|--------|-------------|
| No | Run with prompt only |
| File context | Include contents of specific file(s) |
| Diff context | Include git diff output |
| Session context | Include summary of current Claude session |

Default: `No`

**If "File context":**
- Ask which file(s) to include
- Read file contents and prepend to prompt

**If "Diff context":**
- Ask for diff scope: uncommitted, vs branch, or specific commits
- Run appropriate git diff command and include output

**If "Session context":**
- Generate summary of current Claude session (~100 words)

## 6. Run Ollama

**Without context:**

```bash
ollama run <model> "<prompt>"
```

**With file context:**

```bash
cat <file> | ollama run <model> "Given this code:

$(cat)

<prompt>"
```

**With diff context:**

```bash
git diff <scope> | ollama run <model> "Review these changes:

$(cat)

<prompt>"
```

**With session context:**

```bash
ollama run <model> "$(cat <<'EOF'
## Context

[Session context summary]

---

## Task

<prompt>
EOF
)"
```

## 7. Report Results

After execution completes:

- Display the response to the user
- Ask if they want a follow-up question
- Offer to try a different model or compare with `/codex` or `/gemini`

## Review Fix Detection

Before running Ollama, detect if the prompt is addressing review feedback (e.g., contains phrases like "fix review comment", "address feedback", "fix the issue from review", or originates from an `/address-review` context). If a review-fix prompt is detected:

Append to the Ollama prompt:

```text

---

For every testable fix, write a corresponding test. A fix is testable if it changes observable behavior (return values, errors, side effects, HTTP responses). Skip tests for cosmetic changes (comments, formatting, renames, log changes). Add cases to existing table-driven tests when possible, or create new table-driven tests following the package's conventions.
```

**Note:** Local models commonly skip test generation or produce incomplete tests. The fallback below is especially important for Ollama.

### Review Fix Fallback

After Ollama completes, check if its response includes test code (look for `func Test` or `_test.go` content). If the response contains a fix but no tests for testable changes, Claude generates the missing tests using the same guidelines.

## Error Handling

- If model loading fails (OOM), suggest a smaller model
- If Ollama crashes, suggest restarting with `ollama serve`
- If response is cut off, model may have hit context limit - suggest summarizing input

## Performance Tips

- First run of a model is slower (loading into memory)
- Subsequent prompts to same model are faster
- Close other memory-intensive apps for best performance
- Consider smaller models (7b/3b) for quick tasks

## Privacy Advantage

Unlike cloud LLMs, Ollama runs entirely locally:
- No data sent to external servers
- Works offline after model download
- Ideal for proprietary/sensitive code
- No API keys or accounts needed
