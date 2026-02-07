# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

gopher-ai is a Claude Code plugin marketplace providing Go-focused development tools. It contains seven plugins distributed via the Claude Code plugin system:

- **go-workflow**: Issue-to-PR workflow automation with git worktree management
- **go-dev**: Go-specific development tools (test generation, linting, code explanation)
- **productivity**: Git activity reports (standup, weekly summaries, changelogs, releases)
- **gopher-guides**: MCP integration with Gopher Guides training materials
- **llm-tools**: Multi-LLM utilities (Ollama, Gemini, Codex delegation, comparisons)
- **go-web**: Go web project scaffolding and templUI integration
- **tailwind**: Tailwind CSS v4 migration and optimization tools

## Architecture

```
.claude-plugin/
  marketplace.json     # Marketplace manifest listing all plugins

plugins/
  <plugin-name>/
    .claude-plugin/
      plugin.json      # Plugin metadata, version, MCP server config
    commands/          # Slash command definitions (*.md files)
    skills/            # Auto-invoked skill definitions (SKILL.md)
    agents/            # Agent definitions (if any)
```

### Plugin Components

**Commands** (`commands/*.md`): Define slash commands with YAML frontmatter specifying:
- `argument-hint`: Placeholder shown in command help
- `description`: Short description for command list
- `model`: Optional model override (e.g., `claude-opus-4-6`)
- `allowed-tools`: Tool restrictions for the command

**Skills** (`skills/*/SKILL.md`): Auto-invoked behaviors with YAML frontmatter specifying:
- `description`: WHEN/WHEN NOT conditions for activation

**MCP Servers**: Defined in `plugin.json` under `mcpServers` key, specifying command, args, and environment variables.

## Key Workflows

### Issue Worktree Flow

The `/start-issue`, `/fix-issue`, `/add-feature`, and `/prune-worktree` commands work together:

1. `/start-issue <num>` creates a worktree at `../${reponame}-issue-<num>-<title>/` from the default branch
2. `/fix-issue` or `/add-feature` implements changes with TDD approach
3. `/prune-worktree` cleans up worktrees for closed/merged issues

Requires `gh` CLI authenticated.

## Development Setup

After cloning this repository, install git hooks:

```bash
./scripts/install-hooks.sh
```

This enables automatic syncing of shared files on commit.

### Shared Infrastructure

The `shared/` directory contains code used by multiple plugins:
- `hooks/stop-hook.sh` - Persistent loop hook (**only syncs to go-workflow**)
- `scripts/setup-loop.sh`, `cleanup-loop.sh` - Loop management
- `lib/loop-state.sh` - Loop state functions
- `commands/cancel-loop.md` - Cancel loop command

**Hook ownership**: Only `go-workflow` has the stop hook registered. It owns persistent loop management for all `/start-issue` style commands.

**When editing `shared/`**: The pre-commit hook automatically syncs changes to plugins. If you need to sync manually:

```bash
./scripts/sync-shared.sh      # Sync shared/ to plugins
./scripts/check-shared-sync.sh # Verify sync is correct
```

## Environment Requirements

- **GOPHER_GUIDES_API_KEY**: Required for gopher-guides MCP server
- **gh CLI**: GitHub CLI for issue/PR operations
- **golangci-lint**: For lint-fix command
- **jq**: Required for `/release` command

## Releasing

Use the `/release` command from the productivity plugin to create releases:

```bash
/release           # Auto-detect bump type from commits
/release patch     # 1.1.0 → 1.1.1
/release minor     # 1.1.0 → 1.2.0
/release major     # 1.1.0 → 2.0.0
```

### Version Sync Requirement

**Critical**: Claude Code uses `plugin.json` version (not `marketplace.json`) to create cache directories. Both files must stay in sync:

- `.claude-plugin/marketplace.json` - Marketplace-level versions
- `plugins/<name>/.claude-plugin/plugin.json` - Individual plugin versions

The `/release` command handles this automatically. If manually bumping versions, update both locations.

### Cache Refresh

After releasing, users must refresh their local cache:

```bash
./scripts/refresh-plugins.sh
```

This script works around known Claude Code cache invalidation bugs ([#14061](https://github.com/anthropics/claude-code/issues/14061), [#15621](https://github.com/anthropics/claude-code/issues/15621)).
