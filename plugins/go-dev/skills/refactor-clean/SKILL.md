---
name: refactor-clean
description: "Finds and safely removes dead Go code, orphaned tests, and avoidable complexity with verification. Use for behavior-preserving cleanup; do not use for product feature changes."
argument-hint: "[path] [--dry-run]"
disable-model-invocation: true
---

# Refactor Clean

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root
before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected
  `SKILL.md` path, then ascend two directories (`skills/<name>` to plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Read both files completely, then apply the adapter while following the command
body:

1. `<PLUGIN_ROOT>/lib/codex-command-adapter.md`
2. `<PLUGIN_ROOT>/commands/refactor-clean.md`
