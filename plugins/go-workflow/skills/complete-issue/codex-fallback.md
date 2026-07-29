# Complete Issue — Codex Fallback Flows

Loaded by `SKILL.md` Phase 2 when codex is unavailable or fails at runtime.
Never skip review or replace an explicitly required backend silently.

## Codex NOT Available

Display: `npm install -g @openai/codex`, then run `codex login` for ChatGPT sign-in or API-key authentication.
Re-run availability detection once.

If Codex remains unavailable and the user did not explicitly require it,
resolve a **driver-resolvable gate**: use a synchronous fresh-context Fable
review with the same prompt and structured schema when native delegation is
available. State `Decision`, `Evidence`, and `Rationale`. Never use `claude -p`
because it bills metered API usage rather than the subscription.

If Codex was explicitly required, follow the shared **missing-intent gate**
before replacing it. If neither backend can complete in the current session,
persist `WORKFLOW_RESULT=INCOMPLETE` and
`WORKFLOW_REASON=review-backend-unavailable`, then stop before Phase 3.

## Codex Exec Fails at Runtime

If `codex exec` exits non-zero or produces no output, display the exit code,
stderr, and partial output, then apply the recovery order below.

### Exit Code 124 (Timeout)

1. Retry once with `CODEX_TIMEOUT` doubled and capped at 1800 seconds.
2. If structured schema processing is implicated, retry without
   `--output-schema`.
3. Use `codex review --base` only when the coverage plan can preserve complete
   review across its units.
4. If Codex was not explicitly required, use synchronous Fable review when
   available and state the rationale.
5. Otherwise follow the shared missing-intent gate before replacing Codex, or
   stop incomplete when no review path remains.

### Other Exit Codes

Inspect the exit code, last 50 lines of stderr, command, authentication, and
network state. Retry once for a transient or locally correctable failure. Then
apply the same explicit-backend rule: an unpinned run may use synchronous Fable
with a stated rationale; an explicitly required Codex backend needs missing
intent before replacement. If no complete review path remains, stop incomplete
with `WORKFLOW_REASON=review-backend-failed`. Never continue to Phase 3 without
the review required by the top-level completion criteria.
