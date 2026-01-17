# gopher-guides

Go best practices guidance powered by Gopher Guides training materials.

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

Provides authoritative answers from official Gopher Guides training materials when you ask about Go best practices, patterns, or idioms. This skill activates automatically when discussing:

- Go best practices and idiomatic patterns
- Code review and implementation guidance
- Testing, concurrency, error handling
- Web development, database patterns

## Enhanced MCP Tools (Optional)

For users who want additional functionality, an MCP server is available that provides enhanced code auditing and training material lookups.

### MCP Tools

| Tool | Description |
|------|-------------|
| `audit_code` | Audit Go code against best practices |
| `best_practices` | Get prescriptive guidance on Go topics |
| `get_example` | Find code examples for specific patterns |
| `review_pr` | Review PRs against training materials |

### Manual MCP Setup

To enable the MCP tools, add to `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "gopher-guides": {
      "command": "gopher-guides-mcp",
      "args": ["serve"],
      "env": {
        "GOPHER_GUIDES_API_KEY": "your-api-key-here"
      }
    }
  }
}
```

**Requirements:**
- Install the `gopher-guides-mcp` binary
- Obtain a `GOPHER_GUIDES_API_KEY` from [Gopher Guides](https://gopherguides.com)

## About Gopher Guides

[Gopher Guides](https://gopherguides.com) is the official Go training partner, providing comprehensive training for developers and teams.

## License

MIT - see [LICENSE](../../LICENSE)
