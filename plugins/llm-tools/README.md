# llm-tools

Multi-LLM integration for second opinions and task delegation.

## Installation

```bash
/plugin install llm-tools@gopher-ai
```

Or install via marketplace:
```bash
/plugin marketplace add gopherguides/gopher-ai
```

## Commands

| Command | Description |
|---------|-------------|
| `/llm-tools:codex <prompt>` | Delegate tasks to Codex with official-plugin routing and CLI fallback |
| `/gemini <prompt>` | Query Google Gemini for analysis |
| `/ollama <prompt>` | Use local models (data stays on your machine) |
| `/llm-compare <prompt>` | Compare responses from multiple LLMs |
| `/convert <from> <to>` | Convert between formats (JSON→TS, SQL→Prisma, etc.) |
| `/review-loop [options]` | Iterative LLM review loop: review, fix, verify, repeat until clean |

## Skills (Auto-invoked)

### Second Opinion

Suggests getting another LLM's perspective for complex decisions or when you want to validate an approach.

## Requirements

Install the CLI tools you want to use:

```bash
# OpenAI Codex
npm install -g @openai/codex

# Google Gemini
npm install -g @google/gemini-cli

# Ollama (local models)
brew install ollama
```

## Interactive Codex in Claude Code

For interactive Codex review and delegation inside Claude Code, install OpenAI's official Codex plugin:

```bash
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/reload-plugins
/codex:setup
```

When `codex@openai-codex` is installed, `/llm-tools:codex` prefers the official `/codex:review`, `/codex:adversarial-review`, and `/codex:rescue` commands. If the official plugin is missing, `/llm-tools:codex` warns, offers those install steps, and can proceed with the built-in `codex exec` / `codex review` CLI fallback.

Both paths use the same `~/.codex` authentication and configuration. Scripted gopher-ai pipelines such as `review-loop`, `complete-issue`, and `ship` stay on the CLI flow so they can continue using structured `codex exec --output-schema` automation.

## Codex Model Defaults

llm-tools omits `-m` for Codex calls by default, so Codex CLI chooses its provider default. If `~/.codex/config.toml` contains a `model = "..."` line, that local pin overrides the provider default for these calls; leave it unset to keep using the latest recommended Codex model.

## Privacy Note

- `/ollama` keeps all data local on your machine
- `/codex` and `/gemini` send data to their respective cloud services

## License

MIT - see [LICENSE](../../LICENSE)
