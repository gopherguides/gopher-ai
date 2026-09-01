# llm-tools

Multi-LLM integration for second opinions and task delegation.

## Installation

Claude Code:

```bash
/plugin install llm-tools@gopher-ai
```

Codex, after registering the repository-backed `gopher-ai` marketplace:

```bash
codex plugin add llm-tools@gopher-ai
```

## Provider Workflows

Claude Code uses slash commands. Codex exposes the two cross-model provider
paths as explicit qualified skills.

| Workflow | Claude Code | Codex |
|----------|-------------|-------|
| Gemini delegation | `/llm-tools:gemini <prompt>` | `$llm-tools:gemini <prompt>` |
| Local Ollama delegation | `/llm-tools:ollama <prompt>` | `$llm-tools:ollama <prompt>` |
| Gemini image generation | `/llm-tools:gemini-image <prompt>` | `$llm-tools:gemini-image <prompt>` |
| Claude-to-Codex delegation | `/llm-tools:codex <prompt>` | Intentionally unsupported; the active assistant is already Codex |
| Multi-provider comparison | `/llm-tools:llm-compare <prompt>` | Intentionally unsupported |
| Format conversion | `/llm-tools:convert <from> <to>` | Intentionally unsupported as a dedicated skill |
| Persistent review loop | `/llm-tools:review-loop [options]` | Intentionally unsupported |

`$llm-tools:gemini` and `$llm-tools:ollama` are explicit-only. They are never
selected implicitly because provider choice and data boundaries belong to the
user.

## Advisory Skill

### Second Opinion

Suggests getting another LLM's perspective for complex decisions or when you
want to validate an approach. Its recommendations are surface-aware: Codex sees
only qualified Codex skills, while Claude Code sees slash commands.

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

## Claude Code: Interactive Codex

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

- Ollama keeps prompt data local after its model is installed.
- Gemini sends prompts to Google. An explicit Codex invocation authorizes only
  its attached prompt; adding code, diffs, file contents, logs, or session
  context requires a separate disclosure and explicit confirmation.
- Claude Code's Codex and Gemini commands send data to their respective cloud
  services.

## License

MIT - see [LICENSE](../../LICENSE)
