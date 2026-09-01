---
name: create-go-project
description: "Creates a greenfield Go web project with Echo, Templ, HTMX, Tailwind, sqlc, goose, and Air. Use for new project scaffolding and requested application functionality. Skips conversion of existing applications."
argument-hint: "<project-name>"
---

# Create Go Project

## Plugin Resource Resolution

`<PLUGIN_ROOT>` denotes the absolute path to the `go-web` plugin directory. Resolve it before
reading any shared resource: start from the absolute path of this selected `SKILL.md` and
ascend two directories (`skills/create-go-project` to the plugin root).

Read `<PLUGIN_ROOT>/references/create-go-project.md` completely and follow it, passing
`$ARGUMENTS` as the project name.
