---
argument-hint: "[--ask] <prompt>"
description: "Delegate a task to Codex, preferring the official Codex Claude Code plugin when installed"
allowed-tools: ["Bash(codex:*)", "Bash(claude:*)", "Bash(npx:*)", "Bash(command:*)", "Bash(echo:*)", "Bash(printf:*)", "Bash(git:*)", "Bash(gh:*)", "Bash(awk:*)", "Bash(jq:*)", "Bash(grep:*)", "Bash(sed:*)", "Bash(find:*)", "Bash(md5sum:*)", "Read", "AskUserQuestion"]
---

# Delegate to Codex

**If `$ARGUMENTS` is empty or not provided:**

Display usage and ask for input:

> This command delegates tasks to Codex. In Claude Code, it prefers the official `codex@openai-codex` plugin when installed and falls back to the built-in Codex CLI flow when it is missing or declined.
>
> **Usage:** `/llm-tools:codex [--ask] <prompt>`
>
> All commands use recommended defaults automatically. Add `--ask` to use the customizable built-in CLI flow for model, review depth, context, and other options.

**Examples:**

| Command | Description |
|---------|-------------|
| `/llm-tools:codex refactor the auth module` | Refactor existing code (uses defaults) |
| `/llm-tools:codex write tests for utils.ts` | Generate test files (uses defaults) |
| `/llm-tools:codex fix the bug in checkout flow` | Debug and fix issues (uses defaults) |
| `/llm-tools:codex explain how the API routes work` | Code explanation (uses defaults) |
| `/llm-tools:codex add dark mode support` | Implement new features (uses defaults) |
| `/llm-tools:codex review the auth changes` | Review with recommended defaults |
| `/llm-tools:codex review the auth changes --ask` | Review with interactive configuration |
| `/llm-tools:codex refactor the module --ask` | Exec with interactive model/sandbox selection |

**Codex Model Selection:**

| Option | Behavior |
|--------|----------|
| Provider default | Let Codex CLI choose the latest recommended Codex model |
| Custom model ID | Pass an explicit model with `-m` or `-c model=...` |

Ask the user: "What would you like Codex to do?"

---

**If `$ARGUMENTS` is provided:**

Run a task using Codex with the prompt: `$CODEX_PROMPT`.

## 0. Parse Flags

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

Store `CODEX_ROUTE=review` for review-oriented prompts and `CODEX_ROUTE=exec` for fix-oriented or non-review prompts. Also store `REVIEW_FIX_MODE=true` for fix-oriented review prompts and `REVIEW_FIX_MODE=false` otherwise.

Also detect whether the review asks for an adversarial/challenge review. Prompts that contain "adversarial", "challenge", "pressure-test", "question the approach", "trade-off", "risk", or similar wording alongside "review" route to the official `/codex:adversarial-review` command when the official plugin is installed.

For review-oriented prompts, detect a standalone `--base <ref>` and store its value as `REQUESTED_BASE`. Reject `--base` without a following ref. Preserve this explicit base for official review commands and do not include the flag or its value in adversarial-review focus text.

## 2. Prefer Official Claude Code Plugin

For interactive Claude Code use, prefer the official OpenAI Codex plugin (`codex@openai-codex`) over this command's built-in CLI fallback. This step applies only to this `/llm-tools:codex` command. Scripted pipeline paths such as `review-loop`, `complete-issue`, and `ship` must keep using `codex exec --output-schema` and must not depend on the official plugin.

If `INTERACTIVE_MODE=true`, the user explicitly requested the built-in flow's interactive configuration. Skip the rest of Step 2 and continue directly to Step 3. Do not silently discard `--ask` or route it to an official command that does not support the same review-depth and context questions.

If `REVIEW_FIX_MODE=true`, skip the rest of Step 2 and continue directly to Step 3. Review-feedback fixes must stay on the built-in CLI path so Step 4 can capture the `_test.go` baseline, inject the test-generation requirement, and perform the post-run missing-test fallback before any fix is accepted.

