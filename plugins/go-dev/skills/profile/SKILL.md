---
name: profile
description: "Profiles Go CPU and memory behavior, identifies bottlenecks, and verifies measured optimizations. Use for evidence-driven performance work; do not use for benchmark generation alone."
argument-hint: "<file|function|package>"
disable-model-invocation: true
---

# Profile

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root
before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected
  `SKILL.md` path, then ascend two directories (`skills/<name>` to plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Read both files completely, then apply the adapter while following the command
body:

1. `<PLUGIN_ROOT>/lib/codex-command-adapter.md`
2. `<PLUGIN_ROOT>/commands/profile.md`
