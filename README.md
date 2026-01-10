# Gopher AI

Claude Code plugins for Go developers - by [Gopher Guides](https://gopherguides.com).

## Quick Start

```bash
/plugin marketplace add gopherguides/gopher-ai
```

Then install the plugins you want:

```bash
/plugin install go-workflow@gopher-ai
/plugin install go-dev@gopher-ai
/plugin install productivity@gopher-ai
/plugin install gopher-guides@gopher-ai
/plugin install llm-tools@gopher-ai
/plugin install go-web@gopher-ai
/plugin install tailwind@gopher-ai
```

Or install all at once (copy/paste as one command):

```bash
/plugin install go-workflow@gopher-ai && /plugin install go-dev@gopher-ai && /plugin install productivity@gopher-ai && /plugin install gopher-guides@gopher-ai && /plugin install llm-tools@gopher-ai && /plugin install go-web@gopher-ai && /plugin install tailwind@gopher-ai
```

## Updating Plugins

Due to a [known bug](https://github.com/anthropics/claude-code/issues/14061), `/plugin marketplace update` doesn't properly refresh cached plugin files. Use this one-liner to fully refresh:

```bash
curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/refresh-plugins.sh | bash
```

Then restart Claude Code. That's it - plugins are automatically reinstalled from the updated marketplace.

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

The `/start-issue` command intelligently handles the full issue-to-PR workflow:

1. **Fetches issue details** including all comments for full context
2. **Offers worktree creation** for isolated work (optional - creates `../repo-issue-123-title/`)
3. **Auto-detects issue type** by analyzing labels first (`bug`, `enhancement`, etc.), then title/body patterns
4. **Routes to the right workflow:**
   - **Bug fix**: Checks for duplicates → TDD approach (failing test first) → `fix/` branch
   - **Feature**: Plans approach → Implementation → Tests → `feat/` branch
5. **Asks for clarification** if the type can't be determined automatically

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

### tailwind

Tailwind CSS v4 tools for initialization, auditing, migration, and optimization.

**Commands:**

| Command | Description |
|---------|-------------|
| `/tailwind-init` | Initialize Tailwind CSS v4 in a project |
| `/tailwind-migrate` | Migrate from Tailwind v3 to v4 |
| `/tailwind-audit` | Audit Tailwind usage for best practices |
| `/tailwind-optimize` | Optimize Tailwind configuration and usage |

**Skills (auto-invoked):**

- **Tailwind Best Practices** - Provides v4-specific guidance when working with Tailwind CSS

**MCP Tools:**

- `search_tailwind_docs` - Search Tailwind CSS documentation
- `get_tailwind_utilities` - Get utility classes for CSS properties
- `get_tailwind_colors` - Get color palette information
- `convert_css_to_tailwind` - Convert CSS to Tailwind utilities
- `generate_component_template` - Generate component templates

**Requirements:**

- Node.js 16+ (for MCP server)

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
/plugin install tailwind@gopher-ai
```

### Install Specific Plugins Only

Only install the plugins you need:

```bash
/plugin marketplace add gopherguides/gopher-ai
/plugin install go-dev@gopher-ai      # just Go development tools
/plugin install go-workflow@gopher-ai  # just workflow automation
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

### Development Setup

After cloning the repository:

```bash
./scripts/install-hooks.sh
```

This installs a pre-commit hook that keeps shared files in sync across plugins.

### Shared Infrastructure

The `shared/` directory contains code used by multiple plugins (loop hooks, scripts, etc.). When you edit files in `shared/`:

1. The pre-commit hook automatically syncs changes to all plugins
2. CI will fail if files are out of sync

Manual sync commands:

```bash
./scripts/sync-shared.sh       # Sync shared/ to plugins
./scripts/check-shared-sync.sh # Verify sync is correct
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## About Gopher Guides

[Gopher Guides](https://gopherguides.com) is the official Go training partner, providing comprehensive training for developers and teams. These plugins are powered by our training curriculum.

- [Training Courses](https://gopherguides.com/training)
- [Corporate Training](https://gopherguides.com/corporate)
- [Community Resources](https://gopherguides.com/resources)
