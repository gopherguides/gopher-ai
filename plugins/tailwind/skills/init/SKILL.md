---
name: init
description: "Initializes Tailwind CSS v4 in an existing project, including dependencies, CSS entry points, and build integration. Invoke explicitly when setup changes are requested."
argument-hint: "[project-path]"
disable-model-invocation: true
---

# Initialize Tailwind CSS v4

Bind the requested project path, or the invocation directory when omitted, to
one normalized `<INIT_TARGET>`. The command workflow must use that operation
root for every discovery, package-manager command, write, and validation.

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root
before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected
  `SKILL.md` path, then ascend two directories (`skills/<name>` to plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Read both files completely, then apply the adapter while following the command
body:

1. `<PLUGIN_ROOT>/lib/codex-command-adapter.md`
2. `<PLUGIN_ROOT>/commands/init.md`
