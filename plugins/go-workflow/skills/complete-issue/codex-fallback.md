# Complete Issue — Codex Fallback Flows

Loaded by `SKILL.md` Phase 2 when codex is unavailable or fails at runtime.
The user chooses how to proceed — never fall back silently.

## Codex NOT Available

Use `AskUserQuestion`:

> **"Codex CLI is not available for self-review. How would you like to proceed?"**

| Option | Description |
|--------|-------------|
| **Retry** | Check again (after you install codex) |
| **Install instructions** | Show how to install: `npm install -g @openai/codex` |
| **Use agent-based review** | Fall back to Claude agent review |
| **Skip review** | Proceed to Phase 3 without review (with warning) |

Handle the user's choice:

- **Retry** → Re-run the availability check from `SKILL.md` Phase 2.
- **Install instructions** → Display: `npm install -g @openai/codex` and ensure `OPENAI_API_KEY` is set. Then re-check.
- **Use agent-based review** → Use an Agent subagent to review the diff for correctness, security, and Go idioms.
- **Skip review** → Warn "Self-review skipped — proceeding to E2E verification without code review." and go directly to Phase 3.

## Codex Exec Fails at Runtime

If `codex exec` exits non-zero or produces no output, do NOT silently fall
back. Display the exit code and stderr first, then ask via
`AskUserQuestion`.

### Exit Code 124 (Timeout)

| Option | Description |
|--------|-------------|
| Retry with longer timeout | Re-run with `CODEX_TIMEOUT` doubled (capped at 600s) |
| Use `codex review --base` | Swap to a base-diff invocation instead of `codex exec` |
| Drop `--output-schema` | Some structured-output schemas cause hangs; try without |
| Agent review | Dispatch an Agent subagent for the review |
| Skip review | Warn and go to Phase 3 |

### Other Exit Codes

| Option | Description |
|--------|-------------|
| Retry | Run codex once more with the same parameters |
| Debug | Print the exit code, last 50 lines of stderr, and the command that ran; let the user diagnose |
| Agent review | Dispatch an Agent subagent for the review |
| Skip review | Warn and go to Phase 3 |

The user must choose. Do not pick a fallback automatically — the
"Skip review" option exists precisely so the user gets to make that call,
not the agent.
