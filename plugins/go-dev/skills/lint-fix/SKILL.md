---
name: lint-fix
description: "Finds and fixes Go lint findings while preserving behavior and verifying the result. Use for golangci-lint or formatting failures; do not use for compiler-only failures."
argument-hint: "[path] [--check]"
disable-model-invocation: true
---

# Lint Fix

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root
before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected
  `SKILL.md` path, then ascend two directories (`skills/<name>` to plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Read both files completely, then apply the adapter while following the command
body:

1. `<PLUGIN_ROOT>/lib/codex-command-adapter.md`
2. `<PLUGIN_ROOT>/commands/lint-fix.md`
