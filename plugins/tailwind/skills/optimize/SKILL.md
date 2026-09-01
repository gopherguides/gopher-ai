---
name: optimize
description: "Analyzes Tailwind CSS bundle size, source coverage, class usage, and build performance. Use for read-only optimization reports; use --fix only when safe project changes are requested."
argument-hint: "[path] [--report|--fix|--verbose]"
---

# Optimize Tailwind CSS

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root
before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected
  `SKILL.md` path, then ascend two directories (`skills/<name>` to plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Read both files completely, then apply the adapter while following the command
body:

1. `<PLUGIN_ROOT>/lib/codex-command-adapter.md`
2. `<PLUGIN_ROOT>/commands/optimize.md`
