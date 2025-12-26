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
| `/codex <prompt>` | Delegate tasks to OpenAI Codex CLI |
| `/gemini <prompt>` | Query Google Gemini for analysis |
| `/ollama <prompt>` | Use local models (data stays on your machine) |
| `/llm-compare <prompt>` | Compare responses from multiple LLMs |
| `/convert <from> <to>` | Convert between formats (JSON→TS, SQL→Prisma, etc.) |

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

## Privacy Note

- `/ollama` keeps all data local on your machine
- `/codex` and `/gemini` send data to their respective cloud services

## License

MIT - see [LICENSE](../../LICENSE)
