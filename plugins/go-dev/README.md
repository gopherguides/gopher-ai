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
| `/build-fix [log-path]` | Auto-detect build system, parse errors, and fix until clean |

## Skills (Auto-invoked)

### Go Best Practices

Automatically applies idiomatic Go patterns when writing or reviewing code:
- Effective error handling
- Interface design
- Concurrency patterns
- Testing conventions

## Requirements

- Go toolchain
- `golangci-lint` (for `/lint-fix`)

## License

MIT - see [LICENSE](../../LICENSE)