Detect the official plugin:

```bash
CLAUDE_PLUGINS_DIR="${CLAUDE_PLUGINS_DIR:-$HOME/.claude/plugins}"
INSTALLED_PLUGINS="$CLAUDE_PLUGINS_DIR/installed_plugins.json"
CODEX_PLUGIN_INSTALLED=false
CODEX_PLUGIN_LISTED=false
CODEX_PLUGIN_ENABLED=false
CODEX_PLUGIN_INSTALL_PATH=""

if [ -f "$INSTALLED_PLUGINS" ]; then
  if command -v jq >/dev/null 2>&1; then
    if jq -e '.plugins["codex@openai-codex"] != null' "$INSTALLED_PLUGINS" >/dev/null 2>&1; then
      CODEX_PLUGIN_LISTED=true
    fi

    CODEX_PLUGIN_INSTALL_PATH=$(
      jq -r '
        .plugins["codex@openai-codex"] // empty
        | ..
        | if type == "object" then (.installPath? // .path? // empty)
          elif type == "string" then .
          else empty
          end
      ' "$INSTALLED_PLUGINS" 2>/dev/null |
      while IFS= read -r path; do
        if [ -d "$path" ]; then
          printf '%s\n' "$path"
          break
        fi
      done
    )
  elif awk '/"codex@openai-codex"/ { found=1 } END { exit !found }' "$INSTALLED_PLUGINS"; then
    CODEX_PLUGIN_LISTED=true
  fi

  if [ -n "$CODEX_PLUGIN_INSTALL_PATH" ] && [ -d "$CODEX_PLUGIN_INSTALL_PATH" ]; then
    CODEX_PLUGIN_INSTALLED=true
  fi
fi

if [ "$CODEX_PLUGIN_INSTALLED" != "true" ] && [ "$CODEX_PLUGIN_LISTED" = "true" ]; then
  for plugin_json in "$CLAUDE_PLUGINS_DIR"/cache/openai-codex/codex/*/.claude-plugin/plugin.json; do
    if [ -f "$plugin_json" ]; then
      CODEX_PLUGIN_INSTALL_PATH=${plugin_json%/.claude-plugin/plugin.json}
      CODEX_PLUGIN_INSTALLED=true
      break
    fi
  done
fi

if command -v claude >/dev/null 2>&1; then
  if command -v jq >/dev/null 2>&1; then
    if CLAUDE_PLUGIN_LIST=$(claude plugin list --json 2>/dev/null); then
      if printf '%s\n' "$CLAUDE_PLUGIN_LIST" | jq -e 'any(.[]; .id == "codex@openai-codex")' >/dev/null 2>&1; then
        CODEX_PLUGIN_LISTED=true
        CODEX_PLUGIN_INSTALLED=true
      fi
      if printf '%s\n' "$CLAUDE_PLUGIN_LIST" | jq -e 'any(.[]; .id == "codex@openai-codex" and .enabled == true)' >/dev/null 2>&1; then
        CODEX_PLUGIN_ENABLED=true
        CODEX_PLUGIN_INSTALL_PATH=$(printf '%s\n' "$CLAUDE_PLUGIN_LIST" | jq -r '[.[] | select(.id == "codex@openai-codex" and .enabled == true) | .installPath // empty][0] // empty')
      fi
    fi
  elif CLAUDE_PLUGIN_LIST=$(claude plugin list 2>/dev/null); then
    if printf '%s\n' "$CLAUDE_PLUGIN_LIST" | awk '/codex@openai-codex/ { found=1 } END { exit !found }'; then
      CODEX_PLUGIN_LISTED=true
      CODEX_PLUGIN_INSTALLED=true
    fi
    if printf '%s\n' "$CLAUDE_PLUGIN_LIST" | awk '
      /codex@openai-codex/ { found=1; next }
      found && /Status:/ { status_found=1; enabled=(index($0, "✔ enabled") > 0); exit }
      END { exit !(status_found && enabled) }
    '; then
      CODEX_PLUGIN_ENABLED=true
    fi
  fi
fi
```

