---
argument-hint: "<prompt>"
description: "Delegate a task to Google Gemini CLI"
allowed-tools: ["Bash", "Read", "AskUserQuestion"]
---

# Delegate to Gemini

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command delegates tasks to Google Gemini CLI for analysis and code review.

**Usage:** `/gemini <prompt>`

**Examples:**

| Command | Description |
|---------|-------------|
| `/gemini review the auth implementation` | Code review |
| `/gemini explain this error handling pattern` | Code explanation |
| `/gemini suggest improvements for this function` | Refactoring advice |
| `/gemini what are the security implications here` | Security analysis |

**Available Models:**

| Model | Best For |
|-------|----------|
| `gemini-2.0-flash` | Fast responses, general tasks (default) |
| `gemini-2.0-flash-thinking` | Complex reasoning, step-by-step analysis |
| `gemini-pro` | Production-quality, detailed responses |

Ask the user: "What would you like Gemini to analyze?"

---

**If `$ARGUMENTS` is provided:**

Run a task using Google Gemini CLI with the prompt: $ARGUMENTS

## 1. Check Prerequisites

First, verify Gemini CLI is installed:

```bash
which gemini
```

If not found, inform the user:

> Gemini CLI is not installed. Install it with:
> ```bash
> brew install gemini-cli
> ```
> Or visit: https://github.com/google/gemini-cli

Then ask if they want to proceed after installation or use a different LLM (`/codex` or `/ollama`).

## 2. Select Model

Ask the user which model to use:

| Model | Best For |
|-------|----------|
| gemini-2.0-flash | Fast responses, general tasks |
| gemini-2.0-flash-thinking | Complex reasoning, step-by-step analysis |
| gemini-pro | Production-quality, detailed responses |

Default: `gemini-2.0-flash`

## 3. Include Context (Optional)

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
- Read file contents and include in prompt

**If "Diff context":**
- Ask for diff scope: uncommitted, vs branch, or specific commits
- Run appropriate git diff command and include output

**If "Session context":**
- Generate summary of current Claude session (~100 words)
- Include goal, decisions made, files discussed

## 4. Run Gemini

**Without context:**

```bash
gemini -m <model> "<prompt>"
```

**With file context:**

```bash
cat <file> | gemini -m <model> "Given this code:\n\n<prompt>"
```

**With diff context:**

```bash
git diff <scope> | gemini -m <model> "Review these changes:\n\n<prompt>"
```

**With session context:**

```bash
gemini -m <model> "$(cat <<'EOF'
## Context

[Session context summary]

---

## Task

<prompt>
EOF
)"
```

## 5. Report Results

After execution completes:

- Display the response to the user
- Ask if they want a follow-up question or different perspective
- Offer to try `/codex` or `/ollama` for comparison

## Error Handling

- If Gemini CLI exits with error, display the error message
- If API quota exceeded, suggest waiting or using `/ollama` (local, no quota)
- If authentication fails, guide user to run `gemini auth login`

## Notes

- Gemini CLI requires Google AI Studio API key (`GOOGLE_API_KEY`) or OAuth login
- For private/sensitive code, consider `/ollama` which keeps data local
