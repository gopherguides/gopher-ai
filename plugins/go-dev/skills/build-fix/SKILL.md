---
name: build-fix
description: "Detects project build systems and fixes compiler or generated-code failures until every detected build is clean. Use for active build errors; do not use for lint-only cleanup."
argument-hint: "[log-path]"
disable-model-invocation: true
---

# Build Fix

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root
before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected
  `SKILL.md` path, then ascend two directories (`skills/<name>` to plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Read both files completely, then apply the adapter while following the command
body:

1. `<PLUGIN_ROOT>/lib/codex-command-adapter.md`
2. `<PLUGIN_ROOT>/commands/build-fix.md`
