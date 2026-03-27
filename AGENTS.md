# AGENTS.md

Project instructions for OpenAI Codex CLI.

## Project Overview

gopher-ai is a Go-focused development toolkit distributed as both Claude Code plugins and Codex plugins. Each plugin bundles related skills that activate automatically or can be invoked explicitly.

## Plugins

| Plugin | Description | Skills |
|--------|-------------|--------|
| `go-workflow` | Issue-to-PR workflow automation | start-issue, create-worktree, commit, create-pr, ship, remove-worktree, prune-worktree, address-review, coverage |
| `go-dev` | Go development tools and best practices | go-best-practices, go-profiling-optimization, systematic-debugging, validate-skills |
| `gopher-guides` | Gopher Guides training materials | gopher-guides |
| `llm-tools` | Multi-LLM second opinions and delegation | second-opinion, gemini-image |
| `go-web` | Go web scaffolding (Templ + HTMX) | templui, htmx |
| `tailwind` | Tailwind CSS v4 tools | tailwind-best-practices |

## Workflow Skills (go-workflow plugin)

Invoke explicitly with `$skill-name`:

| Skill | Description |
|-------|-------------|
| `$start-issue <number>` | Full issue-to-PR workflow: fetch, branch, TDD, verify, submit |
| `$create-worktree <number>` | Create isolated git worktree for an issue or PR |
| `$commit` | Auto-generate conventional commit message |
| `$create-pr` | Create PR following repo template |
| `$ship` | Ship a PR: verify, push, create PR, watch CI, merge |
| `$remove-worktree` | Interactively remove a single worktree |
| `$prune-worktree` | Batch cleanup of completed worktrees |

### Example Workflow

```
$start-issue 42
# Codex fetches the issue, creates a worktree, detects bug vs feature,
# guides you through TDD implementation, verifies, and creates a PR.

$ship
# Verifies build/tests/lint, pushes, watches CI, and merges.

$prune-worktree
# Cleans up worktrees for closed issues.
```

## Installation

### Plugin Installation (Recommended)

Codex discovers plugins via the `.agents/plugins/marketplace.json` at the repo root. When you clone this repo and run Codex, all plugins are available automatically.

To install plugins globally:

```bash
git clone https://github.com/gopherguides/gopher-ai
cd gopher-ai
./scripts/build-universal.sh
cp -r dist/codex/plugins/* ~/.codex/plugins/
```

### Repo-Local Installation

Copy the marketplace and plugins to your project:

```bash
mkdir -p /path/to/your-repo/.agents/plugins
cp .agents/plugins/marketplace.json /path/to/your-repo/.agents/plugins/
cp -r plugins/ /path/to/your-repo/plugins/
```

Codex automatically discovers plugins listed in `.agents/plugins/marketplace.json`.

## Architecture

```
.agents/plugins/
  marketplace.json       # Codex plugin marketplace

.claude-plugin/
  marketplace.json       # Claude Code plugin marketplace

plugins/
  <plugin-name>/
    .claude-plugin/
      plugin.json        # Claude Code manifest
    .codex-plugin/
      plugin.json        # Codex manifest
    commands/            # Claude Code slash commands
    skills/              # Skills (shared by both platforms)
    agents/              # Claude Code agent definitions
```

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- Git with worktree support
- `golangci-lint` (optional, for lint checks)

## Links

- [Gopher Guides](https://gopherguides.com) - Official Go training
- [GitHub Repository](https://github.com/gopherguides/gopher-ai)
