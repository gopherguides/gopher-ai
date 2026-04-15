# AGENTS.md

Project instructions for OpenAI Codex CLI.

## Project Overview

gopher-ai is a Go-focused development toolkit distributed as both Claude Code plugins and Codex plugins. Each plugin bundles related skills that activate automatically or can be invoked explicitly.

The Codex plugin set currently includes `go-workflow`, `go-dev`, `gopher-guides`, `llm-tools`, `go-web`, and `tailwind`. The repo's `productivity` module is currently Claude-only.

## Plugins

| Plugin | Description | Skills |
|--------|-------------|--------|
| `go-workflow` | Issue-to-PR workflow automation | start-issue, create-worktree, commit, create-pr, ship, remove-worktree, prune-worktree, address-review, review-deep |
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
| `$review-deep [PR]` | Deep code review with full PR/issue context, then fix findings |

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

### Repo-Local (Recommended)

This repo includes `.agents/plugins/marketplace.json` which Codex reads on startup. When you clone this repo and run Codex inside it, all plugins are discovered automatically — no manual installation needed.

Browse available plugins with the `/plugins` command in Codex CLI.

To add these plugins to **your own repo**:

```bash
./scripts/install-codex.sh --repo /path/to/your-repo
```

### Global (Personal) Installation and Update

To make plugins available across all your repos:

```bash
./scripts/build-universal.sh
./scripts/install-codex.sh --user
```

Or as a one-liner from GitHub (installs for all detected platforms):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-all.sh)"
```

This downloads the repo to a temp directory, builds, installs for every platform it detects (Claude Code, Codex, Gemini), and cleans up.

Restart Codex after installation or update. Use `/plugins` to verify they appear.

### Flat Skills (Legacy)

Individual skills can also be installed without the plugin system:

```bash
cp -r dist/codex/skills/* ~/.codex/skills/
```

Or use the built-in `$skill-installer` for curated skills.

## Architecture

```
.agents/plugins/
  marketplace.json       # Codex plugin discovery

.claude-plugin/
  marketplace.json       # Claude Code plugin discovery

plugins/
  <plugin-name>/
    .claude-plugin/
      plugin.json        # Claude Code manifest
    .codex-plugin/
      plugin.json        # Codex manifest when the plugin is packaged for Codex
    commands/            # Claude Code slash commands
    skills/              # Skills (shared by both platforms)
    agents/              # Claude Code agent definitions
```

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- Git with worktree support
- `golangci-lint` (optional, for lint checks)
- `jq` for `./scripts/install-codex.sh`

## Links

- [Gopher Guides](https://gopherguides.com) - Official Go training
- [GitHub Repository](https://github.com/gopherguides/gopher-ai)
