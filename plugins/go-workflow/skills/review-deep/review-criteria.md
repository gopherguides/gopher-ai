# Review Criteria: Consolidated Go-Specific + General Analysis

This document defines the complete review criteria applied during deep review. Criteria are drawn from multiple proven sources in the gopher-ai system and consolidated here for single-pass application.

## Review Focus Areas

### 1. Correctness (Priority 0-1)

- **Error handling**: All fallible operations must have errors checked. Errors should be wrapped with `%w` for context. Never silently discard errors (`_ = doSomething()`).
- **Nil dereference**: Check pointer safety, especially after type assertions, map lookups, and interface conversions. Verify nil checks before pointer access.
- **Resource cleanup**: `defer Close()` for files, connections, response bodies. Check for leaked goroutines, unclosed channels, database connections.
- **Context propagation**: `context.Context` as first parameter. Cancellation handled correctly. No detached goroutines ignoring parent context.
- **Race conditions**: Shared state protected by `sync.Mutex` or channels. Check for concurrent map access. Verify `go test -race` safety.
- **Logic errors**: Off-by-one, wrong comparison operator, inverted conditions, missing break/fallthrough in switch.
- **Missing error checks**: Every `err` returned by a function call must be checked.

### 2. Security (Priority 0-1)

- **Injection**: SQL parameterization (not string concatenation). Template escaping. Command injection via `os/exec`.
- **Auth bypass**: Missing authorization checks on endpoints. Privilege escalation paths.
- **Data exposure**: Sensitive data in logs, error messages, or API responses. PII handling.
- **Path traversal**: Use `filepath.Clean` for user-provided paths. Validate path boundaries.
- **Hardcoded secrets**: No API keys, passwords, tokens, or connection strings in source code.
- **Unsafe deserialization**: Validate untrusted input before unmarshaling.

### 3. Performance (Priority 1-2)

- **O(n^2) loops**: Nested iterations over large collections. Missing index lookups.
- **Unnecessary allocations**: Allocations in hot paths. Missing `sync.Pool` for frequently allocated objects.
- **Unbounded growth**: Slices, maps, or channels that grow without limit. Missing capacity hints for known sizes.
- **Missing preallocation**: `make([]T, 0, knownSize)` when size is known or estimable.
- **Database**: N+1 query patterns. Missing indexes for frequent queries.
- **Goroutine leaks**: Goroutines that never terminate. Missing `context.WithCancel` or `context.WithTimeout`.

### 4. Maintainability (Priority 2-3)

- **Dead code**: Unused functions, variables, imports, or types introduced in this diff.
- **Function length**: Functions exceeding 50 lines should be flagged for review.
- **Cognitive complexity**: Deeply nested conditionals (>3 levels). Complex boolean expressions.
- **Naming**: Follow Go conventions -- short names for short scopes, descriptive for exports. Acronyms in ALLCAPS (`HTTPClient`, not `HttpClient`).
- **Single responsibility**: Each function should do one thing. Each package should have a clear purpose.
- **Missing cleanup**: `defer` patterns for setup/teardown. Proper test cleanup with `t.Cleanup()`.

### 5. Developer Experience (Priority 2-3)

- **Error context**: Errors should include enough context to diagnose without a debugger. Wrap with `fmt.Errorf("operation on %s: %w", item, err)`.
- **API clarity**: Exported functions should be self-documenting. Parameter names should convey purpose.
- **Poor defaults**: Functions that require callers to remember non-obvious setup steps.
- **Confusing control flow**: Excessive early returns, goto-like patterns, or non-obvious state machines.

---

## Go Idiom Checks

These are Go-specific patterns that distinguish idiomatic code:

