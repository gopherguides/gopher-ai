---
name: go-lint-audit
description: |
  WHEN: User wants to run linting on their Go project, understand lint findings, improve their
  golangci-lint configuration, or asks "what's wrong with my code?" from a linting perspective.
  WHEN NOT: Deep code quality audit (use go-code-audit), or auto-fixing lint issues (use /lint-fix command).
license: MIT
---

# Go Lint Audit

Extended lint analysis with human-readable explanations. Wraps golangci-lint with better categorization, explanations, and configuration recommendations.

## What It Does

1. **Runs golangci-lint** with comprehensive linter set
2. **Groups findings** by category and severity
3. **Explains each finding** in plain language with fix examples
4. **Recommends config improvements** for `.golangci.yml`

## Steps

### 1. Check Configuration

```bash
# Find existing config
ls .golangci.yml .golangci.yaml .golangci.toml 2>/dev/null

# If no config exists, note it — will recommend one
```

### 2. Run Analysis

```bash
# Run with all findings shown
golangci-lint run \
  --max-issues-per-linter 0 \
  --max-same-issues 0 \
  --out-format json \
  ./... 2>&1
```

If `golangci-lint` is not installed:

```bash
# Install
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
```

### 3. Categorize Findings

Group findings into categories:

| Category | Linters | Severity |
|----------|---------|----------|
| **Bugs** | govet, staticcheck, gosec | 🔴 Critical |
| **Error Handling** | errcheck, errorlint | 🔴 Critical |
| **Performance** | prealloc, bodyclose | 🟡 Warning |
| **Style** | gofmt, goimports, misspell | 🟢 Suggestion |
| **Complexity** | cyclop, gocognit, funlen | 🟡 Warning |
| **Maintainability** | gocritic, revive, dupl | 🟡 Warning |
| **Security** | gosec | 🔴 Critical |

### 4. Explain Findings

For each finding, provide:

- **What it means** in plain language
- **Why it matters** (bug risk, performance, maintainability)
- **How to fix it** with a code example
- **When to ignore it** (if applicable, with `//nolint` directive)

Example:

```markdown
#### errcheck: Error return value of `os.Remove` is not checked

**What:** The function `os.Remove()` returns an error that your code ignores.

**Why:** If the file doesn't exist or can't be deleted, your program won't know,
potentially leaving stale files or masking permission issues.

**Fix:**
​```go
// Before
os.Remove(tempFile)

// After
if err := os.Remove(tempFile); err != nil {
    return fmt.Errorf("failed to remove temp file %s: %w", tempFile, err)
}
​```

**Ignore:** Only if the file removal is truly best-effort:
​```go
_ = os.Remove(tempFile) //nolint:errcheck // best-effort cleanup
​```
```

### 5. Configuration Recommendations

Suggest `.golangci.yml` improvements:

```yaml
# Recommended golangci-lint configuration
linters:
  enable:
    # Bug detection
    - govet
    - staticcheck
    - gosec
    # Error handling
    - errcheck
    - errorlint
    # Style
    - gofmt
    - goimports
    - misspell
    # Complexity
    - cyclop
    - gocognit
    # Maintainability
    - gocritic
    - revive
    - dupl
    # Performance
    - prealloc
    - bodyclose

linters-settings:
  cyclop:
    max-complexity: 15
  gocognit:
    min-complexity: 20
  funlen:
    lines: 80
    statements: 50
  goimports:
    local-prefixes: github.com/yourorg
  errcheck:
    check-type-assertions: true
    check-blank: true

issues:
  exclude-use-default: false
  max-issues-per-linter: 0
  max-same-issues: 0

run:
  timeout: 5m
```

## Output Format

```markdown
## Lint Audit Report

**Project:** {name}
**Linters:** {count} active
**Total Findings:** {count}

### Summary

| Category | Count | Severity |
|----------|-------|----------|
| Bugs | {n} | 🔴 |
| Error Handling | {n} | 🔴 |
| Performance | {n} | 🟡 |
| Style | {n} | 🟢 |
| Complexity | {n} | 🟡 |

### Findings by Category

#### 🔴 Bugs ({n})
{detailed findings with explanations}

#### 🔴 Error Handling ({n})
{detailed findings with explanations}

...

### Configuration Recommendations
{suggested .golangci.yml changes}

### Quick Fixes Available
{list of auto-fixable issues with `golangci-lint run --fix`}
```

## Gopher Guides API Integration

When `GOPHER_GUIDES_API_KEY` is available, get expert analysis on lint findings:

**Standard shell:**

```bash
CODE=$(cat main.go | jq -Rs .)
curl -s -X POST \
  -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"code\": $CODE, \"focus\": \"audit\"}" \
  https://gopherguides.com/api/gopher-ai/audit
```

**Claude Code syntax:**

```
Run: CODE=$(cat main.go | jq -Rs .); curl -s -X POST -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" -H "Content-Type: application/json" -d "{\"code\": $CODE, \"focus\": \"audit\"}" https://gopherguides.com/api/gopher-ai/audit
```

### Helper Script

Run the full audit including lint + API:

```bash
bash .github/skills/scripts/audit.sh
```

### Severity Configuration

Lint categories map to severity levels in `.github/skills/config/severity.yaml`. See the [Setup Guide](../SETUP.md) for details.

## References

- Existing gopher-ai command: `plugins/go-dev/commands/lint-fix.md`
- [golangci-lint documentation](https://golangci-lint.run/)
- [Go Code Review Comments](https://github.com/golang/go/wiki/CodeReviewComments)

---

*Powered by [Gopher Guides](https://gopherguides.com) training materials.*
