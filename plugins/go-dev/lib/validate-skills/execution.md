# Validate-Skills — Step 5 Safe Execution

Loaded by `commands/validate-skills.md` Step 5 when executing eligible
GREEN-tier blocks. Owns the guardrail enumeration and rationale.

## Pre-execution Variable Scan

Before executing, scan for **plugin runtime variables** that cannot be
resolved outside the plugin context. Use the explicit list — do NOT match
all uppercase variables, that would falsely flag standard shell variables
like `$HOME`, `$PATH`, `$PWD`.

Known plugin runtime variables (match these literally):

```
$CLAUDE_PLUGIN_ROOT, ${CLAUDE_PLUGIN_ROOT}
$ARGUMENTS, ${ARGUMENTS}
$MODEL, ${MODEL}
$TARGET_PATH, ${TARGET_PATH}
$STAGED, ${STAGED}
$DRY_RUN, ${DRY_RUN}
$REVIEW_JSON, ${REVIEW_JSON}
$DIFF, ${DIFF}
$FINDINGS, ${FINDINGS}
$LLM_CHOICE, ${LLM_CHOICE}
```

Standard shell variables (`$HOME`, `$PATH`, `$PWD`, `$USER`, `$TMPDIR`)
and variables assigned within the block itself are NOT considered runtime
variables.

If runtime variables found → skip execution, report as `info`: "Block
contains plugin runtime variables — skipped execution."

## Timeout Detection

```bash
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
else
  TIMEOUT_CMD=""
fi
```

If neither is available, skip execution and report as `info`: "No
`timeout` or `gtimeout` available — skipping safe execution. Install
coreutils for execution support."

## Execution Command

Dispatch by language tag:

- `bash` or `shell` → `bash --restricted`
- `sh` → `sh` (POSIX mode, no `--restricted` flag — not supported by POSIX sh)
- `zsh` → `zsh` if available, otherwise skip with info note

```bash
$TIMEOUT_CMD 5 env -i \
  HOME=/tmp \
  TMPDIR=/tmp \
  PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  <shell-command> "$TMPDIR/block-NNN.sh" 2>&1
```

## Guardrails

| Guardrail | Mechanism | Why |
|-----------|-----------|-----|
| **Timeout** | 5s via `$TIMEOUT_CMD` | Prevent hangs from a misclassified block |
| **Restricted bash** | `bash --restricted` | Prevents `cd`, changing `PATH`, redirecting output to files outside `/tmp` |
| **Clean environment** | `env -i` | No inherited secrets or developer-specific config (API keys, tokens) |
| **PATH includes /opt/homebrew/bin** | Explicit PATH | Ensures Homebrew tools are available on Apple Silicon |
| **Write restriction** | Only `/tmp` is writable | A misbehaving block can't damage repo state |

Record exit code and any stderr output. Non-zero exit codes become
`warning` findings.

## CRITICAL Rules

- Never execute blocks classified as YELLOW or RED — see `classification.md`
- Never execute blocks with unresolvable plugin runtime variables
- The block-level tier is the most restrictive of any command on any line
