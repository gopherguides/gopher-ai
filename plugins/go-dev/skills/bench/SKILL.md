---
name: bench
description: "Generates and runs statistically useful Go benchmarks with allocation and profile analysis. Use for benchmark creation or measured performance comparison; do not use for general correctness tests."
argument-hint: "<file|function|package>"
disable-model-invocation: true
---

# Bench

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root
before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected
  `SKILL.md` path, then ascend two directories (`skills/<name>` to plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Read both files completely, then apply the adapter while following the command
body:

1. `<PLUGIN_ROOT>/lib/codex-command-adapter.md`
2. `<PLUGIN_ROOT>/commands/bench.md`
