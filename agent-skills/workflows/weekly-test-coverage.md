---
name: weekly-test-coverage
description: Weekly analysis of test coverage gaps with auto-generated improvement PRs
schedule: weekly
skills:
  - go-test-coverage
  - go-best-practices
---

# Weekly Test Coverage

Analyze test coverage gaps weekly and create PRs with test improvements.

## Steps

1. **Measure current coverage** — `go test -coverprofile=coverage.out ./...`
2. **Identify gaps** using the `go-test-coverage` skill
   - Find untested exported functions
   - Identify missing error path tests
   - Flag packages below 60% coverage
3. **Prioritize** — Rank gaps by:
   - Package importance (core business logic first)
   - Risk level (error handling, concurrency)
   - Ease of testing (quick wins first)
4. **Generate test stubs** for the top 5 gaps
   - Table-driven test patterns
   - Edge cases and error paths
   - Use `t.Parallel()` where safe
5. **Create a PR** with the generated tests
   - Branch: `test/coverage-improvement-{date}`
   - Title: "test: improve coverage for {packages}"
   - Include coverage delta in description
6. **Post summary** with:
   - Coverage trend (this week vs last week)
   - Packages improved
   - Remaining gaps for next week

## Expected Output

A PR with:
- New test files following Go table-driven patterns
- Coverage improvement of at least 5%
- No test failures (`go test -race ./...` passes)

## Configuration

Set `GOPHER_GUIDES_API_KEY` for expert-level test recommendations from Gopher Guides training materials.
