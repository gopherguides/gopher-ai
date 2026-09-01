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
$SKILL_ARGS, ${SKILL_ARGS}
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

## Execution Command

Dispatch by language tag:

- `bash` or `shell` → `bash --restricted`
- `sh` → `sh` (POSIX mode, no `--restricted` flag — not supported by POSIX sh)
- `zsh` → `zsh` if available, otherwise skip with info note

The Python helper launches the shell in a new process group with an isolated
working directory and environment. It combines stdout and stderr in a regular
temporary file, applies a 64 KiB `RLIMIT_FSIZE`, waits at most five seconds,
and terminates the process group so background descendants cannot survive the
validation.

## Guardrails

| Guardrail | Mechanism | Why |
|-----------|-----------|-----|
| **Timeout** | 5s subprocess wait | Prevents hangs from a misclassified block |
| **Output limit** | 64 KiB regular-file limit | Prevents unbounded output from exhausting memory or disk |
| **Process ownership** | New process group, terminated after execution | Prevents background descendants from escaping validation |
| **Restricted bash** | `bash --restricted` | Prevents `cd`, changing `PATH`, redirecting output to files outside `/tmp` |
| **Clean environment** | `env -i` | No inherited secrets or developer-specific config (API keys, tokens) |
| **PATH includes /opt/homebrew/bin** | Explicit PATH | Ensures Homebrew tools are available on Apple Silicon |
| **Temporary working root** | Isolated `cwd`, `HOME`, and `TMPDIR` | Keeps incidental files out of the repository |
| **Write prevention** | GREEN excludes commands with file-mutating modes | The shell environment is not a filesystem sandbox |

Record the exit code and bounded combined output. Non-zero exit codes become
`warning` findings.

## CRITICAL Rules

- Never execute blocks classified as YELLOW or RED — see `classification.md`
- Never execute blocks with unresolvable plugin runtime variables
- Never buffer or store more than 64 KiB of execution output
- The block-level tier is the most restrictive of any command on any line
