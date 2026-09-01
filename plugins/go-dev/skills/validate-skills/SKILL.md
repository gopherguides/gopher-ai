---
name: validate-skills
description: "Validates fenced bash, sh, shell, and zsh blocks in plugin Markdown with syntax checks, conservative command classification, guarded execution, and portability review. Use after editing command or skill Markdown or when its shell validation fails."
argument-hint: "[file|directory] [--json]"
---

# Validate Skills

Use `$go-dev:validate-skills [file|directory] [--json]` to validate one file,
one directory, or the default plugin command and skill Markdown paths.

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root
before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected
  `SKILL.md` path, then ascend two directories (`skills/<name>` to plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Read both shared workflow files completely before acting:

1. `<PLUGIN_ROOT>/lib/codex-command-adapter.md`
2. `<PLUGIN_ROOT>/commands/validate-skills.md`

Resolve `<PLUGIN_ROOT>/scripts/validate-skills.py`, pass the adapter-bound
`SKILL_ARGS` as distinct arguments without evaluating them, and execute the
helper. With `--json`, return its stdout unchanged so the result remains one
JSON object. Propagate its exit status.

Use these references when interpreting findings or changing validator rules:

- `<PLUGIN_ROOT>/lib/validate-skills/classification.md`
- `<PLUGIN_ROOT>/lib/validate-skills/execution.md`
- `<PLUGIN_ROOT>/lib/validate-skills/ai-review.md`
