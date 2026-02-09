# Gopher AI Demo Repository

This is a demo repository for testing [Gopher AI Agent Skills](https://github.com/gopherguides/gopher-ai).

The Go code here has **intentional code quality issues** for demonstrating what the skills detect.

## What's Wrong

The `main.go` file contains:
- Unchecked errors
- Missing error wrapping
- Global mutable state
- Name that would stutter in a dedicated package
- Missing godoc comments
- Unnecessary init() function

The `main_test.go` file has:
- Incomplete test coverage
- Missing edge case tests
- No error path testing

## Try It

After installing skills to your repo with `install.sh`:

```bash
# Run the audit
bash .github/skills/scripts/audit.sh .

# Check coverage
bash .github/skills/scripts/coverage-report.sh

# Or use Makefile targets
make audit
make coverage
```

If testing from within the gopher-ai monorepo:

```bash
make audit SKILLS_SCRIPTS=../../agent-skills/scripts
make coverage SKILLS_SCRIPTS=../../agent-skills/scripts
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

*Part of [gopherguides/gopher-ai](https://github.com/gopherguides/gopher-ai)*
