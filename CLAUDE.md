# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

gopher-ai is a Claude Code plugin marketplace providing Go-focused development tools. It contains seven plugins distributed via the Claude Code plugin system:

- **go-workflow**: Issue-to-PR workflow automation with git worktree management
- **go-dev**: Go-specific development tools (test generation, linting, code explanation)
- **productivity**: Git activity reports (standup, weekly summaries, changelogs, releases)
- **gopher-guides**: REST API integration with Gopher Guides training materials
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
- `model`: Optional rolling model alias (e.g., `fable`, `sonnet`, `haiku`)
- `allowed-tools`: Tool restrictions for the command

**Skills** (`skills/*/SKILL.md`): Auto-invoked behaviors with YAML frontmatter specifying:
- `description`: WHEN/WHEN NOT conditions for activation

**MCP Servers** use platform-specific manifest paths:
- Claude Code reads the `mcpServers` object embedded in
  `plugins/<name>/.claude-plugin/plugin.json`.
- Codex reads `plugins/<name>/.codex-plugin/plugin.json`, whose `mcpServers`
  field points to the plugin-root `.mcp.json`.
- Gemini has no checked-in extension manifest. `scripts/build-universal.sh`
  copies the plugin-root `.mcp.json` into the generated
  `gemini-extension.json`; plugins without that file receive an empty
  `mcpServers` object.

## Key Workflows

### Issue Worktree Flow

The `start-issue` workflow and worktree commands work together:

1. `/go-workflow:start-issue <num>` offers to create a worktree at `../${reponame}-issue-<num>-<title>/` from the default branch
2. The issue workflow implements changes with a TDD approach
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

**Hook ownership**: Only `go-workflow` has hooks registered:
- **SessionStart hook** (`codex-cleanup-on-start.sh`): Auto-removes legacy gopher-ai skill files left in `~/.codex/skills/` from older `--user` installs. Gated by a per-version marker file (`~/.codex/.gopher-ai-cleanup-<version>`) so it's nearly free on subsequent sessions. Reads the shipped manifest at `hooks/legacy-skill-hashes.txt` (kept in sync with `scripts/legacy-skill-hashes.txt` by `regen-legacy-hashes.sh`). Removal requires three checks: matching skill name, matching frontmatter `name:`, and matching SKILL.md sha256 in the manifest — false positives are essentially impossible.
- **Stop hook** (`stop-hook.sh`): Persistent loop management for `start-issue` style workflows
- **PreToolUse hook** (`pre-tool-use.sh`): Validates environment, tools, and git state before tool execution:
  - Checks for required env vars (GITHUB_TOKEN, OPENAI_API_KEY) contextually
  - Blocks execution if required tools are missing (golangci-lint, templ, gh, node)
  - Warns on uncommitted changes before tests; blocks releases with dirty git state
- **PostToolUse hook** (`post-tool-use.sh`): Error detection after tool execution:
  - Detects Go compilation errors, lint failures, permission denied
  - Codex observes local Bash only; hosted WebFetch and WebSearch bypass this local hook in Codex but remain matched for Claude
  - Codex transient failures receive model-visible safe retry guidance instead of automatic retries
  - Claude auto-retries network timeouts (up to 3 retries with linear backoff)
  - Claude auto-retries rate limits (up to 3 retries with exponential backoff: 30s, 60s, 120s)
  - Summarizes long output (>200 lines)
**When editing `shared/`**: The pre-commit hook automatically syncs changes to plugins. If you need to sync manually:

```bash
./scripts/sync-shared.sh      # Sync shared/ to plugins
./scripts/check-shared-sync.sh # Verify sync is correct
```

## Environment Requirements

- **GOPHER_GUIDES_API_KEY**: Required for Gopher Guides REST API requests
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

**Critical**: Claude Code and Codex use `plugin.json` versions (not only `marketplace.json`) to create cache directories. All manifest versions must stay in sync:

- `.claude-plugin/marketplace.json` - Marketplace-level versions
- `plugins/<name>/.claude-plugin/plugin.json` - Individual Claude Code plugin versions
- `plugins/<name>/.codex-plugin/plugin.json` - Individual Codex plugin versions

