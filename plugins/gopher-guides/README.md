# gopher-guides

Gopher Guides training materials integrated into Claude via MCP.

## Installation

```bash
/plugin install gopher-guides@gopher-ai
```

Or install via marketplace:
```bash
/plugin marketplace add gopherguides/gopher-ai
```

## Skills (Auto-invoked)

### Gopher Guides Training

Provides authoritative answers from official Gopher Guides training materials when you ask about Go best practices, patterns, or idioms.

## MCP Tools

| Tool | Description |
|------|-------------|
| `audit_code` | Audit Go code against best practices |
| `best_practices` | Get prescriptive guidance on Go topics |
| `get_example` | Find code examples for specific patterns |
| `review_pr` | Review PRs against training materials |

## Configuration

Set your API key to enable the MCP server:

```bash
export GOPHER_GUIDES_API_KEY="your-key-here"
```

## About Gopher Guides

[Gopher Guides](https://gopherguides.com) is the official Go training partner, providing comprehensive training for developers and teams.

## License

MIT - see [LICENSE](../../LICENSE)
