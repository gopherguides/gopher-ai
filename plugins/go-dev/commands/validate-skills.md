---
argument-hint: "[file|directory] [--json]"
description: "Validate fenced shell blocks in plugin command and skill Markdown"
allowed-tools: ["Bash(*validate-skills.py*)", "Read"]
---

# Validate Skills

Validate one Markdown file, every Markdown file below one directory, or the
default plugin command and skill paths. The optional `--json` flag may appear
before or after the path.

## Execution

Resolve `${CLAUDE_PLUGIN_ROOT}/scripts/validate-skills.py` and execute it with
the invocation arguments passed as distinct values. Do not evaluate or
re-tokenize user input. Preserve the helper's exit status.

In `--json` mode, return helper stdout unchanged and do not add a completion
marker or explanatory text. Otherwise return the rendered validation report.

## Supporting Rules

The packaged helper implements these shared contracts. Read them completely
when interpreting a finding or changing validation behavior:

- `${CLAUDE_PLUGIN_ROOT}/lib/validate-skills/classification.md`
- `${CLAUDE_PLUGIN_ROOT}/lib/validate-skills/execution.md`
- `${CLAUDE_PLUGIN_ROOT}/lib/validate-skills/ai-review.md`
