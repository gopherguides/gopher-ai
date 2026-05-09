# Go — Error Handling

Loaded by `SKILL.md` when the user is writing or reviewing Go error-handling code.

You are a Go reliability engineer. Every error is an event that must either be handled or propagated with context — silent failures and duplicate logs are equally unacceptable.

## Modes

**Coding mode** — Writing new error handling code. Follow the best practices sequentially. Write the minimal correct error handling for the situation.

**Review mode** — Reviewing a PR diff. Focus exclusively on the changed lines: check for swallowed errors, missing wrapping, log-and-return pairs, panic misuse, and `%v` where `%w` belongs.

**Audit mode** — Auditing a codebase. Use up to 5 parallel sub-agents targeting independent categories (see Parallel Audit below).

## Core principle

Handle every error exactly once: either log it and handle the failure, or wrap it with context and return it. Never both, never neither.

## Best practices

1. Returned errors MUST always be checked — NEVER discard with `_`
2. Wrap errors with context using `fmt.Errorf("{context}: %w", err)`
3. Error strings MUST be lowercase, no trailing punctuation
4. Use `%w` internally, `%v` at system boundaries (to hide implementation details)
5. Use `errors.Is` and `errors.As` instead of `==` or type assertions
6. Use `errors.Join` (Go 1.20+) to combine independent errors
7. Errors MUST be either logged OR returned, NEVER both (single handling rule)
8. Use sentinel errors (`var ErrNotFound = errors.New(...)`) for expected conditions
9. Use custom error types when errors need to carry structured data
10. NEVER use `panic` for expected error conditions — reserve for truly unrecoverable states
11. Use `slog` (Go 1.21+) for structured error logging
12. Never expose internal errors to users — translate to user-friendly messages
13. Keep error messages low-cardinality — attach variable data as structured attributes, not interpolated into strings

## Reference material

For detailed patterns, examples, and decision tables, see the reference files:

- `references/error-creation.md` — sentinel errors, custom error types, naming conventions, when to use which
- `references/error-wrapping.md` — `%w` vs `%v`, `errors.Is`/`errors.As`, `errors.Join`, unwrap patterns
- `references/error-handling-patterns.md` — single handling rule, panic/recover, structured logging, HTTP error translation

## Parallel audit

When auditing a codebase for error handling issues, dispatch up to 5 parallel sub-agents. Each agent targets one independent category and reports findings as a list of `file:line` entries with a brief description.

1. **Error creation** — Validate `errors.New` and `fmt.Errorf` usage. Check naming conventions (`ErrXxx` for sentinels, `XxxError` for types). Flag errors created with uppercase strings or trailing punctuation.
2. **Error wrapping** — Audit `%w` vs `%v` patterns. Flag `%v` used internally where `%w` should be used. Flag `%w` at public API boundaries where `%v` should be used. Check for double-wrapping.
3. **Single handling rule** — Find log-and-return violations: any code path that both logs an error AND returns it (or returns a wrapped version of it). Also find swallowed errors (`_ = someFunc()`).
4. **Panic/recover** — Audit all `panic()` calls. Flag any panic used for expected error conditions. Verify `recover()` is only used in deferred functions. Check that recovered panics are converted to errors.
5. **Structured logging** — Verify `slog` usage at error sites. Flag `log.Printf` or `fmt.Printf` used for error logging. Check that error values are passed as structured attributes (`slog.Any("error", err)`) not interpolated into message strings.

## Anti-patterns

- **Panic-as-control-flow** — using `panic`/`recover` to short-circuit a deep call stack instead of returning an error. Failures become invisible to the type system and callers.
- **Stringly-typed error matching** (`if err.Error() == "not found"`) — strings are not API. Use sentinel errors with `errors.Is` or typed errors with `errors.As`.
- **Log-and-return** — logging the error inside the inner function AND returning it. Produces duplicate logs and obscures the originating call site.
- **Silent discard** (`_ = doSomething()`) — turns a failure into nothing. If ignoring is intentional, document the reason; otherwise it's a bug.
- **`%v` on a wrapped error** — destroys the error chain. Use `%w` so callers can `errors.Is` / `errors.As` through the wrap.

## Cross-references (within `go` skill)

- See `concurrency.md` for error propagation in goroutines and errgroup patterns
- See `testing.md` for error assertion patterns, testing sentinel errors and custom types
- See `debugging.md` for investigating error causes and tracing error chains
