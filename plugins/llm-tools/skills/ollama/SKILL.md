---
name: ollama
description: "Delegates an explicit analysis, review, or second-opinion request after checking the configured Ollama endpoint and requiring consent for non-loopback destinations. Use only when the user asks for Ollama; do not start a server or download a model without consent."
argument-hint: "<prompt>"
disable-model-invocation: true
---

# Ollama

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root
before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected
  `SKILL.md` path, then ascend two directories (`skills/<name>` to plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Read both files completely, then apply the adapter while following the command
body:

1. `<PLUGIN_ROOT>/lib/codex-command-adapter.md`
2. `<PLUGIN_ROOT>/commands/ollama.md`
