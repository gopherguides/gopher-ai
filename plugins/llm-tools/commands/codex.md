---
argument-hint: "<prompt>"
description: "Delegate a task to OpenAI Codex CLI"
allowed-tools: ["Bash", "Read", "AskUserQuestion"]
---

# Delegate to Codex

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command delegates tasks to OpenAI Codex CLI for autonomous execution.

**Usage:** `/codex <prompt>`

**Examples:**

| Command | Description |
|---------|-------------|
| `/codex refactor the auth module` | Refactor existing code |
| `/codex write tests for utils.ts` | Generate test files |
| `/codex fix the bug in checkout flow` | Debug and fix issues |
| `/codex explain how the API routes work` | Code explanation |
| `/codex add dark mode support` | Implement new features |
| `/codex review the auth changes` | Review with session context |

**Available Models:**

| Model | Best For |
|-------|----------|
| `gpt-5.2` | Newest frontier model, best overall |
| `gpt-5.1-codex-max` | Complex, long-running tasks (can run 24+ hours) |
| `gpt-5.1-codex` | Fast, balanced performance |
| `gpt-5.1-codex-mini` | Simple tasks, cost-efficient |

Ask the user: "What would you like Codex to do?"

---

**If `$ARGUMENTS` is provided:**

Run a task using OpenAI Codex CLI with the prompt: $ARGUMENTS

## 1. Detect Review Mode

Check if the prompt contains "review" (case-insensitive). If yes, route to **Review Flow**.
Otherwise, continue with **Exec Flow**.

---

## Review Flow

Use this flow when the prompt contains "review".

### R1. Select What to Review

Ask the user what to review:

| Option | Description |
|--------|-------------|
| Uncommitted changes | Review staged, unstaged, and untracked changes |
| Changes vs branch | Review changes against a base branch |
| Specific commit | Review changes introduced by a commit |

Default: `Changes vs branch`

**If "Changes vs branch":** Ask for the base branch name. Default: `main`

**If "Specific commit":** Ask for the commit SHA.

### R2. Select Model

Ask the user which model to use:

| Model | Best For |
|-------|----------|
| gpt-5.2 | Newest frontier model, best overall |
| gpt-5.1-codex-max | Complex, long-running tasks (can run 24+ hours) |
| gpt-5.1-codex | Fast, balanced performance |
| gpt-5.1-codex-mini | Simple tasks, cost-efficient |

Default: `gpt-5.1-codex`

### R3. Run Codex Review

Assemble and execute the command based on what to review:

**For uncommitted changes:**

```bash
codex review --uncommitted -c model=<model> 2>/dev/null
```

**For changes vs branch:**

```bash
codex review --base <branch> -c model=<model> 2>/dev/null
```

**For specific commit:**

```bash
codex review --commit <sha> -c model=<model> 2>/dev/null
```

If the user provided custom review instructions beyond just "review", append them as the prompt:

```bash
codex review --base <branch> -c model=<model> "<custom-instructions>" 2>/dev/null
```

### R4. Report Results

After execution completes:

- Show the review output to the user
- Ask if they want to run a follow-up review or switch to exec mode
- For follow-ups, use: `codex resume --last`

---

## Exec Flow

Use this flow for non-review tasks.

### 1. Select Model

Ask the user which model to use:

| Model | Best For |
|-------|----------|
| gpt-5.2 | Newest frontier model, best overall |
| gpt-5.1-codex-max | Complex, long-running tasks (can run 24+ hours) |
| gpt-5.1-codex | Fast, balanced performance |
| gpt-5.1-codex-mini | Simple tasks, cost-efficient |

Default: `gpt-5.2`

### 2. Include Session Context (Optional)

Ask the user: "Do you want to include context from our current Claude session?"

| Option | Description |
|--------|-------------|
| No | Run Codex without session context |
| Summary | Include goal, decisions, and current task (~100 words) |
| Detailed | Include summary plus files changed/discussed (~200 words) |

Default: `No`

**If user selects "Summary":**

Generate a concise context block based on the current session:

```text
## Session Context

**Goal:** [What the user is trying to accomplish]
**Decisions:** [Key decisions made during this session]
**Current Task:** [What was being worked on when /codex was invoked]
```

**If user selects "Detailed":**

Generate an expanded context block based on the current session:

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

Ask the user for sandbox mode:

| Mode | Description |
|------|-------------|
| read-only | Analysis only, no file changes |
| workspace-write | Can edit files in workspace |
| danger-full-access | Full network and system access |

Default: `read-only`

### 4. Run Codex

**If context was NOT requested:**

Assemble and execute the command:

```bash
codex exec -m <model> -s <mode> --skip-git-repo-check "<prompt>" 2>/dev/null
```

**If context WAS requested:**

Construct a combined prompt and execute using heredoc:

```bash
codex exec -m <model> -s <mode> --skip-git-repo-check - 2>/dev/null <<'EOF'
[CONTEXT BLOCK FROM STEP 2]

---

## Task

<prompt>

---

Use the session context above to inform your review/analysis. The context describes what was
being worked on in a previous AI coding session.
EOF
```

### 5. Report Results

After execution completes:

- Show the output to the user
- Ask if they want to continue with a follow-up prompt
- For follow-ups, use: `codex resume --last`

### Error Handling

- If Codex exits with non-zero code, report the error and ask user how to proceed
- If output contains warnings, inform the user and ask if adjustments are needed
- Always request confirmation before using `danger-full-access` mode
