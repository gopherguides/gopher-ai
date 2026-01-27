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

## API Tools

The skill uses the Gopher Guides REST API to provide enhanced code auditing and training material lookups.

### Available Endpoints

| Endpoint | Description |
|----------|-------------|
| `/api/gopher-ai/practices` | Get prescriptive guidance on Go topics |
| `/api/gopher-ai/audit` | Audit Go code against best practices |
| `/api/gopher-ai/examples` | Find code examples for specific patterns |
| `/api/gopher-ai/review` | Review PRs/diffs against training materials |

### Setup

Set your API key as an environment variable:

```bash
export GOPHER_GUIDES_API_KEY="your-key-here"
```

Obtain an API key from [Gopher Guides](https://gopherguides.com).

### Works on All Platforms

The REST API approach works with any AI coding assistant that can make HTTP requests - no MCP server required.

## About Gopher Guides

[Gopher Guides](https://gopherguides.com) is the official Go training partner, providing comprehensive training for developers and teams.

## License

MIT - see [LICENSE](../../LICENSE)
