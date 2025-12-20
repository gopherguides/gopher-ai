# Gopher AI

Claude Code plugins for Go developers - by [Gopher Guides](https://gopherguides.com).

## Quick Start

```bash
/plugin marketplace add gopherguides/gopher-ai
```

That's it! This command adds the marketplace and auto-installs all plugins.

## Updating Plugins

Due to a [known bug](https://github.com/anthropics/claude-code/issues/14061), `/plugin marketplace update` doesn't properly refresh cached plugin files. Use this script to fully refresh:

```bash
# Run from anywhere
curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/refresh-plugins.sh | bash
```

Or clone and run locally:

```bash
./scripts/refresh-plugins.sh
```

After running, restart Claude Code and re-add the marketplace (auto-installs all plugins):

```bash
/plugin marketplace add gopherguides/gopher-ai
```

**Requires:** `jq` for JSON manipulation (`brew install jq`)

## Available Plugins

### go-workflow

Issue-to-PR workflow automation with git worktree management.

**Commands:**

| Command | Description |
|---------|-------------|
| `/start-issue <number>` | Start working on an issue (auto-detects bug vs feature) |
| `/create-worktree <number>` | Create a new git worktree for a GitHub issue |
| `/commit` | Create a git commit with auto-generated message |
| `/remove-worktree` | Interactively select and remove a git worktree |
| `/prune-worktree` | Batch cleanup of all completed issue worktrees |

**`/start-issue` Workflow:**

The `/start-issue` command intelligently routes to the appropriate workflow:

1. **Fetches issue details** including all comments for full context
2. **Auto-detects issue type** by analyzing labels first (`bug`, `enhancement`, etc.), then title/body patterns
3. **Routes to the right workflow:**
   - **Bug fix**: Checks for duplicates → TDD approach (failing test first) → `fix/` branch
   - **Feature**: Plans approach → Implementation → Tests → `feat/` branch
4. **Asks for clarification** if the type can't be determined automatically

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
- `gemini` CLI: `npm install -g @google/gemini-cli`
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

### Install All Plugins (Default)

```bash
/plugin marketplace add gopherguides/gopher-ai
```

Adding the marketplace automatically installs all plugins.

### Install Specific Plugins Only

If you only want certain plugins, first add the marketplace, then uninstall the ones you don't need:

```bash
/plugin marketplace add gopherguides/gopher-ai
/plugin uninstall go-web@gopher-ai  # example: remove go-web if not needed
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

### Gopher Guides MCP

The `gopher-guides` plugin includes an MCP server for training materials. Configure your API key:

```bash
export GOPHER_GUIDES_API_KEY="your-key-here"
```

## Troubleshooting

### Parse Error with Oh My Zsh

If you see errors like `(eval):1: parse error near '('` when running commands, this is a [known Claude Code bug](https://github.com/anthropics/claude-code/issues/1872) with Oh My Zsh.

**Fix:** Run Claude Code with bash instead of zsh:

```bash
SHELL=/bin/bash claude
```

Or add this alias to your `~/.zshrc`:

```bash
alias claude='SHELL=/bin/bash claude'
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
