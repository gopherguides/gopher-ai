---
name: migrate
description: "Migrates Tailwind CSS v3 projects to v4 CSS-based configuration and verifies the result. Invoke explicitly for migration changes; use --check for a read-only preview."
argument-hint: "[--check|--keep-config|--backup]"
disable-model-invocation: true
---

# Migrate Tailwind CSS v3 to v4

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root
before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected
  `SKILL.md` path, then ascend two directories (`skills/<name>` to plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Read both files completely, then apply the adapter while following the command
body:

1. `<PLUGIN_ROOT>/lib/codex-command-adapter.md`
2. `<PLUGIN_ROOT>/commands/migrate.md`
