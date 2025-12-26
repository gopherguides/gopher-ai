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

## Requirements

- Git repository with commit history

## License

MIT - see [LICENSE](../../LICENSE)
