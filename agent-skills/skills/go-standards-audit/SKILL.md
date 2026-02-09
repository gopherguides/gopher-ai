---
name: go-standards-audit
description: |
  WHEN: User wants to validate their Go project against Gopher Guides coding standards, check
  documentation completeness, review concurrency patterns, or validate project structure.
  WHEN NOT: Quick one-off Go questions (use the gopher-guides skill), or linting (use go-lint-audit).
license: MIT
---

# Go Standards Audit

Gopher Guides coding standards enforcement. Validates Go projects against professional standards for documentation, concurrency, dependencies, and project structure.

## API Integration (Optional)

If `GOPHER_GUIDES_API_KEY` is set, verify it:

```bash
curl -s -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  https://gopherguides.com/api/gopher-ai/me
```

If not set, local analysis tools (go vet, staticcheck, golangci-lint) still provide comprehensive analysis. Set the key for enhanced API-powered insights. Get your key at [gopherguides.com](https://gopherguides.com).

## What It Checks

### 1. Documentation Completeness (Godoc)

Every exported type, function, method, and package should have proper documentation:

```bash
# Find exported symbols missing documentation
# Look for exported funcs/types without preceding comments
grep -rn "^func [A-Z]" --include="*.go" | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  linenum=$(echo "$line" | cut -d: -f2)
  prevline=$((linenum - 1))
  prev=$(sed -n "${prevline}p" "$file")
  if [[ ! "$prev" =~ ^// ]]; then
    echo "Missing godoc: $line"
  fi
done
```

**Standards:**
- Package comments in `doc.go` for non-trivial packages
- All exported names have comments starting with the name
- Comments are complete sentences
- Examples in `_test.go` files for complex APIs

### 2. Concurrency Patterns

Review goroutine usage for correctness:

- **Context propagation** — All long-running functions accept `context.Context`
- **Goroutine lifecycle** — Every goroutine has a clear exit path
- **Channel usage** — Buffered vs unbuffered chosen intentionally
- **Mutex vs Channel** — Mutexes for state, channels for coordination
- **errgroup** — Used for coordinating multiple goroutines
- **Race detection** — `go test -race ./...` passes

```bash
# Run race detector
go test -race -count=1 ./...

# Check for common concurrency issues
go vet -copylocks ./...
```

### 3. Dependency Management

```bash
# Check for outdated dependencies
go list -m -u all

# Verify module integrity
go mod verify

# Check for unused dependencies
go mod tidy -diff

# Review direct dependencies
go list -m -f '{{if not .Indirect}}{{.Path}} {{.Version}}{{end}}' all
```

**Standards:**
- Minimal direct dependencies
- No abandoned/unmaintained dependencies
- `go.sum` committed and up to date
- `go mod tidy` produces no changes

### 4. Project Structure

Validate standard Go project layout:

```
project/
├── cmd/            # Main applications
│   └── myapp/
│       └── main.go
├── internal/       # Private packages
│   ├── service/
│   └── repository/
├── pkg/            # Public libraries (if needed)
├── go.mod
├── go.sum
├── README.md
├── Makefile        # Build automation
└── .golangci.yml   # Linter config
```

**Checks:**
- `main()` in `cmd/` directory (not root)
- Business logic in `internal/` (not exported)
- No circular dependencies between packages
- Clean separation of concerns

### 5. Error Handling Patterns

- Errors wrapped with `fmt.Errorf("context: %w", err)`
- Sentinel errors for expected conditions
- `errors.Is()` and `errors.As()` for comparison
- No `log.Fatal()` in library code
- Custom error types implement `Error() string`

### 6. API Design

- Accept interfaces, return structs
- Functional options for configuration
- Small, focused interfaces (1-3 methods)
- No exported constructors returning interfaces

## Gopher Guides API Integration

> **Note:** API calls send source code to gopherguides.com for analysis. Ensure your organization's policy permits external code analysis.

For full API usage examples, see [API Usage Reference](../references/api-usage.md).

### Severity Configuration

After installation via `install.sh`, scripts are at `.github/skills/scripts/`. Findings are categorized using severity configuration at the installed path. See the [Setup Guide](../SETUP.md) for details.

## Output Format

```markdown
## Best Practices Report

**Project:** {name}
**Standards Version:** Gopher Guides 2025

### Documentation
- ✅ Package comments: {n}/{total}
- ⚠️ Missing godoc: {list}
- ✅ Examples present: {n}

### Concurrency
- ✅ Race detector: PASS
- ⚠️ Goroutines without context: {list}
- ✅ errgroup usage: correct

### Dependencies
- ✅ go mod tidy: clean
- ⚠️ Outdated: {list}
- ✅ No abandoned deps

### Project Structure
- ✅ cmd/ layout: correct
- ✅ internal/ usage: correct
- ⚠️ Circular deps: {list}

### Overall Score: {score}/100
```

## References

- Existing gopher-ai skill: `plugins/go-dev/skills/go-best-practices/`
- Gopher Guides API: `plugins/gopher-guides/skills/gopher-guides/`
- [Effective Go](https://go.dev/doc/effective_go)
- [Organizing a Go Module](https://go.dev/doc/modules/layout)

---

*Powered by [Gopher Guides](https://gopherguides.com) training materials.*
