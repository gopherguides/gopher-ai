# Gopher AI

Cross-platform AI coding assistant toolkit for Go developers - by [Gopher Guides](https://gopherguides.com).

## Overview

Gopher AI provides skills and commands for the three major AI coding assistants:

| Platform | Status | Install Method |
|----------|--------|----------------|
| **Claude Code** | Full support | Plugin marketplace |
| **OpenAI Codex CLI** | Full plugin support | Repo-local, installer script, or manual |
| **Google Gemini CLI** | Extensions | Manual install |

**What's included:**
- 7 modules (go-workflow, go-dev, productivity, gopher-guides, llm-tools, go-web, tailwind)
- 6 auto-invoked reference skills for Go best practices, second opinions, and more
- 8 workflow skills for issue-to-PR automation (via Codex plugins and Claude Code commands)
- 20+ slash commands for development workflows

## Quick Start

### Install Everything (Recommended)

One command to build and install for every platform you have:

```bash
git clone https://github.com/gopherguides/gopher-ai
cd gopher-ai
./scripts/install-all.sh
```

This auto-detects which platforms are available (Claude Code, Codex CLI, Gemini CLI) and installs for all of them. Run it again anytime to update.

**Or install from GitHub without cloning** (downloads to tmp, installs, cleans up):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-all.sh)"
```

**Updating:** Just re-run `./scripts/install-all.sh` from the repo (or the one-liner). It rebuilds and reinstalls everything.

### Platform-Specific Install

If you only want one platform, or need first-time setup for Claude Code:

#### Claude Code

```bash
# 1. Add marketplace (in Claude Code)
/plugin marketplace add gopherguides/gopher-ai

# 2. Install all plugins at once (from your terminal)
~/.claude/plugins/marketplaces/gopher-ai/scripts/refresh-plugins.sh

# 3. Restart Claude Code — all 7 plugins are loaded
```

To install plugins individually: `/plugin install go-workflow@gopher-ai`, etc.

**Updating:** Run `/productivity:gopher-ai-refresh` inside Claude Code, or `./scripts/install-all.sh` from the repo.

#### OpenAI Codex CLI

```bash
# Global install — plugins available in every Codex session, regardless of cwd.
# Easiest path (no clone needed):
bash -c "$(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-all.sh)"

# Or, if you've already cloned the repo:
git clone https://github.com/gopherguides/gopher-ai
cd gopher-ai
./scripts/install-codex.sh --user

# Repo-local install — plugins available only when running Codex inside this repo:
codex   # Plugins load automatically from .agents/plugins/marketplace.json

# Add the marketplace to another repo (project-scoped, like the gopher-ai repo itself):
./scripts/install-codex.sh --repo /path/to/your-repo
```

**Pick one mode.** `--user` and `--repo`-when-cwd'd-into-our-repo will both load the
plugins, so having both active doubles the skill metadata Codex loads. The
SessionStart hook on the Claude Code side auto-removes stale unmarked installs
from earlier README versions and clears any stale gopher-ai marketplace cache
when a marked global install is present.

#### Google Gemini CLI

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
| `/review-deep [PR]` | Deep code review with full PR/issue context, then fix findings |
| `/create-worktree <number>` | Create a new git worktree for a GitHub issue |
| `/commit` | Create a git commit with auto-generated message |
| `/remove-worktree` | Interactively select and remove a git worktree |
| `/prune-worktree` | Batch cleanup of all completed issue worktrees |

The `/start-issue` command handles the full issue-to-PR workflow:
1. Fetches issue details including all comments
2. Offers worktree creation for isolated work
3. Auto-detects issue type (bug → `fix/` branch, feature → `feat/` branch)
4. Routes to appropriate TDD or implementation workflow

The `/review-deep` skill performs a thorough code review with full context:
1. Gathers PR metadata, linked issues, review threads, and inline comments
2. Reviews against Go idioms, correctness, security, performance, and spec compliance
3. Fixes all actionable findings, generates tests, and commits

The `/address-review` command automates PR review handling:
1. Addresses feedback from human and bot reviewers
2. Auto-resolves review threads after fixes
3. Requests re-review only from reviewers who actually left feedback on the PR (including bots such as Codex, CodeRabbit, and Greptile when applicable)

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

## Agent Skills (GitHub Copilot)

Distributable [Agent Skills](https://agentskills.io) for Go code quality auditing. Install to your repo:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/agent-skills/scripts/install.sh) --repo .
```

Skills included: `go-code-audit`, `go-test-coverage`, `go-standards-audit`, `go-lint-audit`, `go-code-review`

See [`agent-skills/README.md`](agent-skills/README.md) for details.

## Platform-Specific Notes

### Claude Code

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

