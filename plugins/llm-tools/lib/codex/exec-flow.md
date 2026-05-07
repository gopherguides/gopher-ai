# Codex — Exec Flow

Loaded by `commands/codex.md` for non-review tasks (and for fix-oriented
review prompts that need to modify files). Owns model/sandbox selection,
optional session-context injection, execution, and result reporting.

## If `INTERACTIVE_MODE` is `false` (default — no `--ask` flag)

Use recommended defaults without prompting. Display a brief configuration summary:

```
Exec config (defaults — add --ask to customize):
  Model:    gpt-5.5
  Context:  None
  Sandbox:  workspace-write
```

Store: model = "gpt-5.5", context = "No", sandbox = "workspace-write". Proceed directly to Step 4 (Run Codex).

## If `INTERACTIVE_MODE` is `true` (`--ask` flag provided)

### 1. Select Model

Ask the user which model to use:

| Model | Best For |
|-------|----------|
| gpt-5.5 | Latest frontier model, best overall |
| gpt-5.5-pro | Maximum performance on complex tasks |
| gpt-5.3-codex | Previous generation frontier model |
| gpt-5.1-codex-mini | Simple tasks, cost-efficient |

Default: `gpt-5.5`

### 2. Include Session Context (Optional)

Ask: "Do you want to include context from our current Claude session?"

| Option | Description |
|--------|-------------|
| No | Run Codex without session context |
| Summary | Include goal, decisions, and current task (~100 words) |
| Detailed | Include summary plus files changed/discussed (~200 words) |

Default: `No`

**If user selects "Summary":**

```text
## Session Context

**Goal:** [What the user is trying to accomplish]
**Decisions:** [Key decisions made during this session]
**Current Task:** [What was being worked on when /codex was invoked]
```

**If user selects "Detailed":**

```text
## Session Context

**Goal:** [What the user is trying to accomplish]
**Decisions:** [Key decisions made during this session]
**Files Changed/Discussed:**
- [file1.ts] - [brief description of changes]
- [file2.ts] - [brief description of changes]
**Current Task:** [What was being worked on when /codex was invoked]
**Open Items:** [Any unresolved questions or tasks]
```

### 3. Select Sandbox Mode

| Mode | Description |
|------|-------------|
| read-only | Analysis only, no file changes |
| workspace-write | Can edit files in workspace |
| danger-full-access | Full network and system access |

Default: `read-only` (interactive). Always request confirmation before using `danger-full-access`.

## 4. Run Codex

### If context was NOT requested

```bash
$CODEX_CMD exec -m <model> -s <mode> --skip-git-repo-check "$CODEX_PROMPT"
```

### If context WAS requested

Construct a combined prompt and execute using a temp file. Assemble the full prompt as a variable first (to safely include `$CODEX_PROMPT` without shell expansion risks from the context block), write it to a temp file, then pipe it:

```bash
PROMPT_FILE=$(mktemp /tmp/codex-exec-prompt-XXXXXX)
trap 'rm -f "$PROMPT_FILE"' EXIT

EXEC_PROMPT="[CONTEXT BLOCK FROM STEP 2]

---

## Task

${CODEX_PROMPT}

---

Use the session context above to inform your review/analysis. The context describes what was
being worked on in a previous AI coding session."

printf '%s\n' "$EXEC_PROMPT" > "$PROMPT_FILE"
$CODEX_CMD exec -m <model> -s <mode> --skip-git-repo-check - < "$PROMPT_FILE"
rm -f "$PROMPT_FILE"
trap - EXIT
```

## 5. Report Results

After execution completes:

- Show the output to the user
- Ask if they want to continue with a follow-up prompt
- For follow-ups, use: `codex resume --last`

## Error Handling

- If Codex exits with non-zero code, report the error and ask the user how to proceed
- If output contains warnings, inform the user and ask if adjustments are needed
- Always request confirmation before using `danger-full-access` mode
