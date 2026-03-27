# AGENTS.md

Project instructions for OpenAI Codex CLI.

## Available Skills

Skills auto-activate based on context, or invoke directly with `$skill-name`.

### Go Development

| Skill | Triggers |
|-------|----------|
| `go-best-practices` | Go code, patterns, reviews, "best way to..." |
| `go-profiling-optimization` | Performance, profiling, benchmarks, "why is this slow" |
| `systematic-debugging` | Debugging, test failures, stack traces, "why is this broken" |
| `gopher-guides` | Go training materials, idiomatic patterns |

### Code Quality

| Skill | Triggers |
|-------|----------|
| `validate-skills` | Editing command/skill .md files, shell code validation |
| `address-review` | PR review comments, reviewer feedback, unresolved threads |

### Web Development

| Skill | Triggers |
|-------|----------|
| `tailwind-best-practices` | Tailwind CSS classes, themes, v4 config |
| `templui` | Go/Templ web apps, templUI components, HTMX/Alpine.js |
| `htmx` | htmx attributes, partial page updates, SSE, swaps |

### Multi-LLM

| Skill | Triggers |
|-------|----------|
| `second-opinion` | Architecture decisions, security code, "sanity check" |
| `gemini-image` | Image generation requests |

## Installation

### Via Codex skill installer (recommended)

```
codex> $skill-installer gopherguides/gopher-ai
```

### One-liner install

```bash
# User-level (available across all projects)
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-codex.sh) --user

# Repo-level (available to all contributors)
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-codex.sh) --repo .
```

### Manual install

```bash
git clone https://github.com/gopherguides/gopher-ai
cd gopher-ai
./scripts/build-universal.sh
cp -r dist/codex/skills/* ~/.agents/skills/
```

### Skill locations

| Scope | Path | Use case |
|-------|------|----------|
| Repo-level | `.agents/skills/` | Shared team standards (committed to repo) |
| User-level | `$HOME/.agents/skills/` | Personal toolkit across all projects |
| Legacy | `~/.codex/skills/` | Still loaded for backward compatibility |

> **Migrating from `~/.codex/skills/`?** Move your skills to `~/.agents/skills/` — Codex scans both paths, but `.agents/skills/` is the current convention.

## Updating

Re-run the installer to replace existing skills:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-codex.sh) --user
```

Or update manually:

```bash
rm -rf ~/.agents/skills/{go-best-practices,second-opinion,tailwind-best-practices,templui,gopher-guides,go-profiling-optimization,systematic-debugging,validate-skills,htmx,address-review,gemini-image}
cp -r dist/codex/skills/* ~/.agents/skills/
```

## Development

```bash
./scripts/install-hooks.sh       # Install git hooks
./scripts/build-universal.sh     # Build universal distribution
./scripts/sync-shared.sh         # Sync shared files
```

## Links

- [Gopher Guides](https://gopherguides.com) - Official Go training
- [GitHub Repository](https://github.com/gopherguides/gopher-ai)