Plugins are distributed via the [Codex plugin system](https://developers.openai.com/codex/plugins). Each plugin contains skills that activate automatically or can be invoked explicitly.

**Repo-local discovery:** Codex reads `.agents/plugins/marketplace.json` on startup and syncs plugins automatically. Use `/plugins` to browse and manage installed plugins. Plugins with `.codex-plugin/plugin.json` are packaged for Codex. Today that set is `go-workflow`, `go-dev`, `gopher-guides`, `llm-tools`, `go-web`, and `tailwind`. The repo's `productivity` module remains Claude-only.

**Install into another repo:** `./scripts/install-codex.sh --repo /path/to/your-repo` copies the current plugin set and merges entries into that repo's `.agents/plugins/marketplace.json` without removing unrelated plugin entries.

**GitHub one-liner:** `bash -c "$(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-all.sh)"` auto-detects all platforms — installs Claude Code and Gemini, and installs Codex plugins globally via Codex's marketplace mechanism (so skills load in every Codex session). The Codex install runs `codex plugin marketplace add gopherguides/gopher-ai`, populates `~/.codex/plugins/cache/gopher-ai/<plugin>/<commit>/` from the marketplace clone, and writes `[plugins."<name>@gopher-ai"]\nenabled = true` entries to `~/.codex/config.toml`. The marketplace cache is the only path Codex actually loads from — direct copies to `~/.codex/plugins/<name>/` are silently ignored.

**Migration from older versions:** Three earlier states needed cleanup, all handled automatically by the SessionStart hook (no command required) plus by `install-codex.sh --user` whenever you run install-all:
- Flat skills at `~/.codex/skills/<name>/` from the original (broken) `--user` mode — overflowed Codex's [skill metadata budget](https://developers.openai.com/codex/skills).
- Unmarked plugin directories at `~/.codex/plugins/<name>/` from when the README said "manually copy `dist/codex/plugins/` to `~/.codex/plugins/`" — also caused double-loading.

- Direct plugin copies at `~/.codex/plugins/<name>/` from a previous (also broken) `--user` mode that wrote files Codex never loaded. The current `--user` mode installs via the marketplace cache instead, where Codex actually reads from.

To migrate manually: `./scripts/install-codex.sh --user` (clean reinstall via marketplace) or `./scripts/install-codex.sh --cleanup` (remove leftover skills only).

**Workflow skills** (from `go-workflow` plugin):

```
$start-issue 42    # Full issue-to-PR workflow
$review-deep       # Deep review with full PR/issue context + fix
$create-worktree 42  # Create isolated worktree
$commit            # Auto-generate commit message
$create-pr         # Create PR with template
$ship              # Verify, push, CI watch, merge
$remove-worktree   # Remove a single worktree
$prune-worktree    # Batch cleanup completed worktrees
```

### Google Gemini CLI

Extensions are installed per-module. Each extension includes:
- `gemini-extension.json` - Extension manifest
- `GEMINI.md` - Context file
- `skills/` - Auto-invoked skills
- `commands/` - Command definitions (TOML format)

## MCP Servers

The **tailwind** module includes an MCP (Model Context Protocol) server for Tailwind CSS documentation lookups. This is configured automatically in both Claude Code and Codex plugin installs.

### tailwindcss-mcp-server

**Defined in:** `plugins/tailwind/.claude-plugin/plugin.json` and `plugins/tailwind/.mcp.json`

```json
{
  "mcpServers": {
    "tailwindcss": {
      "command": "npx",
      "args": ["-y", "tailwindcss-mcp-server"]
    }
  }
}
```

**Dependencies:**
- Node.js 16+ (`node` and `npx` must be on your PATH)
- Internet access on first run (to download the package)

**Available MCP tools:**
- `search_tailwind_docs` — Search Tailwind CSS documentation
- `get_tailwind_utilities` — Get utility classes for CSS properties
- `get_tailwind_colors` — Get color palette information
- `convert_css_to_tailwind` — Convert CSS to Tailwind utilities

**Fallback behavior:**
If the MCP server is unavailable (Node.js not installed, network issues, or using a non-Claude platform), the Tailwind slash commands (`/tailwind-init`, `/tailwind-migrate`, `/tailwind-audit`, `/tailwind-optimize`) still work fully — they do not depend on the MCP server. The MCP tools provide supplementary documentation lookups only.

**Troubleshooting:**
- **"npx: command not found"** — Install Node.js 16+ (`brew install node` or [nodejs.org](https://nodejs.org))
- **MCP tools not appearing** — Ensure you installed the `tailwind` plugin module; run `/plugin install tailwind@gopher-ai`
- **Timeout on first run** — The first `npx -y tailwindcss-mcp-server` invocation downloads the package; subsequent runs are cached

## Best Practices Guide

We maintain a [Claude Code Best Practices](docs/claude-best-practices.md) reference — battle-tested `CLAUDE.md` rules for safety, git workflows, CI, PR creation, and more.

**Quick setup:** Copy this prompt into your AI coding assistant to adopt the practices that fit your workflow:

```
Read the Claude Code best practices guide at docs/claude-best-practices.md in the
gopherguides/gopher-ai repo (https://github.com/gopherguides/gopher-ai). Then read
my current ~/.claude/CLAUDE.md (or create one if it doesn't exist). Compare them
section-by-section and walk me through which best practices I'm missing. For each
one, explain what problem it prevents and let me decide whether to adopt it. Apply
my choices to my config file.
```

Works with Claude Code, Codex, Cursor, and any LLM-powered coding assistant.

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

**Building and installing for all platforms:**

```bash
./scripts/install-all.sh    # Build + install for all detected platforms
```

Or build only (without installing):

```bash
./scripts/build-universal.sh
```

This generates:
- `dist/codex/plugins/` - Codex plugin packages
- `dist/gemini/` - Gemini extensions
- `dist/*.tar.gz` - Release archives

## License

MIT License - see [LICENSE](LICENSE) for details.

## About Gopher Guides

[Gopher Guides](https://gopherguides.com) is the official Go training partner, providing comprehensive training for developers and teams.

- [Training Courses](https://gopherguides.com/training)
- [Corporate Training](https://gopherguides.com/corporate)
- [Community Resources](https://gopherguides.com/resources)