The `/release` command handles this automatically. If manually bumping versions, update all three locations.

### Cache Refresh

After releasing, users must refresh their local cache:

```bash
./scripts/refresh-plugins.sh
```

This script works around known Claude Code cache invalidation bugs ([#14061](https://github.com/anthropics/claude-code/issues/14061), [#15621](https://github.com/anthropics/claude-code/issues/15621)).

## Token Efficiency for Skills and Commands

Skill and command bodies enter the context window when invoked and stay there for the session, so every line is a recurring token cost. Prompt caching happens automatically at the API level; there is no in-file marker syntax that affects it.

**Guidelines:**
- Keep SKILL.md under 500 lines and 8,000 bytes. Codex hard-truncates a plugin skill body at 8,000 bytes without a continuation pointer, so the universal build warns at 6,000 bytes and rejects files at the hard limit. Structure large skills as a thin router: overview + workflow in SKILL.md, detail in supporting files referenced one level deep (see `go`, `htmx`, `templui`, and the go-workflow skills for the pattern)
- Supporting files (references, templates, examples) cost zero tokens until Claude reads them — prefer them over inline content for anything static, mutually exclusive, or rarely needed
- Prefer executable scripts over inline code blocks: script contents never enter context, only their output
- Frontmatter `description` should state what the skill does plus WHEN/WHEN NOT to use it, in third person; put the key use case first (the skill listing truncates long descriptions)

**Model and effort tiering:**

Every command and skill inherits the session model and effort unless its frontmatter says otherwise, so an Opus session runs `/cancel-loop` at Opus rates. Set `model:` and `effort:` to push work down to the cheapest tier that still does the job. Use rolling aliases (`haiku`, `sonnet`, `fable`, `inherit`) — never a dated model ID, which goes stale on every model release. When a command and a same-named skill both exist, the skill wins the collision and supplies the invocation metadata, so set the keys on both or the override silently does nothing.

- **Deterministic script-driven work** (`cancel-loop`, `clear-cache`, `create-worktree`, `gopher-ai-refresh`): `model: haiku` + `effort: low`. These run fixed scripts and branch on exit codes.
- **Bounded summarization and autofix reporting** (`standup`, `changelog`, `weekly-summary`, `validate-skills`, `lint-fix`, `commit`): `effort: low` only. Keep the session model — a stronger model at low effort usually beats a weaker model at high effort.
- **Everything else** — diagnosis (`build-fix`), code design (`test-gen`, `bench`), anything that reasons about user intent (`tailwind audit`/`init`), destructive operations (`remove-worktree`, `prune-worktree`), and multi-step workflows (`ship`, `start-issue`, `review-deep`, `e2e-verify`, `migrate`): leave both unset and inherit the session.

Never pin `model:` on a surface that can destroy user work — an unmerged branch, an uncommitted diff, a worktree someone is still using. Scripted cleanup of regenerable state is not that: `cancel-loop` removes its own loop state, `clear-cache` and `gopher-ai-refresh` discard caches that rebuild on demand, and `create-worktree` either creates an isolated directory or reuses the exact matching worktree while skipping and reporting existing destination env entries, including symlinks. Those stay pinned. The distinction is whether a wrong call loses something that cannot be recreated.

Overrides are not free. Switching models mid-session forfeits the prompt cache built for the previous model, and changing `effort:` can break the cached prefix too, so a small pinned command inside a long warm conversation can cost more than it saves. Pin sparingly, and prefer `effort:` alone where the work is bounded.

Before adding an override, compare inherited settings against the proposed configuration on representative held-out tasks — dirty or unmerged worktrees, failed GitHub lookups, generated-code build failures — and record task success, incorrect mutations, tool calls, and token counts. Script-level checks (`scripts/test-commands.sh`) establish packaging validity, not model quality.

Do not add verification rituals ("double-check your work") or thoroughness boosters ("be maximally thorough") to prompts. Current models do this natively; the instructions just buy duplicate tool calls.
