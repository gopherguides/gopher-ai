# productivity

Standup reports and git productivity helpers.

## Installation

```bash
/plugin install productivity@gopher-ai
```

Or install via marketplace:
```bash
/plugin marketplace add gopherguides/gopher-ai
```

## Commands

| Command | Description |
|---------|-------------|
| `/standup [timeframe]` | Generate standup notes from recent git activity |
| `/weekly-summary [weeks]` | Generate weekly work summary with metrics |
| `/changelog [since]` | Generate changelog from commits since last release |

### Structured Output

`/changelog` supports a `--json` flag. When passed, the command outputs structured JSON with categorized changes instead of markdown. Useful for release automation and CI pipelines.

Example: `/changelog --json v1.2.0`

## Examples

```bash
# Generate standup notes for today
/standup

# Generate standup for last 2 days
/standup 2d

# Weekly summary for last week
/weekly-summary

# Changelog since last tag
/changelog
```

## Structured Output

Commands that return data support a `--json` flag for structured JSON output:

| Command | JSON Schema |
|---------|-------------|
| `/changelog [since] --json` | `{version, changes: {features, fixes, breaking}}` |

When `--json` is passed, the command outputs only a JSON object instead of markdown.

## Requirements

- Git repository with commit history

## License

MIT - see [LICENSE](../../LICENSE)
