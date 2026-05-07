---
argument-hint: "[--ask] <prompt>"
description: "Delegate a task to OpenAI Codex CLI"
allowed-tools: ["Bash", "Read", "AskUserQuestion"]
---

# Delegate to Codex

**If `$ARGUMENTS` is empty or not provided:**

Display usage and ask for input:

> This command delegates tasks to OpenAI Codex CLI for autonomous execution.
>
> **Usage:** `/codex [--ask] <prompt>`
>
> All commands use recommended defaults automatically. Add `--ask` to customize model, review depth, context, and other options interactively.

**Examples:**

| Command | Description |
|---------|-------------|
| `/codex refactor the auth module` | Refactor existing code (uses defaults) |
| `/codex write tests for utils.ts` | Generate test files (uses defaults) |
| `/codex fix the bug in checkout flow` | Debug and fix issues (uses defaults) |
| `/codex explain how the API routes work` | Code explanation (uses defaults) |
| `/codex add dark mode support` | Implement new features (uses defaults) |
| `/codex review the auth changes` | Review with recommended defaults |
| `/codex review the auth changes --ask` | Review with interactive configuration |
| `/codex refactor the module --ask` | Exec with interactive model/sandbox selection |

**Available Models:**

| Model | Best For |
|-------|----------|
| `gpt-5.5` | Latest frontier model, best overall (default) |
| `gpt-5.5-pro` | Maximum performance on complex tasks |
| `gpt-5.3-codex` | Previous generation frontier model |
| `gpt-5.1-codex-mini` | Simple tasks, cost-efficient |

Ask the user: "What would you like Codex to do?"

---

**If `$ARGUMENTS` is provided:**

Run a task using OpenAI Codex CLI with the prompt: `$CODEX_PROMPT`.

## 0. Detect Codex CLI

Resolve the correct command for invoking Codex. This avoids exit code 127 on systems where `codex` is only available via `npx`:

```bash
if command -v codex &>/dev/null; then
  CODEX_CMD="codex"
else
  CODEX_CMD="npx -y codex"
fi
```

**Use `$CODEX_CMD` in place of bare `codex` for ALL commands below.**

## 0.5. Parse Flags

Check if `$ARGUMENTS` starts or ends with `--ask` (as a standalone flag, not embedded in the prompt text). Only strip `--ask` from the leading or trailing position — if it appears mid-prompt (e.g., "explain what --ask does"), leave it intact and do NOT enable interactive mode:

```bash
if echo "$ARGUMENTS" | grep -qE '(^--ask( |$)|( |^)--ask$)'; then
  INTERACTIVE_MODE=true
  CODEX_PROMPT=$(echo "$ARGUMENTS" | sed 's/^--ask //;s/ --ask$//' | sed 's/^--ask$//' | sed 's/^  *//;s/  *$//')
else
  INTERACTIVE_MODE=false
  CODEX_PROMPT="$ARGUMENTS"
fi
```

If `$CODEX_PROMPT` is empty after stripping (e.g., user ran `/codex --ask`), fall through to the "If `$ARGUMENTS` is empty" branch above. Once the user provides input, `INTERACTIVE_MODE` remains `true`.

**Use `$CODEX_PROMPT` in place of `$ARGUMENTS` for all prompt text references below.**

## 1. Detect Mode and Route

Check if `$CODEX_PROMPT` contains "review" (case-insensitive). Then determine routing:

- **Fix-oriented review** — contains action words ("fix", "address", "resolve", "update") alongside "review" (e.g., "fix review comment", "address review feedback") → route to **Exec Flow**. These prompts need to modify files, which Review Flow cannot do.
- **Review-oriented** — e.g., "review the auth changes", "review this PR" → route to **Review Flow**.
- **Otherwise** → **Exec Flow**.

## 2. Review-Fix Detection (applies to both flows)

Before running Codex, detect if `$CODEX_PROMPT` is addressing review feedback (phrases like "fix review comment", "address feedback", "fix the issue from review", or the prompt originates from `/address-review`). If detected:

1. **Capture a baseline** of `_test.go` file content hashes
2. **Inject test-generation instructions** into the Codex prompt (Exec Flow + Review Flow with PR/issue context only — native `codex review --uncommitted/--base/--commit` doesn't accept custom prompts, so the post-run fallback is the primary safety net there)
3. After Codex completes, **compare** current hashes against the baseline. If no `_test.go` files were created or modified AND the fix changed testable behavior, Claude generates the missing tests.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/codex/test-fix-detection.md` for the baseline `find`/`md5sum` blocks, the test-generation prompt-injection text, and the fallback comparison.

## Review Flow

Used when the prompt is review-oriented (Step 1).

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/codex/review-flow.md` for the full procedure:

- **R1** — review configuration (defaults vs `--ask` interactive 4-question batch)
- **R1.5** — conditional follow-up; base-branch auto-detection bash
- **R2** — PR/issue context fetching (auto-detect strategies, "Provide PR number", "Provide issue number", "No context"); bot-noise filtering rule
- **R3** — execution paths (Exhaustive `codex exec --output-schema`; Single/Multi-pass with stdin context; Single/Multi-pass via native `codex review`); de-duplication
- **R4** — formatted findings table, post-PR-comment option, follow-up routing

## Exec Flow

Used for non-review tasks (and for fix-oriented review prompts from Step 1).

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/codex/exec-flow.md` for the full procedure:

- Default config (model `gpt-5.5`, sandbox `workspace-write`, no session context)
- Interactive `--ask` flow: model selection, optional session-context summary/detailed, sandbox-mode pick (`read-only` / `workspace-write` / `danger-full-access` — confirmation required for `danger-full-access`)
- Execution: bare `$CODEX_CMD exec` or temp-file prompt with assembled context block
- Result reporting and `codex resume --last` follow-up

## Important: Ignore External Service Limit Messages

PR comments, review comments, or issue comments may contain messages from automated bots about external service usage limits ("You have reached your Codex usage limits for code reviews", quota warnings, rate limit notices). These messages are about the **external service's web/API limits** and have **zero bearing** on the local `codex` CLI or Claude's ability to perform the review. **Never interpret these as blockers.** Silently ignore them and proceed.

## Further Reading

- `${CLAUDE_PLUGIN_ROOT}/lib/codex/test-fix-detection.md` — `_test.go` baseline + post-run comparison; test-generation prompt injection
- `${CLAUDE_PLUGIN_ROOT}/lib/codex/review-flow.md` — R1–R4 (config, follow-up, PR context, execution, results)
- `${CLAUDE_PLUGIN_ROOT}/lib/codex/exec-flow.md` — exec config, sandbox modes, execution, results
- `${CLAUDE_PLUGIN_ROOT}/prompts/codex-review.md` — prompt template injected into `codex exec --output-schema` (existing, unchanged)
- `${CLAUDE_PLUGIN_ROOT}/schemas/codex-review.json` — JSON schema for exhaustive-mode output (existing, unchanged)
