---
name: go-code-audit
description: |
  WHEN: User asks for a code quality audit, code review, or wants to find code smells, anti-patterns,
  or non-idiomatic Go code in their project. Also when asked "how good is this code?" or "audit my code."
  WHEN NOT: When the user wants to fix bugs, run tests, or just lint (use go-lint-audit for linting).
license: MIT
---

# Go Code Audit

Comprehensive code quality analysis against Go best practices. Identifies code smells, anti-patterns, and non-idiomatic patterns with categorized findings.

## What It Checks

### Idiomatic Go Patterns
- Proper use of interfaces (accept interfaces, return structs)
- Channel and goroutine patterns
- Error wrapping with `%w` and sentinel errors
- Use of `context.Context` as first parameter
- Functional options pattern where appropriate

### Naming & Style
- Package naming (short, lowercase, no underscores)
- Exported name stuttering (`user.UserService` → `user.Service`)
- Acronym consistency (`URL`, `HTTP`, `ID`)
- Variable scope and naming length conventions

### Package Structure
- `internal/` usage for non-public packages
- Circular dependency detection
- Package cohesion (single responsibility)
- `cmd/` and `pkg/` conventions

### Error Handling
- Unchecked errors (`errcheck` patterns)
- Bare `log.Fatal` in library code
- Panics in recoverable code paths
- Error wrapping without context

### Code Smells
- Global mutable state
- `init()` function overuse
- Empty interfaces where concrete types suffice
- Overly complex functions (cyclomatic complexity)
- Dead code and unused exports

## How to Run

### API Integration (Optional)

If `GOPHER_GUIDES_API_KEY` is set, verify it:

```bash
curl -s -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  https://gopherguides.com/api/gopher-ai/me
```

If not set, local analysis tools (go vet, staticcheck, golangci-lint) still provide comprehensive analysis. Set the key for enhanced API-powered insights. Get your key at [gopherguides.com](https://gopherguides.com).

### Full Project Audit

Analyze the entire Go project:

```bash
# Run static analysis tools
go vet ./...
staticcheck ./...
golangci-lint run --max-issues-per-linter 0 --max-same-issues 0 ./...
```

Then review the codebase for patterns the tools don't catch:

1. **Read each package's exported API** — check for stuttering, interface bloat, and naming
2. **Trace error paths** — ensure all errors are wrapped with context
3. **Review concurrency** — check goroutine lifecycle management
4. **Check test coverage** — identify untested critical paths

### Gopher Guides API (Enhanced Analysis)

> **Note:** API calls send source code to gopherguides.com for analysis. Ensure your organization's policy permits external code analysis.

For full API usage examples, see [API Usage Reference](../references/api-usage.md).

### Helper Script

After installation via `install.sh`, scripts are at `.github/skills/scripts/`. For a full audit including local tools + API:

```bash
bash .github/skills/scripts/audit.sh
```

### Severity Configuration

After installation via `install.sh`, severity configuration is at `.github/skills/config/severity.yaml`. Teams can override severity levels per category or per rule. See the [Setup Guide](../SETUP.md) for details.

## Output Format

Categorize all findings by severity:

### 🔴 Critical
Issues that will cause bugs, data races, or security vulnerabilities.

### 🟡 Warning
Non-idiomatic patterns, maintainability concerns, or performance issues.

### 🟢 Suggestion
Style improvements, naming refinements, or minor optimizations.

### Report Template

```markdown
## Code Audit Report

**Project:** {name}
**Date:** {date}
**Files Analyzed:** {count}

### Summary
- 🔴 Critical: {n}
- 🟡 Warning: {n}
- 🟢 Suggestion: {n}
- Quality Score: {score}/100

### Findings

#### 🔴 Critical

1. **{title}** — `{file}:{line}`
   - Issue: {description}
   - Fix: {recommendation}

#### 🟡 Warning

1. **{title}** — `{file}:{line}`
   - Issue: {description}
   - Fix: {recommendation}

#### 🟢 Suggestion

1. **{title}** — `{file}:{line}`
   - Issue: {description}
   - Fix: {recommendation}

### Recommendations
1. {top priority action items}
```

## References

- Existing gopher-ai skill: `plugins/go-dev/skills/go/`
- Gopher Guides API: `plugins/gopher-guides/skills/gopher-guides/`
- [Effective Go](https://go.dev/doc/effective_go)
- [Go Code Review Comments](https://github.com/golang/go/wiki/CodeReviewComments)

---

*Powered by [Gopher Guides](https://gopherguides.com) training materials.*
