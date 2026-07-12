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
| **Use Fable subagent review** | Claude subagent with the same prompt + structured JSON schema — no CLI, no extra cost |
| **Skip review** | Proceed to Phase 3 without review (with warning) |

Handle the user's choice:

- **Retry** → Re-run the availability check from `SKILL.md` Phase 2.
- **Install instructions** → Display: `npm install -g @openai/codex`, then run `codex login` for ChatGPT sign-in or API-key authentication. Then re-check.
- **Use Fable subagent review** → Dispatch a fresh-context Agent subagent synchronously with `run_in_background=false`, wait for its final response in the current session, and parse it through the same structured path (see the Fable section in go-workflow `lib/ship/local-review.md`). Never use `claude -p` — it bills metered API usage, not the subscription. If it cannot complete before a headless session ends, treat the review as skipped and proceed to Phase 3; never resume or replace it in a successor session.
- **Skip review** → Warn "Self-review skipped — proceeding to E2E verification without code review." and go directly to Phase 3.

## Codex Exec Fails at Runtime

If `codex exec` exits non-zero or produces no output, do NOT silently fall
back. Display the exit code and stderr first, then ask via
`AskUserQuestion`.

### Exit Code 124 (Timeout)

| Option | Description |
|--------|-------------|
| Retry with longer timeout | Re-run with `CODEX_TIMEOUT` doubled (capped at 1800s) |
| Fable subagent review | Same prompt + schema via a Claude subagent — no timeout, no extra cost |
| Use `codex review --base` | Swap to a base-diff invocation instead of `codex exec` |
| Drop `--output-schema` | Some structured-output schemas cause hangs; try without |
| Skip review | Warn and go to Phase 3 |

### Other Exit Codes

| Option | Description |
|--------|-------------|
| Retry | Run codex once more with the same parameters |
| Debug | Print the exit code, last 50 lines of stderr, and the command that ran; let the user diagnose |
| Fable subagent review | Same prompt + schema via a Claude subagent — no CLI, no extra cost |
| Skip review | Warn and go to Phase 3 |

The user must choose. Do not pick a fallback automatically — the
"Skip review" option exists precisely so the user gets to make that call,
not the agent.
