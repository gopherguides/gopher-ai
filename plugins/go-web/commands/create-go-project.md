---
argument-hint: "<project-name>"
description: "Create a new Go web project with Templ, HTMX, Tailwind, and sqlc"
allowed-tools: ["Bash(*setup-loop.sh*)", "Bash(go:*)", "Bash(git:*)", "Bash(npm:*)", "Bash(npx:*)", "Bash(make:*)", "Bash(mkdir:*)", "Bash(touch:*)", "Bash(cd:*)", "Bash(curl:*)", "Bash(direnv:*)", "Bash(source:*)", "Bash(templ:*)", "Bash(templui:*)", "Bash(cat:*)", "Bash(kill:*)", "Bash(sleep:*)", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

# Create Go Project

Bind the injected `$ARGUMENTS` value to `SKILL_ARGS` without evaluating or re-tokenizing
it.

Bind `<PLUGIN_ROOT>` in the shared workflow to `${CLAUDE_PLUGIN_ROOT}`.

Read `${CLAUDE_PLUGIN_ROOT}/references/create-go-project.md` completely and follow it,
passing `SKILL_ARGS` as the project name.
