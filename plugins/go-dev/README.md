# go-dev

Go-specific development tools with idiomatic best practices.

## Installation

```bash
/plugin install go-dev@gopher-ai
```

Or install via marketplace:
```bash
/plugin marketplace add gopherguides/gopher-ai
```

## Commands

| Command | Description |
|---------|-------------|
| `/test-gen <target>` | Generate comprehensive Go tests with table-driven patterns |
| `/lint-fix [path]` | Auto-fix Go linting issues with golangci-lint |
| `/explain <target>` | Deep-dive explanation of Go code with diagrams |

### Structured Output

`/test-gen`, `/explain`, and `/lint-fix` support a `--json` flag. When passed, the command outputs structured JSON matching a defined schema instead of markdown. This is useful for programmatic consumption, CI pipelines, and tool integration.

Example: `/test-gen --json pkg/auth/login.go`
| `/build-fix [log-path]` | Auto-detect build system, parse errors, and fix until clean |
| `/refactor-clean [path]` | Find and remove dead Go code, orphaned tests, and complexity issues |

## Skills (Auto-invoked)

### Go Best Practices

Automatically applies idiomatic Go patterns when writing or reviewing code:
- Effective error handling
- Interface design
- Concurrency patterns
- Testing conventions

## Structured Output

Commands that return data support a `--json` flag for structured JSON output:

| Command | JSON Schema |
|---------|-------------|
| `/test-gen <target> --json` | `{test_cases, coverage_estimate, testing_framework}` |
| `/explain <target> --json` | `{summary, components, call_graph, recommendations}` |
| `/lint-fix [path] --json` | `{fixes, summary}` |

When `--json` is passed, the command outputs only a JSON object instead of markdown.

## Requirements

- Go toolchain
- `golangci-lint` (for `/lint-fix`)
- `staticcheck` (optional, improves `/refactor-clean` accuracy)

## License

MIT - see [LICENSE](../../LICENSE)