Do not treat a marketplace checkout alone (`$CLAUDE_PLUGINS_DIR/marketplaces/openai-codex/...`) as installed; the commands are available only when `codex@openai-codex` is present in Claude Code's installed plugin registry. If enabled state cannot be queried, leave `CODEX_PLUGIN_ENABLED=false` and offer the inactive-plugin choice rather than assuming an installed plugin is active.

### If `CODEX_PLUGIN_ENABLED=true`

Route to the official plugin command and stop before the built-in CLI fallback:

| Prompt type | Official route |
|-------------|----------------|
| Normal branch review | `/codex:review --base <base-ref> [--background|--wait]` |
| Normal working-tree review | `/codex:review [--background|--wait]` |
| Adversarial or challenge branch review | `/codex:adversarial-review --base <base-ref> [--background|--wait] <focus text>` |
| Adversarial or challenge working-tree review | `/codex:adversarial-review [--background|--wait] <focus text>` |
| Fix-oriented review or delegated task | `/codex:rescue [--background|--wait|--resume|--fresh|--model <id>|--effort <value>] <prompt>` |

When routing reviews, auto-detect the base branch the same way Review Flow does:

```bash
BASE_BRANCH="${REQUESTED_BASE:-}"
if [ -z "$BASE_BRANCH" ]; then
  BASE_BRANCH=$(gh pr view --json baseRefName --jq '.baseRefName' 2>/dev/null || true)
fi
if [ -z "$BASE_BRANCH" ]; then
  BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || true)
fi
if [ -z "$BASE_BRANCH" ]; then
  BASE_BRANCH=$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p' | awk 'NF && $0 !~ /^\(.*\)$/ { print; exit }')
fi
if [ -z "$BASE_BRANCH" ]; then
  BASE_BRANCH="main"
fi
```

Include `--base <base-ref>` for branch reviews. Preserve only flags the official target command supports:

| Official command | Preserve from prompt |
|------------------|----------------------|
| `/codex:review` | `--base <ref>`, `--background`, `--wait` |
| `/codex:adversarial-review` | `--base <ref>`, `--background`, `--wait`, trailing focus text |
| `/codex:rescue` | `--background`, `--wait`, `--resume`, `--fresh`, `--model`, `--effort` |

Do not add model flags by default; the official plugin and Codex share the user's `~/.codex` auth and config. Do not append focus text to `/codex:review`; that command is not steerable. If the user asks for a focused challenge, risk, trade-off, or pressure-test review, route to `/codex:adversarial-review` instead.

Review-oriented prompts default to branch review, matching the built-in Review Flow's "Changes vs branch" default. If `REQUESTED_BASE` is set, preserve it. Otherwise use `--base "$BASE_BRANCH"` for prompts such as "review", "review the auth changes", or "review this PR". Only omit `--base` when the user explicitly asks to review the current working tree or uncommitted changes and did not provide `--base`.

If this command runner cannot invoke another slash command from inside the current slash command, print the exact `/codex:*` command to run and stop. Also state that if the command is unavailable in the current session, the user should run `/reload-plugins` and retry, or rerun `/llm-tools:codex ... --ask` to choose the built-in CLI flow. Do not continue into the CLI fallback after a successful official-plugin route or after printing the official command.

### If `CODEX_PLUGIN_INSTALLED=true` and `CODEX_PLUGIN_ENABLED=false`

Warn the user that the official plugin is installed but disabled or not active in the current Claude Code configuration. Use `AskUserQuestion`: "The official Codex plugin is installed but inactive. How would you like to continue?"

| Option | Description |
|--------|-------------|
| Enable or reload official plugin (Recommended) | Open `/plugin`, enable `codex@openai-codex`, run `/reload-plugins`, and retry |
| Proceed with built-in CLI fallback | Continue to Step 3 and run the existing `codex exec` / `codex review` flow |

