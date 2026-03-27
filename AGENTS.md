# AGENTS.md

Project instructions for OpenAI Codex CLI.

## Project Overview

gopher-ai is a Go-focused development toolkit providing reference skills and workflow skills for AI-assisted Go development. It contains seven plugin modules available as Claude Code plugins, with key skills and workflows also available for Codex CLI.

## Reference Skills

Auto-invoked based on context. These provide knowledge and best practices:

| Skill | Triggers |
|-------|----------|
| `go-best-practices` | Go code, patterns, reviews, "best way to..." |
| `go-profiling-optimization` | Profiling, pprof, optimization, PGO, "why is this slow" |
| `second-opinion` | Architecture decisions, security code, "sanity check" |
| `tailwind-best-practices` | Tailwind CSS classes, themes, utilities |
| `templui` | Go/Templ web apps, HTMX, Alpine.js |
| `gopher-guides` | Go training materials, idiomatic patterns |

## Workflow Skills

Issue-to-PR workflow automation. Invoke explicitly with `$skill-name`:

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

### Repo-Local Installation

To add workflow skills directly to your project:

```bash
# Copy .agents/skills/ to your repo
cp -r .agents/skills/ /path/to/your-repo/.agents/skills/
```

Skills in `.agents/skills/` are automatically discovered by Codex when working in that repo.

## Usage

Reference skills activate automatically. Workflow skills are invoked directly:

```
$go-best-practices
$start-issue 42
$commit
$create-pr
$ship
```

## Architecture

```
.agents/skills/          # Repo-local Codex workflow skills
  start-issue/
  create-worktree/
  commit/
  create-pr/
  ship/
  remove-worktree/
  prune-worktree/

plugins/                 # Claude Code plugins (also distributed as Codex skills)
  <plugin-name>/
    .claude-plugin/
      plugin.json        # Plugin metadata
    commands/            # Claude Code slash commands (*.md)
    skills/              # Auto-invoked skills (SKILL.md)
    agents/              # Agent definitions
```

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- Git with worktree support
- `golangci-lint` (optional, for lint checks)

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
