# AGENTS.md

Project instructions for OpenAI Codex CLI.

## Project Overview

gopher-ai is a Go-focused development toolkit distributed as both Claude Code plugins and Codex plugins. Each plugin bundles related skills that activate automatically or can be invoked explicitly.

The Codex plugin set currently includes `go-workflow`, `go-dev`, `gopher-guides`, `llm-tools`, `go-web`, and `tailwind`. The repo's `productivity` module is currently Claude-only.

## Plugins

| Plugin | Description | Skills |
|--------|-------------|--------|
| `go-workflow` | Issue-to-PR workflow automation | start-issue, worktree, commit, create-pr, ship, address-review, review-deep, complete-issue, e2e-verify, tmux-start |
| `go-dev` | Go development tools and best practices | go, go-profiling-optimization, validate-skills |
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

### Global (Personal) Use

For Codex, "global" means installing plugins through the Codex marketplace cache so they load in every Codex session, regardless of the working directory. This is what `install-all.sh` uses for the curl one-liner.

```bash
./scripts/install-codex.sh --user
```

`--user` registers or upgrades the marketplace and runs `codex plugin add` for each Codex-capable plugin. Codex owns config updates and publishes immutable versioned roots, retaining prior versions for active sessions.

The universal installer handles every detected platform in one step:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-all.sh)"
```

It builds, installs Claude Code and Gemini, runs `install-codex.sh --user` for Codex, and cleans up after itself. Restart Codex after running it; use `/plugins` to verify.

After all Codex sessions have exited, stale marketplace cache roots can be removed explicitly:

```bash
./scripts/install-codex.sh --prune-cache
```

Do not prune while a Codex session is active. Running sessions retain absolute hook and skill paths into their original cache roots. The prune command keeps the current plugin version.

### Migration

Two earlier states are auto-handled by the SessionStart hook + `--user`:

- Flat skills at `~/.codex/skills/<name>/` from the original (broken) `--user` mode that double-loaded against the marketplace.
- Unmarked plugin directories at `~/.codex/plugins/<name>/` from when the README said "manually copy `dist/codex/plugins/` to `~/.codex/plugins/`".

To migrate manually: `./scripts/install-codex.sh --user` (refresh the marketplace install) or `./scripts/install-codex.sh --cleanup` (remove leftover skills only).

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
