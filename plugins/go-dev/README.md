# go-dev

Go-specific development tools with idiomatic best practices.

## Installation

Claude Code:

```bash
/plugin install go-dev@gopher-ai
```

Codex, after registering the repository-backed `gopher-ai` marketplace:

```bash
codex plugin add go-dev@gopher-ai
```

## Development Workflows

Claude Code exposes slash commands. Codex exposes the same focused workflows
as qualified skills; bare skill names are not resolver aliases.

| Workflow | Claude Code | Codex |
|----------|-------------|-------|
| Benchmarks | `/go-dev:bench <target>` | `$go-dev:bench <target>` |
| Build repair | `/go-dev:build-fix [log-path]` | `$go-dev:build-fix [log-path]` |
| Code explanation | `/go-dev:explain <target> [--json]` | `$go-dev:explain <target> [--json]` |
| Lint repair | `/go-dev:lint-fix [path] [--check]` | `$go-dev:lint-fix [path] [--check]` |
| Profiling workflow | `/go-dev:profile <target>` | `$go-dev:profile <target>` |
| Refactoring cleanup | `/go-dev:refactor-clean [path] [--dry-run]` | `$go-dev:refactor-clean [path] [--dry-run]` |
| Test generation | `/go-dev:test-gen <target> [--json]` | `$go-dev:test-gen <target> [--json]` |
| Skill validation | `/go-dev:validate-skills [file\|directory] [--json]` | `$go-dev:validate-skills [file\|directory] [--json]` |
| Full verification | `/go-dev:verify [path]` | `$go-dev:verify [path]` |

`validate-skills` accepts one Markdown file, one directory, or no path for the
default plugin command and skill Markdown paths. Pass `--json` before or after
the optional path for machine-readable results.

The persistent-loop `/go-dev:cancel-loop` command is intentionally Claude-only
because it controls Claude hooks.

## Advisory Skills

The `go` and `go-profiling-optimization` skills provide idiomatic Go and
performance guidance on both platforms. In Codex, their qualified names are
`$go-dev:go` and `$go-dev:go-profiling-optimization`.

## Structured Output

Data-producing workflows support `--json` for structured output:

| Workflow | JSON Schema |
|----------|-------------|
| `test-gen <target> --json` | `{test_cases, coverage_estimate, testing_framework}` |
| `explain <target> --json` | `{summary, components, call_graph, recommendations}` |
| `lint-fix [path] --json` | `{fixes, summary}` |
| `validate-skills [file\|directory] --json` | Machine-readable validation report |

When `--json` is passed, the command outputs only a JSON object instead of markdown.

## Requirements

- Go toolchain
- `golangci-lint` (for `lint-fix`)
- `staticcheck` (optional, improves `refactor-clean` accuracy)

## License

MIT - see [LICENSE](../../LICENSE)
