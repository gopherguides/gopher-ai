---
name: audit
description: "Audits Tailwind CSS projects for consistency, performance, accessibility, and v4 compliance. Use for Tailwind health checks and actionable reports; use --fix only when changes are requested."
argument-hint: "[path] [--fix|--report|--focus=<area>]"
---

# Audit Tailwind CSS

`--focus` is allowlisted to `consistency`, `performance`, `practices`, or `v4`.
A focused run limits discovery, reporting, fixes, counts, and completion checks
to that category.

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root
before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected
  `SKILL.md` path, then ascend two directories (`skills/<name>` to plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Read both files completely, then apply the adapter while following the command
body:

1. `<PLUGIN_ROOT>/lib/codex-command-adapter.md`
2. `<PLUGIN_ROOT>/commands/audit.md`
