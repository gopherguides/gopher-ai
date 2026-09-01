---
name: convert-to-go-project
description: "Converts existing Express/Fastify, Django/Flask/FastAPI, Laravel/PHP, Next.js/React, and Go projects to Go + Templ + HTMX + Tailwind. Applies to whole-project migrations and existing Go projects that need this stack. Skips greenfield creation and isolated HTMX or templUI help."
argument-hint: "[target-directory]"
---

# Convert to Go Project

## Invocation Argument Binding

Bind the optional target directory to `SKILL_ARGS` before reading the shared workflow. For an
explicit Codex invocation, use only the text following the exact qualified
`$go-web:convert-to-go-project` token. Otherwise, derive the target directory from the
activating request. Preserve the text literally, trim only surrounding whitespace, and never
evaluate it as shell code or read it from an environment variable.

## Plugin Resource Resolution

`<PLUGIN_ROOT>` denotes the absolute path to the `go-web` plugin directory. Resolve it before
reading any shared resource: start from the absolute path of this selected `SKILL.md` and
ascend two directories (`skills/convert-to-go-project` to the plugin root).

Read `<PLUGIN_ROOT>/references/convert-to-go-project.md` completely and follow it with
`SKILL_ARGS` as the optional target directory.
