# Gopher AI Demo Repository

This is a demo repository for testing [Gopher AI Agent Skills](https://github.com/gopherguides/gopher-ai).

The Go code here has **intentional code quality issues** for demonstrating what the skills detect.

## What's Wrong

The `main.go` file contains:
- Unchecked errors
- Missing error wrapping
- Global mutable state
- Exported name stuttering
- Missing godoc comments
- Unnecessary init() function

The `main_test.go` file has:
- Incomplete test coverage
- Missing edge case tests
- No error path testing

## Try It

```bash
# Run the audit skill
bash .github/skills/scripts/audit.sh

# Check coverage
bash .github/skills/scripts/coverage-report.sh

# Run golangci-lint
make audit
```

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make audit` | Full code quality audit |
| `make coverage` | Coverage report with gap analysis |
| `make review` | Review changes against main |
| `make test` | Run tests |
| `make lint` | Run golangci-lint |

---

*Part of [gopherguides/gopher-ai](https://github.com/gopherguides/gopher-ai) — ref [#51](https://github.com/gopherguides/gopher-ai/issues/51)*
