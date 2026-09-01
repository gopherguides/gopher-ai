---
name: test-gen
description: "Generates idiomatic table-driven Go tests for a selected file, function, or package and verifies them. Use when test coverage is missing; do not use to diagnose an existing test failure."
argument-hint: "<file|function>"
disable-model-invocation: true
---

# Test Gen

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root
before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected
  `SKILL.md` path, then ascend two directories (`skills/<name>` to plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Read both files completely, then apply the adapter while following the command
body:

1. `<PLUGIN_ROOT>/lib/codex-command-adapter.md`
2. `<PLUGIN_ROOT>/commands/test-gen.md`
