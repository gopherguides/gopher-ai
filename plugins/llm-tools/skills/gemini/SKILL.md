---
name: gemini
description: "Delegates an explicit analysis, review, or second-opinion request to Google Gemini CLI with a disclosed cloud-data boundary. Use only when the user asks to consult Gemini; do not invoke implicitly or send repository context without explicit confirmation."
argument-hint: "[--tier flex|standard|priority] <prompt>"
disable-model-invocation: true
---

# Gemini

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root
before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected
  `SKILL.md` path, then ascend two directories (`skills/<name>` to plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Read both files completely, then apply the adapter while following the command
body:

1. `<PLUGIN_ROOT>/lib/codex-command-adapter.md`
2. `<PLUGIN_ROOT>/commands/gemini.md`