- **Accept interfaces, return structs**: Function parameters should be interfaces (narrow), return types should be concrete.
- **Error wrapping with `%w`**: Use `fmt.Errorf("context: %w", err)` not `fmt.Errorf("context: %s", err.Error())`.
- **`errgroup` for goroutine coordination**: Prefer `golang.org/x/sync/errgroup` over manual `sync.WaitGroup` + error channels.
- **`context.Context` as first param**: Not embedded in structs, not passed via closures.
- **Table-driven tests**: Test functions should use `[]struct{ name string; ... }` pattern with `t.Run`.
- **`t.Helper()`**: Test helper functions must call `t.Helper()` for proper line reporting.
- **`t.Parallel()`**: Tests that don't share state should use `t.Parallel()` for faster execution.
- **Short variable names**: `r` for reader, `w` for writer, `ctx` for context, `err` for error. Avoid stuttering (`httpClient.HTTPDo`).
- **Receiver naming**: Short, consistent receiver names (not `this` or `self`). Same name across all methods of a type.

---

## Spec Compliance Criteria (when issue/PR context available)

When PR or issue context is available, also verify:

1. **Requirement coverage**: Does every acceptance criterion from the issue have a corresponding implementation in the diff?
2. **Test coverage**: Does every acceptance criterion have a corresponding test?
3. **Missing requirements**: Are there requirements mentioned in the issue body or comments that are NOT addressed?
4. **Scope creep**: Does the implementation include changes NOT requested by the issue?
5. **Bug fix root cause** (bug fixes only): Does the fix address the actual root cause, not just the symptom?
6. **Feature completeness** (features only): Do tests cover happy path, edge cases, and error conditions?

**CRITICAL: Do NOT trust the implementer's claims. Independently verify by reading the actual code line-by-line against the requirements.**

---

## Breaking Change Detection

Check for API-breaking changes in exported symbols:

```bash
git diff "${BASE_BRANCH}...HEAD" -- '*.go' | grep -E "^-func [A-Z]|^-type [A-Z]|^-var [A-Z]|^-const [A-Z]"
```

Breaking changes include:
- Removed exported functions, types, methods, variables, or constants
- Changed function signatures (added/removed parameters, changed types)
- Changed struct field types or removed fields
- Removed interface methods (breaks all implementors)
- Changed package paths

---

## Quality Score Rubric

Score the changes on a 100-point scale:

| Criteria | Points | Description |
|----------|--------|-------------|
| Error Handling | 20 | All errors checked, wrapped with context, no silent discards |
| Test Coverage | 20 | New code has tests, edge cases covered, table-driven patterns |
| Naming/Style | 15 | Idiomatic Go conventions, clear naming, consistent formatting |
| Documentation | 15 | Exported symbols documented, complex logic commented |
| Complexity | 15 | Functions focused (<50 lines), low nesting, single responsibility |
| Safety | 15 | No races, no leaks, no panics, proper cleanup |

**Scoring guide:**
- 90-100: Excellent -- ready to merge
- 75-89: Good -- minor issues only
- 60-74: Needs work -- several findings to address
- Below 60: Significant issues -- major rework needed

---

## Confidence Scoring

For each finding, assign a confidence score (0.0 to 1.0):

- **0.9-1.0**: Certain -- clear bug, provable issue, obvious violation
- **0.7-0.8**: High confidence -- very likely an issue, but context might justify it
- **0.5-0.6**: Medium confidence -- possible issue, needs evaluation
- **0.3-0.4**: Low confidence -- might be intentional, worth flagging
- **Below 0.3**: Filtered out -- too uncertain to be actionable

Findings with confidence < 0.3 are automatically discarded. Findings with priority 3 AND confidence < 0.5 are auto-skipped during the fix phase.

---

## Rules

1. Only flag issues INTRODUCED by this diff. Do not flag pre-existing code unless it interacts with new code to create a bug.
2. Every finding MUST cite the exact file path and line range from the diff.
3. Verify line numbers against the diff -- accuracy is critical.
4. Do NOT stop after finding a few issues -- continue reviewing the entire diff until every qualifying finding is listed.
5. If the diff is clean and has no issues, report zero findings with a "patch is correct" verdict and the quality score.
