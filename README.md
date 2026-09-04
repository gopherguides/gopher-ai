# Gopher AI

Cross-platform AI coding assistant toolkit for Go developers - by [Gopher Guides](https://gopherguides.com).

## Overview

Gopher AI provides skills and commands for the three major AI coding assistants:

| Platform | Status | Install Method |
|----------|--------|----------------|
| **Claude Code** | Full support | Plugin marketplace |
| **OpenAI Codex CLI** | 6 plugins; capabilities vary | Repository-backed, user-wide, or manual |
| **Google Gemini CLI** | Extensions | Manual install |

Shipped surface: 36 Claude Code commands across 7 plugins; 37 Codex skills across 6 plugins; 0 optional Codex MCP tools.

See the [platform capability matrix](docs/platform-capabilities.md) for exact
qualified names and workflows that are not yet available on Codex.

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

# Repository-backed staging and activation for a new gopher-ai catalog:
./scripts/install-codex.sh --repo /path/to/your-repo
codex plugin marketplace add /path/to/your-repo
codex plugin add go-dev@gopher-ai
codex plugin add go-web@gopher-ai
codex plugin add go-workflow@gopher-ai
codex plugin add gopher-guides@gopher-ai
codex plugin add llm-tools@gopher-ai
codex plugin add tailwind@gopher-ai
```

`--repo` copies the plugins and writes a marketplace catalog; the catalog alone
does not enable anything. The follow-up commands enable the plugins throughout
the active `CODEX_HOME`, not only while Codex runs in that repository. Do not
combine repository-backed activation and `--user` in the same `CODEX_HOME`.
If the target already has a named marketplace catalog, run the commands printed
by the installer; they use the preserved catalog name instead of `gopher-ai`.
Use a dedicated `CODEX_HOME` for an isolated repository-backed setup. The
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

| Workflow | Description |
|----------|-------------|
| `start-issue <number>` | Start working on an issue (auto-detects bug vs feature) |
| `address-review [PR]` | Address PR review comments, make fixes, reply, and resolve |
| `review-deep [PR]` | Deep code review with full PR context, then fix findings |
| `commit` | Create a git commit with auto-generated message |
| `create-pr` | Create a PR following the repo template |
| `e2e-verify [PR]` | Run browser E2E verification on a PR |
| `ship` | Verify, push, watch CI/reviews, and merge |
| `cancel-loop [loop-name]` | Cancel active persistent workflow state |
| `create-worktree <number>` | Create a new git worktree for a GitHub issue |
| `remove-worktree` | Interactively select and remove a git worktree |
| `prune-worktree` | Batch cleanup of all completed issue worktrees |

Workflow skill invocation modes:

| Mode | Skills |
|------|--------|
| Slash-only | `start-issue`, `address-review`, `cancel-loop`, `worktree` (`/create-worktree`, `/remove-worktree`, `/prune-worktree`), `e2e-verify`, `ship`, `complete-issue`, `tmux-start` |
| Auto-triggerable | `commit`, `create-pr`, `review-deep` |

Slash-only skills require explicit invocation, and their descriptions are omitted from the always-loaded auto-invoked skill list. Use `/go-workflow:<command>` in Claude Code or `$go-workflow:<skill>` in Codex. Codex requires the qualified plugin name; bare skill names are not resolver aliases. In Claude Code, type the slash command directly; `$go-workflow:start-issue` is Codex syntax and causes a blocked Skill-tool invocation. Auto-triggerable skills remain available from natural-language requests such as "commit these changes" or "review my changes".

The `start-issue` skill handles the full issue-to-PR workflow:
1. Fetches issue details including all comments
2. Offers worktree creation for isolated work
3. Auto-detects issue type (bug → `fix/` branch, feature → `feat/` branch)
4. Routes to appropriate TDD or implementation workflow

The `/review-deep` skill performs a thorough code review with full context:
1. Gathers PR metadata, linked issues, review threads, and inline comments
2. Reviews against Go idioms, correctness, security, performance, and spec compliance
3. Fixes all actionable findings, generates tests, and commits

The `address-review` skill automates PR review handling:
1. Addresses feedback from human and bot reviewers
2. Auto-resolves review threads after fixes
3. Requests re-review only from reviewers who actually left feedback on the PR (including bots such as Codex, CodeRabbit, and Greptile when applicable)

### go-dev

Go-specific development tools with idiomatic best practices. Claude Code uses
slash commands; Codex uses the exact qualified skill names below.

| Workflow | Claude Code | Codex |
|----------|-------------|-------|
| Benchmarks | `/go-dev:bench <target>` | `$go-dev:bench <target>` |
| Build repair | `/go-dev:build-fix [log-path]` | `$go-dev:build-fix [log-path]` |
| Code explanation | `/go-dev:explain <target> [--json]` | `$go-dev:explain <target> [--json]` |
| Lint repair | `/go-dev:lint-fix [path] [--check]` | `$go-dev:lint-fix [path] [--check]` |
| Profiling workflow | `/go-dev:profile <target>` | `$go-dev:profile <target>` |
| Refactoring cleanup | `/go-dev:refactor-clean [path] [--dry-run]` | `$go-dev:refactor-clean [path] [--dry-run]` |
| Test generation | `/go-dev:test-gen <target> [--json]` | `$go-dev:test-gen <target> [--json]` |
| Skill validation | `/go-dev:validate-skills [file\|directory] [--json]` | `$go-dev:validate-skills [file\|directory] [--json]` |
| Full verification | `/go-dev:verify [path]` | `$go-dev:verify [path]` |

The advisory `go` and `go-profiling-optimization` skills remain available on
both platforms. In Codex, invoke them explicitly as `$go-dev:go` and
`$go-dev:go-profiling-optimization`. The `cancel-loop` command remains
Claude-only because it controls Claude persistent-loop hooks.

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

| Workflow | Claude Code | Codex |
|----------|-------------|-------|
| Clear response cache | `/gopher-guides:clear-cache` | `$gopher-guides:clear-cache` |

**API Endpoints** (all platforms via REST):
- `/api/gopher-ai/practices` - Get prescriptive guidance on Go topics
- `/api/gopher-ai/audit` - Audit Go code against best practices
- `/api/gopher-ai/examples` - Find code examples for specific patterns
- `/api/gopher-ai/review` - Review PRs/diffs against training materials

Requires `GOPHER_GUIDES_API_KEY` environment variable.

### llm-tools

Multi-LLM integration for second opinions and task delegation. The
`second-opinion` skill recommends invocations that exist on the active client.

| Workflow | Claude Code | Codex |
|----------|-------------|-------|
| Gemini delegation | `/llm-tools:gemini <prompt>` | `$llm-tools:gemini <prompt>` |
| Ollama delegation | `/llm-tools:ollama <prompt>` | `$llm-tools:ollama <prompt>` |
| Gemini image generation | `/llm-tools:gemini-image <prompt>` | `$llm-tools:gemini-image <prompt>` |
| Claude-to-Codex delegation | `/llm-tools:codex <prompt>` | Intentionally unsupported; the active assistant is already Codex |
| Multi-provider comparison | `/llm-tools:llm-compare <prompt>` | Intentionally unsupported |
| Persistent review loop | `/llm-tools:review-loop [options]` | Intentionally unsupported |
| Format conversion | `/llm-tools:convert <from> <to>` | Intentionally unsupported as a dedicated skill |

Only Claude Code uses OpenAI's official `codex@openai-codex` plugin routing.
Codex provider skills never recommend those Claude-only commands. Gemini is a
cloud boundary: adding code, diffs, or repository context requires explicit
confirmation after the payload is disclosed. Ollama privacy depends on
`OLLAMA_HOST`: only verified loopback endpoints are treated as local, and any
other destination requires disclosure and explicit confirmation.

### go-web

Opinionated Go web app scaffolding and project conversion with our recommended stack.

| Platform | Invocation | Description |
|----------|------------|-------------|
| Claude Code | `/create-go-project <name>` | Scaffold a new Go web app from scratch |
| Claude Code | `/convert-to-go-project [target-directory]` | Convert the current or specified project to Go |
| Codex | `$go-web:create-go-project <name>` | Scaffold a new Go web app from scratch |
| Codex | `$go-web:convert-to-go-project [target-directory]` | Convert the current or specified project to Go |

Conversion supports Express and Fastify, Django, Flask, and FastAPI, Laravel
and other PHP projects, Next.js and React, and existing Go projects that should
be extended rather than replaced.

**The Stack:** Go + Echo v4, Templ, HTMX, Alpine.js, Tailwind CSS v4, sqlc, goose, Air

### tailwind

Tailwind CSS v4 tools for initialization, auditing, migration, and optimization.

| Workflow | Claude Code | Codex | Behavior |
|----------|-------------|-------|----------|
| Initialize | `/tailwind-init [path]` | `$tailwind:init [path]` | Explicit-only on Codex; installs and configures Tailwind v4 |
| Migrate | `/tailwind-migrate [options]` | `$tailwind:migrate [options]` | Explicit-only on Codex; `--check` previews without changes |
| Audit | `/tailwind-audit [path] [options]` | `$tailwind:audit [path] [options]` | Read-only by default; `--fix` applies safe fixes |
| Optimize | `/tailwind-optimize [options]` | `$tailwind:optimize [options]` | Read-only by default; `--fix` applies safe optimizations |

The Tailwind `cancel-loop` workflow is intentionally unsupported on Codex
because it controls Claude Code persistent-loop hooks. The
`$tailwind:tailwind-best-practices` skill remains available for Tailwind v4
syntax and styling guidance.

## Skills Reference

Skills are auto-invoked behaviors that activate based on context. Available across all platforms:

| Skill | Triggers When |
|-------|---------------|
| `go` | Writing/reviewing Go code: interfaces, errors, concurrency, testing, organization, debugging |
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

**Repository-backed catalog:** `.agents/plugins/marketplace.json` describes the available plugins but does not enable them by cwd. Use `/plugins` to browse and manage plugins after registering the marketplace and activating them in the current `CODEX_HOME`. Plugins with `.codex-plugin/plugin.json` are packaged for Codex. Today that set is `go-workflow`, `go-dev`, `gopher-guides`, `llm-tools`, `go-web`, and `tailwind`. The repo's `productivity` module remains Claude-only.

**Codex model defaults:** The `llm-tools` Codex commands omit `-m` by default so Codex CLI chooses its provider default. If `~/.codex/config.toml` contains a `model = "..."` line, that local pin overrides the provider default for every llm-tools Codex call that omits `-m`; leave it unset to keep using the latest recommended Codex model.

**Stage in another repo:** `./scripts/install-codex.sh --repo /path/to/your-repo` copies the current plugin set and merges entries into that repo's `.agents/plugins/marketplace.json` without removing unrelated plugin entries. It then prints the marketplace registration command and all six `codex plugin add` commands required to activate the staged plugins, using the merged catalog's actual name in each selector. Those commands modify the active `CODEX_HOME`, so use either this repository-backed source or `--user` in a given home, never both. Set a dedicated `CODEX_HOME` when the activation must be isolated from your normal Codex setup.

**GitHub one-liner:** `bash -c "$(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-all.sh)"` auto-detects all platforms — installs Claude Code and Gemini, and installs Codex plugins globally so skills load in every Codex session. The Codex install registers or upgrades the gopher-ai marketplace, then runs `codex plugin add <plugin>@gopher-ai` for all six Codex-capable plugins. Codex owns the cache publication and plugin enablement; the installer does not write private cache roots or `config.toml` plugin entries.

**Cache lifecycle:** Codex publishes each plugin under its manifest version. Install and refresh refuse to run while any Codex process is active because running sessions retain absolute hook and skill paths into their original roots. After all Codex sessions have exited, run `./scripts/install-codex.sh --user`; superseded roots remain available until you explicitly remove them with `./scripts/install-codex.sh --prune-cache`. The prune command keeps the current version and requires confirmation unless `--yes` is supplied.

**Migration from older versions:** Three earlier states needed cleanup, all handled automatically by the SessionStart hook (no command required) plus by `install-codex.sh --user` whenever you run install-all:
- Flat skills at `~/.codex/skills/<name>/` from the original (broken) `--user` mode — overflowed Codex's [skill metadata budget](https://developers.openai.com/codex/skills).
- Unmarked plugin directories at `~/.codex/plugins/<name>/` from when the README said "manually copy `dist/codex/plugins/` to `~/.codex/plugins/`" — also caused double-loading.

- Direct plugin copies at `~/.codex/plugins/<name>/` from a previous (also broken) `--user` mode that wrote files Codex never loaded. The current `--user` mode installs via the marketplace cache instead, where Codex actually reads from.

To migrate manually: `./scripts/install-codex.sh --user` (refresh the marketplace install) or `./scripts/install-codex.sh --cleanup` (remove leftover skills only).

**Workflow skills** (from `go-workflow` plugin):

```
$go-workflow:start-issue 42     # Full issue-to-PR workflow
$go-workflow:review-deep        # Deep review with full PR/issue context + fix
$go-workflow:worktree create 42 # Create isolated worktree
$go-workflow:commit             # Auto-generate commit message
$go-workflow:create-pr          # Create PR with template
$go-workflow:ship               # Verify, push, CI watch, merge
$go-workflow:worktree remove    # Remove a single worktree
$go-workflow:worktree prune     # Batch cleanup completed worktrees
```

### Google Gemini CLI

Extensions are installed per-module. Each extension includes:
- `gemini-extension.json` - Extension manifest
- `GEMINI.md` - Context file
- `skills/` - Auto-invoked skills
- `commands/` - Command definitions (TOML format)

## MCP Servers

Gopher AI plugins do not currently bundle MCP servers. Their workflows use
maintained skills, bundled references, and the host assistant's native tools.

New or updated integrations should target MCP `2026-07-28`. That revision
removes protocol sessions and the `initialize`/`notifications/initialized`
handshake: requests carry their protocol version and client capabilities in
`_meta`, and servers implement `server/discover` for capability and version
discovery. See the [MCP `2026-07-28` changelog](https://modelcontextprotocol.io/specification/2026-07-28/changelog)
and [release announcement](https://blog.modelcontextprotocol.io/posts/2026-07-28/).

### Deprecated MCP features

MCP `2026-07-28` gives deprecated features a minimum twelve-month compatibility
window, but contributors should not use them in new integrations:

- Replace **Roots** with tool parameters, resource URIs, or server
  configuration.
- Replace **Sampling** with direct LLM provider API integration.
- Replace **Logging** with `stderr` for STDIO servers or OpenTelemetry.
- Replace the legacy **HTTP+SSE transport** with Streamable HTTP.
- Replace OAuth **Dynamic Client Registration** with Client ID Metadata
  Documents.

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
python3 -m pip install --requirement requirements-test.txt
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
