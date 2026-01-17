# AGENTS.md

Project instructions for OpenAI Codex CLI.

## Project Overview

gopher-ai is a Claude Code plugin marketplace providing Go-focused development tools. It contains seven plugins:

- **go-workflow**: Issue-to-PR workflow automation with git worktree management
- **go-dev**: Go-specific development tools (test generation, linting, code explanation)
- **productivity**: Git activity reports (standup, weekly summaries, changelogs, releases)
- **gopher-guides**: MCP integration with Gopher Guides training materials
- **llm-tools**: Multi-LLM utilities (Ollama, Gemini, Codex delegation, comparisons)
- **go-web**: Go web project scaffolding and templUI integration
- **tailwind**: Tailwind CSS v4 migration and optimization tools

## Available Skills

Skills are auto-invoked based on context. Install from `dist/codex/skills/`:

| Skill | Triggers |
|-------|----------|
| `go-best-practices` | Go code, patterns, reviews, "best way to..." |
| `second-opinion` | Architecture decisions, security code, "sanity check" |
| `tailwind-best-practices` | Tailwind CSS classes, themes, utilities |
| `templui` | Go/Templ web apps, HTMX, Alpine.js |
| `gopher-guides` | Go training materials, idiomatic patterns |

## Installation

### Via Skills Installer

```bash
codex> $skill-installer gopherguides/gopher-ai
```

### Manual Installation

```bash
# Clone the repository
git clone https://github.com/gopherguides/gopher-ai
cd gopher-ai

# Build universal distribution
./scripts/build-universal.sh

# Copy skills to Codex
cp -r dist/codex/skills/* ~/.codex/skills/
```

## Usage

Skills activate automatically based on context. You can also invoke directly:

```
$go-best-practices
$second-opinion
$tailwind-best-practices
$templui
$gopher-guides
```

## Architecture

```
plugins/
  <plugin-name>/
    .claude-plugin/
      plugin.json      # Plugin metadata
    commands/          # Slash command definitions (*.md)
    skills/            # Auto-invoked skills (SKILL.md)
    agents/            # Agent definitions
```

## Development

```bash
# Install git hooks
./scripts/install-hooks.sh

# Build universal distribution
./scripts/build-universal.sh

# Sync shared files
./scripts/sync-shared.sh
```

## Links

- [Gopher Guides](https://gopherguides.com) - Official Go training
- [GitHub Repository](https://github.com/gopherguides/gopher-ai)
- [Claude Code Plugin Docs](https://docs.anthropic.com/claude-code/plugins)
