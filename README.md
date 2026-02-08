# Gopher AI

Cross-platform AI coding assistant toolkit for Go developers - by [Gopher Guides](https://gopherguides.com).

## Overview

Gopher AI provides skills and commands for the three major AI coding assistants:

| Platform | Status | Install Method |
|----------|--------|----------------|
| **Claude Code** | Full support | Plugin marketplace |
| **OpenAI Codex CLI** | Skills only | Manual or skills installer |
| **Google Gemini CLI** | Extensions | Manual install |

**What's included:**
- 7 modules (go-workflow, go-dev, productivity, gopher-guides, llm-tools, go-web, tailwind)
- 5 auto-invoked skills for Go best practices, second opinions, and more
- 20+ slash commands for development workflows

## Quick Start

### Claude Code

```bash
# Add marketplace
/plugin marketplace add gopherguides/gopher-ai

# Install all modules
/plugin install go-workflow@gopher-ai
/plugin install go-dev@gopher-ai
/plugin install productivity@gopher-ai
/plugin install gopher-guides@gopher-ai
/plugin install llm-tools@gopher-ai
/plugin install go-web@gopher-ai
/plugin install tailwind@gopher-ai
```

### OpenAI Codex CLI

```bash
# Via skills installer
codex> $skill-installer gopherguides/gopher-ai

# Or manual installation
git clone https://github.com/gopherguides/gopher-ai
cd gopher-ai
./scripts/build-universal.sh
cp -r dist/codex/skills/* ~/.codex/skills/
```

### Google Gemini CLI

```bash
git clone https://github.com/gopherguides/gopher-ai
cd gopher-ai
./scripts/build-universal.sh

# Install specific extensions
gemini extensions install ./dist/gemini/gopher-ai-go-dev
gemini extensions install ./dist/gemini/gopher-ai-go-workflow
# ... or any other module
```

## Tool Categories

Gopher AI includes both **Go-specific** and **general-purpose** tools:

### Go-Specific Tools

These modules are designed specifically for Go development:

| Module | Focus |
|--------|-------|
| **go-dev** | Go testing, linting, and code explanation |
| **go-workflow** | Issue-to-PR workflow with git worktrees |
| **go-web** | Go web app scaffolding (Go + Templ + HTMX + Tailwind) |
| **gopher-guides** | Go best practices from Gopher Guides training materials |

### General-Purpose Tools

These modules work with any language or stack:

| Module | Focus |
|--------|-------|
| **productivity** | Standup reports, changelogs, release management |
| **llm-tools** | Multi-LLM delegation and comparison |
| **tailwind** | Tailwind CSS v4 tooling (init, migrate, audit, optimize) |

## Available Modules

### go-workflow

Issue-to-PR workflow automation with git worktree management.

| Command | Description |
|---------|-------------|
| `/start-issue <number>` | Start working on an issue (auto-detects bug vs feature) |
| `/address-review [PR]` | Address PR review comments, make fixes, reply, and resolve |
| `/create-worktree <number>` | Create a new git worktree for a GitHub issue |
| `/commit` | Create a git commit with auto-generated message |
| `/remove-worktree` | Interactively select and remove a git worktree |
| `/prune-worktree` | Batch cleanup of all completed issue worktrees |

The `/start-issue` command handles the full issue-to-PR workflow:
1. Fetches issue details including all comments
2. Offers worktree creation for isolated work
3. Auto-detects issue type (bug → `fix/` branch, feature → `feat/` branch)
4. Routes to appropriate TDD or implementation workflow

The `/address-review` command automates PR review handling:
1. Addresses feedback from human and bot reviewers
2. Auto-resolves review threads after fixes
3. Requests re-review from bot reviewers (Codex, CodeRabbit, Greptile)

### go-dev

Go-specific development tools with idiomatic best practices.

| Command | Description |
|---------|-------------|
| `/test-gen <target>` | Generate comprehensive Go tests with table-driven patterns |
| `/lint-fix [path]` | Auto-fix Go linting issues with golangci-lint |
| `/explain <target>` | Deep-dive explanation of Go code with diagrams |

### productivity

Standup reports and git productivity helpers.

| Command | Description |
|---------|-------------|
| `/standup [timeframe]` | Generate standup notes from recent git activity |
| `/weekly-summary [weeks]` | Generate weekly work summary with metrics |
| `/changelog [since]` | Generate changelog from commits since last release |
| `/release [bump]` | Create a new release with version bump and changelog |

### gopher-guides

Go best practices guidance powered by Gopher Guides training materials.

**API Endpoints** (all platforms via REST):
- `/api/gopher-ai/practices` - Get prescriptive guidance on Go topics
- `/api/gopher-ai/audit` - Audit Go code against best practices
- `/api/gopher-ai/examples` - Find code examples for specific patterns
- `/api/gopher-ai/review` - Review PRs/diffs against training materials

Requires `GOPHER_GUIDES_API_KEY` environment variable.

### llm-tools

Multi-LLM integration for second opinions and task delegation.

| Command | Description |
|---------|-------------|
| `/codex <prompt>` | Delegate tasks to OpenAI Codex CLI |
| `/gemini <prompt>` | Query Google Gemini for analysis |
| `/ollama <prompt>` | Use local models (data stays on your machine) |
| `/llm-compare <prompt>` | Compare responses from multiple LLMs |
| `/convert <from> <to>` | Convert between formats (JSON→TS, SQL→Prisma, etc.) |

### go-web

Opinionated Go web app scaffolding with our recommended stack.

| Command | Description |
|---------|-------------|
| `/create-go-project <name>` | Scaffold a new Go web app from scratch |
| `/convert-to-go-project` | Migrate Express/Django/Laravel/Next.js to Go |

**The Stack:** Go + Echo v4, Templ, HTMX, Alpine.js, Tailwind CSS v4, sqlc, goose, Air

### tailwind

Tailwind CSS v4 tools for initialization, auditing, migration, and optimization.

| Command | Description |
|---------|-------------|
| `/tailwind-init` | Initialize Tailwind CSS v4 in a project |
| `/tailwind-migrate` | Migrate from Tailwind v3 to v4 |
| `/tailwind-audit` | Audit Tailwind usage for best practices |
| `/tailwind-optimize` | Optimize Tailwind configuration and usage |

**MCP Tools** (Claude Code only):
- `search_tailwind_docs` - Search Tailwind CSS documentation
- `get_tailwind_utilities` - Get utility classes for CSS properties
- `get_tailwind_colors` - Get color palette information
- `convert_css_to_tailwind` - Convert CSS to Tailwind utilities

## Skills Reference

Skills are auto-invoked behaviors that activate based on context. Available across all platforms:

| Skill | Triggers When |
|-------|---------------|
| `go-best-practices` | Writing Go code, asking about patterns, code reviews |
| `second-opinion` | Architecture decisions, security code, "sanity check" requests |
| `tailwind-best-practices` | Working with Tailwind CSS classes, themes, utilities |
| `templui` | Building Go/Templ web apps, HTMX/Alpine.js integration |
| `gopher-guides` | Asking about Go idioms, "what's the right way to..." |

## Platform-Specific Notes

### Claude Code

**Updating plugins:**

Due to a [known bug](https://github.com/anthropics/claude-code/issues/14061), use this script to refresh:

```bash
curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/refresh-plugins.sh | bash
```

**Team installation:**

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

**Oh My Zsh parse errors:**

If you see `parse error near '('`, run Claude Code with bash:

```bash
SHELL=/bin/bash claude
```

### OpenAI Codex CLI

Skills are installed to `~/.codex/skills/`. After installation, skills activate automatically based on context. You can also invoke directly with `$skill-name`.

### Google Gemini CLI

Extensions are installed per-module. Each extension includes:
- `gemini-extension.json` - Extension manifest
- `GEMINI.md` - Context file
- `skills/` - Auto-invoked skills
- `commands/` - Command definitions (TOML format)

## Requirements

**All platforms:**
- Git with worktree support
- GitHub CLI (`gh`) for workflow commands
- `golangci-lint` for lint-fix command

**Platform-specific:**
- Claude Code: Claude Code CLI
- Codex: OpenAI Codex CLI (`npm install -g @openai/codex`)
- Gemini: Google Gemini CLI (`npm install -g @google/gemini-cli`)

**Optional:**
- `ollama` for local model support (`brew install ollama`)
- `jq` for JSON manipulation (`brew install jq`)
- Node.js 16+ for Tailwind MCP server

## Configuration

### Gopher Guides API

The `gopher-guides` module uses a REST API for training materials. Set your API key:

```bash
export GOPHER_GUIDES_API_KEY="your-key-here"
```

Get your API key at [gopherguides.com](https://gopherguides.com).

## Contributing

Contributions welcome! Please open an issue or PR.

**Development setup:**

```bash
git clone https://github.com/gopherguides/gopher-ai
cd gopher-ai
./scripts/install-hooks.sh  # Install pre-commit hooks
```

**Building for all platforms:**

```bash
./scripts/build-universal.sh
```

This generates:
- `dist/codex/` - Codex-compatible skills
- `dist/gemini/` - Gemini extensions
- `dist/*.tar.gz` - Release archives

## License

MIT License - see [LICENSE](LICENSE) for details.

## About Gopher Guides

[Gopher Guides](https://gopherguides.com) is the official Go training partner, providing comprehensive training for developers and teams.

- [Training Courses](https://gopherguides.com/training)
- [Corporate Training](https://gopherguides.com/corporate)
- [Community Resources](https://gopherguides.com/resources)
