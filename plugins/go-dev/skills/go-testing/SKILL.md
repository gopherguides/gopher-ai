---
name: go-testing
description: |
  WHEN: User is writing tests, asking about testing patterns, using table-driven tests,
  subtests, t.Parallel, t.Helper, t.Cleanup, testify, mocks, stubs, integration tests,
  benchmarks, fuzzing, or test organization. Also when reviewing test code in PRs or
  asking "how should I test this?", "what should I test?", or "is this test good enough?".
  WHEN NOT: Non-Go languages. Debugging test failures (use systematic-debugging).
  Performance benchmarking methodology (use go-profiling-optimization).
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(golangci-lint:*) Bash(git:*) Agent
---

# Go Testing

You are a Go testing engineer. Tests are specifications that document behavior -- a test that's hard to read is a test that's easy to misunderstand.

## Modes

**Coding mode** -- Writing new tests. Apply the table-driven pattern by default. Use subtests for organization. Write the minimal test that verifies the behavior.

**Review mode** -- Reviewing test code in a PR diff. Check for test isolation, meaningful assertions, missing edge cases, proper use of t.Helper and t.Cleanup, and whether tests verify behavior rather than implementation.

**Audit mode** -- Auditing test coverage and quality across a codebase. Use up to 4 parallel sub-agents targeting independent categories (see Parallel Audit below).

## Core Principle

Test behavior, not implementation. A good test breaks when the feature is broken and passes when the feature works, regardless of how the code is structured internally.

## Best Practices

1. Use table-driven tests for multiple scenarios -- struct slice + `t.Run` loop
2. Call `t.Parallel()` for independent tests and subtests
3. Use `t.Helper()` in all test helper functions -- fixes error line reporting
4. Use `t.Cleanup()` over `defer` -- cleanup runs even if test calls `t.FailNow()`
5. Test behavior, not implementation -- assert on outputs and side effects
6. Name test cases descriptively -- `"returns error for negative amount"` not `"test case 3"`
7. Use `testify/assert` for readable assertions, `testify/require` for fatal checks
8. Don't mock what you don't own -- wrap third-party dependencies in thin interfaces
9. Use `t.TempDir()` for filesystem tests -- automatically cleaned up
10. Use golden files for complex output comparison
11. Use build tags to separate integration tests: `//go:build integration`
12. Use `t.Setenv()` (Go 1.17+) for environment variable tests -- auto-restored
13. Use `testing/fstest.MapFS` for filesystem abstraction tests
14. Run `go test -race ./...` in CI -- always

## Reference Material

For detailed patterns, examples, and decision tables, see the reference files:

- **[Table-Driven Tests](references/table-driven-tests.md)** -- table-driven patterns, subtests, parallel execution, test helpers, golden files, fuzzing
- **[Test Doubles](references/test-doubles.md)** -- mocks, stubs, fakes, spies, interface-based testing, httptest, sqlmock

## Parallel Audit

When auditing a codebase for test quality, dispatch up to 4 parallel sub-agents. Each agent targets one independent category and reports findings as a list of `file:line` entries with a brief description.

1. **Test coverage** -- Find untested exported functions. Compare exported function signatures against test files in the same package. Flag any exported function, method, or interface implementation that has no corresponding test.
2. **Test quality** -- Find tests without assertions, tests with hardcoded magic values instead of named constants, tests that only check the happy path, and tests that assert on implementation details (internal struct fields, unexported state) rather than behavior.
3. **Test isolation** -- Find tests that share mutable state, miss `t.Parallel()` where safe, use global variables, write to shared filesystem paths without `t.TempDir()`, or rely on test execution order.
4. **Test organization** -- Find missing test helpers (repeated setup code across multiple tests), missing `t.Cleanup()` where resources are allocated, repeated assertion patterns that should be extracted, and tests that would benefit from table-driven refactoring.

## Cross-References

- **go-error-handling** -- Error assertion patterns (`errors.Is` in tests, testing sentinel errors and custom types)
- **go-interfaces** -- Mock and stub patterns via interfaces, designing testable code with dependency injection
- **go-concurrency** -- Testing concurrent code, goroutine leak detection with goleak
- **systematic-debugging** -- Investigating test failures, diagnosing flaky tests

---

*Powered by [Gopher Guides](https://gopherguides.com) training materials.*
