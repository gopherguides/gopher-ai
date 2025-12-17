# Gopher AI

Claude Code plugins for Go developers - by [Gopher Guides](https://gopherguides.com).

## Quick Start

```bash
# Add the marketplace
/plugin marketplace add gopherguides/gopher-ai

# Install plugins
/plugin install go-workflow@gopher-ai
/plugin install go-dev@gopher-ai
/plugin install productivity@gopher-ai
/plugin install gopher-guides@gopher-ai
/plugin install llm-tools@gopher-ai
/plugin install go-web@gopher-ai
```

## Updating Plugins

When new plugins are added or existing ones are updated, refresh your installation:

```bash
/plugin marketplace update gopher-ai
```

To enable automatic updates (checks at startup):

1. Run `/plugin` to open the plugin manager
2. Select **Marketplaces** > **gopher-ai**
3. Enable **auto-update**

## Available Plugins

### go-workflow

Issue-to-PR workflow automation with git worktree management.

**Commands:**

| Command | Description |
|---------|-------------|
| `/start-issue <number>` | Create a new git worktree for a GitHub issue |
| `/fix-issue <number>` | Diagnose, test, fix, and create PR for a bug |
| `/add-feature <number>` | Implement feature from issue with tests |
| `/prune-worktree` | Clean up completed issue worktrees |

### go-dev

Go-specific development tools with idiomatic best practices.

**Commands:**

| Command | Description |
|---------|-------------|
| `/test-gen <target>` | Generate comprehensive Go tests with table-driven patterns |
| `/lint-fix [path]` | Auto-fix Go linting issues with golangci-lint |
| `/explain <target>` | Deep-dive explanation of Go code with diagrams |

**Skills (auto-invoked):**

- **Go Best Practices** - Automatically applies idiomatic Go patterns when writing or reviewing code

### productivity

Standup reports and git productivity helpers.

**Commands:**

| Command | Description |
|---------|-------------|
| `/standup [timeframe]` | Generate standup notes from recent git activity |
| `/weekly-summary [weeks]` | Generate weekly work summary with metrics |
| `/changelog [since]` | Generate changelog from commits since last release |

### gopher-guides

Gopher Guides training materials integrated into Claude via MCP.

**Skills (auto-invoked):**

- **Gopher Guides Training** - Provides authoritative answers from official training materials

**MCP Tools:**

- `audit_code` - Audit Go code against best practices
- `best_practices` - Get prescriptive guidance on Go topics
- `get_example` - Find code examples for specific patterns
- `review_pr` - Review PRs against training materials

### llm-tools

Multi-LLM integration for second opinions and task delegation.

**Commands:**

| Command | Description |
|---------|-------------|
| `/codex <prompt>` | Delegate tasks to OpenAI Codex CLI |
| `/gemini <prompt>` | Query Google Gemini for analysis |
| `/ollama <prompt>` | Use local models (data stays on your machine) |
| `/llm-compare <prompt>` | Compare responses from multiple LLMs |
| `/convert <from> <to>` | Convert between formats (JSON→TS, SQL→Prisma, etc.) |

**Skills (auto-invoked):**

- **Second Opinion** - Suggests getting another LLM's perspective for complex decisions

**Requirements:**

- `codex` CLI: `npm install -g @openai/codex`
- `gemini` CLI: `brew install gemini-cli`
- `ollama`: `brew install ollama`

### go-web

Opinionated Go web app scaffolding with our recommended stack.

**Commands:**

| Command | Description |
|---------|-------------|
| `/create-go-project <name>` | Scaffold a new Go web app from scratch |
| `/convert-to-go-project` | Migrate Express/Django/Laravel/Next.js to Go |

**The Stack:**

- Go + Echo v4 (web framework)
- Templ (type-safe HTML templates)
- HTMX (server-driven interactivity)
- Alpine.js (client-side interactivity)
- Tailwind CSS v4 (styling with dark mode)
- sqlc (type-safe SQL, no ORM)
- goose (database migrations)
- Air (hot reload)

**Default Deployment:** Vercel + Neon PostgreSQL (free tier)

## Installation Options

### Install All Plugins

```bash
/plugin marketplace add gopherguides/gopher-ai
/plugin install go-workflow@gopher-ai
/plugin install go-dev@gopher-ai
/plugin install productivity@gopher-ai
/plugin install gopher-guides@gopher-ai
/plugin install llm-tools@gopher-ai
/plugin install go-web@gopher-ai
```

### Install Specific Plugins

```bash
# Just workflow automation
/plugin install go-workflow@gopher-ai

# Just Go development tools
/plugin install go-dev@gopher-ai
```

### Team Installation

Add to your project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "gopher-ai": {
      "source": {
        "source": "github",
        "repo": "gopherguides/gopher-ai"
      }
    }
  }
}
```

## Requirements

- Claude Code CLI
- GitHub CLI (`gh`) for workflow commands
- `golangci-lint` for lint-fix command
- Git with worktree support

## Configuration

### WORKTREE_PREFIX

The `/start-issue` and `/prune-worktree` commands require a `WORKTREE_PREFIX` environment variable:

```bash
# Add to ~/.zshrc or ~/.bashrc
export WORKTREE_PREFIX="myproject"
```

### Gopher Guides MCP

The `gopher-guides` plugin includes an MCP server for training materials. Configure your API key:

```bash
export GOPHER_GUIDES_API_KEY="your-key-here"
```

## Contributing

Contributions welcome! Please open an issue or PR.

## License

MIT License - see [LICENSE](LICENSE) for details.

## About Gopher Guides

[Gopher Guides](https://gopherguides.com) is the official Go training partner, providing comprehensive training for developers and teams. These plugins are powered by our training curriculum.

- [Training Courses](https://gopherguides.com/training)
- [Corporate Training](https://gopherguides.com/corporate)
- [Community Resources](https://gopherguides.com/resources)
