# Codex Command Adapter

This adapter lets a Codex skill reuse the matching Claude Code command body as
one surface-neutral workflow. Apply these rules before following that body.

## Invocation Arguments

Bind the invocation text to `SKILL_ARGS` without evaluating it:

1. Preserve `SKILL_ARGS` when a parent workflow explicitly supplied it,
   including an explicitly empty value.
2. On Claude Code, bind the injected `$ARGUMENTS` value.
3. On Codex with an explicit invocation, find the exact qualified
   `$go-dev:<skill-name>` token and bind only the text following that name.
4. When Codex selected the skill implicitly, derive the target and relevant
   options from the activating request. For example, `explain
   pkg/auth/login.go` binds `pkg/auth/login.go`.
5. Bind `SKILL_ARGS` to an empty string only when neither an explicit argument
   nor an implicit target or option is present.

Treat every `$ARGUMENTS` or `${ARGUMENTS}` reference in the command body as a
reference to `SKILL_ARGS`. Preserve whitespace and never read arguments from a
shell environment variable.

## Plugin Resources

Resolve the concrete absolute plugin root once from the selected skill. Treat
every `$CLAUDE_PLUGIN_ROOT` or `${CLAUDE_PLUGIN_ROOT}` reference in the command
body as that concrete root. Replace notation before running a command or
reading a resource.

Do not require the go-workflow plugin. The selected go-dev plugin owns every
script, loop helper, and supporting document referenced by its command body.

## Persistent Loop State

The command bodies' `Loop Initialization` sections and `<done>...</done>`
markers implement Claude Code's Stop-hook loop protocol. On Codex, skip every
`Loop Initialization` section, do not run `setup-loop.sh`, do not create
`.local/state/*.loop.local.json`, and do not emit a `<done>...</done>` marker.
Perform any required iteration within the current invocation and preserve the
command body's actual completion criteria and user-decision boundaries.

On Claude Code, follow the loop initialization and completion-marker protocol
unchanged.

## Native Capabilities

Map command-body capabilities by intent:

- For a required user decision, use the active surface's native structured-input capability
  when available. Otherwise ask one concise
  question in the final response and stop before the dependent action.
- For planning, use the active surface's native planning capability. When none
  exists, maintain an explicit plan in the conversation.
- For delegation or a command-body `Agent` step, use the active surface's native delegation capability
  and preserve any required role, concurrency,
  and wait semantics. If delegation is unavailable, do the work in the current
  context unless the command requires an independent review.
- Map `Read`, `Write`, `Edit`, `Glob`, `Grep`, and shell operations to the
  active surface's corresponding file and command capabilities. Ignore the
  Claude Code `allowed-tools` frontmatter after preserving its safety intent.

Keep the command body's completion criteria, safety limits, and output format
unchanged unless a platform-specific marker is explicitly identified as such.