If the user chooses the official plugin, print those enable/reload instructions and stop. If the user chooses fallback, continue below.

### If `CODEX_PLUGIN_INSTALLED=false`

Warn the user:

> The official Codex Claude Code plugin (`codex@openai-codex`) is not installed. Interactive `/llm-tools:codex` use prefers that plugin for `/codex:review`, `/codex:adversarial-review`, and `/codex:rescue`. The built-in Codex CLI fallback is still available and unchanged.

Use `AskUserQuestion`: "How would you like to continue?"

| Option | Description |
|--------|-------------|
| Install official plugin (Recommended) | Show the install steps and stop so the user can reload plugins |
| Proceed with built-in CLI fallback | Continue to Step 3 and run the existing `codex exec` / `codex review` flow |

If the user chooses install, print exactly:

```text
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/reload-plugins
/codex:setup
```

Then stop. If the user chooses fallback, continue below.

## 3. Detect Codex CLI Fallback

Prefer an installed Codex executable. Availability checks must not download or
execute an npm package:

```bash
if command -v codex &>/dev/null; then
  CODEX_CMD="codex"
else
  CODEX_CMD=""
fi
```

If `CODEX_CMD` is empty, use `AskUserQuestion`:

> **"Codex CLI is not installed. How would you like to continue?"**

| Option | Description |
|--------|-------------|
| **Run official package once** | Explicitly consent to run `npx -y @openai/codex` for this request only |
| **Install Codex** | Show `npm install -g @openai/codex`, then stop so the user can authenticate and retry |
| **Abort** | Stop without running Codex or downloading a package |

- **Run official package once** → first verify `npx` is available without
  invoking Codex. If it is, set `CODEX_CMD="npx -y @openai/codex"` and continue.
  If it is unavailable, show the install option and stop.
- **Install Codex** → show `npm install -g @openai/codex`. Explain that
  `codex login` supports ChatGPT sign-in and API-key authentication, then stop.
- **Abort** → stop. Do not run Codex or invoke `npx`.

**Use `$CODEX_CMD` in place of bare `codex` for all built-in fallback commands below.**

## 4. Review-Fix Detection (applies to both fallback flows)

Before running Codex, detect if `$CODEX_PROMPT` is addressing review feedback (phrases like "fix review comment", "address feedback", "fix the issue from review", or the prompt originates from `/address-review`). If detected:

1. **Capture a baseline** of `_test.go` file content hashes
2. **Inject test-generation instructions** into the Codex prompt (Exec Flow + Review Flow with PR/issue context only — native `codex review --uncommitted/--base/--commit` doesn't accept custom prompts, so the post-run fallback is the primary safety net there)
3. After Codex completes, **compare** current hashes against the baseline. If no `_test.go` files were created or modified AND the fix changed testable behavior, Claude generates the missing tests.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/codex/test-fix-detection.md` for the baseline `find`/`md5sum` blocks, the test-generation prompt-injection text, and the fallback comparison.

## Review Flow

Used by the built-in fallback when the prompt is review-oriented (Step 1).

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/codex/review-flow.md` for the full procedure:

- **R1** — review configuration (defaults vs `--ask` interactive 4-question batch)
- **R1.5** — conditional follow-up; base-branch auto-detection bash
- **R2** — PR/issue context fetching (auto-detect strategies, "Provide PR number", "Provide issue number", "No context"); bot-noise filtering rule
- **R3** — execution paths (Exhaustive `codex exec --output-schema`; Single/Multi-pass with stdin context; Single/Multi-pass via native `codex review`); de-duplication
- **R4** — formatted findings table, post-PR-comment option, follow-up routing

## Exec Flow

Used by the built-in fallback for non-review tasks (and for fix-oriented review prompts from Step 1).

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/codex/exec-flow.md` for the full procedure:

- Default config (provider default model, reasoning effort `high`, sandbox `workspace-write`, no session context)
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
